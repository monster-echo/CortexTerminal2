namespace CortexTerminal.AgentRunner;

/// <summary>
/// Per-agent launch setup. Implementations prepare a temp config dir, write hook config
/// files, and return env vars to apply to the spawned agent process. The wrapper cleans up
/// the temp dir after the agent exits.
/// </summary>
public interface IAgentLaunchSetup
{
    /// <summary>Kind name from <see cref="AgentBinaryResolver.SupportedKinds"/> (e.g. "claude").</summary>
    string Kind { get; }

    /// <summary>Prepare the temp config dir and return env vars + cleanup target. Throws on failure.</summary>
    LaunchSetupResult Prepare();
}
