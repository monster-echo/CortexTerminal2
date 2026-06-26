using CortexTerminal.Contracts.Sessions;
using MessagePack;

namespace CortexTerminal.Contracts.Streaming;

/// <summary>
/// Marker base for agent activity frames so adapters and the loopback HTTP endpoint can
/// hand them around polymorphically. The sealed subtypes are what gets serialized.
/// </summary>
public abstract record BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentStartedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] AgentKind Kind,
    [property: Key(2)] string? AgentSessionId,
    [property: Key(3)] string? WorkDir) : BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentPromptSubmittedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string PromptText,
    [property: Key(2)] string? PromptId) : BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentToolCallFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string ToolName,
    [property: Key(2)] string? Input,
    [property: Key(3)] string? Output,
    [property: Key(4)] long DurationMs,
    [property: Key(5)] bool IsError) : BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentStoppedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] double? TotalCostUsd,
    [property: Key(2)] long? TotalTokensIn,
    [property: Key(3)] long? TotalTokensOut,
    [property: Key(4)] string? StopReason) : BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentSessionEndedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string? Reason) : BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentSubagentStoppedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string? SubagentId) : BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentNotifiedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string? Title,
    [property: Key(2)] string? Body) : BaseAgentActivityFrame;

[MessagePackObject]
public sealed record AgentCompactingFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string? Trigger) : BaseAgentActivityFrame;

