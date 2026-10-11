using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner;
using CortexTerminal.Worker.Agent;
using Microsoft.Extensions.Logging;
using Xunit;

namespace CortexTerminal.Worker.Tests.Agent;

public sealed class ClaudeHooksInstallerTests : IDisposable
{
    private readonly string _installDir;
    private readonly string _homeDir;
    private readonly string _settingsPath;

    public ClaudeHooksInstallerTests()
    {
        _installDir = Directory.CreateTempSubdirectory("corterm-install-").FullName;
        _homeDir = Directory.CreateTempSubdirectory("corterm-home-").FullName;
        Directory.CreateDirectory(Path.Combine(_homeDir, ".claude"));
        _settingsPath = Path.Combine(_homeDir, ".claude", "settings.json");
    }

    public void Dispose()
    {
        Directory.Delete(_installDir, recursive: true);
        Directory.Delete(_homeDir, recursive: true);
    }

    private ClaudeHooksInstaller CreateInstaller(bool enabled = true)
        => new(_installDir, enabled, LoggerFactory.Create(_ => { }).CreateLogger<ClaudeHooksInstaller>(), _settingsPath);

    // ── merge: idempotent, preserves user hooks ──

    [Fact]
    public void Install_MergesHooksIntoExistingSettings_AndPreservesUserEntries()
    {
        File.WriteAllText(_settingsPath, """
            {
              "theme": "dark",
              "hooks": {
                "UserPromptSubmit": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "/usr/bin/my-own-hook" } ] }
                ]
              }
            }
            """);

        var installer = CreateInstaller();
        installer.MarkReady("http://127.0.0.1:51423/agent-event");

        var root = JsonNode.Parse(File.ReadAllText(_settingsPath))!.AsObject();
        Assert.Equal("dark", root["theme"]?.GetValue<string>());

        var userEntry = root["hooks"]!["UserPromptSubmit"]!.AsArray()
            .Single(e => e!["hooks"]!.AsArray()[0]!["command"]!.GetValue<string>() == "/usr/bin/my-own-hook");
        Assert.NotNull(userEntry);

        foreach (var evt in ClaudeHooksInstaller.HookEvents)
        {
            var entries = root["hooks"]![evt]!.AsArray();
            var managed = entries.OfType<JsonObject>().Where(ClaudeHooksInstallerTests.IsManaged).ToArray();
            Assert.Single(managed);
            Assert.Equal(evt, managed[0]["hooks"]!.AsArray()[0]!["command"]!.GetValue<string>().Split(' ').Last());
        }
    }

    [Fact]
    public void Install_IsIdempotent_NoDuplicateEntriesAndNoRewrite()
    {
        var installer = CreateInstaller();
        installer.MarkReady("http://127.0.0.1:51423/agent-event");
        var afterFirst = File.ReadAllText(_settingsPath);
        var mtimeAfterFirst = File.GetLastWriteTimeUtc(_settingsPath);

        installer.MarkReady("http://127.0.0.1:99999/agent-event");  // second startup, new port

        var root = JsonNode.Parse(File.ReadAllText(_settingsPath))!.AsObject();
        foreach (var evt in ClaudeHooksInstaller.HookEvents)
        {
            Assert.Single(root["hooks"]![evt]!.AsArray());
        }
        // Backup written once; content stable; no rewrite on the no-change second merge.
        Assert.False(File.Exists(_settingsPath + ".corterm-bak"));
        Assert.Equal(afterFirst, File.ReadAllText(_settingsPath));
        Assert.Equal(mtimeAfterFirst, File.GetLastWriteTimeUtc(_settingsPath));
    }

    [Fact]
    public void Install_CreatesSettingsFile_WhenMissing_AndWritesBackupOnFirstModify()
    {
        File.WriteAllText(_settingsPath, "{ \"theme\": \"light\" }");
        CreateInstaller().MarkReady("http://127.0.0.1:51423/agent-event");

        Assert.True(File.Exists(_settingsPath + ".corterm-bak"));
        Assert.Equal("{ \"theme\": \"light\" }", File.ReadAllText(_settingsPath + ".corterm-bak"));
        Assert.Equal("light", JsonNode.Parse(File.ReadAllText(_settingsPath))!["theme"]!.GetValue<string>());
    }

