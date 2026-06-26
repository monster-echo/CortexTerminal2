using System.Text.Json;
using System.Text.Json.Nodes;

namespace CortexTerminal.AgentRunner;

/// <summary>
/// Claude Code launch setup. Writes a per-session settings.json that wires each Claude Code
/// hook event to <c>corterm-agent hook claude-code</c>, then points <c>CLAUDE_CONFIG_DIR</c>
/// at the per-session dir so Claude Code reads our settings without polluting the user's
/// <c>~/.claude/</c>.
///
/// On Unix we symlink the rest of the user's <c>~/.claude/</c> contents (credentials, projects,
/// etc.) into the temp dir so Claude Code still has its normal context. Windows falls back to
/// a bare settings.json with no symlinks (Phase 4.1 will handle Windows more robustly).
/// </summary>
public sealed class ClaudeCodeLaunchSetup : IAgentLaunchSetup
{
    private static readonly string[] HookEvents =
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

    private readonly string _sessionId;
    private readonly string _hookUrl;

    public ClaudeCodeLaunchSetup(string sessionId, string hookUrl)
    {
        if (string.IsNullOrEmpty(sessionId)) throw new ArgumentException("sessionId must not be empty", nameof(sessionId));
        if (string.IsNullOrEmpty(hookUrl)) throw new ArgumentException("hookUrl must not be empty", nameof(hookUrl));
        _sessionId = sessionId;
        _hookUrl = hookUrl;
    }

    public string Kind => "claude";

    public LaunchSetupResult Prepare()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrEmpty(home))
        {
            throw new InvalidOperationException("Could not resolve user home directory.");
        }

        var userClaudeDir = Path.Combine(home, ".claude");
        var tempDir = Path.Combine(home, ".corterm", "agent-hooks", _sessionId);
        Directory.CreateDirectory(tempDir);

        try
        {
            if (OperatingSystem.IsWindows())
            {
                PrepareWindows(tempDir, userClaudeDir);
            }
            else
            {
                PrepareUnix(tempDir, userClaudeDir);
            }

            var settingsPath = Path.Combine(tempDir, "settings.json");
            File.WriteAllText(settingsPath, BuildSettingsJson(userClaudeDir));

            return new LaunchSetupResult(tempDir, new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["CLAUDE_CONFIG_DIR"] = tempDir,
            });
        }
        catch
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
            throw;
        }
    }

    private static void PrepareUnix(string tempDir, string userClaudeDir)
    {
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
                // Skip the entry — Claude Code will recreate what it needs.
            }
        }
    }

    private static void PrepareWindows(string tempDir, string userClaudeDir)
    {
        // Symlinks on Windows require Developer Mode or admin. Skip mirroring for now —
        // Claude Code will run with a fresh CLAUDE_CONFIG_DIR. Phase 4.1 will handle this
        // more gracefully (likely via deep copy or a different injection mechanism).
        _ = tempDir;
        _ = userClaudeDir;
    }

    /// <summary>
    /// Build merged settings.json: user's existing settings (if any) with Corterm hooks
    /// appended to each event's hooks array. User hooks stay in place so we don't break
    /// their custom automation.
    /// </summary>
    internal string BuildSettingsJson(string userClaudeDir)
    {
        var wrapperPath = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine wrapper process path for hook command.");
        var hookCommand = $"\"{wrapperPath}\" hook claude-code";

        var root = LoadUserSettings(userClaudeDir);
        var hooks = root.TryGetPropertyValue("hooks", out var h) && h is JsonObject ho ? ho : new JsonObject();
        root["hooks"] = hooks!;

        foreach (var evt in HookEvents)
        {
            var existingArr = hooks.TryGetPropertyValue(evt, out var e) && e is JsonArray arr ? arr : new JsonArray();
            var ourHook = new JsonObject
            {
                ["matcher"] = "*",
                ["hooks"] = new JsonArray(new JsonObject
                {
                    ["type"] = "command",
                    ["command"] = hookCommand,
                }),
            };
            existingArr.Add((JsonNode)ourHook);
            hooks[evt] = existingArr;
        }

        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    private static JsonObject LoadUserSettings(string userClaudeDir)
    {
        var path = Path.Combine(userClaudeDir, "settings.json");
        if (!File.Exists(path)) return new JsonObject();
        try
        {
            var content = File.ReadAllText(path);
            return JsonNode.Parse(content, documentOptions: new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip }) as JsonObject
                ?? new JsonObject();
        }
        catch (JsonException)
        {
            // User's settings.json is malformed — start fresh rather than crashing.
            return new JsonObject();
        }
        catch (IOException)
        {
            return new JsonObject();
        }
    }
}
