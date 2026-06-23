using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class SessionLaunchCoordinatorTests
{
    [Fact]
    public async Task CreateSessionAsync_PassesScrollbackSettingsMaxBytesToWorker()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-scrollback-1", "conn-scrollback-1");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var dispatcher = new RecordingWorkerCommandDispatcher();
        var scrollback = new ScrollbackSettings { MaxBytesOverride = 1024 * 1024 };
        var coordinator = new SessionLaunchCoordinator(sessions, dispatcher, scrollback, TestSessionFactory.CreatePreferenceService());

        var result = await coordinator.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        dispatcher.StartCommands.Should().ContainSingle()
            .Which.MaxBytes.Should().Be(1024 * 1024);
    }

    [Fact]
    public async Task CreateSessionAsync_UsesDerivedMaxBytesWhenNoOverride()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-scrollback-2", "conn-scrollback-2");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var dispatcher = new RecordingWorkerCommandDispatcher();
        var scrollback = new ScrollbackSettings { MaxMegabytes = 3 };
        var coordinator = new SessionLaunchCoordinator(sessions, dispatcher, scrollback, TestSessionFactory.CreatePreferenceService());

        await coordinator.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);

        dispatcher.StartCommands.Should().ContainSingle()
            .Which.MaxBytes.Should().Be(3 * 1024 * 1024);
    }

    [Fact]
    public async Task CreateSessionAsync_UsesUserPreferenceWhenSet()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-pref-1", "conn-pref-1");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var dispatcher = new RecordingWorkerCommandDispatcher();
        var prefService = TestSessionFactory.CreatePreferenceService();
        await prefService.SetScrollbackMaxBytesAsync("test-user", 1024 * 1024, CancellationToken.None);
        var coordinator = new SessionLaunchCoordinator(sessions, dispatcher, new ScrollbackSettings(), prefService);

        await coordinator.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);

        dispatcher.StartCommands.Should().ContainSingle()
            .Which.MaxBytes.Should().Be(1024 * 1024);
    }

    [Fact]
    public async Task CreateSessionAsync_ClampsAboveMaxAllowed()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-pref-2", "conn-pref-2");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var dispatcher = new RecordingWorkerCommandDispatcher();
        var prefService = TestSessionFactory.CreatePreferenceService();
        await prefService.SetScrollbackMaxBytesAsync("test-user", 10 * 1024 * 1024, CancellationToken.None);
        var coordinator = new SessionLaunchCoordinator(sessions, dispatcher, new ScrollbackSettings(), prefService);

        await coordinator.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);

        dispatcher.StartCommands.Should().ContainSingle()
            .Which.MaxBytes.Should().Be(5 * 1024 * 1024);
    }

    [Fact]
    public async Task CreateSessionAsync_ClampsBelowMinAllowed()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-pref-3", "conn-pref-3");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var dispatcher = new RecordingWorkerCommandDispatcher();
        var prefService = TestSessionFactory.CreatePreferenceService();
        await prefService.SetScrollbackMaxBytesAsync("test-user", 1024, CancellationToken.None);
        var coordinator = new SessionLaunchCoordinator(sessions, dispatcher, new ScrollbackSettings(), prefService);

        await coordinator.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);

        dispatcher.StartCommands.Should().ContainSingle()
            .Which.MaxBytes.Should().Be(16 * 1024);
    }

    private sealed class RecordingWorkerCommandDispatcher : IWorkerCommandDispatcher
    {
        public List<StartSessionCommand> StartCommands { get; } = [];

        public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken)
        {
            StartCommands.Add(command);
            return Task.CompletedTask;
        }

        public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task ProbeLatencyAsync(string workerConnectionId, LatencyProbeFrame frame, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task UpgradeWorkerAsync(string workerConnectionId, UpgradeWorkerCommand command, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task<IReadOnlyList<TerminalChunk>> RequestScrollbackAsync(string workerConnectionId, string sessionId, CancellationToken cancellationToken)
            => Task.FromResult<IReadOnlyList<TerminalChunk>>(Array.Empty<TerminalChunk>());
    }
}
