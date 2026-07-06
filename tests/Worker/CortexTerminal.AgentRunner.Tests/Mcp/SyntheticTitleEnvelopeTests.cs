using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Mcp;

/// <summary>
/// AgentRunnerEntry produces a synthetic <c>AiTitleGenerated</c> envelope that crosses an
/// assembly boundary into CortexTerminal.Worker's AgentEventEndpoint + ClaudeCodeAdapter. The two
/// assemblies are tied together only by literal field names, so this test pins the producer side.
/// The consumer side is pinned by ClaudeCodeAdapterTests.ParseEvent_AiTitleGenerated_*; a rename on
/// either side fails the test in its own assembly rather than silently dropping titles on the wire.
/// </summary>
public sealed class SyntheticTitleEnvelopeTests
{
    [Fact]
    public void BuildSyntheticTitleEnvelope_UsesFieldsConsumerExpects()
    {
        var json = AgentRunnerEntry.BuildSyntheticTitleEnvelope("sess-1", "Download Bilibili Videos");

        // Field names mirror AgentEventEndpoint.Envelope* constants.
        var envelope = JsonNode.Parse(json)!.AsObject();
        envelope["session_id"]!.GetValue<string>().Should().Be("sess-1");
        envelope["agent_kind"]!.GetValue<string>().Should().Be("claude-code");
        envelope["event_type"]!.GetValue<string>().Should().Be("AiTitleGenerated");
        var payload = envelope["payload"]!.AsObject();
        // Mirrors ClaudeCodeAdapter.ParseAiTitleGenerated's read of payload["aiTitle"].
        payload["aiTitle"]!.GetValue<string>().Should().Be("Download Bilibili Videos");
    }

    [Fact]
    public void BuildSyntheticTitleEnvelope_PreservesUnicodeAndEmoji()
    {
        // UnsafeRelaxedJsonEscaping is not applied here, so non-ASCII travels as \uXXXX escapes in
        // the JSON string — but JsonNode.Parse decodes them on the consumer side, so the in-memory
        // value the adapter sees is intact.
        var json = AgentRunnerEntry.BuildSyntheticTitleEnvelope("sess-1", "保存 Bilibili 📺");

        var payload = JsonNode.Parse(json)!["payload"]!.AsObject();
        payload["aiTitle"]!.GetValue<string>().Should().Be("保存 Bilibili 📺");
    }
}
