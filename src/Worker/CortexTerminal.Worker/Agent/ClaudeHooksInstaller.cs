using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Non-invasive Claude Code integration. Instead of hijacking the user's shell PATH with
/// shim scripts, this installer merges Corterm-managed hook entries into the user's
/// <c>~/.claude/settings.json</c> and writes a lightweight reporter script into the
/// Worker install dir. Each hook execs the reporter, which forwards the raw Claude Code
/// event payload (wrapped in the Corterm envelope) to the Worker's loopback
/// <c>/agent-event</c> endpoint.
///
/// <para>
/// Ownership is marked by the reporter command path: any hook entry whose command contains
/// <see cref="ReporterMarker"/> belongs to Corterm and is replaced on re-install and
/// removed by <see cref="RemoveInstalledHooks"/>. User-authored hook entries are never
/// touched. A <c>settings.json.corterm-bak</c> copy is written before the first
/// modification of an existing file.
/// </para>
/// </summary>
public sealed class ClaudeHooksInstaller : IAgentIntegration
{
    /// <summary>Marker substring that identifies Corterm-owned hook commands.</summary>
    internal const string ReporterMarker = "cortap-hook-reporter";

    /// <summary>Claude Code hook events Corterm subscribes to (all parsed by ClaudeCodeAdapter).</summary>
    internal static readonly string[] HookEvents =
    {
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Notification",
        "Stop",
    };

    internal static readonly string[] LegacyShimNames = { "claude", "codex", "opencode" };

    private readonly ILogger<ClaudeHooksInstaller> _logger;
    private readonly string _installDir;
    private readonly string _shimsDir;
    private readonly string _zdotdir;
    private readonly string _powershellInitFile;
    private readonly string _settingsPath;
    private readonly bool _configEnabled;
    private readonly bool _isWindows;
    private volatile string? _hookUrl;
    private volatile bool _installed;

