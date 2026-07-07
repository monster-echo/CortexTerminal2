using CortexTerminal.Worker.Agent;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Agent;

/// <summary>
/// The installer must (a) merge the codex section idempotently without clobbering the user's own
/// AGENTS.md, (b) write cache + agent-global files atomically enough that a reinstall is a no-op
/// for unchanged content, and (c) let the startup fast-path install straight from cache. All paths
/// derive from an injected temp HOME so the suite never touches the real user profile.
/// </summary>
public sealed class AgentSkillInstallerTests
{
    [Fact]
    public void MergeCodexSection_NoMarkers_AppendsSectionAfterUserContent()
    {
        var existing = "# my repo\n\nDo good things.\n";

        var merged = AgentSkillInstaller.MergeCodexSection(existing, "RULES");

        merged.Should().Contain("# my repo").And.Contain("Do good things.").And.Contain("RULES");
        merged.Should().Contain(AgentSkillInstaller.CodexBeginMarker).And.Contain(AgentSkillInstaller.CodexEndMarker);
        merged.IndexOf("# my repo", StringComparison.Ordinal)
            .Should().BeLessThan(merged.IndexOf(AgentSkillInstaller.CodexBeginMarker, StringComparison.Ordinal));
    }

    [Fact]
    public void MergeCodexSection_ExistingMarkers_ReplacesContentBetween()
    {
        var existing = $"preamble\n\n{AgentSkillInstaller.CodexBeginMarker}\nOLD\n{AgentSkillInstaller.CodexEndMarker}\n\nepilogue\n";

        var merged = AgentSkillInstaller.MergeCodexSection(existing, "NEW");

        merged.Should().Contain("preamble").And.Contain("epilogue");
        merged.Should().Contain("NEW").And.NotContain("OLD");
        merged.Split(AgentSkillInstaller.CodexBeginMarker, StringSplitOptions.None).Length.Should().Be(2);
    }

    [Fact]
    public void MergeCodexSection_EmptyExisting_ReturnsBareSectionWithTrailingNewline()
    {
        AgentSkillInstaller.MergeCodexSection("", "RULES")
            .Should().Be($"{AgentSkillInstaller.CodexBeginMarker}\nRULES\n{AgentSkillInstaller.CodexEndMarker}\n");
    }

    [Fact]
    public async Task SaveCacheAndInstallAsync_WritesCacheAndInstallsToBothAgentLocations()
    {
        using var home = new TempHome();
        var installer = new AgentSkillInstaller(NullLogger<AgentSkillInstaller>.Instance, home.Path);

        await installer.SaveCacheAndInstallAsync("# skill\n", "codex body", CancellationToken.None);

        (await File.ReadAllTextAsync(Path.Combine(installer.CacheDir, "SKILL.md"))).Should().Be("# skill\n");
        (await File.ReadAllTextAsync(Path.Combine(installer.CacheDir, "CODEX.md"))).Should().Be("codex body");
        File.Exists(Path.Combine(installer.CacheDir, ".sha256")).Should().BeTrue();

        var claudeSkill = Path.Combine(installer.ClaudeSkillDir, "SKILL.md");
        File.Exists(claudeSkill).Should().BeTrue();
        (await File.ReadAllTextAsync(claudeSkill)).Should().Be("# skill\n");

        var codex = await File.ReadAllTextAsync(installer.CodexAgentsPath);
        codex.Should().Contain(AgentSkillInstaller.CodexBeginMarker).And.Contain("codex body").And.Contain(AgentSkillInstaller.CodexEndMarker);
    }

    [Fact]
    public async Task SaveCacheAndInstallAsync_Twice_PreservesUserCodexContentAndStaysIdempotent()
    {
        using var home = new TempHome();
        var installer = new AgentSkillInstaller(NullLogger<AgentSkillInstaller>.Instance, home.Path);
        Directory.CreateDirectory(Path.GetDirectoryName(installer.CodexAgentsPath)!);
        await File.WriteAllTextAsync(installer.CodexAgentsPath, "# my codex rules\n\nBe concise.\n");

        await installer.SaveCacheAndInstallAsync("skill v1", "codex v1", CancellationToken.None);
        await installer.SaveCacheAndInstallAsync("skill v2", "codex v2", CancellationToken.None);

        var codex = await File.ReadAllTextAsync(installer.CodexAgentsPath);
        codex.Should().Contain("# my codex rules").And.Contain("Be concise.");      // user content survives
        codex.Should().Contain("codex v2").And.NotContain("codex v1");             // latest wins
        codex.Split(AgentSkillInstaller.CodexBeginMarker, StringSplitOptions.None).Length.Should().Be(2); // no dup
    }

    [Fact]
    public async Task InstallFromCacheAsync_NoCache_ReturnsFalse()
    {
        using var home = new TempHome();
        var installer = new AgentSkillInstaller(NullLogger<AgentSkillInstaller>.Instance, home.Path);

        (await installer.InstallFromCacheAsync(CancellationToken.None)).Should().BeFalse();
        Directory.Exists(installer.ClaudeSkillDir).Should().BeFalse();
    }

    [Fact]
    public async Task InstallFromCacheAsync_WithCache_ReinstallsAndReturnsTrue()
    {
        using var home = new TempHome();
        var installer = new AgentSkillInstaller(NullLogger<AgentSkillInstaller>.Instance, home.Path);
        await installer.SaveCacheAndInstallAsync("cached skill", "cached codex", CancellationToken.None);
        // Simulate a fresh agent profile: wipe the agent-global files but keep the cache.
        if (Directory.Exists(installer.ClaudeSkillDir)) Directory.Delete(installer.ClaudeSkillDir, recursive: true);
        if (File.Exists(installer.CodexAgentsPath)) File.Delete(installer.CodexAgentsPath);

        (await installer.InstallFromCacheAsync(CancellationToken.None)).Should().BeTrue();
        File.Exists(Path.Combine(installer.ClaudeSkillDir, "SKILL.md")).Should().BeTrue();
        (await File.ReadAllTextAsync(installer.CodexAgentsPath)).Should().Contain("cached codex");
    }

    private sealed class TempHome : IDisposable
    {
        public string Path { get; }
        public TempHome()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "corterm-home-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path);
        }
        public void Dispose()
        {
            try { if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true); } catch { }
        }
    }
}
