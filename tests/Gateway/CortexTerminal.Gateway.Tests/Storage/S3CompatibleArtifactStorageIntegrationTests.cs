using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using CortexTerminal.Gateway.Storage;
using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Storage;

/// <summary>
/// Round-trip integration test against a real S3-compatible endpoint (MinIO by default). Opt-in:
/// tagged <c>Category=Integration</c> and skipped by CI. Run locally after
/// <c>bash scripts/start-test-minio.sh</c>.
/// </summary>
[Trait("Category", "Integration")]
public sealed class S3CompatibleArtifactStorageIntegrationTests
{
    private static ArtifactStorageOptions LoadOptionsFromEnv()
    {
        var endpoint = Environment.GetEnvironmentVariable("CORTERM_TEST_S3_ENDPOINT") ?? "http://localhost:9000";
        var accessKey = Environment.GetEnvironmentVariable("CORTERM_TEST_S3_ACCESS_KEY") ?? "corterm";
        var secretKey = Environment.GetEnvironmentVariable("CORTERM_TEST_S3_SECRET_KEY") ?? "corterm-dev-secret";
        var bucket = Environment.GetEnvironmentVariable("CORTERM_TEST_S3_BUCKET") ?? "corterm-artifacts-test";
        var region = Environment.GetEnvironmentVariable("CORTERM_TEST_S3_REGION") ?? "us-east-1";
        var forcePathStyle = bool.TryParse(Environment.GetEnvironmentVariable("CORTERM_TEST_S3_FORCE_PATH_STYLE") ?? "true", out var fps) && fps;
        return new ArtifactStorageOptions
        {
            Endpoint = endpoint,
            Bucket = bucket,
            Region = region,
            AccessKey = accessKey,
            SecretKey = secretKey,
            ForcePathStyle = forcePathStyle,
            PresignedUrlTtl = TimeSpan.FromMinutes(15),
        };
    }

    private static S3CompatibleArtifactStorage BuildStorage()
    {
        var opts = LoadOptionsFromEnv();
        return new S3CompatibleArtifactStorage(new OptionsWrapper<ArtifactStorageOptions>(opts));
    }

    private static async Task EnsureBucketExistsAsync()
    {
        var opts = LoadOptionsFromEnv();
        var creds = new BasicAWSCredentials(opts.AccessKey, opts.SecretKey);
        var config = new AmazonS3Config
        {
            RegionEndpoint = Amazon.RegionEndpoint.GetBySystemName(opts.Region),
            ForcePathStyle = opts.ForcePathStyle,
            ServiceURL = opts.Endpoint,
        };
        using var client = new AmazonS3Client(creds, config);
        try
        {
            await client.PutBucketAsync(new PutBucketRequest { BucketName = opts.Bucket }, CancellationToken.None);
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.Conflict
                                        || (ex.ErrorCode?.Contains("BucketAlreadyOwnedByYou") ?? false)
                                        || (ex.ErrorCode?.Contains("BucketAlreadyExists") ?? false))
        {
            // Bucket already exists — expected when the start script ran already.
        }
    }

    [Fact]
    public async Task GenerateUploadUrl_PutRoundTrip_ObjectIsRetrievable()
    {
        await EnsureBucketExistsAsync();
        var storage = BuildStorage();
        var sessionId = $"it-{Guid.NewGuid():N}";
        var filename = "roundtrip.txt";
        var payload = "integration-payload"u8.ToArray();

        try
        {
            var upload = await storage.GenerateUploadUrlAsync(sessionId, filename, CancellationToken.None);
            upload.UploadUrl.Should().NotBeNullOrEmpty();

            using var http = new HttpClient();
            using var put = new HttpRequestMessage(HttpMethod.Put, upload.UploadUrl)
            {
                Content = new ByteArrayContent(payload)
            };
            using var putResp = await http.SendAsync(put, CancellationToken.None);
            putResp.EnsureSuccessStatusCode();

            (await storage.ObjectExistsAsync(sessionId, filename, CancellationToken.None)).Should().BeTrue();
            var size = await storage.GetObjectSizeAsync(sessionId, filename, CancellationToken.None);
            size.Should().Be(payload.Length);
        }
        finally
        {
            await storage.DeleteObjectAsync(sessionId, filename, CancellationToken.None);
        }
    }

    [Fact]
    public async Task ObjectExistsAsync_MissingObject_ReturnsFalse()
    {
        await EnsureBucketExistsAsync();
        var storage = BuildStorage();
        var sessionId = $"missing-{Guid.NewGuid():N}";

        var exists = await storage.ObjectExistsAsync(sessionId, "no-such-file.bin", CancellationToken.None);
        exists.Should().BeFalse();
    }

    [Fact]
    public async Task DeleteSessionPrefixAsync_RemovesAllObjectsUnderSession()
    {
        await EnsureBucketExistsAsync();
        var storage = BuildStorage();
        var sessionId = $"bulk-{Guid.NewGuid():N}";
        var filenames = new[] { "a.txt", "b.txt", "c.txt" };

        try
        {
            foreach (var filename in filenames)
            {
                var upload = await storage.GenerateUploadUrlAsync(sessionId, filename, CancellationToken.None);
                using var http = new HttpClient();
                using var put = new HttpRequestMessage(HttpMethod.Put, upload.UploadUrl)
                {
                    Content = new ByteArrayContent("x"u8.ToArray())
                };
                using var resp = await http.SendAsync(put, CancellationToken.None);
                resp.EnsureSuccessStatusCode();
            }

            await storage.DeleteSessionPrefixAsync(sessionId, CancellationToken.None);

            foreach (var filename in filenames)
            {
                (await storage.ObjectExistsAsync(sessionId, filename, CancellationToken.None)).Should().BeFalse();
            }
        }
        finally
        {
            await storage.DeleteSessionPrefixAsync(sessionId, CancellationToken.None);
        }
    }
}
