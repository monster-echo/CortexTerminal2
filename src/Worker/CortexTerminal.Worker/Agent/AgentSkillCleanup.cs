using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// One-time migration cleanup, run at every worker startup (cheap no-op once done):
/// removes the prompt-injection leftovers of the retired corterm-artifacts skill — the
/// installed copy Claude Code would still auto-discover, the codex AGENTS.md section, the
/// local skill cache, and the legacy per-session artifacts tree. Without the cleanup, a
/// worker upgraded past the skill's removal would keep injecting stale prompt content.
/// </summary>
/// <remarks>
/// Data-migration semantics apply: each step logs and continues on failure rather than
/// failing the worker — unlike product logic, a leftover file must not block startup.
/// </remarks>
internal static class AgentSkillCleanup
{
    internal const string SkillName = "corterm-artifacts";
    internal const string CodexBeginMarker = "<!-- BEGIN corterm -->";
    internal const string CodexEndMarker = "<!-- END corterm -->";

    public static Task RunOnceAsync(ILogger logger, CancellationToken ct)
        => Task.Run(() =>
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

            TryDeleteDir(logger, Path.Combine(home, ".claude", "skills", SkillName), "installed Claude Code skill dir");
            TryDeleteDir(logger, Path.Combine(home, ".corterm", "skill-cache", SkillName), "skill cache dir");
            TryDeleteDir(logger, Path.Combine(home, ".corterm", "sessions"), "legacy per-session artifacts tree");
            TryStripCodexSection(logger, Path.Combine(home, ".codex", "AGENTS.md"));
        }, ct);

    private static void TryDeleteDir(ILogger logger, string path, string description)
    {
        try
        {
            if (!Directory.Exists(path)) return;
            Directory.Delete(path, recursive: true);
            logger.LogInformation("Removed retired {Description} at {Path}.", description, path);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Could not remove retired {Description} at {Path}.", description, path);
        }
    }

    private static void TryStripCodexSection(ILogger logger, string agentsPath)
    {
        try
        {
            if (!File.Exists(agentsPath)) return;
            var existing = File.ReadAllText(agentsPath);
            var beginIdx = existing.IndexOf(CodexBeginMarker, StringComparison.Ordinal);
            var endIdx = existing.IndexOf(CodexEndMarker, StringComparison.Ordinal);
            if (beginIdx < 0 || endIdx <= beginIdx) return;

            var before = existing[..beginIdx].Trim('\n', '\r', ' ');
            var after = existing[(endIdx + CodexEndMarker.Length)..].Trim('\n', '\r', ' ');
            var stripped = before.Length > 0 && after.Length > 0 ? before + "\n\n" + after + "\n"
                : before.Length > 0 ? before + "\n"
                : after.Length > 0 ? after + "\n"
                : string.Empty;

            if (stripped.Length == 0)
            {
                File.Delete(agentsPath);
                logger.LogInformation("Removed retired codex instructions file (empty after strip) at {Path}.", agentsPath);
                return;
            }

            File.WriteAllText(agentsPath, stripped);
            logger.LogInformation("Stripped retired corterm section from {Path}.", agentsPath);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Could not strip the retired corterm section from {Path}.", agentsPath);
        }
    }
}
