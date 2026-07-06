using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Registration;

namespace CortexTerminal.Worker.Tests.Artifacts.Fakes;

/// <summary>
/// In-memory <see cref="IWorkerGatewayClient"/> for ArtifactSyncService / ArtifactMirror tests.
/// Records every artifact-related RPC in observable lists. The polling-based awaiters snapshot
/// list contents on each tick, so they correctly handle requests that arrive before the test
/// registers the waiter (a common case when <see cref="ArtifactSyncService.StartAsync"/> runs
/// synchronously and fires its first upload URL request before the test awaits).
/// </summary>
internal sealed class FakeWorkerGatewayClient : IWorkerGatewayClient
{
    public List<CreateArtifactRequest> UploadUrlRequests { get; } = [];
    public List<CompleteArtifactRequest> CompleteRequests { get; } = [];
    public List<ReportArtifactDeletedFrame> DeletedReports { get; } = [];
    public List<NotifyArtifactUploadedFrame> NotifyFrames { get; } = [];
    public List<AgentTitleUpdatedFrame> AgentTitleUpdatedFrames { get; } = [];

    /// <summary>Optional responder used to answer <see cref="RequestArtifactUploadUrlAsync"/>. Default returns a synthetic URL.</summary>
    public Func<CreateArtifactRequest, UploadUrlResponse>? UploadUrlResponder { get; set; }

    /// <summary>Optional responder used to answer <see cref="CompleteArtifactUploadAsync"/>. Default returns success.</summary>
    public Func<CompleteArtifactRequest, CompleteArtifactAck>? CompleteResponder { get; set; }

    public Task<CreateArtifactRequest> WaitForUploadUrlRequestAsync(string filename, TimeSpan? timeout = null)
        => PollAsync(() => UploadUrlRequests.FirstOrDefault(r => r.Filename == filename),
                     x => x is not null, timeout ?? TimeSpan.FromSeconds(30))!;

    public Task<ReportArtifactDeletedFrame> WaitForDeleteReportAsync(string filename, TimeSpan? timeout = null)
        => PollAsync(() => DeletedReports.FirstOrDefault(r => r.Filename == filename),
                     x => x is not null, timeout ?? TimeSpan.FromSeconds(30))!;

    public Task<NotifyArtifactUploadedFrame> WaitForNotifyAsync(string filename, TimeSpan? timeout = null)
        => PollAsync(() => NotifyFrames.FirstOrDefault(f => f.Filename == filename),
                     x => x is not null, timeout ?? TimeSpan.FromSeconds(30))!;

    public Task<CompleteArtifactRequest> WaitForAnyCompleteRequestAsync(TimeSpan? timeout = null)
        => PollAsync(() => CompleteRequests.FirstOrDefault(), x => x is not null, timeout ?? TimeSpan.FromSeconds(30))!;

