using System.Security.Claims;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.SignalR;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Stats;
using CortexTerminal.Gateway.Workspaces;
using CortexTerminal.Gateway.Workers;

namespace CortexTerminal.Gateway.Tests.Hubs;

internal sealed record ClientInvocation(string Method, IReadOnlyList<object?> Arguments);

internal sealed class RecordingClientProxy(Action<string, object?[]>? onSend = null) : ISingleClientProxy
{
    private readonly List<ClientInvocation> _invocations = [];

    public IReadOnlyList<ClientInvocation> Invocations => _invocations;

    public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
    {
        onSend?.Invoke(method, args);
        _invocations.Add(new ClientInvocation(method, args));
        return Task.CompletedTask;
    }

    public Task<T> InvokeCoreAsync<T>(string method, object?[] args, CancellationToken cancellationToken = default)
    {
        _invocations.Add(new ClientInvocation(method, args));
        return Task.FromResult<T>(default!);
    }
}

internal sealed class TestHubCallerClients(IClientProxy caller, IReadOnlyDictionary<string, IClientProxy>? clients = null) : IHubCallerClients
{
    private readonly IReadOnlyDictionary<string, IClientProxy> _clients = clients ?? new Dictionary<string, IClientProxy>();

    public IClientProxy All => NullClientProxy.Instance;
    public IClientProxy Caller => caller;
    public IClientProxy Others => NullClientProxy.Instance;

    public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => NullClientProxy.Instance;

    public IClientProxy Client(string connectionId)
        => _clients.TryGetValue(connectionId, out var client)
            ? client
            : NullClientProxy.Instance;

    public IClientProxy Clients(IReadOnlyList<string> connectionIds) => NullClientProxy.Instance;
    public IClientProxy Group(string groupName) => NullClientProxy.Instance;
    public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => NullClientProxy.Instance;
    public IClientProxy Groups(IReadOnlyList<string> groupNames) => NullClientProxy.Instance;
    public IClientProxy OthersInGroup(string groupName) => NullClientProxy.Instance;
    public IClientProxy User(string userId) => NullClientProxy.Instance;
    public IClientProxy Users(IReadOnlyList<string> userIds) => NullClientProxy.Instance;

    private sealed class NullClientProxy : IClientProxy
    {
        public static NullClientProxy Instance { get; } = new();

        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
            => Task.CompletedTask;
    }
}

internal sealed class TestHubCallerContext(string connectionId, string? userIdentifier = null) : HubCallerContext
{
    private readonly ClaimsPrincipal _user = new(new ClaimsIdentity(
    [
        new Claim(ClaimTypes.NameIdentifier, userIdentifier ?? "unknown")
    ], "Test"));
    private readonly IDictionary<object, object?> _items = new Dictionary<object, object?>();

    public override string ConnectionId => connectionId;
    public override string? UserIdentifier => userIdentifier;
    public override ClaimsPrincipal? User => _user;
    public override IDictionary<object, object?> Items => _items;
    public override IFeatureCollection Features { get; } = new FeatureCollection();
    public override CancellationToken ConnectionAborted => CancellationToken.None;

    public override void Abort()
    {
    }
}

internal sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => utcNow;
}

