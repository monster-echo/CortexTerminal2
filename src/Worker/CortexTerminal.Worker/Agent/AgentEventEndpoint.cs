using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Loopback Kestrel HTTP server that receives POST /agent-event from corterm-agent
/// (the wrapper binary spawned when a user runs `claude`/`codex`/`opencode` inside
/// a Corterm PTY). Validates the envelope, looks up the adapter, parses into a
/// structured frame, and dispatches via <see cref="IAgentEventSink"/>.
///
/// Wire format (set by the wrapper binary, which controls the envelope):
/// <code>
/// POST /agent-event
/// { "session_id": "...", "agent_kind": "claude-code", "event_type": "UserPromptSubmit", "payload": { ... } }
/// </code>
/// </summary>
public sealed class AgentEventEndpoint : BackgroundService
{
    private const string EnvelopeSessionId = "session_id";
    private const string EnvelopeAgentKind = "agent_kind";
    private const string EnvelopeEventType = "event_type";
    private const string EnvelopePayload = "payload";

    private readonly AgentIntegration _integration;
    private readonly IAgentAdapterRegistry _adapters;
    private readonly IAgentEventSink _sink;
    private readonly ILogger<AgentEventEndpoint> _logger;

    public AgentEventEndpoint(
        AgentIntegration integration,
        IAgentAdapterRegistry adapters,
        IAgentEventSink sink,
        ILogger<AgentEventEndpoint> logger)
    {
        _integration = integration;
        _adapters = adapters;
        _sink = sink;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            var builder = WebApplication.CreateBuilder();
            builder.Logging.ClearProviders();
            builder.Logging.AddProvider(new ForwardingLoggerProvider(_logger));
            builder.WebHost.UseKestrel(serverOptions =>
            {
                serverOptions.Listen(System.Net.IPAddress.Loopback, 0);
            });

            var app = builder.Build();
            app.MapPost("/agent-event", async (HttpContext ctx) =>
            {
                await HandleAgentEventAsync(ctx, stoppingToken);
            });

            await app.StartAsync(stoppingToken);

            var addresses = app.Services
                .GetRequiredService<IServer>()
                .Features
                .Get<IServerAddressesFeature>()
                ?.Addresses ?? Array.Empty<string>();
            var firstAddress = addresses.FirstOrDefault()
                ?? throw new InvalidOperationException("Kestrel did not report any bound addresses.");
            var hookUrl = firstAddress.TrimEnd('/') + "/agent-event";

            _integration.MarkReady(hookUrl);
            _logger.LogInformation("Agent event endpoint listening on {HookUrl}.", hookUrl);

            try
            {
                await Task.Delay(Timeout.Infinite, stoppingToken);
            }
            finally
            {
                await app.StopAsync(CancellationToken.None);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Agent event endpoint crashed.");
            throw;
        }
    }

    private async Task HandleAgentEventAsync(HttpContext ctx, CancellationToken cancellationToken)
    {
        if (!HttpMethods.IsPost(ctx.Request.Method))
        {
            ctx.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
            return;
        }

        JsonObject? envelope;
        try
        {
            envelope = await JsonSerializer.DeserializeAsync<JsonObject>(ctx.Request.Body, cancellationToken: cancellationToken);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Agent event payload was not valid JSON.");
            ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }

        if (envelope is null
            || !envelope.TryGetPropertyValue(EnvelopeSessionId, out var sessionIdNode)
            || sessionIdNode?.GetValue<string>() is not { Length: > 0 } sessionId
            || !envelope.TryGetPropertyValue(EnvelopeAgentKind, out var kindNode)
            || kindNode?.GetValue<string>() is not { Length: > 0 } kindName
            || !envelope.TryGetPropertyValue(EnvelopeEventType, out var eventTypeNode)
            || eventTypeNode?.GetValue<string>() is not { Length: > 0 } eventType)
        {
            _logger.LogWarning("Agent event envelope missing required fields: {Envelope}", envelope?.ToJsonString());
            ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }

        var kind = AgentKindNames.FromName(kindName);
        if (kind == AgentKind.None)
        {
            _logger.LogWarning("Unknown agent_kind '{Kind}' in agent event envelope.", kindName);
            ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }

        var adapter = _adapters.Resolve(kind);
        if (adapter is null)
        {
            _logger.LogDebug("No adapter for agent_kind '{Kind}'; ignoring event.", kindName);
            ctx.Response.StatusCode = StatusCodes.Status202Accepted;
            return;
        }

        var payloadNode = envelope.TryGetPropertyValue(EnvelopePayload, out var p) && p is JsonObject po
            ? po
            : new JsonObject();

        var context = new AgentSessionContext(
            sessionId,
            _integration.HookUrl,
            WorkDir: string.Empty,
            TempConfigDir: string.Empty);

        BaseAgentActivityFrame? frame;
        try
        {
            frame = adapter.ParseEvent(eventType, payloadNode, context);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Adapter {Kind} threw while parsing event '{EventType}'.", kind, eventType);
            ctx.Response.StatusCode = StatusCodes.Status500InternalServerError;
            return;
        }

        if (frame is null)
        {
            ctx.Response.StatusCode = StatusCodes.Status202Accepted;
            return;
        }

        try
        {
            await _sink.DispatchAsync(frame, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Agent event sink threw while dispatching {FrameType}.", frame.GetType().Name);
            ctx.Response.StatusCode = StatusCodes.Status500InternalServerError;
            return;
        }

        ctx.Response.StatusCode = StatusCodes.Status200OK;
    }

    private sealed class ForwardingLoggerProvider(ILogger forward) : ILoggerProvider
    {
        private readonly ILogger _forward = forward;

        public ILogger CreateLogger(string categoryName) => new ForwardingLogger(_forward);

        public void Dispose() { }
    }

    private sealed class ForwardingLogger(ILogger forward) : ILogger
    {
        private readonly ILogger _forward = forward;

        public IDisposable BeginScope<TState>(TState state) where TState : notnull => NullScope.Instance;

        public bool IsEnabled(LogLevel logLevel) => _forward.IsEnabled(logLevel);

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
            => _forward.Log(logLevel, eventId, state, exception, formatter);
    }

    private sealed class NullScope : IDisposable
    {
        public static readonly NullScope Instance = new();
        public void Dispose() { }
    }
}
