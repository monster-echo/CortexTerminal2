namespace CortexTerminal.Mobile.Core.Diagnostics;

public sealed record BridgeOperationInfo(
    string Operation,
    long DurationMs,
    bool IsSuccess,
    DateTimeOffset Timestamp,
    string? ErrorMessage = null);

public sealed record BridgeDiagnosticsSnapshot(
    int TotalCalls,
    int FailureCount,
    IReadOnlyList<BridgeOperationInfo> RecentOperations);
