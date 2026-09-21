namespace CortexTerminal.AgentRunner;

/// <summary>
/// Output of a per-agent launch setup: the temp config dir to clean up on exit, and any
/// passthrough args to prepend to the user's args. The wrapper prepends PassthroughArgs
/// to the user's args, then removes the temp dir after the agent exits. Environment vars
/// are deliberately not part of this record — no launch setup has ever needed them.
/// </summary>
public sealed record LaunchSetupResult(
    string TempConfigDir,
    IReadOnlyList<string> PassthroughArgs);
