using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Workers;

namespace CortexTerminal.Gateway.Tests.Sessions.Fakes;

/// <summary>
/// Captures every NotifyArtifactUploaded call so tests can assert that the Gateway
/// forwarded the right frame to the right worker connection. Doesn't actually push
/// anything to a worker.
/// </summary>
internal sealed class RecordingArtifactCommandDispatcher : IArtifactCommandDispatcher
{
    private readonly Func<string, NotifyArtifactUploadedFrame, Task>? _onNotify;

    public List<(string WorkerConnectionId, NotifyArtifactUploadedFrame Frame)> Notifications { get; } = new();

    public RecordingArtifactCommandDispatcher(Func<string, NotifyArtifactUploadedFrame, Task>? onNotify = null)
    {
        _onNotify = onNotify;
    }

    public async Task NotifyArtifactUploadedAsync(string workerConnectionId, NotifyArtifactUploadedFrame frame, CancellationToken ct)
    {
        Notifications.Add((workerConnectionId, frame));
        if (_onNotify is not null) await _onNotify(workerConnectionId, frame);
    }
}
