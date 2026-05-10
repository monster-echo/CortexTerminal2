namespace CortexTerminal.Gateway.Workers;

public static class WorkerReleaseAsset
{
    public static string GetAssetName(string? operatingSystem, string? architecture)
    {
        var ridOs = operatingSystem != null && operatingSystem.Contains("Darwin", StringComparison.OrdinalIgnoreCase) ? "osx"
            : operatingSystem != null && operatingSystem.Contains("Windows", StringComparison.OrdinalIgnoreCase) ? "win"
            : "linux";
        var ridArch = string.Equals(architecture, "Arm64", StringComparison.OrdinalIgnoreCase) ? "arm64" : "x64";
        var ext = ridOs == "win" ? "zip" : "tar.gz";
        return $"corterm-{ridOs}-{ridArch}.{ext}";
    }
}
