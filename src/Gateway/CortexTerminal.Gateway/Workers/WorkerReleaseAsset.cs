namespace CortexTerminal.Gateway.Workers;

public static class WorkerReleaseAsset
{
    public static string GetAssetName(string? operatingSystem, string? architecture)
    {
        if (operatingSystem is null)
            throw new InvalidOperationException("Cannot determine release asset: worker OS metadata is missing.");

        var ridOs = operatingSystem.Contains("Darwin", StringComparison.OrdinalIgnoreCase)
            || operatingSystem.Contains("macOS", StringComparison.OrdinalIgnoreCase) ? "osx"
            : operatingSystem.Contains("Windows", StringComparison.OrdinalIgnoreCase) ? "win"
            : IsLinuxDistro(operatingSystem) ? "linux"
            : throw new InvalidOperationException($"Unsupported OS: '{operatingSystem}'. Cannot determine release asset.");
        var ridArch = string.Equals(architecture, "Arm64", StringComparison.OrdinalIgnoreCase) ? "arm64" : "x64";
        var ext = ridOs == "win" ? "zip" : "tar.gz";
        return $"corterm-{ridOs}-{ridArch}.{ext}";
    }

    private static readonly string[] LinuxIdentifiers = ["Linux", "Ubuntu", "Debian", "CentOS", "Fedora", "Alpine", "Arch", "Amazon", "SUSE", "Red Hat"];

    private static bool IsLinuxDistro(string operatingSystem)
    {
        foreach (var id in LinuxIdentifiers)
        {
            if (operatingSystem.Contains(id, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }
}
