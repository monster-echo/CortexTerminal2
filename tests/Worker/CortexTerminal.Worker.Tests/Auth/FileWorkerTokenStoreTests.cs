using System.Reflection;
using CortexTerminal.Worker.Auth;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.Auth;

public sealed class FileWorkerTokenStoreTests : IDisposable
{
    private readonly string _tempDir;
    private readonly FileWorkerTokenStore _store;

    public FileWorkerTokenStoreTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"worker-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        _store = new FileWorkerTokenStore(_tempDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, true);
    }

    [Fact]
    public async Task GetAccessTokenAsync_NoFile_ReturnsNull()
    {
        var token = await _store.GetAccessTokenAsync(CancellationToken.None);

        token.Should().BeNull();
    }

    [Fact]
    public async Task SaveAndGetAccessToken_RoundTrips()
    {
        const string jwt = "eyJhbGciOiJIUzI1NiJ9.test-payload.test-signature";

        await _store.SaveAccessTokenAsync(jwt, CancellationToken.None);
        var result = await _store.GetAccessTokenAsync(CancellationToken.None);

        result.Should().Be(jwt);
    }

    [Fact]
    public async Task SaveAccessToken_CreatesFileWithContent()
    {
        await _store.SaveAccessTokenAsync("my-token", CancellationToken.None);

        var filePath = Path.Combine(_tempDir, ".auth");
        File.Exists(filePath).Should().BeTrue();
        (await File.ReadAllTextAsync(filePath)).Should().Be("my-token");
    }

    [Fact]
    public async Task Clear_DeletesFile()
    {
        await _store.SaveAccessTokenAsync("token", CancellationToken.None);
        await _store.ClearAsync(CancellationToken.None);

        var filePath = Path.Combine(_tempDir, ".auth");
        File.Exists(filePath).Should().BeFalse();
    }

    [Fact]
    public async Task Clear_WhenNoFile_DoesNotThrow()
    {
        var act = () => _store.ClearAsync(CancellationToken.None);

        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task SaveAccessToken_OverwritesExisting()
    {
        await _store.SaveAccessTokenAsync("old-token", CancellationToken.None);
        await _store.SaveAccessTokenAsync("new-token", CancellationToken.None);

        var result = await _store.GetAccessTokenAsync(CancellationToken.None);
        result.Should().Be("new-token");
    }
}
