using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Concrete <see cref="IAgentIntegration"/>. Owns:
///  - the loopback HTTP URL the hook events POST to
///  - the shim directory prepended to every PTY PATH
///  - the original PATH snapshot so the wrapper binary can locate the real agent
///
/// The HookUrl is filled in by <see cref="AgentEventEndpoint"/> once Kestrel binds
/// to a random loopback port. Until that happens, <see cref="Enabled"/> stays false
/// and PTY spawns skip the agent-tracking env vars.
/// </summary>
public sealed class AgentIntegration : IAgentIntegration
{
    private static readonly string[] AgentKinds = { "claude", "codex", "opencode" };

    private readonly ILogger<AgentIntegration> _logger;
    private readonly string _installDir;
    private readonly string _shimsDir;
    private readonly string _zdotdir;
    private readonly string _bashrcFile;
    private readonly string _originalPath;
    private volatile string? _hookUrl;
    private volatile bool _enabled;

    public AgentIntegration(string installDir, ILogger<AgentIntegration> logger)
    {
        _logger = logger;
        _installDir = installDir;
        _shimsDir = Path.Combine(installDir, "shims");
        _zdotdir = Path.Combine(installDir, "zdotdir");
        _bashrcFile = Path.Combine(_zdotdir, "bashrc");
        _originalPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
    }

    public bool Enabled => _enabled && _hookUrl is not null;

    public string HookUrl =>
        _hookUrl ?? throw new InvalidOperationException("Agent event endpoint has not started yet.");

    public string ShimsDir => _shimsDir;

    public string Zdotdir => _zdotdir;

    public string BashrcFile => _bashrcFile;

    public string OriginalPath => _originalPath;

    /// <summary>Called by <see cref="AgentEventEndpoint"/> after Kestrel has bound its loopback port.</summary>
    public void MarkReady(string hookUrl)
    {
        if (string.IsNullOrWhiteSpace(hookUrl))
            throw new ArgumentException("Hook URL must not be empty.", nameof(hookUrl));
        _hookUrl = hookUrl;
        _enabled = true;
        _logger.LogInformation("Agent integration ready: hook URL = {HookUrl}, shims = {ShimsDir}.", hookUrl, _shimsDir);
    }

    /// <summary>
    /// Write the claude/codex/opencode shims into <see cref="ShimsDir"/>. Idempotent — overwrites
    /// every startup so a Worker upgrade picks up script changes. The shims exec &lt;install&gt;/cortap
    /// (cortap.exe on Windows), which the wrapper project produces in Phase 3.
    ///
    /// Also writes a managed <see cref="Zdotdir"/> for zsh sessions whose <c>.zshrc</c> sources
    /// the user's real <c>.zshrc</c> and then prepends <see cref="ShimsDir"/> to <c>PATH</c>.
    /// Without this, a user <c>.zshrc</c> that does <c>export PATH=$HOME/.local/bin:$PATH</c>
    /// would shadow the shim — making <c>claude</c> resolve to the real binary instead of cortap.
    /// </summary>
    public void EnsureShimsInstalled()
    {
        Directory.CreateDirectory(_shimsDir);
        var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
        var wrapperName = isWindows ? "cortap.exe" : "cortap";
        var wrapperPath = Path.Combine(_installDir, wrapperName);

        foreach (var kind in AgentKinds)
        {
            if (isWindows)
            {
                var scriptPath = Path.Combine(_shimsDir, kind + ".cmd");
                File.WriteAllText(scriptPath, WindowsShimBody(wrapperPath, kind));
            }
            else
            {
                var scriptPath = Path.Combine(_shimsDir, kind);
                File.WriteAllText(scriptPath, UnixShimBody(wrapperPath, kind));
                try
                {
                    File.SetUnixFileMode(scriptPath, UnixFileMode.UserExecute | UnixFileMode.UserWrite | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute | UnixFileMode.UserRead | UnixFileMode.GroupRead | UnixFileMode.OtherRead);
                }
                catch (IOException ioEx)
                {
                    _logger.LogWarning(ioEx, "Failed to set executable mode on shim {Path}.", scriptPath);
                }
            }
        }

        if (!isWindows)
        {
            EnsureZdotdirWritten();
        }

        _logger.LogInformation("Agent shims installed at {ShimsDir} (wrapper = {Wrapper}).", _shimsDir, wrapperPath);
    }

    /// <summary>
    /// Writes the managed ZDOTDIR for zsh. The <c>.zshrc</c> sources the user's real zsh
    /// startup files (resolved via <c>$CORTERM_REAL_ZDOTDIR</c>, defaulting to <c>$HOME</c>)
    /// and then prepends <see cref="ShimsDir"/> to PATH — guaranteeing the shim wins the
    /// lookup no matter what the user's <c>.zshrc</c> does to PATH.
    /// </summary>
    private void EnsureZdotdirWritten()
    {
        Directory.CreateDirectory(_zdotdir);
        File.WriteAllText(Path.Combine(_zdotdir, ".zshenv"), ZdotZshenvBody);
        File.WriteAllText(Path.Combine(_zdotdir, ".zprofile"), ZdotZprofileBody);
        File.WriteAllText(Path.Combine(_zdotdir, ".zshrc"), ZdotZshrcBody);
        File.WriteAllText(Path.Combine(_zdotdir, ".zlogin"), ZdotZloginBody);
        File.WriteAllText(_bashrcFile, BashrcBody);
    }