    [Fact]
    public void Install_WritesReporterScript_AndCommandPointsAtIt()
    {
        CreateInstaller().MarkReady("http://127.0.0.1:51423/agent-event");

        var reporter = Path.Combine(_installDir, ClaudeHooksInstaller.ReporterMarker + (OperatingSystem.IsWindows() ? ".cmd" : ""));
        Assert.True(File.Exists(reporter));
        if (!OperatingSystem.IsWindows())
        {
            Assert.Equal(UnixFileMode.UserExecute | UnixFileMode.UserWrite | UnixFileMode.UserRead
                | UnixFileMode.GroupExecute | UnixFileMode.GroupRead
                | UnixFileMode.OtherExecute | UnixFileMode.OtherRead, File.GetUnixFileMode(reporter));
        }

        var root = JsonNode.Parse(File.ReadAllText(_settingsPath))!.AsObject();
        var command = root["hooks"]!["UserPromptSubmit"]!.AsArray()[0]!["hooks"]!.AsArray()[0]!["command"]!.GetValue<string>();
        Assert.StartsWith(reporter, command, StringComparison.Ordinal);
        Assert.EndsWith("UserPromptSubmit", command, StringComparison.Ordinal);
    }

    [Fact]
    public void MarkReady_DisabledConfig_DoesNotInstallAnything()
    {
        var installer = CreateInstaller(enabled: false);
        installer.MarkReady("http://127.0.0.1:51423/agent-event");

        Assert.False(installer.Enabled);
        Assert.False(File.Exists(Path.Combine(_installDir, ClaudeHooksInstaller.ReporterMarker)));
        Assert.False(File.Exists(_settingsPath));
    }

    // ── removal path ──

    [Fact]
    public void RemoveInstalledHooks_StripsOnlyManagedEntries_KeepsUserConfig()
    {
        File.WriteAllText(_settingsPath, """
            {
              "theme": "dark",
              "hooks": {
                "UserPromptSubmit": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "/usr/bin/my-own-hook" } ] },
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "/opt/corterm/cortap-hook-reporter UserPromptSubmit" } ] }
                ],
                "SessionStart": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "/opt/corterm/cortap-hook-reporter SessionStart" } ] }
                ],
                "PreCompact": [
                  { "matcher": "*", "hooks": [ { "type": "command", "command": "/usr/bin/my-compact-hook" } ] }
                ]
              }
            }
            """);

        CreateInstaller().RemoveInstalledHooks();

        var root = JsonNode.Parse(File.ReadAllText(_settingsPath))!.AsObject();
        Assert.Equal("dark", root["theme"]?.GetValue<string>());
        var promptEntries = root["hooks"]!["UserPromptSubmit"]!.AsArray();
        Assert.Single(promptEntries);
        Assert.Equal("/usr/bin/my-own-hook", promptEntries[0]!["hooks"]!.AsArray()[0]!["command"]!.GetValue<string>());
        // Event array that only held managed entries is gone; user-only events survive.
        Assert.Null(root["hooks"]!["SessionStart"]);
        Assert.NotNull(root["hooks"]!["PreCompact"]);
    }

    [Fact]
    public void RemoveInstalledHooks_RemovesEmptyHooksKey_AndIsNoOpWithoutOurEntries()
    {
        File.WriteAllText(_settingsPath, "{ \"hooks\": { \"Stop\": [ { \"matcher\": \"*\", \"hooks\": [ { \"type\": \"command\", \"command\": \"/x/cortap-hook-reporter Stop\" } ] } ] } }");
        CreateInstaller().RemoveInstalledHooks();
        var root = JsonNode.Parse(File.ReadAllText(_settingsPath))!.AsObject();
        Assert.Null(root["hooks"]);

        // No-op second pass must not rewrite the file.
        var before = File.ReadAllText(_settingsPath);
        var mtime = File.GetLastWriteTimeUtc(_settingsPath);
        CreateInstaller().RemoveInstalledHooks();
        Assert.Equal(before, File.ReadAllText(_settingsPath));
        Assert.Equal(mtime, File.GetLastWriteTimeUtc(_settingsPath));
    }

    [Fact]
    public void RemoveInstalledHooks_IsNoOp_WhenSettingsFileMissing()
    {
        CreateInstaller().RemoveInstalledHooks();  // must not throw
        Assert.False(File.Exists(_settingsPath));
    }

    // ── legacy shim cleanup ──

    [Fact]
    public void CleanupLegacyShims_DeletesOnlyOwnShimNames()
    {
        var shimsDir = Path.Combine(_installDir, "shims");
        Directory.CreateDirectory(shimsDir);
        foreach (var name in new[] { "claude", "codex", "opencode", "claude.cmd", "codex.cmd", "opencode.cmd", "user-keep-me" })
        {
            File.WriteAllText(Path.Combine(shimsDir, name), "stale");
        }

        CreateInstaller().CleanupLegacyShims();

        Assert.False(File.Exists(Path.Combine(shimsDir, "claude")));
        Assert.False(File.Exists(Path.Combine(shimsDir, "codex")));
        Assert.False(File.Exists(Path.Combine(shimsDir, "opencode")));
        Assert.False(File.Exists(Path.Combine(shimsDir, "claude.cmd")));
        Assert.True(File.Exists(Path.Combine(shimsDir, "user-keep-me")));
    }

