using System.Collections.Concurrent;
using System.Threading.Tasks;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Registration;
using FluentAssertions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Connections;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.SignalR;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Worker.Tests.Registration;

public sealed class WorkerGatewayClientTests
{
    [Fact]
    public async Task RegisterAndForwardMethods_InvokeGatewayHubMethods()
    {
        await using var server = await WorkerGatewayTestServer.StartAsync();
        await using var connection = server.CreateConnection();
        await using var client = new WorkerGatewayClient(connection);

        await client.StartAsync(CancellationToken.None);
        await client.RegisterAsync("worker-1", CancellationToken.None);
        await client.ForwardStdoutAsync(new TerminalChunk("sess-1", "stdout", [0x01]), CancellationToken.None);
        await client.ForwardStderrAsync(new TerminalChunk("sess-1", "stderr", [0x02]), CancellationToken.None);
        await client.ForwardExitedAsync(new SessionExited("sess-1", 7, "process-exited"), CancellationToken.None);
        await client.ForwardStartFailedAsync(new SessionStartFailedEvent("sess-2", "failed"), CancellationToken.None);

        server.State.RegisteredWorkerIds.Should().ContainSingle().Which.Should().Be("worker-1");
        server.State.StdoutChunks.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new TerminalChunk("sess-1", "stdout", [0x01]));
        server.State.StderrChunks.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new TerminalChunk("sess-1", "stderr", [0x02]));
        server.State.ExitedEvents.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new SessionExited("sess-1", 7, "process-exited"));
        server.State.StartFailedEvents.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new SessionStartFailedEvent("sess-2", "failed"));
    }

    [Fact]
    public async Task InboundSubscriptions_DeliverGatewayCommandsToHandlers()
    {
        await using var server = await WorkerGatewayTestServer.StartAsync();
        await using var connection = server.CreateConnection();
        await using var client = new WorkerGatewayClient(connection);

        StartSessionCommand? start = null;
        WriteInputFrame? write = null;
        ResizePtyRequest? resize = null;
        CloseSessionRequest? close = null;

        var startTcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var writeTcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var resizeTcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var closeTcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        using var _ = new CompositeDisposable(
            client.OnStartSession(command =>
            {
                start = command;
                startTcs.TrySetResult();
                return Task.CompletedTask;
            }),
            client.OnWriteInput(frame =>
            {
                write = frame;
                writeTcs.TrySetResult();
                return Task.CompletedTask;
            }),
            client.OnResizeSession(request =>
            {
                resize = request;
                resizeTcs.TrySetResult();
                return Task.CompletedTask;
            }),
            client.OnCloseSession(request =>
            {
                close = request;
                closeTcs.TrySetResult();
                return Task.CompletedTask;
            }));

        await client.StartAsync(CancellationToken.None);
        await connection.InvokeAsync("DispatchCommands");
        await Task.WhenAll(startTcs.Task, writeTcs.Task, resizeTcs.Task, closeTcs.Task);

        start.Should().BeEquivalentTo(new StartSessionCommand("sess-1", 120, 40));
        write.Should().BeEquivalentTo(new WriteInputFrame("sess-1", [0x0A]));
        resize.Should().BeEquivalentTo(new ResizePtyRequest("sess-1", 90, 30));
        close.Should().BeEquivalentTo(new CloseSessionRequest("sess-1"));
    }
}

internal sealed class WorkerGatewayTestServer : IAsyncDisposable
{
    private readonly WebApplication _app;

    private WorkerGatewayTestServer(WebApplication app, TestServer server, TestWorkerHubState state)
    {
        _app = app;
        Server = server;
        State = state;
    }

    public TestServer Server { get; }
    public TestWorkerHubState State { get; }

    public static async Task<WorkerGatewayTestServer> StartAsync()
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseTestServer();
        builder.Services.AddSignalR();
        builder.Services.AddSingleton<TestWorkerHubState>();

        var app = builder.Build();
        app.MapHub<TestWorkerHub>("/worker");
        await app.StartAsync();

        return new WorkerGatewayTestServer(
            app,
            app.GetTestServer(),
            app.Services.GetRequiredService<TestWorkerHubState>());
    }

    public HubConnection CreateConnection()
        => new HubConnectionBuilder()
            .WithUrl("http://localhost/worker", options =>
            {
                options.HttpMessageHandlerFactory = _ => Server.CreateHandler();
                options.Transports = HttpTransportType.LongPolling;
            })
            .Build();

    public async ValueTask DisposeAsync()
    {
        await _app.StopAsync();
        await _app.DisposeAsync();
    }
}

internal sealed class TestWorkerHub(TestWorkerHubState state) : Hub
{
    public Task RegisterWorker(string workerId)
    {
        state.RegisteredWorkerIds.Enqueue(workerId);
        return Task.CompletedTask;
    }

    public Task ForwardStdout(TerminalChunk chunk)
    {
        state.StdoutChunks.Enqueue(chunk);
        return Task.CompletedTask;
    }

    public Task ForwardStderr(TerminalChunk chunk)
    {
        state.StderrChunks.Enqueue(chunk);
        return Task.CompletedTask;
    }

    public Task SessionExited(SessionExited evt)
    {
        state.ExitedEvents.Enqueue(evt);
        return Task.CompletedTask;
    }

    public Task SessionStartFailed(SessionStartFailedEvent evt)
    {
        state.StartFailedEvents.Enqueue(evt);
        return Task.CompletedTask;
    }

    public Task DispatchCommands()
        => Task.WhenAll(
            Clients.Caller.SendAsync("StartSession", new StartSessionCommand("sess-1", 120, 40)),
            Clients.Caller.SendAsync("WriteInput", new WriteInputFrame("sess-1", [0x0A])),
            Clients.Caller.SendAsync("ResizeSession", new ResizePtyRequest("sess-1", 90, 30)),
            Clients.Caller.SendAsync("CloseSession", new CloseSessionRequest("sess-1")));
}

internal sealed class TestWorkerHubState
{
    public ConcurrentQueue<string> RegisteredWorkerIds { get; } = [];
    public ConcurrentQueue<TerminalChunk> StdoutChunks { get; } = [];
    public ConcurrentQueue<TerminalChunk> StderrChunks { get; } = [];
    public ConcurrentQueue<SessionExited> ExitedEvents { get; } = [];
    public ConcurrentQueue<SessionStartFailedEvent> StartFailedEvents { get; } = [];
}

internal sealed class CompositeDisposable(params IDisposable[] disposables) : IDisposable
{
    public void Dispose()
    {
        foreach (var disposable in disposables)
        {
            disposable.Dispose();
        }
    }
}
