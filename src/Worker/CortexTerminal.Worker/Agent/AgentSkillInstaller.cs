using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Caches the fetched skill content under <c>~/.corterm/skill-cache/corterm-artifacts/</c> and
/// installs it into the agent-global locations discovered at agent startup:
/// <list type="bullet">
/// <item><c>~/.claude/skills/corterm-artifacts/SKILL.md</c> — Claude Code personal scope
/// (auto-discovered at startup) and opencode (via its Claude Code compatibility fallback).</item>
/// <item><c>~/.codex/AGENTS.md</c> — codex global instructions. Merged as a marker-bounded
/// section so the user's own AGENTS.md content survives reinstalls.</item>
/// </list>
///
/// <para>All paths derive from a single home root (defaults to the user profile) so tests can
/// inject a temp HOME. Install steps are serialized — the startup fast-path and the background
/// sync service both call into here.</para>
/// </summary>
internal sealed class AgentSkillInstaller
{
    internal const string SkillName = "corterm-artifacts";
    internal const string CodexBeginMarker = "<!-- BEGIN corterm -->";
    internal const string CodexEndMarker = "<!-- END corterm -->";

    private readonly string _home;
    private readonly string _cacheDir;
    private readonly string _skillMdCachePath;
    private readonly string _codexMdCachePath;
    private readonly string _shaCachePath;
    private readonly ILogger<AgentSkillInstaller> _logger;
    private readonly SemaphoreSlim _installLock = new(1, 1);

    public AgentSkillInstaller(ILogger<AgentSkillInstaller> logger) : this(logger, home: null) { }

    /// <summary>Test hook: inject a temp HOME so the suite never touches the real user profile.</summary>
    internal AgentSkillInstaller(ILogger<AgentSkillInstaller> logger, string? home)
    {
        _logger = logger;
        _home = string.IsNullOrEmpty(home)
            ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            : home;
        _cacheDir = Path.Combine(_home, ".corterm", "skill-cache", SkillName);
        _skillMdCachePath = Path.Combine(_cacheDir, "SKILL.md");
        _codexMdCachePath = Path.Combine(_cacheDir, "CODEX.md");
        _shaCachePath = Path.Combine(_cacheDir, ".sha256");
    }

    internal string CacheDir => _cacheDir;
    internal string ClaudeSkillDir => Path.Combine(_home, ".claude", "skills", SkillName);
    internal string CodexAgentsPath => Path.Combine(_home, ".codex", "AGENTS.md");

    /// <summary>sha256 of the last successfully fetched skill content, or null if none cached.</summary>
    internal async Task<string?> GetCachedShaAsync(CancellationToken ct)
    {
        if (!File.Exists(_shaCachePath)) return null;
        return await File.ReadAllTextAsync(_shaCachePath, ct);
    }

    /// <summary>
    /// Install whatever is in the cache, if anything. No network — used at worker startup so the
    /// agent has its skill the moment the PTY is ready. Returns false if no cache exists yet
    /// (first run; the background sync service will populate it within seconds).
    /// </summary>
    public async Task<bool> InstallFromCacheAsync(CancellationToken ct)
    {
        if (!File.Exists(_skillMdCachePath) || !File.Exists(_codexMdCachePath)) return false;
        var skillMd = await File.ReadAllTextAsync(_skillMdCachePath, ct);
        var codexMd = await File.ReadAllTextAsync(_codexMdCachePath, ct);
        await InstallAsync(skillMd, codexMd, ct);
        _logger.LogInformation("Corterm agent skill installed from cache at {Dir}.", ClaudeSkillDir);
        return true;
    }

    /// <summary>Persist fetched content to the cache and (re)install into agent-global dirs.</summary>
    public async Task SaveCacheAndInstallAsync(string skillMd, string codexMd, CancellationToken ct)
    {
        Directory.CreateDirectory(_cacheDir);
        await File.WriteAllTextAsync(_skillMdCachePath, skillMd, ct);
        await File.WriteAllTextAsync(_codexMdCachePath, codexMd, ct);
        var sha = ComputeContentSha(skillMd, codexMd);
        await File.WriteAllTextAsync(_shaCachePath, sha, ct);
        await InstallAsync(skillMd, codexMd, ct);
        _logger.LogInformation("Corterm agent skill installed (sha {Sha}).", sha[..8]);
    }

    private async Task InstallAsync(string skillMd, string codexMd, CancellationToken ct)
    {
        await _installLock.WaitAsync(ct);
        try
        {
            Directory.CreateDirectory(ClaudeSkillDir);
            await File.WriteAllTextAsync(Path.Combine(ClaudeSkillDir, "SKILL.md"), skillMd, ct);

            Directory.CreateDirectory(Path.GetDirectoryName(CodexAgentsPath)!);
            var existing = File.Exists(CodexAgentsPath)
                ? await File.ReadAllTextAsync(CodexAgentsPath, ct)
                : string.Empty;
            var merged = MergeCodexSection(existing, codexMd);
            await File.WriteAllTextAsync(CodexAgentsPath, merged, ct);
        }
        finally
        {
            _installLock.Release();
        }
    }

    /// <summary>
    /// Replace the marker-bounded corterm section in <paramref name="existing"/> with
    /// <paramref name="codexMd"/>, or append the section if no markers are present yet. User
    /// content outside the markers is preserved verbatim, and blank-line spacing is normalized
    /// around the section so repeated reinstalls don't accumulate blank lines.
    /// </summary>
    internal static string MergeCodexSection(string existing, string codexMd)
    {
        var section = $"{CodexBeginMarker}\n{codexMd.Trim('\n', '\r', ' ')}\n{CodexEndMarker}";

        var beginIdx = existing.IndexOf(CodexBeginMarker, StringComparison.Ordinal);
        var endIdx = existing.IndexOf(CodexEndMarker, StringComparison.Ordinal);
        if (beginIdx >= 0 && endIdx > beginIdx)
        {
            var before = existing[..beginIdx];
            var afterEnd = endIdx + CodexEndMarker.Length;
            var after = afterEnd < existing.Length ? existing[afterEnd..] : string.Empty;
            return CombinePreservingUserContent(before, section, after);
        }

        if (string.IsNullOrWhiteSpace(existing)) return section + "\n";
        return CombinePreservingUserContent(existing, section, after: string.Empty);
    }

    private static string CombinePreservingUserContent(string before, string section, string after)
    {
        var sb = new StringBuilder();
        var leading = before.Trim('\n', '\r', ' ');
        if (leading.Length > 0) sb.Append(leading).Append("\n\n");
        sb.Append(section);
        var trailing = after.Trim('\n', '\r', ' ');
        if (trailing.Length > 0) sb.Append("\n\n").Append(trailing);
        sb.Append('\n');
        return sb.ToString();
    }

    /// <summary>Stable content hash used both for the cache record and change detection.</summary>
    internal static string ComputeContentSha(string skillMd, string codexMd)
    {
        using var sha = SHA256.Create();
        var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(skillMd + "\n" + codexMd));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
