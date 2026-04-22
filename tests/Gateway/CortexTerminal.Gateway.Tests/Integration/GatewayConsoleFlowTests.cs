using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Integration;

public sealed class GatewayConsoleFlowTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public GatewayConsoleFlowTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task HttpCreatedSession_CanBeEnteredBySessionIdOverTerminalHub()
    {
        using var factory = new GatewayApplicationFactory();
        var writeInputTcs = new TaskCompletionSource<WriteInputFrame>(TaskCreationOptions.RunContinuationsAsynchronously);
        var resizeTcs = new TaskCompletionSource<ResizePtyRequest>(TaskCreationOptions.RunContinuationsAsynchronously);
        var closeTcs = new TaskCompletionSource<CloseSessionRequest>(TaskCreationOptions.RunContinuationsAsynchronously);

        await using var worker = factory.CreateHubConnection("/hubs/worker");
        worker.On<WriteInputFrame>("WriteInput", frame =>
        {
            writeInputTcs.TrySetResult(frame);
            return Task.CompletedTask;
        });
        worker.On<ResizePtyRequest>("ResizeSession", request =>
        {
            resizeTcs.TrySetResult(request);
            return Task.CompletedTask;
        });
        worker.On<CloseSessionRequest>("CloseSession", request =>
        {
            closeTcs.TrySetResult(request);
            return Task.CompletedTask;
        });

        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "worker-console-flow");

        using var client = factory.CreateAuthenticatedClient();
        using var createResponse = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));
        createResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var created = await createResponse.Content.ReadFromJsonAsync<CreateSessionResponse>();
        created.Should().NotBeNull();

        await using var terminal = factory.CreateAuthenticatedHubConnection("/hubs/terminal");
        await terminal.StartAsync();

        var reattach = await terminal.InvokeAsync<ReattachSessionResult>(
            "ReattachSession",
            new ReattachSessionRequest(created!.SessionId));

        reattach.Should().BeEquivalentTo(ReattachSessionResult.Success());

        await terminal.InvokeAsync("WriteInput", new WriteInputFrame(created.SessionId, [0x09]));
        await terminal.InvokeAsync("ResizeSession", new ResizePtyRequest(created.SessionId, 100, 50));
        await terminal.InvokeAsync("CloseSession", new CloseSessionRequest(created.SessionId));

        (await writeInputTcs.Task.WaitAsync(TimeSpan.FromSeconds(5)))
            .Should()
            .BeEquivalentTo(new WriteInputFrame(created.SessionId, [0x09]));
        (await resizeTcs.Task.WaitAsync(TimeSpan.FromSeconds(5)))
            .Should()
            .BeEquivalentTo(new ResizePtyRequest(created.SessionId, 100, 50));
        (await closeTcs.Task.WaitAsync(TimeSpan.FromSeconds(5)))
            .Should()
            .BeEquivalentTo(new CloseSessionRequest(created.SessionId));
    }
}
