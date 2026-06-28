namespace CortexTerminal.AgentRunner;

/// <summary>
/// Output of a per-agent launch setup: the temp config dir to clean up on exit, any env
/// vars to apply to the spawned agent process, and any passthrough args to prepend to the
/// user's args. The wrapper applies env vars on top of the inherited environment (so the
/// agent still sees CORTERM_* vars), prepends PassthroughArgs to the user's args, then
/// removes the temp dir after the agent exits.
/// </summary>
public sealed record LaunchSetupResult(
    string TempConfigDir,
    IReadOnlyDictionary<string, string> EnvironmentVariables,
    IReadOnlyList<string> PassthroughArgs);
