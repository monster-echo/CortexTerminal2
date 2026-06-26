namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Per-session context handed to <see cref="IAgentAdapter"/> when generating
/// hook config / parsing events. Captures everything the adapter needs to
/// correlate the agent run with the Corterm session.
/// </summary>
public sealed record AgentSessionContext(
    string SessionId,
    string HookUrl,
    string WorkDir,
    string TempConfigDir);
