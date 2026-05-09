using System.Net.Http.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Mobile.App.Services.Auth;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Mobile.App.Services.Terminal;

public sealed class TerminalGatewayService
{
    private readonly Uri _gatewayBaseUri;
    private readonly AuthService _authService;
    private readonly HttpClient _httpClient;
    private readonly ILogger<TerminalGatewayService> _logger;
    private HubConnection? _connection;
    private string? _connectedSessionId;

    public TerminalGatewayService(Uri gatewayBaseUri, AuthService authService, HttpClient httpClient, ILogger<TerminalGatewayService> logger)
    {
        _gatewayBaseUri = gatewayBaseUri;
        _authService = authService;
        _httpClient = httpClient;
        _logger = logger;
        // Pre-warm the HttpClient connection pool (DNS + TLS) in the background
        _ = WarmUpAsync();
    }

    private async Task WarmUpAsync()
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            LogDiag($"[GATEWAY] WarmUp START");
            using var request = new HttpRequestMessage(HttpMethod.Head, _gatewayBaseUri);
            using var response = await _httpClient.SendAsync(request, CancellationToken.None);
            LogDiag($"[GATEWAY] WarmUp DONE in {sw.ElapsedMilliseconds}ms status={response.StatusCode}");
        }
        catch (Exception ex)
        {
            LogDiag($"[GATEWAY] WarmUp FAIL in {sw.ElapsedMilliseconds}ms: {ex.Message}");
        }
    }

    public event Func<object, Task>? TerminalEvent;

    public async Task<IReadOnlyList<SessionSummaryDto>> ListSessionsAsync(CancellationToken cancellationToken)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var token = await RequireTokenAsync(cancellationToken);
        _logger.LogInformation("ListSessions: token acquired in {Ms}ms", sw.ElapsedMilliseconds);
        using var request = CreateRequest(HttpMethod.Get, "/api/me/sessions", token);
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var result = await response.Content.ReadFromJsonAsync<List<SessionSummaryDto>>(cancellationToken) ?? [];
        _logger.LogInformation("ListSessions: completed in {Ms}ms, {Count} sessions", sw.ElapsedMilliseconds, result.Count);
        return result;
    }

    public async Task<IReadOnlyList<WorkerSummaryDto>> ListWorkersAsync(CancellationToken cancellationToken)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        LogDiag($"[GATEWAY] ListWorkers START thread={Environment.CurrentManagedThreadId}");
        var token = await RequireTokenAsync(cancellationToken);
        LogDiag($"[GATEWAY] ListWorkers RequireToken done in {sw.ElapsedMilliseconds}ms");
        using var request = CreateRequest(HttpMethod.Get, "/api/me/workers", token);
        LogDiag($"[GATEWAY] ListWorkers SendAsync START");
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        LogDiag($"[GATEWAY] ListWorkers SendAsync done in {sw.ElapsedMilliseconds}ms status={response.StatusCode}");
        response.EnsureSuccessStatusCode();
        var result = await response.Content.ReadFromJsonAsync<List<WorkerSummaryDto>>(cancellationToken) ?? [];
        LogDiag($"[GATEWAY] ListWorkers TOTAL {sw.ElapsedMilliseconds}ms, {result.Count} workers");
        return result;
    }

    public async Task<CreateSessionResponse> CreateSessionAsync(int columns, int rows, string? workerId, CancellationToken cancellationToken)
    {
        using var request = CreateRequest(HttpMethod.Post, "/api/sessions", await RequireTokenAsync(cancellationToken));
        request.Content = JsonContent.Create(new CreateSessionRequest(
            "shell",
            columns,
            rows,
            Guid.NewGuid().ToString("N"),
            string.IsNullOrWhiteSpace(workerId) ? null : workerId));

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<CreateSessionResponse>(cancellationToken)
            ?? throw new InvalidOperationException("Gateway returned an empty create session response.");
    }

    public async Task ConnectSessionAsync(string sessionId, CancellationToken cancellationToken)
    {
        if (_connection is not null && _connectedSessionId == sessionId)
        {
            return;
        }

        await DisconnectAsync();

        var connection = new HubConnectionBuilder()
            .WithUrl(new Uri(_gatewayBaseUri, "/hubs/terminal"), options =>
            {
                options.AccessTokenProvider = async () => (await _authService.GetSessionAsync(CancellationToken.None))?.Token;
                options.HttpMessageHandlerFactory = _ => MauiProgram.CreateGatewayHandler();
                options.Transports = Microsoft.AspNetCore.Http.Connections.HttpTransportType.WebSockets |
                                     Microsoft.AspNetCore.Http.Connections.HttpTransportType.LongPolling;
            })
            .AddMessagePackProtocol()
            .WithAutomaticReconnect()
            .Build();

        RegisterHandlers(connection, sessionId);

        LogDiag($"[GATEWAY] ConnectSession StartAsync START");
        await connection.StartAsync(cancellationToken);
        LogDiag($"[GATEWAY] ConnectSession StartAsync DONE, invoking ReattachSession");
        var result = await connection.InvokeAsync<ReattachSessionResult>(
            "ReattachSession",
            new ReattachSessionRequest(sessionId),
            cancellationToken);

        if (!result.IsSuccess)
        {
            await connection.DisposeAsync();
            throw new InvalidOperationException(result.ErrorCode ?? "Could not reattach session.");
        }

        _connection = connection;
        _connectedSessionId = sessionId;
        await PushEventAsync(new { type = "terminal.connected", sessionId });
    }

    public async Task WriteInputAsync(string sessionId, string text, CancellationToken cancellationToken)
    {
        var connection = RequireConnection(sessionId);
        await connection.InvokeAsync(
            "WriteInput",
            new WriteInputFrame(sessionId, System.Text.Encoding.UTF8.GetBytes(text)),
            cancellationToken);
    }

    public async Task ResizeAsync(string sessionId, int columns, int rows, CancellationToken cancellationToken)
    {
        var connection = RequireConnection(sessionId);
        await connection.InvokeAsync(
            "ResizeSession",
            new ResizePtyRequest(sessionId, columns, rows),
            cancellationToken);
    }

    public async Task CloseSessionAsync(string sessionId, CancellationToken cancellationToken)
    {
        var connection = RequireConnection(sessionId);
        await connection.InvokeAsync("CloseSession", new CloseSessionRequest(sessionId), cancellationToken);
    }

    public async Task DisconnectAsync()
    {
        if (_connection is null)
        {
            return;
        }

        var connection = _connection;
        var sessionId = _connectedSessionId;
        _connection = null;
        _connectedSessionId = null;

        try
        {
            await connection.StopAsync();
            await connection.DisposeAsync();
        }
        finally
        {
            if (!string.IsNullOrWhiteSpace(sessionId))
            {
                await PushEventAsync(new { type = "terminal.disconnected", sessionId });
            }
        }
    }

    private void RegisterHandlers(HubConnection connection, string sessionId)
    {
        connection.On<SessionReattachedEvent>("SessionReattached", evt =>
        {
            if (evt.SessionId == sessionId)
            {
                _ = PushEventAsync(new { type = "terminal.reattached", evt.SessionId });
            }
        });
        connection.On<ReplayChunk>("ReplayChunk", chunk => PushTerminalChunkAsync("terminal.replay", sessionId, chunk.SessionId, chunk.Stream, chunk.Payload));
        connection.On<ReplayCompleted>("ReplayCompleted", evt =>
        {
            if (evt.SessionId == sessionId)
            {
                _ = PushEventAsync(new { type = "terminal.replayCompleted", evt.SessionId });
            }
        });
        connection.On<TerminalChunk>("StdoutChunk", chunk => PushTerminalChunkAsync("terminal.output", sessionId, chunk.SessionId, "stdout", chunk.Payload));
        connection.On<TerminalChunk>("StderrChunk", chunk => PushTerminalChunkAsync("terminal.output", sessionId, chunk.SessionId, "stderr", chunk.Payload));
        connection.On<SessionExpiredEvent>("SessionExpired", evt =>
        {
            if (evt.SessionId == sessionId)
            {
                _ = PushEventAsync(new { type = "terminal.expired", evt.SessionId, evt.Reason });
            }
        });
        connection.On<SessionExited>("SessionExited", evt =>
        {
            if (evt.SessionId == sessionId)
            {
                _ = PushEventAsync(new { type = "terminal.exited", evt.SessionId, evt.ExitCode, evt.Reason });
            }
        });
        connection.On<SessionStartFailedEvent>("SessionStartFailed", evt =>
        {
            if (evt.SessionId == sessionId)
            {
                _ = PushEventAsync(new { type = "terminal.startFailed", evt.SessionId, evt.Reason });
            }
        });
        connection.Reconnecting += error => PushEventAsync(new { type = "terminal.reconnecting", sessionId, reason = error?.Message });
        connection.Reconnected += _ => PushEventAsync(new { type = "terminal.reconnected", sessionId });
        connection.Closed += error => PushEventAsync(new { type = "terminal.closed", sessionId, reason = error?.Message });
    }

    private Task PushTerminalChunkAsync(string type, string expectedSessionId, string actualSessionId, string stream, byte[] payload)
    {
        if (actualSessionId != expectedSessionId)
        {
            return Task.CompletedTask;
        }

        return PushEventAsync(new
        {
            type,
            sessionId = actualSessionId,
            stream,
            base64 = Convert.ToBase64String(payload),
            byteLength = payload.Length,
        });
    }

    private async Task PushEventAsync(object payload)
    {
        var handler = TerminalEvent;
        if (handler is null)
        {
            return;
        }

        try
        {
            await handler(payload);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to push terminal event to web view.");
        }
    }

    private HubConnection RequireConnection(string sessionId)
    {
        if (_connection is null || _connectedSessionId != sessionId)
        {
            throw new InvalidOperationException("Terminal session is not connected.");
        }

        return _connection;
    }

    private async Task<string> RequireTokenAsync(CancellationToken cancellationToken)
    {
        LogDiag($"[GATEWAY] RequireToken START thread={Environment.CurrentManagedThreadId}");
        var session = await _authService.GetSessionAsync(cancellationToken);
        LogDiag($"[GATEWAY] RequireToken GetSessionAsync done, token={session?.Token?.Length ?? 0} chars");
        if (session is null || string.IsNullOrWhiteSpace(session.Token) || session.Token == "guest")
        {
            throw new InvalidOperationException("Gateway authentication is required.");
        }

        return session.Token;
    }

    private HttpRequestMessage CreateRequest(HttpMethod method, string path, string token)
    {
        var request = new HttpRequestMessage(method, new Uri(_gatewayBaseUri, path));
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    public sealed record SessionSummaryDto(
        string SessionId,
        string WorkerId,
        string Status,
        DateTimeOffset CreatedAt,
        DateTimeOffset LastActivityAt);

    public sealed record WorkerSummaryDto(
        string WorkerId,
        string? Name,
        string? Hostname,
        string? OperatingSystem,
        string? Architecture,
        string? Version,
        string? Address,
        bool IsOnline,
        DateTimeOffset? LastSeenAtUtc,
        int SessionCount);

    private static void LogDiag(string message)
    {
#if ANDROID
        Android.Util.Log.Info("CT", message);
#else
        System.Diagnostics.Debug.WriteLine(message);
#endif
    }
}
