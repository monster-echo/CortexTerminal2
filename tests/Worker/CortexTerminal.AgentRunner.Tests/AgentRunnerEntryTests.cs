using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests;

/// <summary>
/// Verifies the entry-point argument parsing and env-var validation. Doesn't actually
/// spawn agent processes — those tests would require a real claude/codex/opencode
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
    public void Run_ReturnsErrorWhenSessionEnvVarsMissing()
    {
        // Clear all CORTERM_* env vars so the test is deterministic.
        var saved = SaveEnv();
        try
        {
            Environment.SetEnvironmentVariable("CORTERM_AGENT", null);
            Environment.SetEnvironmentVariable("CORTERM_SESSION_ID", null);
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

    private static Dictionary<string, string?> SaveEnv()
    {
        var keys = new[] { "CORTERM_AGENT", "CORTERM_SESSION_ID", "CORTERM_AGENT_HOOK_URL", "CORTERM_ORIGINAL_PATH" };
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
