namespace CortexTerminal.AgentRunner;

/// <summary>
/// Output of a per-agent launch setup: the temp config dir to clean up on exit and any env
/// vars to apply to the spawned agent process. The wrapper applies env vars on top of the
/// inherited environment (so the agent still sees CORTERM_* vars) and removes the temp dir
/// after the agent exits.
/// </summary>
public sealed record LaunchSetupResult(string TempConfigDir, IReadOnlyDictionary<string, string> EnvironmentVariables);
