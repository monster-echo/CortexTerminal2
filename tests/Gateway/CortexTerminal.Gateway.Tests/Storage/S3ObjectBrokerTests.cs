using Amazon.S3;
using Amazon.S3.Model;
using CortexTerminal.Gateway.Storage;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Storage;

public sealed class S3ObjectBrokerTests
{
    private static ObjectStorageOptions Options(string endpoint) => new()
    {
        Endpoint = endpoint,
        Bucket = "test-bucket",
        Region = "us-east-1",
        AccessKey = "ak",
        SecretKey = "sk",
        ForcePathStyle = true,
        PresignedUrlTtl = TimeSpan.FromMinutes(15),
    };

    [Fact]
    public async Task GeneratePutUrlAsync_UsesExactKey_AndHttpForPlainEndpoint()
    {
        var client = Substitute.For<IAmazonS3>();
        client.GetPreSignedURLAsync(Arg.Do<GetPreSignedUrlRequest>(r => { }))
            .Returns(Task.FromResult("http://minio.local/test-bucket/transfers/abc?sig=1"));
        var broker = new S3ObjectBroker(Options("http://minio.local"), client);

        var url = await broker.GeneratePutUrlAsync("transfers/abc", CancellationToken.None);

        url.Url.Should().StartWith("http://");
        await client.Received(1).GetPreSignedURLAsync(Arg.Is<GetPreSignedUrlRequest>(r =>
            r.BucketName == "test-bucket"
            && r.Key == "transfers/abc"
            && r.Verb == HttpVerb.PUT
            && r.Protocol == Protocol.HTTP));
    }

    [Fact]
    public async Task GenerateGetUrlAsync_ForcesHttps_WhenEndpointIsHttps()
    {
        var client = Substitute.For<IAmazonS3>();
        GetPreSignedUrlRequest? seen = null;
        client.GetPreSignedURLAsync(Arg.Do<GetPreSignedUrlRequest>(r => seen = r))
            .Returns(Task.FromResult("https://s3.test/get"));
        var broker = new S3ObjectBroker(Options("https://s3.test"), client);

        await broker.GenerateGetUrlAsync("feedback/u/x.png", CancellationToken.None);

        seen!.Protocol.Should().Be(Protocol.HTTPS);
        seen.Key.Should().Be("feedback/u/x.png");
        seen.Verb.Should().Be(HttpVerb.GET);
    }

    [Fact]
    public async Task ListByPrefixAsync_PaginatesAndMaps()
    {
        var client = Substitute.For<IAmazonS3>();
        var lastModified = new DateTime(2026, 8, 30, 0, 0, 0, DateTimeKind.Utc);
        var firstPage = new ListObjectsV2Response
        {
            S3Objects = [new S3Object { Key = "transfers/a", LastModified = lastModified }],
            IsTruncated = true,
            NextContinuationToken = "next",
        };
        var secondPage = new ListObjectsV2Response
        {
            S3Objects = [new S3Object { Key = "transfers/b", LastModified = lastModified }],
        };
        client.ListObjectsV2Async(Arg.Any<ListObjectsV2Request>(), Arg.Any<CancellationToken>())
            .Returns(firstPage, secondPage);
        var broker = new S3ObjectBroker(Options("https://s3.test"), client);

        var objects = await broker.ListByPrefixAsync("transfers/", CancellationToken.None);

        objects.Should().HaveCount(2);
        objects[0].Key.Should().Be("transfers/a");
        objects[0].LastModified.Should().Be(new DateTimeOffset(lastModified));
    }

    [Fact]
    public async Task DeleteAsync_TargetsBucketAndKey()
    {
        var client = Substitute.For<IAmazonS3>();
        var broker = new S3ObjectBroker(Options("https://s3.test"), client);

        await broker.DeleteAsync("transfers/abc", CancellationToken.None);

        await client.Received(1).DeleteObjectAsync(Arg.Is<DeleteObjectRequest>(r =>
            r.BucketName == "test-bucket" && r.Key == "transfers/abc"), Arg.Any<CancellationToken>());
    }
}
