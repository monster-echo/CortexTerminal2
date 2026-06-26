using MessagePack;

namespace CortexTerminal.Contracts.Sessions;

[MessagePackObject]
public sealed record AgentRuntimeInfo(
    [property: Key(0)] AgentKind Kind,
    [property: Key(1)] string? AgentSessionId,
    [property: Key(2)] DateTimeOffset StartedAtUtc,
    [property: Key(3)] string? WorkDir);

public enum AgentKind
{
    None = 0,
    ClaudeCode = 1,
    Codex = 2,
    OpenCode = 3,
}

public static class AgentKindNames
{
    public const string ClaudeCode = "claude-code";
    public const string Codex = "codex";
    public const string OpenCode = "opencode";

    public static string? ToName(AgentKind kind) => kind switch
    {
        AgentKind.ClaudeCode => ClaudeCode,
        AgentKind.Codex => Codex,
        AgentKind.OpenCode => OpenCode,
        _ => null,
    };

    public static AgentKind FromName(string? name) => name switch
    {
        ClaudeCode => AgentKind.ClaudeCode,
        Codex => AgentKind.Codex,
        OpenCode => AgentKind.OpenCode,
        _ => AgentKind.None,
    };
}
