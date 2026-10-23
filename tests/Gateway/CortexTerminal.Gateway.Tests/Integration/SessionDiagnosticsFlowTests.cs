using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Integration;

public sealed class SessionDiagnosticsFlowTests
{
    [Fact]
    public async Task Diagnosis_RoundTripsThroughWorker_AndRejectsOtherUsersBeforeDispatch()
    {
        using var factory = new GatewayApplicationFactory();
        await using var worker = factory.CreateAuthenticatedHubConnection("/hubs/worker");
        var calls = 0;
        var report = new SessionDiagnosticReport("waiting-for-output", false, "/workspace/example", "permission-denied", null, "macos", 15);
        worker.On<string, SessionDiagnosticReport>("DiagnoseSession", id => { Interlocked.Increment(ref calls); return report; });
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "diagnostic-worker");
        var coordinator = factory.Services.GetRequiredService<ISessionCoordinator>();
        var created = await coordinator.CreateSessionAsync("test-user", new CreateSessionRequest("shell", 80, 24), null, CancellationToken.None);
        created.IsSuccess.Should().BeTrue();
        var path = $"/api/me/sessions/{created.Response!.SessionId}/diagnostics";

        using var anonymous = factory.CreateClient();
        (await anonymous.GetAsync(path)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        using var other = factory.CreateAuthenticatedClient("test-admin");
        (await other.GetAsync(path)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        calls.Should().Be(0);

        using var owner = factory.CreateAuthenticatedClient();
        var result = await owner.GetFromJsonAsync<SessionDiagnosticReport>(path);
        result.Should().BeEquivalentTo(report);
        calls.Should().Be(1);
        coordinator.TryGetSession(created.Response.SessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);

        // Registration may change after reconnect: diagnostics must use the current connection.
        var registry = factory.Services.GetRequiredService<IWorkerRegistry>();
        registry.Unregister("diagnostic-worker", worker.ConnectionId!).Should().BeTrue();
        result = await owner.GetFromJsonAsync<SessionDiagnosticReport>(path);
        result!.State.Should().Be("worker-offline");
        calls.Should().Be(1);
    }

    [Fact]
    public async Task OlderWorkerWithoutHandler_ReturnsActionableUnavailableResponse()
    {
        using var factory = new GatewayApplicationFactory();
        await using var worker = factory.CreateAuthenticatedHubConnection("/hubs/worker");
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "older-worker");
        var coordinator = factory.Services.GetRequiredService<ISessionCoordinator>();
        var created = await coordinator.CreateSessionAsync("test-user", new CreateSessionRequest("shell", 80, 24), null, CancellationToken.None);
        created.IsSuccess.Should().BeTrue();
        using var owner = factory.CreateAuthenticatedClient();
        var report = await owner.GetFromJsonAsync<SessionDiagnosticReport>($"/api/me/sessions/{created.Response!.SessionId}/diagnostics");
        report!.State.Should().BeOneOf("diagnostics-unavailable", "diagnostic-timeout");
        report.DirectoryAccess.Should().Be("not-checked");
    }
}