    // .zshenv runs for every zsh invocation (interactive, login, scripts). Source the user's
    // real .zshenv if present, so any env exports there still apply.
    private const string ZdotZshenvBody =
        "# Corterm-managed zshenv. Sources the user's real .zshenv.\n" +
        "_corterm_real_zdotdir=\"${CORTERM_REAL_ZDOTDIR:-$HOME}\"\n" +
        "[[ -f \"$_corterm_real_zdotdir/.zshenv\" ]] && source \"$_corterm_real_zdotdir/.zshenv\"\n" +
        "unset _corterm_real_zdotdir\n";

    // .zprofile runs once for login shells. Source the user's real .zprofile so PATH/exports
    // set there still apply (we don't touch PATH here — .zshrc handles the prepend).
    private const string ZdotZprofileBody =
        "# Corterm-managed zprofile. Sources the user's real .zprofile.\n" +
        "_corterm_real_zdotdir=\"${CORTERM_REAL_ZDOTDIR:-$HOME}\"\n" +
        "[[ -f \"$_corterm_real_zdotdir/.zprofile\" ]] && source \"$_corterm_real_zdotdir/.zprofile\"\n" +
        "unset _corterm_real_zdotdir\n";

    // .zshrc is the critical file: source the user's .zshrc so aliases/completions/history all
    // load, then forcibly prepend CORTERM_SHIMS_DIR. Running AFTER the user's .zshrc means
    // their PATH manipulation (export PATH=$HOME/.local/bin:$PATH) cannot shadow the shim.
    // We strip any existing occurrence of the shims dir before prepending so the user's .zshrc
    // can't bury it in the middle of PATH — the shim must be FIRST.
    private const string ZdotZshrcBody =
        "# Corterm-managed zshrc.\n" +
        "_corterm_real_zdotdir=\"${CORTERM_REAL_ZDOTDIR:-$HOME}\"\n" +
        "[[ -f \"$_corterm_real_zdotdir/.zshrc\" ]] && source \"$_corterm_real_zdotdir/.zshrc\"\n" +
        "unset _corterm_real_zdotdir\n" +
        "\n" +
        "# Force-prepend CORTERM_SHIMS_DIR after the user's .zshrc so claude/codex/opencode\n" +
        "# always resolve to the Corterm shim, not the real binary the user may have installed\n" +
        "# elsewhere. Strip any existing occurrence first so the shim is unconditionally first.\n" +
        "if [[ -n \"$CORTERM_SHIMS_DIR\" && -d \"$CORTERM_SHIMS_DIR\" ]]; then\n" +
        "  _corterm_path=\"${PATH//$CORTERM_SHIMS_DIR:/}\"\n" +
        "  _corterm_path=\"${_corterm_path%:$CORTERM_SHIMS_DIR}\"\n" +
        "  export PATH=\"$CORTERM_SHIMS_DIR:$_corterm_path\"\n" +
        "  unset _corterm_path\n" +
        "fi\n";

    // .zlogin runs after .zshrc for login shells. Source the user's real .zlogin.
    private const string ZdotZloginBody =
        "# Corterm-managed zlogin. Sources the user's real .zlogin.\n" +
        "_corterm_real_zdotdir=\"${CORTERM_REAL_ZDOTDIR:-$HOME}\"\n" +
        "[[ -f \"$_corterm_real_zdotdir/.zlogin\" ]] && source \"$_corterm_real_zdotdir/.zlogin\"\n" +
        "unset _corterm_real_zdotdir\n";

    // Bash rcfile passed via `bash -i --rcfile=<this file>`. Bash doesn't honor ZDOTDIR, so
    // we launch as non-login interactive and manually source the user's .profile (login-style
    // exports) and .bashrc (interactive customizations). Then force-prepend CORTERM_SHIMS_DIR
    // so it always wins the PATH lookup regardless of what the user's rcfiles do to PATH.
    private const string BashrcBody =
        "# Corterm-managed bashrc.\n" +
        "[[ -f \"$HOME/.profile\" ]] && source \"$HOME/.profile\"\n" +
        "[[ -f \"$HOME/.bashrc\" ]] && source \"$HOME/.bashrc\"\n" +
        "\n" +
        "# Force-prepend CORTERM_SHIMS_DIR after the user's rcfiles so claude/codex/opencode\n" +
        "# always resolve to the Corterm shim. Strip any existing occurrence first.\n" +
        "if [[ -n \"$CORTERM_SHIMS_DIR\" && -d \"$CORTERM_SHIMS_DIR\" ]]; then\n" +
        "  _corterm_path=\"${PATH//$CORTERM_SHIMS_DIR:/}\"\n" +
        "  _corterm_path=\"${_corterm_path%:$CORTERM_SHIMS_DIR}\"\n" +
        "  export PATH=\"$CORTERM_SHIMS_DIR:$_corterm_path\"\n" +
        "  unset _corterm_path\n" +
        "fi\n";

    private static string UnixShimBody(string wrapperPath, string kind)
    {
        return $"#!/bin/sh\n" +
               $"# Corterm shim. Forwards `{kind}` to cortap so the agent tracking\n" +
               $"# wrapper can inject hooks, name the session, and stream activity frames.\n" +
               $"# Escape hatches: CORTERM_AGENT=0 {kind}, `command {kind}`, or use the\n" +
               $"# absolute path to the real binary.\n" +
               $"exec \"{wrapperPath}\" {kind} \"$@\"\n";
    }

    private static string WindowsShimBody(string wrapperPath, string kind)
    {
        return "@echo off\n" +
               "rem Corterm shim. Forwards `" + kind + "` to cortap.\n" +
               "rem Escape hatches: set CORTERM_AGENT=0, or call the absolute path.\n" +
               "setlocal\n" +
               $"\"{wrapperPath}\" {kind} %*\n";
    }
}
