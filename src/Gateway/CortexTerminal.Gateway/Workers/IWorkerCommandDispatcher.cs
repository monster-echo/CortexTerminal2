using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Workers;

public interface IWorkerCommandDispatcher
{
    Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken);
    Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken);
    Task ProbeLatencyAsync(string workerConnectionId, LatencyProbeFrame frame, CancellationToken cancellationToken);
    Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken);
    Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken);
    Task UpgradeWorkerAsync(string workerConnectionId, UpgradeWorkerCommand command, CancellationToken cancellationToken);
    Task<IReadOnlyList<TerminalChunk>> RequestScrollbackAsync(string workerConnectionId, string sessionId, CancellationToken cancellationToken);
    Task<ScrollbackDelta> RequestScrollbackSinceAsync(string workerConnectionId, string sessionId, long sinceSeq, CancellationToken cancellationToken);
    Task<FileListingResult> ListFilesAsync(string workerConnectionId, string relativePath, CancellationToken cancellationToken);
    Task<FileOperationAck> MirrorUploadedFileAsync(string workerConnectionId, FileMirrorRequest request, CancellationToken cancellationToken);
    Task<FileOperationAck> BeginFileUploadAsync(string workerConnectionId, BeginFileUploadRequest request, CancellationToken cancellationToken);
    Task<ProbePortResponse> ProbeTunnelPortAsync(string workerConnectionId, int port, CancellationToken cancellationToken);
    Task<TunnelHttpResponse> SendTunnelHttpRequestAsync(string workerConnectionId, string tunnelId, TunnelHttpRequest request, CancellationToken cancellationToken);
}
