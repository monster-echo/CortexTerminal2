using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Http.Json;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Integration;

public sealed class WorkerRuntimeDispatchFlowTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public WorkerRuntimeDispatchFlowTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task CreateSession_DispatchesStartSessionToConnectedWorker()
    {
        using var factory = new GatewayApplicationFactory();
        var startSessionTcs = new TaskCompletionSource<StartSessionCommand>(TaskCreationOptions.RunContinuationsAsynchronously);

        await using var worker = factory.CreateHubConnection("/hubs/worker");
        worker.On<StartSessionCommand>("StartSession", command =>
        {
            startSessionTcs.TrySetResult(command);
            return Task.CompletedTask;
        });

        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "worker-integration-dispatch");

        using var client = factory.CreateAuthenticatedClient();
        using var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var createResponse = await response.Content.ReadFromJsonAsync<CreateSessionResponse>();
        createResponse.Should().NotBeNull();

        var dispatched = await startSessionTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        dispatched.Should().BeEquivalentTo(new StartSessionCommand(createResponse!.SessionId, 120, 40));
    }

    [Fact]
    public async Task SessionExited_NotifiesAttachedClientAndMarksSessionExited()
    {
        using var factory = new GatewayApplicationFactory();
        var exitedTcs = new TaskCompletionSource<SessionExited>(TaskCreationOptions.RunContinuationsAsynchronously);

        await using var worker = factory.CreateHubConnection("/hubs/worker");
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "worker-integration-exit");

        await using var terminal = factory.CreateAuthenticatedHubConnection("/hubs/terminal");
        terminal.On<SessionExited>("SessionExited", evt =>
        {
            exitedTcs.TrySetResult(evt);
            return Task.CompletedTask;
        });
        await terminal.StartAsync();

        var sessions = factory.Services.GetRequiredService<ISessionCoordinator>();
        var created = await sessions.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            terminal.ConnectionId,
            CancellationToken.None);

        created.IsSuccess.Should().BeTrue();
        var sessionId = created.Response!.SessionId;

        var expectedExit = new SessionExited(sessionId, 0, "process-exited");
        await worker.InvokeAsync("SessionExited", expectedExit, CancellationToken.None);

        var exited = await exitedTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        exited.Should().BeEquivalentTo(expectedExit);

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Exited);
        session.ExitCode.Should().Be(0);
        session.ExitReason.Should().Be("process-exited");
    }

    [Fact]
    public async Task ForwardStdout_NotifiesAttachedTerminalClient()
    {
        using var factory = new GatewayApplicationFactory();
        var stdoutTcs = new TaskCompletionSource<TerminalChunk>(TaskCreationOptions.RunContinuationsAsynchronously);

        await using var worker = factory.CreateHubConnection("/hubs/worker");
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "worker-integration-stdout");

        await using var terminal = factory.CreateAuthenticatedHubConnection("/hubs/terminal");
        terminal.On<TerminalChunk>("StdoutChunk", chunk =>
        {
            stdoutTcs.TrySetResult(chunk);
            return Task.CompletedTask;
        });
        await terminal.StartAsync();

        var sessions = factory.Services.GetRequiredService<ISessionCoordinator>();
        var created = await sessions.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            terminal.ConnectionId,
            CancellationToken.None);

        created.IsSuccess.Should().BeTrue();
        var sessionId = created.Response!.SessionId;

        var expectedChunk = new TerminalChunk(sessionId, "stdout", [0x41, 0x42]);
        await worker.InvokeAsync("ForwardStdout", expectedChunk, CancellationToken.None);

        var chunk = await stdoutTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        chunk.Should().BeEquivalentTo(expectedChunk);
    }
}
