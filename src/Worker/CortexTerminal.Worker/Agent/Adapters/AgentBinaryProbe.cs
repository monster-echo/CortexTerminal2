namespace CortexTerminal.Worker.Agent.Adapters;

/// <summary>
/// Scans a PATH-style string for an executable. Used by adapters to locate the real
/// agent binary on the worker side. Mirrors the resolution logic in the wrapper's
/// <c>AgentBinaryResolver</c>, but kept here so adapters don't depend on the wrapper assembly.
/// </summary>
internal static class AgentBinaryProbe
{
    public static string? FindOnPath(string binaryName, string? path)
    {
        if (string.IsNullOrEmpty(path)) return null;
        var separator = OperatingSystem.IsWindows() ? ';' : ':';
        var names = OperatingSystem.IsWindows()
            ? new[] { binaryName + ".exe", binaryName + ".cmd", binaryName + ".bat" }
            : new[] { binaryName };

        foreach (var dir in path.Split(separator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var name in names)
            {
                var candidate = Path.Combine(dir, name);
                if (!File.Exists(candidate)) continue;
                if (!OperatingSystem.IsWindows())
                {
                    try
                    {
                        var mode = File.GetUnixFileMode(candidate);
                        if ((mode & UnixFileMode.UserExecute) == 0) continue;
                    }
                    catch (UnauthorizedAccessException)
                    {
                        continue;
                    }
                }
                return candidate;
            }
        }
        return null;
    }
}
