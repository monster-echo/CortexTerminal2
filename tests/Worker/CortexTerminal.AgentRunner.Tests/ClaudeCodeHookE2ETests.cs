using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests;

/// <summary>
/// End-to-end test that spawns the real <c>claude</c> binary with a generated settings.json and
/// asserts that the hook events documented at https://code.claude.com/docs/en/hooks actually fire.
///
/// <para>
/// This test exists because every other test in the agent-tracking pipeline feeds mock payloads to
/// the adapter / sink / hub. None of them prove that a real Claude Code process, configured with a
/// real <c>settings.json</c>, will actually invoke the registered hook commands. If Claude Code
/// changes its hook contract (renames an event, alters payload schema, etc.) the unit tests will
/// keep passing while production silently breaks.
/// </para>
///
/// <para>
/// The test silently skips when <c>claude</c> is not on PATH (CI runners, fresh dev boxes). It does
/// <strong>not</strong> use the <c>cortap</c> wrapper — that path is covered by
/// <see cref="HookForwarderTests"/>. Instead it points hooks at a shell command that appends stdin
/// to a log file, so we measure the claude → hook contract directly.
/// </para>
/// </summary>
public sealed class ClaudeCodeHookE2ETests
{
    // claude --print can take 2–3 minutes when the model gateway is overloaded (529s in
    // practice). 5 minutes gives us headroom for one retry + slow inference.
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(300);

