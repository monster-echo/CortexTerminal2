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
    Task<FileListingResult> ListFilesAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken);
    Task<FileOpResult> MkdirAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken);
    Task<FileOpResult> WriteTextFileAsync(string workerConnectionId, string rootDir, string relativePath, string content, CancellationToken cancellationToken);
    Task<FileOpResult> RenameAsync(string workerConnectionId, string rootDir, string relativePath, string newName, CancellationToken cancellationToken);
    Task<FileOpResult> DeleteAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken);
    Task<FileOperationAck> PrepareFileReceiveAsync(string workerConnectionId, PrepareFileReceiveCommand command, CancellationToken cancellationToken);
    Task<PrepareFileSendAck> PrepareFileSendAsync(string workerConnectionId, PrepareFileSendCommand command, CancellationToken cancellationToken);
    Task<WorkspaceDirectoryAck> CreateWorkspaceDirectoryAsync(string workerConnectionId, CreateWorkspaceDirectoryCommand command, CancellationToken cancellationToken);
    Task<FileOperationAck> IssueRelayTokenAsync(string workerConnectionId, string relayUrl, string token, CancellationToken cancellationToken);
    Task<ProbePortResponse> ProbeTunnelPortAsync(string workerConnectionId, int port, CancellationToken cancellationToken);
}
