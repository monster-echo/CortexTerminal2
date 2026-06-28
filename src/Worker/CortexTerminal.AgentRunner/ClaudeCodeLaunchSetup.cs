using System.Text.Json;
using System.Text.Json.Nodes;

namespace CortexTerminal.AgentRunner;

/// <summary>
/// Claude Code launch setup. Writes a per-session settings.json that wires each Claude Code
/// hook event to <c>cortap hook claude-code</c>, then prepends <c>--settings &lt;path&gt;</c>
/// to the user's args so Claude Code loads our hooks as additional settings.
///
/// <para>
/// We deliberately do <b>not</b> touch <c>CLAUDE_CONFIG_DIR</c>: Claude Code follows that
/// env var to locate its global state file <c>~/.claude.json</c> (which lives at the user's
/// home root, not inside <c>~/.claude/</c>, so symlinking <c>~/.claude/</c> can't reach it).
/// Setting <c>CLAUDE_CONFIG_DIR</c> to a fresh dir makes Claude Code think it's a brand-new
/// install (numStartups reset, theme picker reappears, login state lost) and spams the user
/// with "Claude configuration file not found / backup restored" warnings. With
/// <c>--settings</c>, Claude Code runs entirely in its native <c>~/.claude/</c> and our
/// hooks layer on top as "additional settings" — the user sees zero difference from running
/// <c>claude</c> directly.
/// </para>
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

    public ClaudeCodeLaunchSetup(string sessionId)
    {
        if (string.IsNullOrEmpty(sessionId)) throw new ArgumentException("sessionId must not be empty", nameof(sessionId));
        _sessionId = sessionId;
    }

    public string Kind => "claude";

    public LaunchSetupResult Prepare()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrEmpty(home))
        {
            throw new InvalidOperationException("Could not resolve user home directory.");
        }

        var tempDir = Path.Combine(home, ".corterm", "agent-hooks", _sessionId);
        Directory.CreateDirectory(tempDir);

        var settingsPath = Path.Combine(tempDir, "settings.json");
        File.WriteAllText(settingsPath, BuildSettingsJson());

        return new LaunchSetupResult(
            tempDir,
            EnvironmentVariables: new Dictionary<string, string>(StringComparer.Ordinal),
            PassthroughArgs: new[] { "--settings", settingsPath });
    }

    /// <summary>
    /// Build settings.json containing only the Corterm hook wiring. Claude Code treats
    /// <c>--settings</c> as additional settings layered on top of the user's
    /// <c>~/.claude/settings.json</c>, so we don't merge user settings here — Claude Code
    /// does that itself.
    /// </summary>
    internal string BuildSettingsJson()
    {
        var wrapperPath = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine wrapper process path for hook command.");
        var hookCommand = $"\"{wrapperPath}\" hook claude";

        var root = new JsonObject();
        var hooks = new JsonObject();
        root["hooks"] = hooks;

        foreach (var evt in HookEvents)
        {
            var ourHook = new JsonObject
            {
                ["matcher"] = "*",
                ["hooks"] = new JsonArray(new JsonObject
                {
                    ["type"] = "command",
                    ["command"] = hookCommand,
                }),
            };
            hooks[evt] = new JsonArray((JsonNode)ourHook);
        }

        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }
}
