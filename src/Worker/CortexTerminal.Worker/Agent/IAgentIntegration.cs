namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Provides the per-Worker agent tracking configuration: the loopback HTTP
/// endpoint that hook events POST to, the directory where shim scripts live
/// (prepended to PTY PATH), and the original PATH so the wrapper binary can
/// locate the real agent binary.
/// </summary>
public interface IAgentIntegration
{
    /// <summary>True when agent tracking is wired up (HTTP endpoint running, shims installed).</summary>
    bool Enabled { get; }

    /// <summary>Loopback HTTP URL that hook events should POST to, e.g. http://127.0.0.1:51423/agent-event.</summary>
    string HookUrl { get; }

    /// <summary>Directory containing claude/codex/opencode shim scripts. Prepended to PTY PATH.</summary>
    string ShimsDir { get; }

    /// <summary>
    /// Managed ZDOTDIR for zsh sessions. Its <c>.zshrc</c> sources the user's real
    /// <c>.zshrc</c> (so aliases/completions still load) and then prepends
    /// <see cref="ShimsDir"/> to <c>PATH</c> — guaranteeing the shim wins the lookup
    /// even when the user's <c>.zshrc</c> rewrites PATH (e.g. <c>export PATH=$HOME/.local/bin:$PATH</c>).
    /// </summary>
    string Zdotdir { get; }

    /// <summary>
    /// Path to a managed bash rcfile. The PTY launches bash as
    /// <c>bash -i --rcfile=&lt;BashrcFile&gt;</c>; the rcfile sources the user's real
    /// <c>.profile</c> and <c>.bashrc</c> (so existing exports/aliases still apply) and
    /// then prepends <see cref="ShimsDir"/> to <c>PATH</c> — same guarantee as
    /// <see cref="Zdotdir"/> but for bash.
    /// </summary>
    string BashrcFile { get; }

    /// <summary>PATH before the shim dir was prepended. The wrapper uses this to find the real agent binary.</summary>
    string OriginalPath { get; }
}