internal class NoOpWorkerCommandDispatcher : IWorkerCommandDispatcher
{
    public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ProbeLatencyAsync(string workerConnectionId, LatencyProbeFrame frame, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task UpgradeWorkerAsync(string workerConnectionId, UpgradeWorkerCommand command, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task<IReadOnlyList<TerminalChunk>> RequestScrollbackAsync(string workerConnectionId, string sessionId, CancellationToken cancellationToken)
        => Task.FromResult<IReadOnlyList<TerminalChunk>>(Array.Empty<TerminalChunk>());
    public Task<ScrollbackDelta> RequestScrollbackSinceAsync(string workerConnectionId, string sessionId, long sinceSeq, CancellationToken cancellationToken)
        => Task.FromResult(new ScrollbackDelta(Gap: true, LastSeq: 0, Items: []));
    public Task<FileListingResult> ListFilesAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken)
        => Task.FromResult(new FileListingResult(null, new FileOperationError(FileTransferErrorCode.TransferFailed, "no-op dispatcher")));
    public virtual Task<FileOperationAck> PrepareFileReceiveAsync(string workerConnectionId, PrepareFileReceiveCommand command, CancellationToken cancellationToken)
        => Task.FromResult(new FileOperationAck(false, new FileOperationError(FileTransferErrorCode.TransferFailed, "no-op dispatcher")));
    public Task<PrepareFileSendAck> PrepareFileSendAsync(string workerConnectionId, PrepareFileSendCommand command, CancellationToken cancellationToken)
        => Task.FromResult(new PrepareFileSendAck(false, new FileOperationError(FileTransferErrorCode.TransferFailed, "no-op dispatcher"), 0, ""));
    public Task<WorkspaceDirectoryAck> CreateWorkspaceDirectoryAsync(string workerConnectionId, CreateWorkspaceDirectoryCommand command, CancellationToken cancellationToken)
        => Task.FromResult(new WorkspaceDirectoryAck(false, new FileOperationError(FileTransferErrorCode.TransferFailed, "no-op dispatcher"), ""));
    public Task<FileOperationAck> IssueRelayTokenAsync(string workerConnectionId, string relayUrl, string token, CancellationToken cancellationToken)
        => Task.FromResult(new FileOperationAck(true, null));
    public Task<ProbePortResponse> ProbeTunnelPortAsync(string workerConnectionId, int port, CancellationToken cancellationToken)
        => Task.FromResult(new ProbePortResponse(true, null));
}

internal sealed class NoOpStatsService : IGatewayStatsService
{
    public void ClientConnected() { }
    public void ClientDisconnected() { }
    public void TouchHttpUser(string userId) { }
    public void RecordBytesTransferred(int byteCount) { }
    public GatewayStatsSnapshot GetSnapshot() => throw new NotSupportedException();
    public IReadOnlyList<HourlyStatsPoint> GetHourlyHistory(int hours) => [];
    public void CaptureSnapshot() { }
}

internal sealed class NoOpSessionStatsService : ISessionStatsService
{
    public void RecordBytes(string sessionId, string userId, int byteCount) { }
    public long GetSessionBytes(string sessionId) => 0;
    public long GetUserBytes(string userId) => 0;
    public IReadOnlyDictionary<string, long> GetAllSessionBytes() => new Dictionary<string, long>();
    public IReadOnlyDictionary<string, long> GetAllUserBytes() => new Dictionary<string, long>();
    public Task FlushAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

internal sealed class ThrowingWorkerCommandDispatcher(string message) : IWorkerCommandDispatcher
{
    public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken)
        => Task.FromException(new InvalidOperationException(message));

    public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken)
        => Task.CompletedTask;

    public Task ProbeLatencyAsync(string workerConnectionId, LatencyProbeFrame frame, CancellationToken cancellationToken)
        => Task.CompletedTask;

    public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
        => Task.CompletedTask;

    public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
        => Task.CompletedTask;

    public Task UpgradeWorkerAsync(string workerConnectionId, UpgradeWorkerCommand command, CancellationToken cancellationToken)
        => Task.FromException(new InvalidOperationException(message));

    public Task<IReadOnlyList<TerminalChunk>> RequestScrollbackAsync(string workerConnectionId, string sessionId, CancellationToken cancellationToken)
        => Task.FromException<IReadOnlyList<TerminalChunk>>(new InvalidOperationException(message));
    public Task<ScrollbackDelta> RequestScrollbackSinceAsync(string workerConnectionId, string sessionId, long sinceSeq, CancellationToken cancellationToken)
        => Task.FromException<ScrollbackDelta>(new InvalidOperationException(message));
    public Task<FileListingResult> ListFilesAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken)
        => Task.FromException<FileListingResult>(new InvalidOperationException(message));
    public Task<FileOperationAck> PrepareFileReceiveAsync(string workerConnectionId, PrepareFileReceiveCommand command, CancellationToken cancellationToken)
        => Task.FromException<FileOperationAck>(new InvalidOperationException(message));
    public Task<PrepareFileSendAck> PrepareFileSendAsync(string workerConnectionId, PrepareFileSendCommand command, CancellationToken cancellationToken)
        => Task.FromException<PrepareFileSendAck>(new InvalidOperationException(message));
    public Task<WorkspaceDirectoryAck> CreateWorkspaceDirectoryAsync(string workerConnectionId, CreateWorkspaceDirectoryCommand command, CancellationToken cancellationToken)
        => Task.FromException<WorkspaceDirectoryAck>(new InvalidOperationException(message));
    public Task<FileOperationAck> IssueRelayTokenAsync(string workerConnectionId, string relayUrl, string token, CancellationToken cancellationToken)
        => Task.FromResult(new FileOperationAck(true, null));
    public Task<ProbePortResponse> ProbeTunnelPortAsync(string workerConnectionId, int port, CancellationToken cancellationToken)
        => Task.FromException<ProbePortResponse>(new InvalidOperationException(message));
}

/// <summary>PrepareFileReceive 永远成功（其余成员与 NoOp 一致），用于端点协商测试。</summary>
internal sealed class PrepareAcceptingWorkerCommandDispatcher : NoOpWorkerCommandDispatcher
{
    public override Task<FileOperationAck> PrepareFileReceiveAsync(string workerConnectionId, PrepareFileReceiveCommand command, CancellationToken cancellationToken)
        => Task.FromResult(new FileOperationAck(true, null));
}