    [Fact]
    public void CleanupLegacyShims_IsNoOp_WhenShimsDirMissing()
    {
        CreateInstaller().CleanupLegacyShims();  // must not throw
    }

    // ── payload compatibility: reporter envelope == HookForwarder envelope ──

    [Theory]
    [InlineData("SessionStart")]
    [InlineData("UserPromptSubmit")]
    [InlineData("PreToolUse")]
    [InlineData("PostToolUse")]
    [InlineData("Notification")]
    [InlineData("Stop")]
    public void ReporterEnvelope_MatchesHookForwarderEnvelope(string eventType)
    {
        var rawPayload = """
            {
              "session_id": "agent-internal-id",
              "hook_event_name": "EVENT",
              "cwd": "/tmp/work",
              "prompt": "hello"
            }
            """.Replace("EVENT", eventType);

        // Reporter path: stdin wrapped by ClaudeHooksInstaller.BuildEnvelopeJson.
        var reporterEnvelope = JsonNode.Parse(
            ClaudeHooksInstaller.BuildEnvelopeJson(rawPayload, sessionId: "corterm-session-1", eventType: eventType))!.AsObject();

        // Old path: stdin fed to cortap hook claude → HookForwarder.BuildEnvelopeJson
        // (event_type derived from the payload's hook_event_name).
        var forwarderEnvelope = JsonNode.Parse(
            HookForwarder.BuildEnvelopeJson(rawPayload, sessionId: "corterm-session-1", kindName: "claude-code"))!.AsObject();

        Assert.Equal(forwarderEnvelope["session_id"]!.GetValue<string>(), reporterEnvelope["session_id"]!.GetValue<string>());
        Assert.Equal(forwarderEnvelope["agent_kind"]!.GetValue<string>(), reporterEnvelope["agent_kind"]!.GetValue<string>());
        Assert.Equal(forwarderEnvelope["event_type"]!.GetValue<string>(), reporterEnvelope["event_type"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(forwarderEnvelope["payload"], reporterEnvelope["payload"]));
    }

    [Fact]
    public void ReporterScripts_BuildEnvelopeInShellExactlyLikeBuildEnvelopeJson()
    {
        var installer = CreateInstaller();
        installer.MarkReady("http://127.0.0.1:51423/agent-event");

        var shScript = File.ReadAllText(Path.Combine(_installDir, ClaudeHooksInstaller.ReporterMarker + (OperatingSystem.IsWindows() ? ".cmd" : "")));
        var scripts = new List<string> { shScript };
        if (OperatingSystem.IsWindows())
        {
            scripts.Add(File.ReadAllText(Path.Combine(_installDir, ClaudeHooksInstaller.ReporterMarker + ".ps1")));
        }
        foreach (var script in scripts)
        {
            // The printf/concat envelope must emit exactly the four HookForwarder fields,
            // in the same order, with agent_kind hardcoded to the claude-code adapter name.
            Assert.Contains("{\"session_id\":\"", script);
            Assert.Contains("\",\"agent_kind\":\"claude-code\",\"event_type\":\"", script);
            Assert.Contains("\",\"payload\":", script);
        }
        // Both reporter variants read the payload verbatim from stdin (no jq/rewriting).
        Assert.Contains("$(cat)", shScript);
        if (OperatingSystem.IsWindows())
        {
            Assert.Contains("[Console]::In.ReadToEnd()", scripts[1]);
        }
    }

    [Fact]
    public void ReporterScript_SilentlyExitsZeroWithoutCortermEnv()
    {
        if (OperatingSystem.IsWindows()) return;  // POSIX shell only
        var installer = CreateInstaller();
        installer.MarkReady("http://127.0.0.1:51423/agent-event");
        var reporter = Path.Combine(_installDir, ClaudeHooksInstaller.ReporterMarker);

        var psi = new System.Diagnostics.ProcessStartInfo(reporter, "UserPromptSubmit")
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        psi.Environment.Remove("CORTERM_AGENT_HOOK_URL");
        psi.Environment.Remove("CORTERM_SESSION_ID");

        using var process = System.Diagnostics.Process.Start(psi)!;
        process.StandardInput.Write("{\"hook_event_name\":\"UserPromptSubmit\"}");
        process.StandardInput.Close();
        process.WaitForExit(10_000);
        Assert.Equal(0, process.ExitCode);
        Assert.Equal(string.Empty, process.StandardOutput.ReadToEnd());
    }

    private static bool IsManaged(JsonObject entry)
        => entry["hooks"] is JsonArray inner && inner.OfType<JsonObject>().Any(h =>
            h["command"]?.GetValue<string>()?.Contains(ClaudeHooksInstaller.ReporterMarker, StringComparison.Ordinal) == true);
}
