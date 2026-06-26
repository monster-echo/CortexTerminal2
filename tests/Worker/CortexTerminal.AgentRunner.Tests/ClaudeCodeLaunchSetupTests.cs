using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests;

/// <summary>
/// Verifies the Claude Code settings.json generator. The output merges Corterm hooks into the
/// user's existing settings (preserving their custom hooks) and wires each of the five hook
/// events to <c>corterm-agent hook claude-code</c>.
/// </summary>
public sealed class ClaudeCodeLaunchSetupTests
{
    [Fact]
    public void BuildSettingsJson_AddsAllFiveHookEvents()
    {
        var setup = new ClaudeCodeLaunchSetup("sess-1", "http://127.0.0.1:9999/agent-event");
        var userClaudeDir = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "no-such-user-claude-" + Guid.NewGuid().ToString("N"))).FullName;

        var json = setup.BuildSettingsJson(userClaudeDir);
        var root = JsonNode.Parse(json)!.AsObject();
        var hooks = root["hooks"]!.AsObject();

        var expected = new[] { "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop" };
        foreach (var evt in expected)
        {
            var arr = hooks[evt]!.AsArray();
            arr.Count.Should().BeGreaterThan(0);
            var matcher = arr[0]!.AsObject()["matcher"]!.GetValue<string>();
            matcher.Should().Be("*");
            var cmd = arr[0]!.AsObject()["hooks"]!.AsArray()[0]!.AsObject()["command"]!.GetValue<string>();
            cmd.Should().Contain("hook");
            cmd.Should().Contain("claude-code");
        }
    }

    [Fact]
    public void BuildSettingsJson_PreservesUserHooksAndAppendsOurs()
    {
        var userClaudeDir = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "claude-user-" + Guid.NewGuid().ToString("N"))).FullName;
        var userSettings = Path.Combine(userClaudeDir, "settings.json");
        const string userContent = """
            {
              "permissions": { "allow": ["Bash(ls:*)"] },
              "hooks": {
                "SessionStart": [
                  {
                    "matcher": "*",
                    "hooks": [{ "type": "command", "command": "echo user-hook" }]
                  }
                ]
              }
            }
            """;
        File.WriteAllText(userSettings, userContent);

        try
        {
            var setup = new ClaudeCodeLaunchSetup("sess-1", "http://127.0.0.1:9999/agent-event");
            var json = setup.BuildSettingsJson(userClaudeDir);

            var root = JsonNode.Parse(json)!.AsObject();
            root["permissions"]!.AsObject()["allow"]!.AsArray()[0]!.GetValue<string>().Should().Be("Bash(ls:*)");

            var sessionStartArr = root["hooks"]!["SessionStart"]!.AsArray();
            // Should have user's hook + our hook
            sessionStartArr.Count.Should().BeGreaterThanOrEqualTo(2);
            var commands = sessionStartArr
                .Select(e => e!["hooks"]!.AsArray()[0]!["command"]!.GetValue<string>())
                .ToArray();
            commands.Should().Contain(c => c.Contains("echo user-hook"));
            commands.Should().Contain(c => c.Contains("claude-code"));
        }
        finally
        {
            try { Directory.Delete(userClaudeDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void BuildSettingsJson_HandlesMissingUserSettings()
    {
        var userClaudeDir = Path.Combine(Path.GetTempPath(), "claude-missing-" + Guid.NewGuid().ToString("N"));

        var setup = new ClaudeCodeLaunchSetup("sess-1", "http://127.0.0.1:9999/agent-event");
        var json = setup.BuildSettingsJson(userClaudeDir);

        var root = JsonNode.Parse(json)!.AsObject();
        root["hooks"]!.AsObject().Count.Should().Be(5);
    }

    [Fact]
    public void BuildSettingsJson_RecoversFromMalformedUserSettings()
    {
        var userClaudeDir = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "claude-broken-" + Guid.NewGuid().ToString("N"))).FullName;
        File.WriteAllText(Path.Combine(userClaudeDir, "settings.json"), "{ not valid json");

        try
        {
            var setup = new ClaudeCodeLaunchSetup("sess-1", "http://127.0.0.1:9999/agent-event");
            var json = setup.BuildSettingsJson(userClaudeDir);

            var root = JsonNode.Parse(json)!.AsObject();
            root["hooks"]!.AsObject().Count.Should().Be(5);
        }
        finally
        {
            try { Directory.Delete(userClaudeDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Prepare_CreatesTempDirWithSettingsFile()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var sessionId = "test-sess-" + Guid.NewGuid().ToString("N");
        var expectedTempDir = Path.Combine(home, ".corterm", "agent-hooks", sessionId);

        try
        {
            var setup = new ClaudeCodeLaunchSetup(sessionId, "http://127.0.0.1:9999/agent-event");
            var result = setup.Prepare();

            result.TempConfigDir.Should().Be(expectedTempDir);
            File.Exists(Path.Combine(result.TempConfigDir, "settings.json")).Should().BeTrue();
            result.EnvironmentVariables.Should().ContainKey("CLAUDE_CONFIG_DIR");
            result.EnvironmentVariables["CLAUDE_CONFIG_DIR"].Should().Be(expectedTempDir);
        }
        finally
        {
            try { if (Directory.Exists(expectedTempDir)) Directory.Delete(expectedTempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Constructor_RejectsEmptySessionId()
    {
        var act = () => new ClaudeCodeLaunchSetup("", "http://127.0.0.1:9999/agent-event");
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Constructor_RejectsEmptyHookUrl()
    {
        var act = () => new ClaudeCodeLaunchSetup("sess-1", "");
        act.Should().Throw<ArgumentException>();
    }
}
