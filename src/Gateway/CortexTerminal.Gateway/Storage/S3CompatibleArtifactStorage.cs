using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using CortexTerminal.Contracts.Sessions;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Gateway.Storage;

public sealed class S3CompatibleArtifactStorage : IArtifactStorage
{
    private readonly IAmazonS3 _client;
    private readonly ArtifactStorageOptions _options;
    private readonly Protocol _protocol;

    public S3CompatibleArtifactStorage(IOptions<ArtifactStorageOptions> options)
        : this(options.Value, CreateClient(options.Value))
    {
    }

    // Test entry point: inject a (mocked) IAmazonS3 so unit tests don't need a real S3 endpoint.
    internal S3CompatibleArtifactStorage(ArtifactStorageOptions options, IAmazonS3 client)
    {
        _options = options;
        _client = client;
        // Honor the endpoint scheme so http:// MinIO/local-dev returns http:// presigned URLs.
        // The SDK defaults to HTTPS, which produces mixed-content / connection-refused failures
        // when the browser Console PUTs to a plain-HTTP S3 endpoint.
        _protocol = !string.IsNullOrWhiteSpace(options.Endpoint)
                    && options.Endpoint.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            ? Protocol.HTTP
            : Protocol.HTTPS;
    }

    private static IAmazonS3 CreateClient(ArtifactStorageOptions options)
    {
        var creds = new BasicAWSCredentials(options.AccessKey, options.SecretKey);
        var config = new AmazonS3Config
        {
            RegionEndpoint = Amazon.RegionEndpoint.GetBySystemName(options.Region),
            ForcePathStyle = options.ForcePathStyle,
        };
        if (!string.IsNullOrWhiteSpace(options.Endpoint))
        {
            config.ServiceURL = options.Endpoint;
        }
        return new AmazonS3Client(creds, config);
    }

    public async Task<UploadUrlResponse> GenerateUploadUrlAsync(string sessionId, string filename, CancellationToken ct)
    {
        var key = BuildKey(sessionId, filename);
        var expires = DateTime.UtcNow.Add(_options.PresignedUrlTtl);
        var url = await _client.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            Verb = HttpVerb.PUT,
            Protocol = _protocol,
            Expires = expires,
        });
        return new UploadUrlResponse(Guid.NewGuid().ToString("N"), url, key, expires);
    }

    public async Task<DownloadUrlResponse> GenerateDownloadUrlAsync(string sessionId, string filename, CancellationToken ct)
    {
        var key = BuildKey(sessionId, filename);
        var expires = DateTime.UtcNow.Add(_options.PresignedUrlTtl);
        var url = await _client.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            Verb = HttpVerb.GET,
            Protocol = _protocol,
            Expires = expires,
        });
        return new DownloadUrlResponse(url, expires);
    }

    public async Task DeleteObjectAsync(string sessionId, string filename, CancellationToken ct)
    {
        var key = BuildKey(sessionId, filename);
        await _client.DeleteObjectAsync(new DeleteObjectRequest
        {
            BucketName = _options.Bucket,
            Key = key,
        }, ct);
    }

    public async Task DeleteSessionPrefixAsync(string sessionId, CancellationToken ct)
    {
        var listResponse = await _client.ListObjectsV2Async(new ListObjectsV2Request
        {
            BucketName = _options.Bucket,
            Prefix = $"{sessionId}/",
        }, ct);

        if (listResponse.S3Objects is null || listResponse.S3Objects.Count == 0) return;

        foreach (var obj in listResponse.S3Objects)
        {
            await _client.DeleteObjectAsync(new DeleteObjectRequest
            {
                BucketName = _options.Bucket,
                Key = obj.Key,
            }, ct);
        }
    }

    public async Task<long> GetObjectSizeAsync(string sessionId, string filename, CancellationToken ct)
    {
        var key = BuildKey(sessionId, filename);
        var resp = await _client.GetObjectMetadataAsync(new GetObjectMetadataRequest
        {
            BucketName = _options.Bucket,
            Key = key,
        }, ct);
        return resp.ContentLength;
    }

    public async Task<bool> ObjectExistsAsync(string sessionId, string filename, CancellationToken ct)
    {
        try
        {
            await GetObjectSizeAsync(sessionId, filename, ct);
            return true;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return false;
        }
    }

    private static string BuildKey(string sessionId, string filename) => $"{sessionId}/{filename}";
}