    /// <summary>Polls <paramref name="selector"/> until it returns a value satisfying <paramref name="predicate"/>, with a small delay between checks.</summary>
    private static async Task<T> PollAsync<T>(Func<T> selector, Func<T, bool> predicate, TimeSpan timeout)
    {
        var deadline = DateTimeOffset.UtcNow + timeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            var value = selector();
            if (predicate(value)) return value;
            await Task.Delay(25);
        }
        throw new TimeoutException($"Timed out after {timeout.TotalSeconds:0.##}s waiting for gateway condition.");
    }

    public Task<UploadUrlResponse> RequestArtifactUploadUrlAsync(CreateArtifactRequest request, CancellationToken ct)
    {
        UploadUrlRequests.Add(request);
        var resp = UploadUrlResponder?.Invoke(request)
            ?? new UploadUrlResponse(
                ArtifactId: $"artifact-{request.Filename}",
                UploadUrl: $"https://fake-s3.local/{request.SessionId}/{request.Filename}?sig=test",
                S3Key: $"{request.SessionId}/{request.Filename}",
                ExpiresAt: DateTimeOffset.UtcNow.AddMinutes(15));
        return Task.FromResult(resp);
    }

    public Task<CompleteArtifactAck> CompleteArtifactUploadAsync(CompleteArtifactRequest request, CancellationToken ct)
    {
        CompleteRequests.Add(request);
        var ack = CompleteResponder?.Invoke(request) ?? new CompleteArtifactAck(Success: true, Error: null);
        return Task.FromResult(ack);
    }

    public Task ReportArtifactDeletedAsync(ReportArtifactDeletedFrame frame, CancellationToken ct)
    {
        DeletedReports.Add(frame);
        return Task.CompletedTask;
    }

    public Task ReportWorkerSessionsAsync(WorkerSessionsSnapshot snapshot, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentStartedAsync(AgentStartedFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentPromptSubmittedAsync(AgentPromptSubmittedFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentToolCallAsync(AgentToolCallFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentStoppedAsync(AgentStoppedFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentSessionEndedAsync(AgentSessionEndedFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentSubagentStoppedAsync(AgentSubagentStoppedFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentNotifiedAsync(AgentNotifiedFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentCompactingAsync(AgentCompactingFrame frame, CancellationToken ct) => Task.CompletedTask;
    public Task ForwardAgentTitleUpdatedAsync(AgentTitleUpdatedFrame frame, CancellationToken ct)
    {
        AgentTitleUpdatedFrames.Add(frame);
        return Task.CompletedTask;
    }

    // Outbound-only APIs that ArtifactSyncService tests don't exercise. Provide harmless stubs.
    public Task StartAsync(CancellationToken cancellationToken) => Task.CompletedTask;
    public Task RegisterAsync(string workerId, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ForwardStderrAsync(TerminalChunk chunk, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ForwardLatencyProbeAsync(LatencyProbeFrame frame, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ForwardExitedAsync(SessionExited evt, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ForwardStartFailedAsync(SessionStartFailedEvent evt, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task SendWorkerInfoAsync(WorkerInfoFrame info, CancellationToken ct) => Task.CompletedTask;

    public IDisposable OnStartSession(Func<StartSessionCommand, Task> handler) => NoOpDisposable.Instance;
    public IDisposable OnWriteInput(Func<WriteInputFrame, Task> handler) => NoOpDisposable.Instance;
    public IDisposable OnLatencyProbe(Func<LatencyProbeFrame, Task> handler) => NoOpDisposable.Instance;
    public IDisposable OnResizeSession(Func<ResizePtyRequest, Task> handler) => NoOpDisposable.Instance;
    public IDisposable OnCloseSession(Func<CloseSessionRequest, Task> handler) => NoOpDisposable.Instance;
    public IDisposable OnUpgradeWorker(Func<UpgradeWorkerCommand, Task> handler) => NoOpDisposable.Instance;
    public IDisposable OnRequestScrollback(Func<string, IReadOnlyList<TerminalChunk>> handler) => NoOpDisposable.Instance;
    public IDisposable OnReconnected(Func<string?, Task> handler) => NoOpDisposable.Instance;
    public IDisposable OnClosed(Func<Exception?, Task> handler) => NoOpDisposable.Instance;

    public IDisposable OnNotifyArtifactUploaded(Func<NotifyArtifactUploadedFrame, Task> handler)
    {
        // Mirror the SignalR client behavior: capture the handler so tests can invoke it directly.
        return new NotifyArtifactHandlerDisposable(frame =>
        {
            NotifyFrames.Add(frame);
            return handler(frame);
        });
    }

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;

    internal sealed class NoOpDisposable : IDisposable
    {
        public static readonly NoOpDisposable Instance = new();
        public void Dispose() { }
    }

    internal sealed class NotifyArtifactHandlerDisposable(Func<NotifyArtifactUploadedFrame, Task> handler) : IDisposable
    {
        private readonly Func<NotifyArtifactUploadedFrame, Task> _handler = handler;
        public Task RaiseAsync(NotifyArtifactUploadedFrame frame) => _handler(frame);
        public void Dispose() { }
    }
}
