namespace CortexTerminal.AgentRunner;

/// <summary>
/// Resolves which real agent binary to launch given the kind the shim was invoked as.
/// Walks <c>CORTERM_ORIGINAL_PATH</c> (set by the Worker to PATH minus the shims dir)
/// so the wrapper skips its own shim and finds the user-installed <c>claude</c>/<c>codex</c>/<c>opencode</c>.
/// </summary>
public static class AgentBinaryResolver
{
    public static readonly IReadOnlySet<string> SupportedKinds = new HashSet<string>(StringComparer.Ordinal)
    {
        "claude", "codex", "opencode",
    };

    /// <summary>
    /// Find the absolute path to the real agent binary, or null if not on <paramref name="originalPath"/>.
    /// On Unix, skips non-executable files. On Windows, considers .exe/.cmd/.bat/.ps1 extensions.
    /// </summary>
    public static string? Resolve(string kind, string? originalPath)
    {
        if (!SupportedKinds.Contains(kind)) return null;
        if (string.IsNullOrEmpty(originalPath)) return null;

        var separator = OperatingSystem.IsWindows() ? ';' : ':';
        var dirs = originalPath.Split(separator, StringSplitOptions.RemoveEmptyEntries);
        var names = GetCandidateNames(kind);

        foreach (var dir in dirs)
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

    /// <summary>Per-OS candidate filenames for the given agent kind. Order = preference.</summary>
    public static IReadOnlyList<string> GetCandidateNames(string kind)
    {
        var unix = kind switch
        {
            "claude" => new[] { "claude" },
            "codex" => new[] { "codex" },
            "opencode" => new[] { "opencode" },
            _ => Array.Empty<string>(),
        };
        var windows = kind switch
        {
            "claude" => new[] { "claude.exe", "claude.cmd", "claude.bat" },
            "codex" => new[] { "codex.exe", "codex.cmd", "codex.bat" },
            "opencode" => new[] { "opencode.exe", "opencode.cmd", "opencode.bat" },
            _ => Array.Empty<string>(),
        };
        return OperatingSystem.IsWindows() ? windows : unix;
    }

    public static string GetInstallHint(string kind) => kind switch
    {
        "claude" => "npm install -g @anthropic-ai/claude-code",
        "codex" => "npm install -g @openai/codex",
        "opencode" => "npm install -g opencode-ai",
        _ => $"install the '{kind}' agent",
    };
}