    public ClaudeHooksInstaller(string installDir, bool enabled, ILogger<ClaudeHooksInstaller> logger, string? settingsPath = null)
    {
        if (string.IsNullOrWhiteSpace(installDir))
            throw new ArgumentException("Install directory must not be empty.", nameof(installDir));
        _installDir = installDir;
        _shimsDir = Path.Combine(installDir, "shims");
        _zdotdir = Path.Combine(installDir, "zdotdir");
        _powershellInitFile = Path.Combine(installDir, "prompt.ps1");
        _configEnabled = enabled;
        _logger = logger;
        _isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
        _settingsPath = settingsPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "settings.json");
    }

    public bool Enabled => _configEnabled && _installed && _hookUrl is not null;

    public string HookUrl =>
        _hookUrl ?? throw new InvalidOperationException("Agent event endpoint has not started yet.");

    /// <summary>Called by <see cref="AgentEventEndpoint"/> after Kestrel has bound its loopback port.</summary>
    public void MarkReady(string hookUrl)
    {
        if (string.IsNullOrWhiteSpace(hookUrl))
            throw new ArgumentException("Hook URL must not be empty.", nameof(hookUrl));
        _hookUrl = hookUrl;
        if (_configEnabled)
        {
            Install();
        }
        _logger.LogInformation("Agent integration ready: hook URL = {HookUrl}, hooks installed = {Installed}.", hookUrl, _configEnabled);
    }

    /// <summary>
    /// Deletes the leftovers of the retired shim-era agent integration from the install
    /// dir: the shim scripts (claude/codex/opencode plus their .cmd twins — only these
    /// names are removed, anything else in the directory is left untouched), the managed
    /// zdotdir, and the PowerShell init file. Cheap no-op on fresh installs; runs at every
    /// startup so upgrades from the shim era self-clean.
    /// </summary>
    public void CleanupLegacyShims()
    {
        if (Directory.Exists(_shimsDir))
        {
            foreach (var name in LegacyShimNames)
            {
                DeleteLegacyShim(Path.Combine(_shimsDir, name));
                DeleteLegacyShim(Path.Combine(_shimsDir, name + ".cmd"));
            }
            if (Directory.EnumerateFileSystemEntries(_shimsDir).Any())
            {
                _logger.LogInformation("Legacy agent shims cleaned from {ShimsDir}.", _shimsDir);
            }
            else
            {
                Directory.Delete(_shimsDir);
                _logger.LogInformation("Removed empty legacy shims dir {ShimsDir}.", _shimsDir);
            }
        }

        TryDeleteLegacyDir(_zdotdir, "legacy managed zdotdir");
        TryDeleteLegacyFile(_powershellInitFile, "legacy PowerShell init file");
    }

    private void TryDeleteLegacyDir(string path, string description)
    {
        try
        {
            if (!Directory.Exists(path)) return;
            Directory.Delete(path, recursive: true);
            _logger.LogInformation("Deleted {Description} at {Path}.", description, path);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to delete {Description} at {Path}; will retry next startup.", description, path);
        }
    }

    private void TryDeleteLegacyFile(string path, string description)
    {
        try
        {
            if (!File.Exists(path)) return;
            File.Delete(path);
            _logger.LogInformation("Deleted {Description} at {Path}.", description, path);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to delete {Description} at {Path}; will retry next startup.", description, path);
        }
    }

    private void DeleteLegacyShim(string path)
    {
        if (!File.Exists(path)) return;
        File.Delete(path);
        _logger.LogInformation("Deleted legacy agent shim {Path}.", path);
    }

    /// <summary>
    /// Removes every Corterm-owned hook entry from <c>~/.claude/settings.json</c>,
    /// preserving all user configuration. Used when <c>Agent:Enabled=false</c> and as the
    /// uninstall path. No-op when our hooks are not present.
    /// </summary>
    public void RemoveInstalledHooks()
    {
        if (!File.Exists(_settingsPath)) return;

        var root = JsonNode.Parse(File.ReadAllText(_settingsPath)) as JsonObject
            ?? throw new JsonException($"Claude Code settings at {_settingsPath} is not a JSON object.");
        var before = root.ToJsonString();
        StripManagedHooks(root);
        var after = root.ToJsonString();
        if (before == after) return;

        WriteSettingsWithBackup(root);
        _logger.LogInformation("Removed Corterm hooks from {SettingsPath}.", _settingsPath);
    }

    private void Install()
    {
        WriteReporterScripts();
        MergeHooksIntoSettings();
        _installed = true;
        _logger.LogInformation("Claude Code hooks installed at {SettingsPath} (reporter = {Reporter}).",
            _settingsPath, ReporterPath);
    }

    private string ReporterPath => Path.Combine(_installDir,
        _isWindows ? ReporterMarker + ".cmd" : ReporterMarker);

    private string ReporterEventArg => _isWindows ? "%1" : "$1";

    /// <summary>
    /// Rewrites the reporter scripts on every startup so upgrades pick up changes.
    /// Idempotent: same content every time.
    /// </summary>
    private void WriteReporterScripts()
    {
        if (_isWindows)
        {
            File.WriteAllText(ReporterPath, WindowsReporterCmdBody);
            File.WriteAllText(Path.Combine(_installDir, ReporterMarker + ".ps1"), PowerShellReporterBody);
        }
        else
        {
            var path = ReporterPath;
            File.Delete(path);
            File.WriteAllText(path, UnixReporterBody);
            if (!OperatingSystem.IsWindows())
            {
                File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute
                    | UnixFileMode.GroupRead | UnixFileMode.GroupExecute
                    | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
            }
        }
    }

    private void MergeHooksIntoSettings()
    {
        var root = ReadOrCreateSettingsRoot();
        var before = root.ToJsonString();
        MergeManagedHooks(root, ReporterPath);
        if (root.ToJsonString() == before) return;
        WriteSettingsWithBackup(root);
    }

    private JsonObject ReadOrCreateSettingsRoot()
    {
        if (!File.Exists(_settingsPath)) return new JsonObject();
        return JsonNode.Parse(File.ReadAllText(_settingsPath)) as JsonObject
            ?? throw new JsonException($"Claude Code settings at {_settingsPath} is not a JSON object.");
    }

    private void WriteSettingsWithBackup(JsonObject root)
    {
        if (File.Exists(_settingsPath))
        {
            File.Copy(_settingsPath, _settingsPath + ".corterm-bak", overwrite: true);
        }
        var parent = Path.GetDirectoryName(_settingsPath);
        if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
        File.WriteAllText(_settingsPath, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>
    /// Builds the envelope JSON the reporter POSTs. Field layout is identical to
    /// <c>HookForwarder.BuildEnvelopeJson</c>: session_id (Corterm session, from
    /// CORTERM_SESSION_ID), agent_kind ("claude-code"), event_type (the hook event),
    /// payload (the raw Claude Code hook payload verbatim).
    /// </summary>
    internal static string BuildEnvelopeJson(string rawBody, string sessionId, string eventType)
    {
        var payloadNode = JsonNode.Parse(rawBody) ?? throw new JsonException("Hook payload is not valid JSON.");
        var envelope = new JsonObject
        {
            ["session_id"] = sessionId,
            ["agent_kind"] = "claude-code",
            ["event_type"] = eventType,
            ["payload"] = payloadNode,
        };
        return envelope.ToJsonString();
    }

    /// <summary>Adds/refreshes the Corterm hook entries under root["hooks"], preserving user entries.</summary>
    internal static void MergeManagedHooks(JsonObject root, string reporterPath)
    {
        var hooks = root.TryGetPropertyValue("hooks", out var hooksNode) && hooksNode is JsonObject ho
            ? ho
            : new JsonObject();
        root["hooks"] = hooks;

        foreach (var evt in HookEvents)
        {
            var entries = hooks.TryGetPropertyValue(evt, out var arr) && arr is JsonArray existing
                ? existing
                : new JsonArray();
            hooks[evt] = entries;

            RemoveManagedEntries(entries);
            entries.Add(new JsonObject
            {
                ["matcher"] = "*",
                ["hooks"] = new JsonArray(new JsonObject
                {
                    ["type"] = "command",
                    ["command"] = $"{reporterPath} {evt}",
                }),
            });
        }
    }

    /// <summary>Strips every Corterm-owned hook entry from root["hooks"], preserving user entries.</summary>
    internal static void StripManagedHooks(JsonObject root)
    {
        if (!root.TryGetPropertyValue("hooks", out var hooksNode) || hooksNode is not JsonObject hooks) return;
        foreach (var (evt, value) in hooks.ToArray())
        {
            if (value is not JsonArray entries) continue;
            RemoveManagedEntries(entries);
            if (entries.Count == 0) hooks.Remove(evt);
        }
        if (hooks.Count == 0) root.Remove("hooks");
    }

    private static void RemoveManagedEntries(JsonArray entries)
    {
        for (var i = entries.Count - 1; i >= 0; i--)
        {
            if (entries[i] is JsonObject entry && IsManagedEntry(entry))
            {
                entries.RemoveAt(i);
            }
        }
    }

    private static bool IsManagedEntry(JsonObject entry)
    {
        return entry.TryGetPropertyValue("hooks", out var inner)
            && inner is JsonArray innerHooks
            && innerHooks.OfType<JsonObject>().Any(h =>
                h.TryGetPropertyValue("command", out var cmd)
                && cmd?.GetValue<string>()?.Contains(ReporterMarker, StringComparison.Ordinal) == true);
    }

    // ── reporter script bodies ──
    //
    // SILENT-FAILURE EXCEPTION (the only one allowed by CLAUDE.md): these scripts run
    // inside Claude Code's hook chain. A non-zero exit or stdout garbage can block, abort,
    // or corrupt the user's claude session. Every failure — unset env, bad stdin, curl
    // error, endpoint down — MUST exit 0 quietly. Nothing here may throw, log, or print.

    private const string UnixReporterBody = "#!/bin/sh\n" +
        "# Corterm hook reporter. Reads the raw Claude Code hook payload from stdin and\n" +
        "# POSTs it (wrapped in the Corterm envelope) to the Worker's /agent-event loopback\n" +
        "# endpoint. Echoes the endpoint's response to stdout (Claude Code's\n" +
        "# UserPromptSubmit reads additionalContext from hook stdout).\n" +
        "#\n" +
        "# SILENT-FAILURE EXCEPTION: this script runs inside Claude Code's hook chain — any\n" +
        "# non-zero exit or stray output can break the user's claude session. Every failure\n" +
        "# here must exit 0 quietly. This is the only sanctioned silent-failure point.\n" +
        "[ -n \"$CORTERM_AGENT_HOOK_URL\" ] || exit 0\n" +
        "[ -n \"$CORTERM_SESSION_ID\" ] || exit 0\n" +
        "[ $# -ge 1 ] || exit 0\n" +
        "body=\"$(cat)\" || exit 0\n" +
        "[ -n \"$body\" ] || exit 0\n" +
        "sid=$(printf '%s' \"$CORTERM_SESSION_ID\" | sed 's/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g')\n" +
        "response=$(printf '{\"session_id\":\"%s\",\"agent_kind\":\"claude-code\",\"event_type\":\"%s\",\"payload\":%s}' \\\n" +
        "  \"$sid\" \"$1\" \"$body\" \\\n" +
        "  | curl -fsS -X POST -H 'Content-Type: application/json' --data-binary @- \"$CORTERM_AGENT_HOOK_URL\" 2>/dev/null) || exit 0\n" +
        "[ -n \"$response\" ] && printf '%s' \"$response\"\n" +
        "exit 0\n";

    private const string WindowsReporterCmdBody = "@echo off\n" +
        "rem Corterm hook reporter (Windows). Delegates to the PowerShell twin so stdin can\n" +
        "rem be read reliably; batch cannot capture multi-line stdin.\n" +
        "rem\n" +
        "rem SILENT-FAILURE EXCEPTION: runs inside Claude Code's hook chain — any non-zero\n" +
        "rem exit or stray output can break the user's claude session. Every failure must\n" +
        "rem exit 0 quietly. This is the only sanctioned silent-failure point.\n" +
        "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%~dp0" + ReporterMarker + ".ps1\" %1\n" +
        "exit /b 0\n";

    private const string PowerShellReporterBody = "# Corterm hook reporter (Windows PowerShell twin). Reads the raw Claude Code hook\n" +
        "# payload from stdin and POSTs it (wrapped in the Corterm envelope) to the Worker's\n" +
        "# /agent-event loopback endpoint.\n" +
        "#\n" +
        "# SILENT-FAILURE EXCEPTION: this script runs inside Claude Code's hook chain — any\n" +
        "# non-zero exit or stray output can break the user's claude session. Every failure\n" +
        "# here must exit 0 quietly. This is the only sanctioned silent-failure point.\n" +
        "param([string]$EventType)\n" +
        "try {\n" +
        "    if (-not $env:CORTERM_AGENT_HOOK_URL) { exit 0 }\n" +
        "    if (-not $env:CORTERM_SESSION_ID) { exit 0 }\n" +
        "    if (-not $EventType) { exit 0 }\n" +
        "    $body = [Console]::In.ReadToEnd()\n" +
        "    if (-not $body -or -not $body.Trim()) { exit 0 }\n" +
        "    $sid = $env:CORTERM_SESSION_ID.Replace('\\', '\\\\').Replace('\"', '\\\"')\n" +
        "    $envelope = '{\"session_id\":\"' + $sid + '\",\"agent_kind\":\"claude-code\",\"event_type\":\"' + $EventType + '\",\"payload\":' + $body + '}'\n" +
        "    $response = Invoke-WebRequest -Uri $env:CORTERM_AGENT_HOOK_URL -Method Post -ContentType 'application/json' -Body $envelope -UseBasicParsing\n" +
        "    if ($response.Content) { Write-Output $response.Content }\n" +
        "} catch {\n" +
        "    # Swallowed on purpose — see the SILENT-FAILURE EXCEPTION note above.\n" +
        "}\n" +
        "exit 0\n";
}
