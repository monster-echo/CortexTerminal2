namespace CortexTerminal.Worker.Auth;

public sealed class FileWorkerTokenStore : IWorkerTokenStore
{
    private readonly string _tokenFilePath;

    public FileWorkerTokenStore(string installDir)
    {
        _tokenFilePath = Path.Combine(installDir, ".auth");
    }

    public async Task<string?> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_tokenFilePath)) return null;
        var content = await File.ReadAllTextAsync(_tokenFilePath, cancellationToken);
        return content.Trim();
    }

    public async Task SaveAccessTokenAsync(string accessToken, CancellationToken cancellationToken)
    {
        await File.WriteAllTextAsync(_tokenFilePath, accessToken, cancellationToken);
        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(_tokenFilePath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
    }

    public Task ClearAsync(CancellationToken cancellationToken)
    {
        if (File.Exists(_tokenFilePath))
            File.Delete(_tokenFilePath);
        return Task.CompletedTask;
    }
}
