using System.Text.Json;
using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests;

/// <summary>
/// Validates the envelope-building logic for the hook subcommand. We don't exercise the HTTP
/// POST path here — that's covered by integration tests with a real listener.
/// </summary>
public sealed class HookForwarderTests
{
    [Fact]
    public void BuildEnvelopeJson_WrapsPayloadUnderEnvelope()
    {
        var rawBody = """{"hook_event_name":"UserPromptSubmit","session_id":"claude-internal","prompt":"hello"}""";

        var envelope = HookForwarder.BuildEnvelopeJson(rawBody, "corterm-sess-1", "claude-code");

        using var doc = JsonDocument.Parse(envelope);
        var root = doc.RootElement;
        root.GetProperty("session_id").GetString().Should().Be("corterm-sess-1");
        root.GetProperty("agent_kind").GetString().Should().Be("claude-code");
        root.GetProperty("event_type").GetString().Should().Be("UserPromptSubmit");
        root.GetProperty("payload").GetProperty("prompt").GetString().Should().Be("hello");
        root.GetProperty("payload").GetProperty("session_id").GetString().Should().Be("claude-internal");
    }

    [Fact]
    public void BuildEnvelopeJson_PreservesAllOriginalFields()
    {
        var rawBody = """{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"content":["out"]}}""";

        var envelope = HookForwarder.BuildEnvelopeJson(rawBody, "sess", "claude-code");

        using var doc = JsonDocument.Parse(envelope);
        var payload = doc.RootElement.GetProperty("payload");
        payload.GetProperty("tool_name").GetString().Should().Be("Bash");
        payload.GetProperty("tool_input").GetProperty("command").GetString().Should().Be("ls");
    }

    [Fact]
    public void BuildEnvelopeJson_ReturnsEmptyWhenNoHookEventName()
    {
        var rawBody = """{"some_other_field":"value"}""";

        var envelope = HookForwarder.BuildEnvelopeJson(rawBody, "sess", "claude-code");

        envelope.Should().BeEmpty();
    }

    [Fact]
    public void BuildEnvelopeJson_ReturnsEmptyWhenPayloadIsArray()
    {
        var rawBody = """["not","an","object"]""";

        var envelope = HookForwarder.BuildEnvelopeJson(rawBody, "sess", "claude-code");

        envelope.Should().BeEmpty();
    }

    [Fact]
    public void BuildEnvelopeJson_ReturnsEmptyWhenHookEventNameIsEmpty()
    {
        var rawBody = """{"hook_event_name":""}""";

        var envelope = HookForwarder.BuildEnvelopeJson(rawBody, "sess", "claude-code");

        envelope.Should().BeEmpty();
    }

    [Fact]
    public void BuildEnvelopeJson_HandlesUnicodeInPrompt()
    {
        var rawBody = """{"hook_event_name":"UserPromptSubmit","prompt":"你好世界 🌍"}""";

        var envelope = HookForwarder.BuildEnvelopeJson(rawBody, "sess", "claude-code");

        using var doc = JsonDocument.Parse(envelope);
        doc.RootElement.GetProperty("payload").GetProperty("prompt").GetString().Should().Be("你好世界 🌍");
    }

    [Fact]
    public void BuildEnvelopeJson_IgnoresJsonComments()
    {
        const string rawBody = """
            // leading comment
            {"hook_event_name":"Stop","session_id":"x"}
            """;

        var envelope = HookForwarder.BuildEnvelopeJson(rawBody, "sess", "claude-code");

        envelope.Should().NotBeEmpty();
        using var doc = JsonDocument.Parse(envelope);
        doc.RootElement.GetProperty("event_type").GetString().Should().Be("Stop");
    }
}
