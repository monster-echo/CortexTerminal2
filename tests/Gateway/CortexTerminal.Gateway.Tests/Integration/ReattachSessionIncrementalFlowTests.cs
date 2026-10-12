using System.Text;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using CortexTerminal.Gateway.Tests.Hubs;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Integration;

/// <summary>
/// Production regression harness: the Harmony client observed
/// "Failed to invoke 'ReattachSessionIncremental' due to an error on the server"
/// on EVERY reattach, forcing the legacy full-replay fallback. These tests pin
/// the incremental endpoint to succeed over the wire for both worker shapes
/// (with and without the RequestScrollbackSince handler).
/// </summary>
public sealed class ReattachSessionIncrementalFlowTests
{
    private static IServiceProvider ServicesOf(GatewayApplicationFactory factory) => factory.Services;

    private static GatewayApplicationFactory NewFactory()
    {
        // Plain factory; detailed errors are enabled per-test via WithWebHostBuilder
        // so the client observes the REAL server exception instead of the generic
        // "due to an error on the server" wrapper.
        return new GatewayApplicationFactory();
    }

    private static GatewayApplicationFactory NewDetailedFactory()
    {
        var factory = new GatewayApplicationFactory();
        factory.WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
            {
                services.PostConfigure<HubOptions>(options => options.EnableDetailedErrors = true);
                services.PostConfigure<HubOptions<CortexTerminal.Gateway.Hubs.TerminalHub>>(options =>
                {
                    options.EnableDetailedErrors = true;
                    options.AddFilter<ExceptionCapturingFilter>();
                });
            }));
        return factory;
    }

    /// <summary>Server-side probe: prints the REAL exception a hub method threw.</summary>
    public sealed class ExceptionCapturingFilter : IHubFilter
    {
        public async ValueTask<object?> InvokeMethodAsync(
            HubInvocationContext invocationContext, Func<HubInvocationContext, ValueTask<object?>> next)
        {
            Console.WriteLine($"[HUB-ENTER] {invocationContext.HubMethodName}");
            try
            {
                var result = await next(invocationContext);
                Console.WriteLine($"[HUB-OK] {invocationContext.HubMethodName}");
                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HUB-EXC] {invocationContext.HubMethodName}: {ex}");
                throw;
            }
        }
    }

    private static async Task<(HubConnection Worker, string SessionId)> CreateSessionWithWorkerAsync(
        GatewayApplicationFactory factory, string workerName)
    {
        var services = ServicesOf(factory);
        var sessions = services.GetRequiredService<ISessionCoordinator>();

        var worker = factory.CreateAuthenticatedHubConnection("/hubs/worker");
        worker.Closed += ex =>
        {
            Console.WriteLine($"[TEST] WORKER CLOSED: {ex?.GetType().Name}: {ex?.Message}");
            return Task.CompletedTask;
        };
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", workerName);

        var created = await sessions.CreateSessionAsync(
            "test-user", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        created.IsSuccess.Should().BeTrue();
        await sessions.DetachSessionAsync("test-user", created.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);
        return (worker, created.Response!.SessionId);
    }

    [Fact]
    public async Task Incremental_OldWorkerWithoutSinceHandler_FallsBackToLegacyEvents()
    {
        using var factory = NewDetailedFactory();
        var deltaTcs = new TaskCompletionSource<SessionReattachedEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
        var (worker, sessionId) = await CreateSessionWithWorkerAsync(factory, "worker-incremental-old");

        // Old worker: only the legacy scrollback handler exists.
        worker.On<string, IReadOnlyList<TerminalChunk>>("RequestScrollback", _ =>
            (IReadOnlyList<TerminalChunk>)new List<TerminalChunk>
            {
                new(sessionId, "stdout", Encoding.UTF8.GetBytes("legacy full buffer"))
            });

        var terminal = factory.CreateAuthenticatedHubConnection("/hubs/terminal");
        terminal.On<SessionReattachedEvent>("SessionReattached", e => { deltaTcs.TrySetResult(e); return Task.CompletedTask; });
        await terminal.StartAsync();

        // Control: the legacy endpoint (same payload style, one property) must work.
        var legacy = await terminal.InvokeAsync<ReattachSessionResult>(
            "ReattachSession", new ReattachSessionRequest(sessionId));
        legacy.IsSuccess.Should().BeTrue();

        var result = await terminal.InvokeAsync<ReattachSessionResult>(
            "ReattachSessionIncremental", new ReattachSessionSinceRequest(sessionId, 0));

        result.IsSuccess.Should().BeTrue();
        (await deltaTcs.Task.WaitAsync(TimeSpan.FromSeconds(5))).SessionId.Should().Be(sessionId);
    }

    [Fact]
    public async Task Incremental_WorkerWithSinceHandler_FlowsDeltaEvents()
    {
        using var factory = NewDetailedFactory();
        var (worker, sessionId) = await CreateSessionWithWorkerAsync(factory, "worker-incremental-delta");

        worker.On<string, long, ScrollbackDelta>("RequestScrollbackSince", (_, _) =>
            new ScrollbackDelta(Gap: false, LastSeq: 7, Items: new[]
            {
                new ScrollbackItem(7, new TerminalChunk(sessionId, "stdout", Encoding.UTF8.GetBytes("delta chunk")))
            }));

        var startedTcs = new TaskCompletionSource<ReplayDeltaStarted>(TaskCreationSource());
        var chunkTcs = new TaskCompletionSource<ReplayDeltaChunk>(TaskCreationSource());
        var completedTcs = new TaskCompletionSource<ReplayDeltaCompleted>(TaskCreationSource());

        var terminal = factory.CreateAuthenticatedHubConnection("/hubs/terminal");
        terminal.On<ReplayDeltaStarted>("ReplayDeltaStarted", e => { startedTcs.TrySetResult(e); return Task.CompletedTask; });
        terminal.On<ReplayDeltaChunk>("ReplayDeltaChunk", e => { chunkTcs.TrySetResult(e); return Task.CompletedTask; });
        terminal.On<ReplayDeltaCompleted>("ReplayDeltaCompleted", e => { completedTcs.TrySetResult(e); return Task.CompletedTask; });
        await terminal.StartAsync();

        var result = await terminal.InvokeAsync<ReattachSessionResult>(
            "ReattachSessionIncremental", new ReattachSessionSinceRequest(sessionId, 0));

        result.IsSuccess.Should().BeTrue();
        (await startedTcs.Task.WaitAsync(TimeSpan.FromSeconds(5))).SessionId.Should().Be(sessionId);
        (await chunkTcs.Task.WaitAsync(TimeSpan.FromSeconds(5))).Payload.Should().NotBeNull();
        (await completedTcs.Task.WaitAsync(TimeSpan.FromSeconds(5))).LastSeq.Should().Be(7);
    }

    private static TaskCreationOptions TaskCreationSource() => TaskCreationOptions.RunContinuationsAsynchronously;

    /// <summary>
    /// Diagnostic: invoke the hub method DIRECTLY (no SignalR pipeline) so any
    /// exception surfaces with its full stack instead of the generic wrapper.
    /// </summary>
    [Fact]
    public async Task Diagnostic_DirectInvocation_ExceptionSurfaces()
    {
        using var factory = NewFactory();
        var services = ServicesOf(factory);
        var registry = services.GetRequiredService<CortexTerminal.Gateway.Workers.IWorkerRegistry>();
        var sessions = services.GetRequiredService<ISessionCoordinator>();
        registry.Register("worker-diag", "worker-conn-diag");
        var created = await sessions.CreateSessionAsync(
            "test-user", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        created.IsSuccess.Should().BeTrue();
        var sessionId = created.Response!.SessionId;
        await sessions.DetachSessionAsync("test-user", sessionId, DateTimeOffset.UtcNow, CancellationToken.None);

        var hub = ActivatorUtilities.CreateInstance<TerminalHub>(services);
        hub.Context = new TestHubCallerContext("client-diag", "test-user");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        Exception? failure = null;
        try
        {
            var result = await hub.ReattachSessionIncremental(new ReattachSessionSinceRequest(sessionId, 0));
            Console.WriteLine($"[DIAG] returned: IsSuccess={result.IsSuccess} ErrorCode={result.ErrorCode} Restart={result.ShellRestartRequired}");
        }
        catch (Exception ex)
        {
            failure = ex;
        }

        if (failure is not null)
        {
            Assert.Fail(failure.ToString());
        }
    }
}
