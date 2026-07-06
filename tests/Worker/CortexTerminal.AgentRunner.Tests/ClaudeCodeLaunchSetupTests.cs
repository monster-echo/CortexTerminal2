using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests;

/// <summary>
/// Verifies ClaudeCodeLaunchSetup generates a hook-only settings.json and injects it via
/// the <c>--settings</c> passthrough arg. We deliberately do NOT merge user settings here —
/// Claude Code treats <c>--settings</c> as additional layered on top of the user's own
/// <c>~/.claude/settings.json</c>, so user hooks/permissions are preserved by Claude Code
/// itself.
/// </summary>
public sealed class ClaudeCodeLaunchSetupTests
{
    [Fact]
    public void BuildSettingsJson_AddsAllNineHookEvents()
    {
        var setup = new ClaudeCodeLaunchSetup("sess-1");

        var json = setup.BuildSettingsJson();
        var root = JsonNode.Parse(json)!.AsObject();
        var hooks = root["hooks"]!.AsObject();

        var expected = new[] { "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SubagentStop", "Notification", "PreCompact" };
        foreach (var evt in expected)
        {
            var arr = hooks[evt]!.AsArray();
            arr.Count.Should().Be(1);
            var matcher = arr[0]!.AsObject()["matcher"]!.GetValue<string>();
            matcher.Should().Be("*");
            var cmd = arr[0]!.AsObject()["hooks"]!.AsArray()[0]!.AsObject()["command"]!.GetValue<string>();
            cmd.Should().Contain("hook claude");
            cmd.Should().NotContain("claude-code", "cortap uses short kind 'claude'; HookForwarder maps it to the envelope kind");
        }
    }

    [Fact]
    public void BuildSettingsJson_ContainsOnlyHooks_NoUserSettingsMerge()
    {
        // We layer on top of user settings via --settings; we do not merge. So our
        // settings.json should contain ONLY the hooks key — no permissions, no env, etc.
        var setup = new ClaudeCodeLaunchSetup("sess-1");

        var json = setup.BuildSettingsJson();
        var root = JsonNode.Parse(json)!.AsObject();

        root.Count.Should().Be(1);
        root.ContainsKey("hooks").Should().BeTrue();
    }

    [Fact]
    public void BuildSettingsJson_NoMcpUrl_OmitsMcpServers()
    {
        // Backward compatibility: when no MCP URL is supplied (older wrapper build, or non-claude
        // kinds in the future), settings.json should NOT mention mcpServers or permissions.
        var setup = new ClaudeCodeLaunchSetup("sess-1");

        var json = setup.BuildSettingsJson();
        var root = JsonNode.Parse(json)!.AsObject();

        root.ContainsKey("mcpServers").Should().BeFalse();
        root.ContainsKey("permissions").Should().BeFalse();
    }

    [Fact]
    public void BuildSettingsJson_WithMcpUrl_AddsCortermHttpServerAndAutoApproval()
    {
        var setup = new ClaudeCodeLaunchSetup("sess-1", mcpUrl: "http://127.0.0.1:54321/mcp");

        var json = setup.BuildSettingsJson();
        var root = JsonNode.Parse(json)!.AsObject();

        var mcp = root["mcpServers"]!.AsObject();
        var corterm = mcp["corterm"]!.AsObject();
        corterm["type"]!.GetValue<string>().Should().Be("http");
        corterm["url"]!.GetValue<string>().Should().Be("http://127.0.0.1:54321/mcp");

        var allow = root["permissions"]!["allow"]!.AsArray();
        allow.Select(n => n!.GetValue<string>())
            .Should().Contain("mcp__corterm__change_title");
    }

    [Fact]
    public void Prepare_ReturnsSettingsPathInPassthroughArgs()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var sessionId = "test-sess-" + Guid.NewGuid().ToString("N");
        var expectedTempDir = Path.Combine(home, ".corterm", "agent-hooks", sessionId);

        try
        {
            var setup = new ClaudeCodeLaunchSetup(sessionId);
            var result = setup.Prepare();

            result.TempConfigDir.Should().Be(expectedTempDir);
            var settingsPath = Path.Combine(result.TempConfigDir, "settings.json");
            File.Exists(settingsPath).Should().BeTrue();

            result.PassthroughArgs.Should().ContainInOrder("--settings", settingsPath);
            result.EnvironmentVariables.Should().BeEmpty();
        }
        finally
        {
            try { if (Directory.Exists(expectedTempDir)) Directory.Delete(expectedTempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Prepare_DoesNotSetClaudeConfigDir()
    {
        // Critical regression guard: we must NOT set CLAUDE_CONFIG_DIR, or Claude Code will
        // treat the temp dir as a fresh install (numStartups reset, theme picker, login
        // state lost, "Claude configuration file not found" spam).
        var sessionId = "test-sess-" + Guid.NewGuid().ToString("N");
        var expectedTempDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".corterm", "agent-hooks", sessionId);

        try
        {
            var setup = new ClaudeCodeLaunchSetup(sessionId);
            var result = setup.Prepare();

            result.EnvironmentVariables.Should().NotContainKey("CLAUDE_CONFIG_DIR");
        }
        finally
        {
            try { if (Directory.Exists(expectedTempDir)) Directory.Delete(expectedTempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Constructor_RejectsEmptySessionId()
    {
        var act = () => new ClaudeCodeLaunchSetup("");
        act.Should().Throw<ArgumentException>();
    }
}
