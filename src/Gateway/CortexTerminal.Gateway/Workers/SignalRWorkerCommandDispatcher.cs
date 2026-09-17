using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Workers;

public sealed class SignalRWorkerCommandDispatcher(IHubContext<WorkerHub> hubContext) : IWorkerCommandDispatcher
{
    public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("StartSession", command, cancellationToken);

    public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("WriteInput", frame, cancellationToken);

    public Task ProbeLatencyAsync(string workerConnectionId, LatencyProbeFrame frame, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("ProbeLatency", frame, cancellationToken);

    public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("ResizeSession", request, cancellationToken);

    public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("CloseSession", request, cancellationToken);

    public Task UpgradeWorkerAsync(string workerConnectionId, UpgradeWorkerCommand command, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("UpgradeWorker", command, cancellationToken);

    public Task<IReadOnlyList<TerminalChunk>> RequestScrollbackAsync(string workerConnectionId, string sessionId, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<IReadOnlyList<TerminalChunk>>("RequestScrollback", sessionId, cancellationToken);

    public Task<ScrollbackDelta> RequestScrollbackSinceAsync(string workerConnectionId, string sessionId, long sinceSeq, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<ScrollbackDelta>("RequestScrollbackSince", sessionId, sinceSeq, cancellationToken);

    public Task<FileListingResult> ListFilesAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<FileListingResult>("ListFiles", rootDir, relativePath, cancellationToken);

    public Task<FileOperationAck> PrepareFileReceiveAsync(string workerConnectionId, PrepareFileReceiveCommand command, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<FileOperationAck>("PrepareFileReceive", command, cancellationToken);

    public Task<PrepareFileSendAck> PrepareFileSendAsync(string workerConnectionId, PrepareFileSendCommand command, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<PrepareFileSendAck>("PrepareFileSend", command, cancellationToken);

    public Task<WorkspaceDirectoryAck> CreateWorkspaceDirectoryAsync(string workerConnectionId, CreateWorkspaceDirectoryCommand command, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<WorkspaceDirectoryAck>("CreateWorkspaceDirectory", command, cancellationToken);

    public Task<FileOperationAck> IssueRelayTokenAsync(string workerConnectionId, string relayUrl, string token, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<FileOperationAck>("IssueRelayToken", relayUrl, token, cancellationToken);

    public Task<ProbePortResponse> ProbeTunnelPortAsync(string workerConnectionId, int port, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).InvokeAsync<ProbePortResponse>("ProbeTunnelPort", port, cancellationToken);
}
