using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Gateway.Storage;

public sealed class S3ObjectBroker : IS3ObjectBroker
{
    private readonly IAmazonS3 _client;
    private readonly ObjectStorageOptions _options;
    private readonly Protocol _protocol;

    public S3ObjectBroker(IOptions<ObjectStorageOptions> options)
        : this(options.Value, CreateClient(options.Value))
    {
    }

    // Test entry point: inject a (mocked) IAmazonS3 so unit tests don't need a real S3 endpoint.
    internal S3ObjectBroker(ObjectStorageOptions options, IAmazonS3 client)
    {
        _options = options;
        _client = client;
        // Honor the endpoint scheme so http:// MinIO/local-dev returns http:// presigned URLs.
        // The SDK defaults to HTTPS, which produces mixed-content / connection-refused failures
        // when clients PUT to a plain-HTTP S3 endpoint.
        _protocol = !string.IsNullOrWhiteSpace(options.Endpoint)
                    && options.Endpoint.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            ? Protocol.HTTP
            : Protocol.HTTPS;
    }

    private static IAmazonS3 CreateClient(ObjectStorageOptions options)
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

    public async Task<PresignedUrl> GeneratePutUrlAsync(string key, CancellationToken ct)
    {
        var expires = DateTime.UtcNow.Add(_options.PresignedUrlTtl);
        var url = await _client.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            Verb = HttpVerb.PUT,
            Protocol = _protocol,
            Expires = expires,
        });
        return new PresignedUrl(url, expires);
    }

    public async Task<PresignedUrl> GenerateGetUrlAsync(string key, CancellationToken ct)
    {
        var expires = DateTime.UtcNow.Add(_options.PresignedUrlTtl);
        var url = await _client.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            Verb = HttpVerb.GET,
            Protocol = _protocol,
            Expires = expires,
        });
        return new PresignedUrl(url, expires);
    }

    public async Task DeleteAsync(string key, CancellationToken ct)
    {
        await _client.DeleteObjectAsync(new DeleteObjectRequest
        {
            BucketName = _options.Bucket,
            Key = key,
        }, ct);
    }

    public async Task<IReadOnlyList<StoredObject>> ListByPrefixAsync(string prefix, CancellationToken ct)
    {
        var results = new List<StoredObject>();
        string? continuationToken = null;
        do
        {
            var listResponse = await _client.ListObjectsV2Async(new ListObjectsV2Request
            {
                BucketName = _options.Bucket,
                Prefix = prefix,
                ContinuationToken = continuationToken,
            }, ct);

            foreach (var obj in listResponse.S3Objects ?? [])
            {
                var lastModified = obj.LastModified
                    ?? throw new InvalidOperationException($"S3 object {obj.Key} has no LastModified timestamp.");
                results.Add(new StoredObject(obj.Key, new DateTimeOffset(lastModified)));
            }
            continuationToken = listResponse.IsTruncated == true ? listResponse.NextContinuationToken : null;
        } while (continuationToken is not null);

        return results;
    }
}
