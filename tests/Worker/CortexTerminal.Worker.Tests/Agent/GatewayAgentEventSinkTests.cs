using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Agent;
using CortexTerminal.Worker.Registration;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Agent;

/// <summary>
/// GatewayAgentEventSink routes each structured frame to a dedicated hub RPC. The
/// AgentTitleUpdatedFrame branch ships with the title-update pipeline and has no other coverage —
/// these tests pin the routing so the title reaches ForwardAgentTitleUpdatedAsync instead of
/// falling through and being silently dropped.
/// </summary>
public sealed class GatewayAgentEventSinkTests
{
    [Fact]
    public async Task DispatchAsync_AgentTitleUpdatedFrame_RoutesToForwardAgentTitleUpdated()
    {
        var gateway = new RecordingGateway();
        var sink = new GatewayAgentEventSink(gateway, NullLogger<GatewayAgentEventSink>.Instance);
        var frame = new AgentTitleUpdatedFrame("sess-1", "Live Title");

        await sink.DispatchAsync(frame, CancellationToken.None);

        gateway.TitleUpdatedFrames.Should().ContainSingle().Which.Should().Be(frame);
    }

    [Fact]
    public async Task DispatchAsync_UnknownFrame_ThrowsInvalidOperationException()
    {
        var gateway = new RecordingGateway();
        var sink = new GatewayAgentEventSink(gateway, NullLogger<GatewayAgentEventSink>.Instance);

        var act = async () => await sink.DispatchAsync(new UnknownFrame(), CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>();
    }

    private sealed record UnknownFrame : BaseAgentActivityFrame;

    /// <summary>
    /// Minimal self-contained IWorkerGatewayClient that only records title-update calls. Every
    /// other member is a no-op so this tracked test does not depend on the gitignored test doubles
    /// under Worker.Tests/Artifacts/ (which would break on a fresh checkout).
    /// </summary>
    private sealed class RecordingGateway : IWorkerGatewayClient
    {
        public List<AgentTitleUpdatedFrame> TitleUpdatedFrames { get; } = [];

        public Task ForwardAgentTitleUpdatedAsync(AgentTitleUpdatedFrame frame, CancellationToken ct)
        {
            TitleUpdatedFrames.Add(frame);
            return Task.CompletedTask;
        }

        public Task StartAsync(CancellationToken cancellationToken) => Task.CompletedTask;
        public Task RegisterAsync(string workerId, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task ForwardStderrAsync(TerminalChunk chunk, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task ForwardLatencyProbeAsync(LatencyProbeFrame frame, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task ForwardExitedAsync(SessionExited evt, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task ForwardStartFailedAsync(SessionStartFailedEvent evt, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task ForwardAgentStartedAsync(AgentStartedFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task ForwardAgentPromptSubmittedAsync(AgentPromptSubmittedFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task ForwardAgentToolCallAsync(AgentToolCallFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task ForwardAgentStoppedAsync(AgentStoppedFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task ForwardAgentSessionEndedAsync(AgentSessionEndedFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task ForwardAgentSubagentStoppedAsync(AgentSubagentStoppedFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task ForwardAgentNotifiedAsync(AgentNotifiedFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task ForwardAgentCompactingAsync(AgentCompactingFrame frame, CancellationToken ct) => Task.CompletedTask;
        public Task SendWorkerInfoAsync(WorkerInfoFrame info, CancellationToken ct) => Task.CompletedTask;
        public Task<UploadUrlResponse> RequestArtifactUploadUrlAsync(CreateArtifactRequest request, CancellationToken ct)
            => throw new NotImplementedException();
        public Task<CompleteArtifactAck> CompleteArtifactUploadAsync(CompleteArtifactRequest request, CancellationToken ct)
            => throw new NotImplementedException();
        public Task ReportArtifactDeletedAsync(ReportArtifactDeletedFrame frame, CancellationToken ct) => Task.CompletedTask;
        public IDisposable OnStartSession(Func<StartSessionCommand, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnWriteInput(Func<WriteInputFrame, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnLatencyProbe(Func<LatencyProbeFrame, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnResizeSession(Func<ResizePtyRequest, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnCloseSession(Func<CloseSessionRequest, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnUpgradeWorker(Func<UpgradeWorkerCommand, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnRequestScrollback(Func<string, IReadOnlyList<TerminalChunk>> handler) => NoOpDisposable.Instance;
        public IDisposable OnNotifyArtifactUploaded(Func<NotifyArtifactUploadedFrame, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnReconnected(Func<string?, Task> handler) => NoOpDisposable.Instance;
        public IDisposable OnClosed(Func<Exception?, Task> handler) => NoOpDisposable.Instance;
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;

        private sealed class NoOpDisposable : IDisposable
        {
            public static readonly NoOpDisposable Instance = new();
            public void Dispose() { }
        }
    }
}
