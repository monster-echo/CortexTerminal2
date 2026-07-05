using System.Net;
using Amazon.S3;
using Amazon.S3.Model;
using CortexTerminal.Gateway.Storage;
using FluentAssertions;
using NSubstitute;
using NSubstitute.ExceptionExtensions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Storage;

/// <summary>
/// Unit tests for <see cref="S3CompatibleArtifactStorage"/> using an NSubstitute mock of
/// <see cref="IAmazonS3"/>. No real S3 endpoint required — these verify the orchestration
/// logic (correct keys, verbs, prefix handling) rather than real S3 round-trips.
/// </summary>
public sealed class S3CompatibleArtifactStorageTests
{
    private static readonly ArtifactStorageOptions Options = new()
    {
        Endpoint = "https://s3.example.com",
        Bucket = "test-bucket",
        Region = "us-east-1",
        AccessKey = "ak",
        SecretKey = "sk",
        ForcePathStyle = false,
        PresignedUrlTtl = TimeSpan.FromMinutes(15),
    };

    private static S3CompatibleArtifactStorage Create(IAmazonS3 client) => new(Options, client);

    [Fact]
    public async Task GenerateUploadUrlAsync_ReturnsPresignedUrlAndKey()
    {
        var client = Substitute.For<IAmazonS3>();
        const string url = "https://s3.example.com/test-bucket/sess/file?sig=abc";
        client.GetPreSignedURLAsync(Arg.Any<GetPreSignedUrlRequest>()).Returns(url);

        var storage = Create(client);
        var upload = await storage.GenerateUploadUrlAsync("sess", "file.txt", CancellationToken.None);

        upload.UploadUrl.Should().Be(url);
        upload.S3Key.Should().Be("sess/file.txt");
        upload.ArtifactId.Should().NotBeNullOrEmpty();
        await client.Received(1).GetPreSignedURLAsync(Arg.Is<GetPreSignedUrlRequest>(r =>
            r.Verb == HttpVerb.PUT && r.BucketName == "test-bucket" && r.Key == "sess/file.txt"));
    }

    [Fact]
    public async Task GenerateDownloadUrlAsync_ReturnsPresignedUrl()
    {
        var client = Substitute.For<IAmazonS3>();
        const string url = "https://s3.example.com/test-bucket/sess/file?sig=get";
        client.GetPreSignedURLAsync(Arg.Any<GetPreSignedUrlRequest>()).Returns(url);

        var storage = Create(client);
        var download = await storage.GenerateDownloadUrlAsync("sess", "file.txt", CancellationToken.None);

        download.DownloadUrl.Should().Be(url);
        await client.Received(1).GetPreSignedURLAsync(Arg.Is<GetPreSignedUrlRequest>(r =>
            r.Verb == HttpVerb.GET && r.Key == "sess/file.txt"));
    }

    [Fact]
    public async Task ObjectExistsAsync_ExistingObject_ReturnsTrue()
    {
        var client = Substitute.For<IAmazonS3>();
        client.GetObjectMetadataAsync(Arg.Any<GetObjectMetadataRequest>(), Arg.Any<CancellationToken>())
              .Returns(new GetObjectMetadataResponse());

        var storage = Create(client);
        var exists = await storage.ObjectExistsAsync("sess", "file.txt", CancellationToken.None);

        exists.Should().BeTrue();
    }

    [Fact]
    public async Task ObjectExistsAsync_MissingObject_ReturnsFalse()
    {
        var client = Substitute.For<IAmazonS3>();
        client.GetObjectMetadataAsync(Arg.Any<GetObjectMetadataRequest>(), Arg.Any<CancellationToken>())
              .Throws(new AmazonS3Exception("Not Found") { StatusCode = HttpStatusCode.NotFound });

        var storage = Create(client);
        var exists = await storage.ObjectExistsAsync("sess", "nope", CancellationToken.None);

        exists.Should().BeFalse();
    }

    [Fact]
    public async Task GetObjectSizeAsync_ReturnsContentLength()
    {
        var client = Substitute.For<IAmazonS3>();
        client.GetObjectMetadataAsync(Arg.Any<GetObjectMetadataRequest>(), Arg.Any<CancellationToken>())
              .Returns(new GetObjectMetadataResponse { ContentLength = 1234 });

        var storage = Create(client);
        var size = await storage.GetObjectSizeAsync("sess", "file.txt", CancellationToken.None);

        size.Should().Be(1234);
    }

    [Fact]
    public async Task DeleteObjectAsync_PassesCorrectKey()
    {
        var client = Substitute.For<IAmazonS3>();
        client.DeleteObjectAsync(Arg.Any<DeleteObjectRequest>(), Arg.Any<CancellationToken>())
              .Returns(new DeleteObjectResponse());

        var storage = Create(client);
        await storage.DeleteObjectAsync("sess", "file.txt", CancellationToken.None);

        await client.Received(1).DeleteObjectAsync(
            Arg.Is<DeleteObjectRequest>(r => r.BucketName == "test-bucket" && r.Key == "sess/file.txt"),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task DeleteSessionPrefixAsync_DeletesEveryListedObject()
    {
        var client = Substitute.For<IAmazonS3>();
        client.ListObjectsV2Async(Arg.Any<ListObjectsV2Request>(), Arg.Any<CancellationToken>())
              .Returns(new ListObjectsV2Response
              {
                  S3Objects = new List<S3Object>
                  {
                      new() { Key = "sess/a.txt" },
                      new() { Key = "sess/b.txt" },
                      new() { Key = "sess/c.txt" },
                  }
              });

        var storage = Create(client);
        await storage.DeleteSessionPrefixAsync("sess", CancellationToken.None);

        await client.Received(1).ListObjectsV2Async(
            Arg.Is<ListObjectsV2Request>(r => r.Prefix == "sess/"), Arg.Any<CancellationToken>());
        await client.Received(1).DeleteObjectAsync(
            Arg.Is<DeleteObjectRequest>(r => r.Key == "sess/a.txt"), Arg.Any<CancellationToken>());
        await client.Received(1).DeleteObjectAsync(
            Arg.Is<DeleteObjectRequest>(r => r.Key == "sess/b.txt"), Arg.Any<CancellationToken>());
        await client.Received(1).DeleteObjectAsync(
            Arg.Is<DeleteObjectRequest>(r => r.Key == "sess/c.txt"), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task DeleteSessionPrefixAsync_NoObjects_DoesNotCallDelete()
    {
        var client = Substitute.For<IAmazonS3>();
        client.ListObjectsV2Async(Arg.Any<ListObjectsV2Request>(), Arg.Any<CancellationToken>())
              .Returns(new ListObjectsV2Response { S3Objects = new List<S3Object>() });

        var storage = Create(client);
        await storage.DeleteSessionPrefixAsync("sess", CancellationToken.None);

        await client.DidNotReceive().DeleteObjectAsync(
            Arg.Any<DeleteObjectRequest>(), Arg.Any<CancellationToken>());
    }
}
