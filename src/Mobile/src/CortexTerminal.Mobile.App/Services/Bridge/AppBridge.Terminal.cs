using CortexTerminal.Mobile.App.Services.Terminal;
using CortexTerminal.Mobile.Core.Bridge;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    private TerminalGatewayService? _terminalGateway;

    internal void SetTerminalGateway(TerminalGatewayService terminalGateway)
    {
        _terminalGateway = terminalGateway;
        terminalGateway.TerminalEvent += payload => SendEventToWebViewAsync(payload, "terminal gateway event");
    }

    [BridgeMethod]
    public Task<string> ListTerminalSessionsAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            var terminal = RequireTerminalGateway();
            var sessions = await terminal.ListSessionsAsync(default);
            return sessions.Select(session => new
            {
                id = session.SessionId,
                title = ShortSessionTitle(session.SessionId),
                subtitle = session.WorkerId,
                cwd = (string?)null,
                status = MapSessionStatus(session.Status),
                updatedAt = session.LastActivityAt,
                pinned = false,
                workerId = session.WorkerId,
                gatewayStatus = session.Status,
            });
        });
    }

    [BridgeMethod]
    public Task<string> ListTerminalWorkersAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            LogDiag($"[BRIDGE] ListTerminalWorkersAsync START thread={Environment.CurrentManagedThreadId}");
            var terminal = RequireTerminalGateway();
            LogDiag($"[BRIDGE] ListTerminalWorkersAsync RequireTerminalGateway done");
            var workers = await terminal.ListWorkersAsync(default);
            LogDiag($"[BRIDGE] ListTerminalWorkersAsync ListWorkersAsync done, {workers.Count} workers");
            return workers.Select(worker => new
            {
                id = worker.WorkerId,
                name = worker.Name ?? worker.Hostname ?? worker.WorkerId,
                status = !worker.IsOnline ? "offline" : (worker.SessionCount > 0 ? "running" : "idle"),
                activeTask = worker.IsOnline ? $"{worker.SessionCount} sessions" : "offline",
                workerId = worker.WorkerId,
                worker.Hostname,
                worker.OperatingSystem,
                worker.Architecture,
                worker.Version,
                worker.SessionCount,
                worker.Address,
                LastSeenAtUtc = worker.LastSeenAtUtc?.ToString("o"),
            });
        });
    }

    [BridgeMethod]
    public Task<string> CreateTerminalSessionAsync(int columns = 120, int rows = 40, string? workerId = null)
    {
        return ExecuteSafeAsync(async () =>
        {
            var terminal = RequireTerminalGateway();
            var session = await terminal.CreateSessionAsync(columns, rows, workerId, default);
            return new
            {
                id = session.SessionId,
                title = ShortSessionTitle(session.SessionId),
                subtitle = session.WorkerId,
                cwd = (string?)null,
                status = "idle",
                updatedAt = DateTimeOffset.UtcNow,
                pinned = false,
                workerId = session.WorkerId,
            };
        });
    }

    [BridgeMethod]
    public Task<string> ConnectTerminalSessionAsync(string sessionId)
    {
        return ExecuteSafeVoidAsync(() => RequireTerminalGateway().ConnectSessionAsync(sessionId, default));
    }

    [BridgeMethod]
    public Task<string> WriteTerminalInputAsync(string sessionId, string text)
    {
        return ExecuteSafeVoidAsync(() => RequireTerminalGateway().WriteInputAsync(sessionId, text, default));
    }

    [BridgeMethod]
    public Task<string> ResizeTerminalSessionAsync(string sessionId, int columns, int rows)
    {
        return ExecuteSafeVoidAsync(() => RequireTerminalGateway().ResizeAsync(sessionId, columns, rows, default));
    }

    [BridgeMethod]
    public Task<string> CloseTerminalSessionAsync(string sessionId)
    {
        return ExecuteSafeVoidAsync(() => RequireTerminalGateway().CloseSessionAsync(sessionId, default));
    }

    [BridgeMethod]
    public Task<string> DisconnectTerminalSessionAsync()
    {
        return ExecuteSafeVoidAsync(() => RequireTerminalGateway().DisconnectAsync());
    }

    private TerminalGatewayService RequireTerminalGateway()
        => _terminalGateway ?? throw new InvalidOperationException("Terminal gateway is not configured.");

    private static string ShortSessionTitle(string sessionId)
        => sessionId.Length <= 12 ? sessionId : $"session {sessionId[..8]}";

    private static string MapSessionStatus(string status)
    {
        return status switch
        {
            "Attached" => "running",
            "DetachedGracePeriod" => "idle",
            "Exited" => "failed",
            "Expired" => "failed",
            _ => "idle",
        };
    }
}
