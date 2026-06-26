using System.Diagnostics;

namespace CortexTerminal.AgentRunner;

/// <summary>
/// Entry point for the <c>corterm-agent</c> wrapper binary. Shim scripts exec this with
/// <c>corterm-agent &lt;kind&gt; [passthrough args...]</c>. The wrapper:
///
/// <list type="number">
/// <item>Validates kind + env vars set by the Worker (<c>CORTERM_SESSION_ID</c>, <c>CORTERM_AGENT_HOOK_URL</c>, <c>CORTERM_ORIGINAL_PATH</c>).</item>
/// <item>Locates the real agent binary via <c>CORTERM_ORIGINAL_PATH</c> (PATH without the shims dir).</item>
/// <item>(Phase 4+) Generates adapter-specific hook config + applies env vars like <c>CLAUDE_SETTINGS_FILE</c>.</item>
/// <item>Spawns the real agent with inherited stdio so the Corterm PTY stays interactive, then propagates exit code.</item>
/// </list>
///
/// Escape hatches: <c>CORTERM_AGENT=0 &lt;kind&gt;</c> skips all interception; the absolute path
/// and <c>command &lt;kind&gt;</c> bypass the shim entirely.
/// </summary>
public static class AgentRunnerEntry
{
    public static int Run(string[] args)
    {
        if (args.Length == 0)
        {
            PrintUsage();
            return 2;
        }

        // Dispatch the `hook` subcommand first — it's invoked by Claude Code's settings.json
        // hooks, not by the user. Reads event JSON on stdin, POSTs to the Worker.
        if (string.Equals(args[0], "hook", StringComparison.Ordinal))
        {
            return HookForwarder.Run(args.Skip(1).ToArray());
        }

        var kind = args[0];
        var passthrough = args.Skip(1).ToArray();

        if (!AgentBinaryResolver.SupportedKinds.Contains(kind))
        {
            Console.Error.WriteLine($"corterm-agent: unknown agent kind '{kind}'.");
            PrintUsage();
            return 2;
        }

        var originalPath = Environment.GetEnvironmentVariable("CORTERM_ORIGINAL_PATH");

        if (Environment.GetEnvironmentVariable("CORTERM_AGENT") == "0")
        {
            var escapeBinary = AgentBinaryResolver.Resolve(kind, originalPath);
            if (escapeBinary is null)
            {
                Console.Error.WriteLine($"corterm-agent: escape hatch failed — '{kind}' not found in PATH.");
                Console.Error.WriteLine($"  {AgentBinaryResolver.GetInstallHint(kind)}");
                return 127;
            }
            return SpawnAndAwait(escapeBinary, passthrough, setup: null);
        }

        var sessionId = Environment.GetEnvironmentVariable("CORTERM_SESSION_ID");
        var hookUrl = Environment.GetEnvironmentVariable("CORTERM_AGENT_HOOK_URL");

        if (string.IsNullOrEmpty(sessionId) || string.IsNullOrEmpty(hookUrl))
        {
            Console.Error.WriteLine("corterm-agent: missing CORTERM_SESSION_ID or CORTERM_AGENT_HOOK_URL.");
            Console.Error.WriteLine("  This shim only works inside a Corterm PTY session.");
            Console.Error.WriteLine("  Escape hatches:");
            Console.Error.WriteLine($"    - Use the absolute path to the real {kind} binary");
            Console.Error.WriteLine("    - Set CORTERM_AGENT=0 to skip interception");
            return 1;
        }

        var realBinary = AgentBinaryResolver.Resolve(kind, originalPath);
        if (realBinary is null)
        {
            Console.Error.WriteLine($"corterm-agent: '{kind}' binary not found in PATH.");
            Console.Error.WriteLine("  Install the agent first:");
            Console.Error.WriteLine($"    {AgentBinaryResolver.GetInstallHint(kind)}");
            return 127;
        }

        var setup = CreateLaunchSetup(kind, sessionId!, hookUrl!);
        LaunchSetupResult? setupResult = null;
        if (setup is not null)
        {
            try
            {
                setupResult = setup.Prepare();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"corterm-agent: failed to prepare {kind} hook config: {ex.Message}");
                Console.Error.WriteLine("  Falling back to no-hook spawn. Agent activity tracking will be limited.");
                setupResult = null;
            }
        }

        try
        {
            return SpawnAndAwait(realBinary, passthrough, setupResult);
        }
        finally
        {
            if (setupResult is not null)
            {
                try { Directory.Delete(setupResult.TempConfigDir, recursive: true); } catch { }
            }
        }
    }

    /// <summary>
    /// Pick the per-agent launch setup. Returns null when no setup is needed (Codex/OpenCode
    /// until their adapters land in Phase 5/6, or escape hatch is used).
    /// </summary>
    private static IAgentLaunchSetup? CreateLaunchSetup(string kind, string sessionId, string hookUrl)
    {
        return kind switch
        {
            "claude" => new ClaudeCodeLaunchSetup(sessionId, hookUrl),
            _ => null,
        };
    }

    private static void PrintUsage()
    {
        Console.Error.WriteLine("usage: corterm-agent <kind> [args...]");
        Console.Error.WriteLine("  Shim wrapper invoked from Corterm PTY sessions.");
        Console.Error.WriteLine($"  Supported kinds: {string.Join(", ", AgentBinaryResolver.SupportedKinds)}.");
    }

    private static int SpawnAndAwait(string binary, string[] args, LaunchSetupResult? setup)
    {
        var psi = new ProcessStartInfo
        {
            FileName = binary,
            UseShellExecute = false,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        if (setup is not null)
        {
            foreach (var (k, v) in setup.EnvironmentVariables)
            {
                psi.Environment[k] = v;
            }
        }

        try
        {
            var process = Process.Start(psi);
            if (process is null)
            {
                Console.Error.WriteLine($"corterm-agent: failed to start '{binary}'.");
                return 1;
            }
            process.WaitForExit();
            return process.ExitCode;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"corterm-agent: failed to start '{binary}': {ex.Message}");
            return 1;
        }
    }
}
