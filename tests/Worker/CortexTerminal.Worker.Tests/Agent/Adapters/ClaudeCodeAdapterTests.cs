using System.Text.Json.Nodes;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Agent;
using CortexTerminal.Worker.Agent.Adapters;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Agent.Adapters;

/// <summary>
/// Verifies Claude Code hook payload parsing. Each event type maps to a structured activity
/// frame; the adapter must extract the right fields and ignore uninteresting events like
/// PreToolUse (we emit tool-call frames only on PostToolUse).
/// </summary>
public sealed class ClaudeCodeAdapterTests
{
    private readonly ClaudeCodeAdapter _adapter = new();
    private readonly AgentSessionContext _context = new(
        SessionId: "sess-123",
        HookUrl: "http://127.0.0.1:9999/agent-event",
        WorkDir: "/tmp/work",
        TempConfigDir: "/tmp/.corterm/agent-hooks/sess-123");

    [Fact]
    public void Kind_IsClaudeCode()
    {
        _adapter.Kind.Should().Be(AgentKind.ClaudeCode);
    }

    [Fact]
    public void HookConfigFilename_IsSettingsJson()
    {
        _adapter.HookConfigFilename.Should().Be("settings.json");
    }

    [Fact]
    public void ParseEvent_SessionStart_YieldsAgentStartedFrame()
    {
        var payload = new JsonObject
        {
            ["session_id"] = "claude-internal-1",
            ["cwd"] = "/home/user/project",
            ["hook_event_name"] = "SessionStart",
        };

        var frame = _adapter.ParseEvent("SessionStart", payload, _context);

        var started = frame.Should().BeOfType<AgentStartedFrame>().Subject;
        started.SessionId.Should().Be("sess-123");
        started.Kind.Should().Be(AgentKind.ClaudeCode);
        started.AgentSessionId.Should().Be("claude-internal-1");
        started.WorkDir.Should().Be("/home/user/project");
    }

    [Fact]
    public void ParseEvent_UserPromptSubmit_YieldsPromptSubmittedFrame()
    {
        var payload = new JsonObject
        {
            ["session_id"] = "claude-internal-1",
            ["hook_event_name"] = "UserPromptSubmit",
            ["prompt"] = "Fix the bug in auth flow",
        };

        var frame = _adapter.ParseEvent("UserPromptSubmit", payload, _context);

        var prompt = frame.Should().BeOfType<AgentPromptSubmittedFrame>().Subject;
        prompt.SessionId.Should().Be("sess-123");
        prompt.PromptText.Should().Be("Fix the bug in auth flow");
        prompt.PromptId.Should().BeNullOrEmpty();
    }

    [Fact]
    public void ParseEvent_UserPromptSubmit_MissingPrompt_YieldsEmptyText()
    {
        var payload = new JsonObject
        {
            ["hook_event_name"] = "UserPromptSubmit",
        };

        var frame = _adapter.ParseEvent("UserPromptSubmit", payload, _context);

        var prompt = frame.Should().BeOfType<AgentPromptSubmittedFrame>().Subject;
        prompt.PromptText.Should().BeEmpty();
    }

    [Fact]
    public void ParseEvent_PostToolUse_YieldsToolCallFrameWithInputAndOutput()
    {
        var payload = new JsonObject
        {
            ["hook_event_name"] = "PostToolUse",
            ["tool_name"] = "Bash",
            ["tool_input"] = new JsonObject { ["command"] = "ls -la" },
            ["tool_response"] = new JsonObject
            {
                ["content"] = new JsonArray("total 0"),
                ["is_error"] = false,
            },
        };

        var frame = _adapter.ParseEvent("PostToolUse", payload, _context);

        var call = frame.Should().BeOfType<AgentToolCallFrame>().Subject;
        call.SessionId.Should().Be("sess-123");
        call.ToolName.Should().Be("Bash");
        call.Input.Should().Contain("ls -la");
        call.Output.Should().Contain("total 0");
        call.DurationMs.Should().Be(0);
        call.IsError.Should().BeFalse();
    }

    [Fact]
    public void ParseEvent_PostToolUse_MarksErrorWhenToolResponseHasError()
    {
        var payload = new JsonObject
        {
            ["hook_event_name"] = "PostToolUse",
            ["tool_name"] = "Bash",
            ["tool_input"] = new JsonObject { ["command"] = "exit 1" },
            ["tool_response"] = new JsonObject { ["is_error"] = true },
        };

        var frame = _adapter.ParseEvent("PostToolUse", payload, _context);

        var call = frame.Should().BeOfType<AgentToolCallFrame>().Subject;
        call.IsError.Should().BeTrue();
    }

    [Fact]
    public void ParseEvent_Stop_YieldsAgentStoppedFrameWithNullCost()
    {
        var payload = new JsonObject
        {
            ["hook_event_name"] = "Stop",
            ["session_id"] = "claude-internal-1",
        };

        var frame = _adapter.ParseEvent("Stop", payload, _context);

        var stopped = frame.Should().BeOfType<AgentStoppedFrame>().Subject;
        stopped.SessionId.Should().Be("sess-123");
        stopped.TotalCostUsd.Should().BeNull();
        stopped.TotalTokensIn.Should().BeNull();
        stopped.TotalTokensOut.Should().BeNull();
        stopped.StopReason.Should().BeNull();
    }

    [Fact]
    public void ParseEvent_PreToolUse_ReturnsNull()
    {
        var payload = new JsonObject
        {
            ["hook_event_name"] = "PreToolUse",
            ["tool_name"] = "Bash",
        };

        var frame = _adapter.ParseEvent("PreToolUse", payload, _context);

        frame.Should().BeNull();
    }

    [Fact]
    public void ParseEvent_UnknownEventType_ReturnsNull()
    {
        var payload = new JsonObject { ["hook_event_name"] = "Whatever" };

        _adapter.ParseEvent("Whatever", payload, _context).Should().BeNull();
    }

    [Fact]
    public void GenerateHookConfig_ContainsAllFiveEventsWithHookCommand()
    {
        var json = _adapter.GenerateHookConfig(_context);
        var root = JsonNode.Parse(json)!.AsObject();
        var hooks = root["hooks"]!.AsObject();
        var expected = new[] { "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop" };
        foreach (var evt in expected)
        {
            var entry = hooks[evt]?.AsArray();
            entry.Should().NotBeNull();
            entry!.Count.Should().BeGreaterThan(0);
            var hookObj = entry[0]!.AsObject();
            hookObj["matcher"]!.GetValue<string>().Should().Be("*");
            var hookCmd = hookObj["hooks"]!.AsArray()[0]!.AsObject();
            hookCmd["type"]!.GetValue<string>().Should().Be("command");
            hookCmd["command"]!.GetValue<string>().Should().Contain("hook");
            hookCmd["command"]!.GetValue<string>().Should().Contain("claude-code");
        }
    }

    [Fact]
    public void BuildEnvironment_SetsClaudeConfigDir()
    {
        var env = _adapter.BuildEnvironment(_context);

        env.Should().ContainKey("CLAUDE_CONFIG_DIR");
        env["CLAUDE_CONFIG_DIR"].Should().Be(_context.TempConfigDir);
    }
}
