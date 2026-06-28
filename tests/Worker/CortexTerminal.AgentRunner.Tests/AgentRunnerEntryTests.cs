using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests;

/// <summary>
/// Verifies the entry-point argument parsing, env-var validation, and mode detection. Doesn't
/// actually spawn agent processes — those tests would require a real claude/codex/opencode
/// install and are better covered by end-to-end smoke tests in CI.
/// </summary>
public sealed class AgentRunnerEntryTests
{
    [Fact]
    public void Run_ReturnsUsageErrorWhenNoArgs()
    {
        var exit = AgentRunnerEntry.Run(Array.Empty<string>());
        exit.Should().Be(2);
    }

    [Fact]
    public void Run_ReturnsUsageErrorForUnknownKind()
    {
        var exit = AgentRunnerEntry.Run(new[] { "gemini", "--foo" });
        exit.Should().Be(2);
    }

    [Fact]
    public void Run_PartialEnv_Returns1()
    {
        // sessionId set but hookUrl missing — partial env, neither Worker nor Independent.
        var saved = SaveEnv();
        try
        {
            Environment.SetEnvironmentVariable("CORTERM_AGENT", null);
            Environment.SetEnvironmentVariable("CORTERM_SESSION_ID", "sess-1");
            Environment.SetEnvironmentVariable("CORTERM_AGENT_HOOK_URL", null);
            Environment.SetEnvironmentVariable("CORTERM_ORIGINAL_PATH", null);

            var exit = AgentRunnerEntry.Run(new[] { "claude" });
            exit.Should().Be(1);
        }
        finally
        {
            RestoreEnv(saved);
        }
    }

    [Fact]
    public void Run_NoEnv_IndependentModeIsSilentAndExits127WhenBinaryMissing()
    {
        // No Corterm env at all → independent mode → tries to locate binary, fails → 127.
        // Independent mode must be silent (cortap should look identical to running `claude`
        // directly). The only stderr output should be the "binary not found" error.
        var saved = SaveEnv();
        try
        {
            Environment.SetEnvironmentVariable("CORTERM_AGENT", null);
            Environment.SetEnvironmentVariable("CORTERM_SESSION_ID", null);
            Environment.SetEnvironmentVariable("CORTERM_AGENT_HOOK_URL", null);
            Environment.SetEnvironmentVariable("CORTERM_ORIGINAL_PATH", "/nonexistent-corterm-test-path");
            Environment.SetEnvironmentVariable("PATH", "/nonexistent-corterm-test-path");

            var (exit, stderr) = CaptureStderr(() => AgentRunnerEntry.Run(new[] { "claude" }));

            exit.Should().Be(127);
            stderr.Should().NotContain("independent mode");
            stderr.Should().NotContain("session id = i-");
            stderr.Should().Contain("not found in PATH");
        }
        finally
        {
            RestoreEnv(saved);
        }
    }

    private static (int exit, string stderr) CaptureStderr(Func<int> action)
    {
        var original = Console.Error;
        using var sw = new StringWriter();
        Console.SetError(sw);
        try
        {
            var exit = action();
            return (exit, sw.ToString());
        }
        finally
        {
            Console.SetError(original);
        }
    }

    private static Dictionary<string, string?> SaveEnv()
    {
        var keys = new[] { "CORTERM_AGENT", "CORTERM_SESSION_ID", "CORTERM_AGENT_HOOK_URL", "CORTERM_ORIGINAL_PATH", "PATH" };
        return keys.ToDictionary(k => k, k => Environment.GetEnvironmentVariable(k));
    }

    private static void RestoreEnv(Dictionary<string, string?> saved)
    {
        foreach (var (k, v) in saved)
        {
            Environment.SetEnvironmentVariable(k, v);
        }
    }
}
