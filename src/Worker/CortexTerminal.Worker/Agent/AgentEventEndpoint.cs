using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Artifacts;
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
/// Loopback Kestrel HTTP server that receives POST /agent-event from cortap
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
            // Use JsonNode.Parse instead of JsonSerializer.DeserializeAsync<JsonObject>: the Worker
            // runtime has System.Text.Json.JsonSerializer.IsReflectionEnabledByDefault=false (set
            // automatically by PublishTrimmed in .NET 10), which makes the JsonSerializer facade
            // throw even for JsonNode-based types. JsonNode.Parse is parser-only and side-steps
            // the resolver entirely.
            using var reader = new StreamReader(ctx.Request.Body);
            var body = await reader.ReadToEndAsync(cancellationToken);
            envelope = JsonNode.Parse(body) as JsonObject;
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
            await WriteHookResponseIfNeededAsync(ctx, kind, eventType, sessionId, cancellationToken);
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

        await WriteHookResponseIfNeededAsync(ctx, kind, eventType, sessionId, cancellationToken);
        ctx.Response.StatusCode = StatusCodes.Status200OK;
    }

    /// <summary>
    /// Write the Claude Code <c>UserPromptSubmit</c> hook response listing files uploaded via
    /// Console. Claude Code parses stdout strictly, so we write either valid JSON or nothing.
    /// Sent regardless of whether the adapter tracked the event — Claude Code's hook subprocess
    /// is waiting for our response either way.
    /// </summary>
    private static async Task WriteHookResponseIfNeededAsync(
        HttpContext ctx, AgentKind kind, string eventType, string sessionId, CancellationToken cancellationToken)
    {
        if (kind != AgentKind.ClaudeCode || eventType != "UserPromptSubmit") return;

        var hookResponse = BuildHookResponse(sessionId);
        if (string.IsNullOrEmpty(hookResponse)) return;

        ctx.Response.ContentType = "application/json; charset=utf-8";
        await ctx.Response.WriteAsync(hookResponse, cancellationToken);
    }

    /// <summary>
    /// Build the Claude Code <c>UserPromptSubmit</c> hook response that lists files uploaded via
    /// the Console. Returns null when the artifacts dir is missing or empty — Claude Code parses
    /// stdout strictly, so we must return either valid JSON or nothing.
    /// </summary>
    internal static string? BuildHookResponse(string sessionId)
        => BuildHookResponseForDir(ArtifactPaths.GetSessionArtifactsDir(sessionId));

    /// <summary>
    /// Directory-scoped variant exposed for unit tests so they don't have to touch the user's
    /// real <c>~/.corterm/sessions/</c> tree.
    /// </summary>
    internal static string? BuildHookResponseForDir(string artifactsDir)
    {
        if (!Directory.Exists(artifactsDir)) return null;

        FileInfo[] files;
        try
        {
            files = new DirectoryInfo(artifactsDir)
                .GetFiles()
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .Take(MaxFilesToList)
                .ToArray();
        }
        catch (DirectoryNotFoundException) { return null; }
        catch (UnauthorizedAccessException) { return null; }

        if (files.Length == 0) return null;

        var context = new StringBuilder();
        context.Append("[Corterm] ").Append(files.Length).Append(" file(s) uploaded via Console in ")
            .Append(artifactsDir).Append(':');
        foreach (var f in files)
        {
            context.Append("\n- ").Append(f.Name).Append(" (").Append(FormatFileSize(f.Length)).Append(')');
        }

        var response = new JsonObject
        {
            ["hookSpecificOutput"] = new JsonObject
            {
                ["hookEventName"] = "UserPromptSubmit",
                ["additionalContext"] = context.ToString(),
            },
        };
        return response.ToJsonString(HookResponseJsonOptions);
    }

    internal static string FormatFileSize(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024L * 1024) return $"{bytes / 1024.0:F1} KB";
        if (bytes < 1024L * 1024 * 1024) return $"{bytes / (1024.0 * 1024):F1} MB";
        return $"{bytes / (1024.0 * 1024 * 1024):F1} GB";
    }

    private const int MaxFilesToList = 10;

    private static readonly JsonSerializerOptions HookResponseJsonOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = false,
    };

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
