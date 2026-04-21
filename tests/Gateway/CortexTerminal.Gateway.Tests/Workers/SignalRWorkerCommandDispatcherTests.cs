using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workers;

public sealed class SignalRWorkerCommandDispatcherTests
{
    [Fact]
    public async Task StartSessionAsync_TargetsOnlySelectedWorkerConnection()
    {
        var workerClient = new RecordingClientProxy();
        var hubContext = new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-1"] = workerClient,
            ["worker-2"] = new RecordingClientProxy()
        });
        var dispatcher = new SignalRWorkerCommandDispatcher(hubContext);

        await dispatcher.StartSessionAsync("worker-1", new StartSessionCommand("sess-1", 120, 40), CancellationToken.None);

        workerClient.Invocations.Should().ContainSingle()
            .Which.Method.Should().Be("StartSession");
        workerClient.Invocations[0].Arguments[0].Should().BeEquivalentTo(new StartSessionCommand("sess-1", 120, 40));
    }

    [Fact]
    public async Task WriteInputAsync_TargetsOnlySelectedWorkerConnection()
    {
        var workerClient = new RecordingClientProxy();
        var hubContext = new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-1"] = workerClient,
            ["worker-2"] = new RecordingClientProxy()
        });
        var dispatcher = new SignalRWorkerCommandDispatcher(hubContext);

        await dispatcher.WriteInputAsync("worker-1", new WriteInputFrame("sess-1", [0x01]), CancellationToken.None);

        workerClient.Invocations.Should().ContainSingle()
            .Which.Method.Should().Be("WriteInput");
    }

    [Fact]
    public async Task ResizeSessionAsync_TargetsOnlySelectedWorkerConnection()
    {
        var workerClient = new RecordingClientProxy();
        var hubContext = new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-1"] = workerClient,
            ["worker-2"] = new RecordingClientProxy()
        });
        var dispatcher = new SignalRWorkerCommandDispatcher(hubContext);

        await dispatcher.ResizeSessionAsync("worker-1", new ResizePtyRequest("sess-1", 100, 50), CancellationToken.None);

        workerClient.Invocations.Should().ContainSingle()
            .Which.Method.Should().Be("ResizeSession");
    }

    [Fact]
    public async Task CloseSessionAsync_TargetsOnlySelectedWorkerConnection()
    {
        var workerClient = new RecordingClientProxy();
        var hubContext = new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-1"] = workerClient,
            ["worker-2"] = new RecordingClientProxy()
        });
        var dispatcher = new SignalRWorkerCommandDispatcher(hubContext);

        await dispatcher.CloseSessionAsync("worker-1", new CloseSessionRequest("sess-1"), CancellationToken.None);

        workerClient.Invocations.Should().ContainSingle()
            .Which.Method.Should().Be("CloseSession");
    }
}

internal sealed class TestHubContext<THub>(IReadOnlyDictionary<string, IClientProxy> clients) : IHubContext<THub> where THub : Hub
{
    public IHubClients Clients { get; } = new TestHubClients(clients);
    public IGroupManager Groups { get; } = new TestGroupManager();

    private sealed class TestHubClients(IReadOnlyDictionary<string, IClientProxy> clients) : IHubClients
    {
        public IClientProxy All => throw new NotSupportedException();
        public IClientProxy Caller => throw new NotSupportedException();
        public IClientProxy Others => throw new NotSupportedException();

        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();

        public IClientProxy Client(string connectionId)
            => clients.TryGetValue(connectionId, out var client)
                ? client
                : throw new InvalidOperationException($"Missing client {connectionId}");

        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => throw new NotSupportedException();
        public IClientProxy Group(string groupName) => throw new NotSupportedException();
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => throw new NotSupportedException();
        public IClientProxy OthersInGroup(string groupName) => throw new NotSupportedException();
        public IClientProxy User(string userId) => throw new NotSupportedException();
        public IClientProxy Users(IReadOnlyList<string> userIds) => throw new NotSupportedException();
    }

    private sealed class TestGroupManager : IGroupManager
    {
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
