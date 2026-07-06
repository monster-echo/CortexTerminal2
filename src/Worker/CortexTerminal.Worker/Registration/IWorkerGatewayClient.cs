using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Worker.Registration;

public interface IWorkerGatewayClient : IAsyncDisposable
{
    Task StartAsync(CancellationToken cancellationToken);
    Task RegisterAsync(string workerId, CancellationToken cancellationToken);
    IDisposable OnStartSession(Func<StartSessionCommand, Task> handler);
    IDisposable OnWriteInput(Func<WriteInputFrame, Task> handler);
    IDisposable OnLatencyProbe(Func<LatencyProbeFrame, Task> handler);
    IDisposable OnResizeSession(Func<ResizePtyRequest, Task> handler);
    IDisposable OnCloseSession(Func<CloseSessionRequest, Task> handler);
    IDisposable OnUpgradeWorker(Func<UpgradeWorkerCommand, Task> handler);
    IDisposable OnRequestScrollback(Func<string, IReadOnlyList<TerminalChunk>> handler);
    IDisposable OnReconnected(Func<string?, Task> handler);
    IDisposable OnClosed(Func<Exception?, Task> handler);
    IDisposable OnNotifyArtifactUploaded(Func<NotifyArtifactUploadedFrame, Task> handler);
    Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken);
    Task ForwardStderrAsync(TerminalChunk chunk, CancellationToken cancellationToken);
    Task ForwardLatencyProbeAsync(LatencyProbeFrame frame, CancellationToken cancellationToken);
    Task ForwardExitedAsync(SessionExited evt, CancellationToken cancellationToken);
    Task ForwardStartFailedAsync(SessionStartFailedEvent evt, CancellationToken cancellationToken);
    Task ForwardAgentStartedAsync(AgentStartedFrame frame, CancellationToken ct);
    Task ForwardAgentPromptSubmittedAsync(AgentPromptSubmittedFrame frame, CancellationToken ct);
    Task ForwardAgentToolCallAsync(AgentToolCallFrame frame, CancellationToken ct);
    Task ForwardAgentStoppedAsync(AgentStoppedFrame frame, CancellationToken ct);
    Task ForwardAgentSessionEndedAsync(AgentSessionEndedFrame frame, CancellationToken ct);
    Task ForwardAgentSubagentStoppedAsync(AgentSubagentStoppedFrame frame, CancellationToken ct);
    Task ForwardAgentNotifiedAsync(AgentNotifiedFrame frame, CancellationToken ct);
    Task ForwardAgentCompactingAsync(AgentCompactingFrame frame, CancellationToken ct);
    Task ForwardAgentTitleUpdatedAsync(AgentTitleUpdatedFrame frame, CancellationToken ct);
    Task SendWorkerInfoAsync(WorkerInfoFrame info, CancellationToken ct);
    Task<UploadUrlResponse> RequestArtifactUploadUrlAsync(CreateArtifactRequest request, CancellationToken ct);
    Task<CompleteArtifactAck> CompleteArtifactUploadAsync(CompleteArtifactRequest request, CancellationToken ct);
    Task ReportArtifactDeletedAsync(ReportArtifactDeletedFrame frame, CancellationToken ct);
}