    [Fact]
    public async Task RealClaudeBinary_FiresConfiguredHookEvents()
    {
        var claudeBinary = ResolveClaudeBinary();
        if (claudeBinary is null)
        {
            // Skip silently — not an assertion failure. CI runners without claude should pass.
            return;
        }

        var tempConfigDir = Directory.CreateTempSubdirectory("corterm-e2e-config-").FullName;
        var eventLogPath = Path.Combine(Path.GetTempPath(), "corterm-e2e-events-" + Guid.NewGuid().ToString("N") + ".log");

        try
        {
            MirrorUserClaudeDir(tempConfigDir);
            File.WriteAllText(Path.Combine(tempConfigDir, "settings.json"), BuildSettingsJson(eventLogPath));

            var psi = new ProcessStartInfo
            {
                FileName = claudeBinary,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            psi.ArgumentList.Add("--print");
            psi.ArgumentList.Add("Reply with exactly one word: hello");
            psi.Environment["CLAUDE_CONFIG_DIR"] = tempConfigDir;
            // Quieter claude behavior — no auto-update, no telemetry, no extra model calls.
            psi.Environment["DISABLE_AUTOUPDATER"] = "1";
            psi.Environment["DISABLE_BUG_COMMAND"] = "1";
            psi.Environment["DISABLE_TELEMETRY"] = "1";
            psi.Environment["DISABLE_COST_WARNINGS"] = "1";
            psi.Environment["DISABLE_NON_ESSENTIAL_MODEL_CALLS"] = "1";
            psi.Environment["MAX_THINKING_TOKENS"] = "0";

            using var process = Process.Start(psi)
                ?? throw new InvalidOperationException($"Failed to start process '{claudeBinary}'.");
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();

            var exited = process.WaitForExit((int)Timeout.TotalMilliseconds);
            if (!exited)
            {
                try { process.Kill(entireProcessTree: true); } catch { }
                throw new TimeoutException($"claude --print did not exit within {Timeout.TotalSeconds:0}s.");
            }

            await Task.WhenAll(stdoutTask, stderrTask);
            var stderr = await stderrTask;

            if (!File.Exists(eventLogPath))
            {
                throw new InvalidOperationException(
                    $"No hook events were captured. claude exit code={process.ExitCode}, stderr:\n{stderr}");
            }

            var eventNames = ExtractHookEventNames(File.ReadAllText(eventLogPath));

            // These three fire regardless of whether the model call succeeds:
            // - SessionStart fires at process startup, before any network call.
            // - UserPromptSubmit fires when the prompt is accepted into the session.
            // - SessionEnd fires on every clean termination, success or API error.
            // Stop is intentionally excluded — it only fires after a successful model response,
            // which doesn't happen when the inference gateway returns 529 (a real-world
            // condition we can't reliably rule out in the test environment).
            eventNames.Should().Contain("SessionStart",
                $"SessionStart must always fire when claude starts. exit={process.ExitCode}, events=[{string.Join(", ", eventNames)}], stderr:\n{stderr}");
            eventNames.Should().Contain("UserPromptSubmit",
                $"--print should emit UserPromptSubmit. exit={process.ExitCode}, events=[{string.Join(", ", eventNames)}], stderr:\n{stderr}");
            eventNames.Should().Contain("SessionEnd",
                $"SessionEnd should fire on termination. exit={process.ExitCode}, events=[{string.Join(", ", eventNames)}], stderr:\n{stderr}");
        }
        finally
        {
            try { if (Directory.Exists(tempConfigDir)) Directory.Delete(tempConfigDir, recursive: true); } catch { }
            try { if (File.Exists(eventLogPath)) File.Delete(eventLogPath); } catch { }
        }
    }

    /// <summary>
    /// Locate the claude binary. Respects <c>CLAUDE_BINARY_PATH</c> first, then PATH search.
    /// Returns null when no binary is available — caller should silently skip the test.
    /// </summary>
    private static string? ResolveClaudeBinary()
    {
        var explicitPath = Environment.GetEnvironmentVariable("CLAUDE_BINARY_PATH");
        if (!string.IsNullOrWhiteSpace(explicitPath) && File.Exists(explicitPath)) return explicitPath;

        var pathEnv = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        var executableName = OperatingSystem.IsWindows() ? "claude.exe" : "claude";
        foreach (var dir in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            string candidate;
            try { candidate = Path.Combine(dir, executableName); }
            catch (ArgumentException) { continue; }
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }

    /// <summary>
    /// Mirror the user's <c>~/.claude/</c> contents (credentials, projects, MCP config) into the
    /// temp config dir via symlinks, so the spawned claude process inherits the user's auth.
    /// <c>settings.json</c> is excluded — we write our own with hook commands.
    /// Windows is skipped because symlinks need admin / Developer Mode; the test will only work
    /// there if <c>ANTHROPIC_API_KEY</c> is set in the environment.
    /// </summary>
    private static void MirrorUserClaudeDir(string tempDir)
    {
        if (OperatingSystem.IsWindows()) return;

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var userClaudeDir = Path.Combine(home, ".claude");
        if (!Directory.Exists(userClaudeDir)) return;

        foreach (var entry in Directory.EnumerateFileSystemEntries(userClaudeDir))
        {
            var name = Path.GetFileName(entry);
            if (name == "settings.json") continue;
            var linkPath = Path.Combine(tempDir, name);
            try
            {
                if (Directory.Exists(entry))
                {
                    Directory.CreateSymbolicLink(linkPath, Path.GetFullPath(entry));
                }
                else
                {
                    File.CreateSymbolicLink(linkPath, Path.GetFullPath(entry));
                }
            }
            catch (IOException)
            {
                // Symlink creation can race with concurrent invocations or hit permission errors.
                // Skip — claude will surface auth failures via exit code / stderr if it can't auth.
            }
        }
    }

    /// <summary>
    /// Build a settings.json that wires each of the 9 Claude Code hook events to a shell command
    /// that captures stdin to <paramref name="eventLogPath"/>. Each invocation prepends a
    /// delimiter line so we can split concatenated payloads apart later.
    /// </summary>
    private static string BuildSettingsJson(string eventLogPath)
    {
        var command = OperatingSystem.IsWindows()
            ? $"powershell -NoProfile -Command \"'===END===' | Add-Content -Path '{eventLogPath}'; $input | Add-Content -Path '{eventLogPath}'\""
            : $"sh -c 'echo ===END=== >> {eventLogPath} && cat >> {eventLogPath}'";

        var hookEvents = new[]
        {
            "SessionStart",
            "SessionEnd",
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "Stop",
            "SubagentStop",
            "Notification",
            "PreCompact",
        };

        var hooks = new JsonObject();
        foreach (var evt in hookEvents)
        {
            hooks[evt] = new JsonArray(new JsonObject
            {
                ["matcher"] = "*",
                ["hooks"] = new JsonArray(new JsonObject
                {
                    ["type"] = "command",
                    ["command"] = command,
                }),
            });
        }

        var root = new JsonObject { ["hooks"] = hooks };
        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>
    /// Parse the captured hook log. Each hook invocation appended a delimiter line followed by a
    /// JSON object; we split on the delimiter and try to parse each chunk, extracting
    /// <c>hook_event_name</c>. Malformed chunks (partial writes, etc.) are silently skipped.
    /// </summary>
    private static HashSet<string> ExtractHookEventNames(string log)
    {
        var names = new HashSet<string>(StringComparer.Ordinal);
        var chunks = log.Split("===END===", StringSplitOptions.RemoveEmptyEntries);
        foreach (var chunk in chunks)
        {
            var trimmed = chunk.Trim();
            if (trimmed.Length == 0) continue;
            try
            {
                using var doc = JsonDocument.Parse(trimmed);
                if (doc.RootElement.TryGetProperty("hook_event_name", out var nameEl))
                {
                    var name = nameEl.GetString();
                    if (!string.IsNullOrEmpty(name)) names.Add(name);
                }
            }
            catch (JsonException)
            {
                // Partial write or interleaved output — ignore.
            }
        }
        return names;
    }
}
