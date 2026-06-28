using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Agent;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Agent;

/// <summary>
/// Phase 2.2 + 2.5 plumbing verification: starts the loopback HTTP endpoint via the
/// hosted-service lifecycle, posts an agent event envelope, and asserts that the sink
/// received the expected structured frame.
///
/// The fake adapter emits a deterministic AgentStartedFrame for the "SessionStart" event
/// so we don't need a real Claude Code adapter to validate the wire path.
/// </summary>
public sealed class AgentEventEndpointTests
{
    [Fact]
    public async Task Endpoint_AcceptsAgentEventAndDispatchesToSink()
    {
        var installDir = Path.Combine(Path.GetTempPath(), "cortap-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(installDir);
        try
        {
            var (integration, endpoint, sink) = BuildComponents(installDir);

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            await endpoint.StartAsync(cts.Token);
            try
            {
                await WaitUntilReadyAsync(integration, cts.Token);

                using var http = new HttpClient();
                var body = JsonContent(new Dictionary<string, object?>
                {
                    ["session_id"] = "sess-123",
                    ["agent_kind"] = "claude-code",
                    ["event_type"] = "SessionStart",
                    ["payload"] = new Dictionary<string, object?> { ["session_id"] = "agent-1" },
                });
                var response = await http.PostAsync(integration.HookUrl, body, cts.Token);

                response.StatusCode.Should().Be(HttpStatusCode.OK);
                sink.Received.Count.Should().Be(1);
                var frame = sink.Received[0];
                var started = frame.Should().BeOfType<AgentStartedFrame>().Subject;
                started.SessionId.Should().Be("sess-123");
                started.Kind.Should().Be(AgentKind.ClaudeCode);
                started.AgentSessionId.Should().Be("agent-1");
            }
            finally
            {
                await endpoint.StopAsync(CancellationToken.None);
            }
        }
        finally
        {
            try { Directory.Delete(installDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public async Task Endpoint_RejectsEnvelopeMissingAgentKind()
    {
        var installDir = Path.Combine(Path.GetTempPath(), "cortap-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(installDir);
        try
        {
            var (integration, endpoint, sink) = BuildComponents(installDir);

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            await endpoint.StartAsync(cts.Token);
            try
            {
                await WaitUntilReadyAsync(integration, cts.Token);

                using var http = new HttpClient();
                var body = JsonContent(new Dictionary<string, object?>
                {
                    ["session_id"] = "sess-123",
                    ["event_type"] = "SessionStart",
                });
                var response = await http.PostAsync(integration.HookUrl, body, cts.Token);

                response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
                sink.Received.Count.Should().Be(0);
            }
            finally
            {
                await endpoint.StopAsync(CancellationToken.None);
            }
        }
        finally
        {
            try { Directory.Delete(installDir, recursive: true); } catch { }
        }
    }

    private static (AgentIntegration integration, AgentEventEndpoint endpoint, CapturingSink sink) BuildComponents(string installDir)
    {
        var loggerFactory = LoggerFactory.Create(builder =>
        {
            builder.SetMinimumLevel(LogLevel.Debug);
            builder.AddConsole();
        });

        var integration = new AgentIntegration(installDir, loggerFactory.CreateLogger<AgentIntegration>());
        var adapter = new TestAdapter();
        var registry = new TestRegistry(adapter);
        var sink = new CapturingSink();
        var endpoint = new AgentEventEndpoint(integration, registry, sink, loggerFactory.CreateLogger<AgentEventEndpoint>());
        return (integration, endpoint, sink);
    }

    private static StringContent JsonContent(Dictionary<string, object?> body)
        => new(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

    private static async Task WaitUntilReadyAsync(AgentIntegration integration, CancellationToken cancellationToken)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(20);
        while (!integration.Enabled)
        {
            if (DateTimeOffset.UtcNow >= deadline)
                throw new TimeoutException("AgentIntegration did not become ready within 20 seconds.");
            await Task.Delay(50, cancellationToken);
        }
    }

    private sealed class TestRegistry : IAgentAdapterRegistry
    {
        private readonly IAgentAdapter _adapter;
        public TestRegistry(IAgentAdapter adapter) { _adapter = adapter; }
        public IAgentAdapter? Resolve(AgentKind kind) => kind == _adapter.Kind ? _adapter : null;
        public IAgentAdapter? ResolveByName(string? name) => _adapter;
    }

    private sealed class TestAdapter : IAgentAdapter
    {
        public AgentKind Kind => AgentKind.ClaudeCode;
        public string HookConfigFilename => "settings.json";
        public string? ResolveBinary() => "/usr/local/bin/claude";
        public IReadOnlyDictionary<string, string> BuildEnvironment(AgentSessionContext context) => new Dictionary<string, string>();
        public string GenerateHookConfig(AgentSessionContext context) => "{}";
        public BaseAgentActivityFrame? ParseEvent(string eventType, JsonObject payload, AgentSessionContext context)
        {
            if (eventType != "SessionStart") return null;
            var agentSessionId = payload.TryGetPropertyValue("session_id", out var id) ? id?.GetValue<string>() : null;
            return new AgentStartedFrame(context.SessionId, AgentKind.ClaudeCode, agentSessionId, WorkDir: null);
        }
    }

    private sealed class CapturingSink : IAgentEventSink
    {
        public List<BaseAgentActivityFrame> Received { get; } = new();
        public Task DispatchAsync(BaseAgentActivityFrame frame, CancellationToken cancellationToken)
        {
            Received.Add(frame);
            return Task.CompletedTask;
        }
    }
}
