using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.WebSockets;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.WebSockets;

public sealed class TerminalWebSocketHandlerTests
{
    [Fact]
    public async Task HandleAsync_WithLatencyProbe_ReturnsLatencyAck()
    {
        var (handler, sessionId) = await CreateHandlerWithSessionAsync();
        var ws = new ScriptedWebSocket(
            """{"type":"latencyProbe","sessionId":"SESSION","probeId":"probe-1","clientTime":123}"""
                .Replace("SESSION", sessionId),
            closeAfterMessages: true);

        await handler.HandleAsync(ws, "test-user", sessionId, CancellationToken.None);

        ws.SentFrames.Select(ReadType).Should().ContainInOrder(
            "replaying",
            "replayCompleted",
            "live",
            "latencyAck");
        ReadFrame(ws.SentFrames.Last(ReadTypeIs("latencyAck")))
            .GetProperty("probeId").GetString()
            .Should().Be("probe-1");
    }

    [Fact]
    public async Task HandleAsync_WithDetach_SendsDetachedAndClosesSocket()
    {
        var (handler, sessionId) = await CreateHandlerWithSessionAsync();
        var ws = new ScriptedWebSocket(
            """{"type":"detach","sessionId":"SESSION"}""".Replace("SESSION", sessionId),
            closeAfterMessages: false);

        await handler.HandleAsync(ws, "test-user", sessionId, CancellationToken.None);

        ws.SentFrames.Select(ReadType).Should().Contain("detached");
        ws.CloseStatus.Should().Be(WebSocketCloseStatus.NormalClosure);
        ws.State.Should().Be(WebSocketState.Closed);
    }

    [Fact]
    public async Task HandleAsync_WithInvalidInputPayload_ReturnsInvalidFrame()
    {
        var (handler, sessionId) = await CreateHandlerWithSessionAsync();
        var ws = new ScriptedWebSocket(
            """{"type":"input","sessionId":"SESSION","payload":"not-base64!"}"""
                .Replace("SESSION", sessionId),
            closeAfterMessages: true);

        await handler.HandleAsync(ws, "test-user", sessionId, CancellationToken.None);

        var errorFrame = ReadFrame(ws.SentFrames.Last(ReadTypeIs("error")));
        errorFrame.GetProperty("code").GetString().Should().Be("invalid-frame");
    }

    private static async Task<(TerminalWebSocketHandler Handler, string SessionId)> CreateHandlerWithSessionAsync()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-ws-1", "worker-connection-1");

        var sessions = TestSessionFactory.CreateCoordinator(workers, timeProvider: new FixedTimeProvider(DateTimeOffset.UnixEpoch));
        var dispatcher = new NoOpWorkerCommandDispatcher();
        var launcher = new SessionLaunchCoordinator(sessions, dispatcher);
        var created = await launcher.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);

        created.IsSuccess.Should().BeTrue();

        var handler = new TerminalWebSocketHandler(
            sessions,
            new ReplayCoordinator(),
            dispatcher,
            launcher,
            new FixedTimeProvider(DateTimeOffset.UnixEpoch.AddSeconds(1)),
            new NoOpStatsService(),
            NullLogger<TerminalWebSocketHandler>.Instance);

        return (handler, created.Response!.SessionId);
    }

    private static string ReadType(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.GetProperty("type").GetString() ?? string.Empty;
    }

    private static Func<string, bool> ReadTypeIs(string type)
        => json => ReadType(json) == type;

    private static JsonElement ReadFrame(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.Clone();
    }

    private sealed class ScriptedWebSocket : WebSocket
    {
        private readonly Queue<byte[]> _messages;
        private readonly bool _closeAfterMessages;
        private WebSocketState _state = WebSocketState.Open;
        private WebSocketCloseStatus? _closeStatus;
        private string? _closeStatusDescription;

        public ScriptedWebSocket(string message, bool closeAfterMessages)
        {
            _messages = new Queue<byte[]>([Encoding.UTF8.GetBytes(message)]);
            _closeAfterMessages = closeAfterMessages;
        }

        public List<string> SentFrames { get; } = [];

        public override WebSocketCloseStatus? CloseStatus => _closeStatus;
        public override string? CloseStatusDescription => _closeStatusDescription;
        public override WebSocketState State => _state;
        public override string? SubProtocol => null;

        public override void Abort()
        {
            _state = WebSocketState.Aborted;
        }

        public override Task CloseAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken)
        {
            _closeStatus = closeStatus;
            _closeStatusDescription = statusDescription;
            _state = WebSocketState.Closed;
            return Task.CompletedTask;
        }

        public override Task CloseOutputAsync(WebSocketCloseStatus closeStatus, string? statusDescription, CancellationToken cancellationToken)
        {
            _closeStatus = closeStatus;
            _closeStatusDescription = statusDescription;
            _state = WebSocketState.CloseSent;
            return Task.CompletedTask;
        }

        public override void Dispose()
        {
            _state = WebSocketState.Closed;
        }

        public override Task<WebSocketReceiveResult> ReceiveAsync(ArraySegment<byte> buffer, CancellationToken cancellationToken)
        {
            if (_messages.TryDequeue(out var message))
            {
                message.CopyTo(buffer.Array!, buffer.Offset);
                return Task.FromResult(new WebSocketReceiveResult(message.Length, WebSocketMessageType.Text, endOfMessage: true));
            }

            if (!_closeAfterMessages)
            {
                cancellationToken.ThrowIfCancellationRequested();
            }

            _state = WebSocketState.CloseReceived;
            return Task.FromResult(new WebSocketReceiveResult(0, WebSocketMessageType.Close, endOfMessage: true));
        }

        public override Task SendAsync(ArraySegment<byte> buffer, WebSocketMessageType messageType, bool endOfMessage, CancellationToken cancellationToken)
        {
            SentFrames.Add(Encoding.UTF8.GetString(buffer.Array!, buffer.Offset, buffer.Count));
            return Task.CompletedTask;
        }
    }
}
