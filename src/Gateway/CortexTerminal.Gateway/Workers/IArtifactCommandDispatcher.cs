using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Workers;

/// <summary>
/// Sends artifact-related commands from Gateway to a specific Worker over the WorkerHub SignalR connection.
/// Used to notify the Worker about artifacts uploaded by Console clients so it can pull them locally.
/// </summary>
public interface IArtifactCommandDispatcher
{
    /// <summary>
    /// Tell the Worker that a Console client uploaded an artifact. The frame carries a
    /// short-lived presigned GET URL the Worker uses to download the bytes from S3.
    /// </summary>
    Task NotifyArtifactUploadedAsync(string workerConnectionId, NotifyArtifactUploadedFrame frame, CancellationToken ct);
}
