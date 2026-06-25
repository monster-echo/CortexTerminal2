using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Storage;

namespace CortexTerminal.Gateway.Tests.Sessions.Fakes;

/// <summary>
/// In-memory IArtifactStorage fake. Records every presigned URL issued and every
/// object mutation. Tests seed object contents via <see cref="Seed"/> and assert
/// via <see cref="Objects"/> / <see cref="ObjectExists"/> / counter properties.
/// </summary>
internal sealed class FakeArtifactStorage : IArtifactStorage
{
    private readonly Dictionary<string, byte[]> _objects = new(StringComparer.Ordinal);
    private readonly Dictionary<string, long> _sizeOverrides = new(StringComparer.Ordinal);

    public IReadOnlyDictionary<string, byte[]> Objects => _objects;
    public int DeleteObjectCalls { get; private set; }
    public int DeletePrefixCalls { get; private set; }
    public int UploadUrlCalls { get; private set; }
    public int DownloadUrlCalls { get; private set; }

    public void Seed(string sessionId, string filename, byte[] content)
    {
        _objects[Key(sessionId, filename)] = content;
        _sizeOverrides.Remove(Key(sessionId, filename));
    }

    public void OverrideSize(string sessionId, string filename, long size)
    {
        _sizeOverrides[Key(sessionId, filename)] = size;
    }

    public bool ObjectExists(string sessionId, string filename)
        => _objects.ContainsKey(Key(sessionId, filename));

    public Task<UploadUrlResponse> GenerateUploadUrlAsync(string sessionId, string filename, CancellationToken ct)
    {
        UploadUrlCalls++;
        var key = Key(sessionId, filename);
        var artifactId = Guid.NewGuid().ToString("N");
        var url = $"https://fake-s3.local/{key}?sig=upload&aid={artifactId}";
        return Task.FromResult(new UploadUrlResponse(artifactId, url, key, DateTimeOffset.UtcNow.AddMinutes(15)));
    }

    public Task<DownloadUrlResponse> GenerateDownloadUrlAsync(string sessionId, string filename, CancellationToken ct)
    {
        DownloadUrlCalls++;
        var key = Key(sessionId, filename);
        return Task.FromResult(new DownloadUrlResponse(
            $"https://fake-s3.local/{key}?sig=download",
            DateTimeOffset.UtcNow.AddMinutes(15)));
    }

    public Task DeleteObjectAsync(string sessionId, string filename, CancellationToken ct)
    {
        DeleteObjectCalls++;
        _objects.Remove(Key(sessionId, filename));
        _sizeOverrides.Remove(Key(sessionId, filename));
        return Task.CompletedTask;
    }

    public Task DeleteSessionPrefixAsync(string sessionId, CancellationToken ct)
    {
        DeletePrefixCalls++;
        var prefix = $"{sessionId}/";
        var keys = _objects.Keys.Where(k => k.StartsWith(prefix, StringComparison.Ordinal)).ToList();
        foreach (var k in keys)
        {
            _objects.Remove(k);
            _sizeOverrides.Remove(k);
        }
        return Task.CompletedTask;
    }

    public Task<long> GetObjectSizeAsync(string sessionId, string filename, CancellationToken ct)
    {
        var key = Key(sessionId, filename);
        if (_sizeOverrides.TryGetValue(key, out var s)) return Task.FromResult(s);
        if (_objects.TryGetValue(key, out var bytes)) return Task.FromResult((long)bytes.Length);
        return Task.FromResult(0L);
    }

    public Task<bool> ObjectExistsAsync(string sessionId, string filename, CancellationToken ct)
        => Task.FromResult(_objects.ContainsKey(Key(sessionId, filename)));

    private static string Key(string sessionId, string filename) => $"{sessionId}/{filename}";
}
