using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Integration;

public sealed class ReattachSessionFlowTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public ReattachSessionFlowTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task ReattachSession_BeforeLeaseExpiry_SucceedsThroughGateway()
    {
        var services = _factory.Services;
        var registry = services.GetRequiredService<IWorkerRegistry>();
        var sessions = services.GetRequiredService<ISessionCoordinator>();
        registry.Register("worker-integration-reattach", "worker-conn-reattach");
        var created = await sessions.CreateSessionAsync("unknown", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        created.IsSuccess.Should().BeTrue();
        var sessionId = created.Response!.SessionId;
        var detachedAt = DateTimeOffset.UtcNow;

        var detachCaller = new RecordingClientProxy();
        var detachHub = ActivatorUtilities.CreateInstance<TerminalHub>(services);
        detachHub.Context = new TestHubCallerContext("client-detach");
        detachHub.Clients = new TestHubCallerClients(detachCaller);

        await detachHub.DetachSession(sessionId, CancellationToken.None);

        var detached = detachCaller.Invocations.Should().ContainSingle().Subject.Arguments[0].Should().BeOfType<SessionDetachedEvent>().Subject;
        detached.SessionId.Should().Be(sessionId);
        detached.LeaseExpiresAtUtc.Should().BeAfter(DateTimeOffset.UtcNow);
        detached.LeaseExpiresAtUtc.Should().BeOnOrBefore(detachedAt.AddMinutes(5).AddSeconds(1));

        var reattachCaller = new RecordingClientProxy();
        var reattachHub = ActivatorUtilities.CreateInstance<TerminalHub>(services);
        reattachHub.Context = new TestHubCallerContext("client-reattach");
        reattachHub.Clients = new TestHubCallerClients(reattachCaller);

        var reattachResult = await reattachHub.ReattachSession(
            new ReattachSessionRequest(sessionId),
            CancellationToken.None);

        reattachResult.Should().BeEquivalentTo(ReattachSessionResult.Success());
        reattachCaller.Invocations.Select(static invocation => invocation.Method).Should().Equal("SessionReattached", "ReplayCompleted");
        var reattached = reattachCaller.Invocations[0].Arguments[0].Should().BeOfType<SessionReattachedEvent>().Subject;
        reattached.Should().BeEquivalentTo(new SessionReattachedEvent(sessionId));

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.SessionId.Should().Be(sessionId);
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.AttachedClientConnectionId.Should().Be("client-reattach");
        session.ReplayPending.Should().BeFalse();
    }
}
