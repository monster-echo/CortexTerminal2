using System.Diagnostics;
using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Commands;
using CortexTerminal.AgentRunner.Logging;
using CortexTerminal.AgentRunner.Mcp;
using CortexTerminal.AgentRunner.Sinks;

namespace CortexTerminal.AgentRunner;

/// <summary>
/// Entry point for the <c>cortap</c> wrapper binary. Shim scripts exec this with
/// <c>cortap &lt;kind&gt; [passthrough args...]</c>. The wrapper:
///
/// <list type="number">
/// <item>Detects mode from env vars:
///   <list type="bullet">
///   <item><b>Worker mode</b>: both <c>CORTERM_SESSION_ID</c> + <c>CORTERM_AGENT_HOOK_URL</c> set (Worker injected them).</item>
///   <item><b>Independent mode</b>: neither set — wrapper generates a session id and logs events locally.</item>
///   </list>
/// </item>
/// <item>Locates the real agent binary via <c>CORTERM_ORIGINAL_PATH</c>.</item>
/// <item>Generates adapter-specific hook config (e.g. per-session <c>--settings</c> for Claude Code).</item>
/// <item>Manages the session lifecycle: writes <c>meta.json</c> + <c>pid</c> at start, marks <c>endedAt</c> on exit.</item>
/// <item>Spawns the real agent with stdio inherited, propagates exit code.</item>
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
        // hooks, not by the user. Reads event JSON on stdin, dispatches to FileSink + HttpSink.
        if (string.Equals(args[0], "hook", StringComparison.Ordinal))
        {
            return HookForwarder.Run(args.Skip(1).ToArray());
        }

        // Inspection subcommands — operate on local session logs without spawning agents.
        if (string.Equals(args[0], "tail", StringComparison.Ordinal))
        {
            return TailCommand.Run(args.Skip(1).ToArray());
        }
        if (string.Equals(args[0], "events", StringComparison.Ordinal))
        {
            return EventsCommand.Run(args.Skip(1).ToArray());
        }
        if (string.Equals(args[0], "sessions", StringComparison.Ordinal))
        {
            return SessionsCommand.Run(args.Skip(1).ToArray());
        }
        if (string.Equals(args[0], "--help", StringComparison.Ordinal) ||
            string.Equals(args[0], "-h", StringComparison.Ordinal) ||
            string.Equals(args[0], "help", StringComparison.Ordinal))
        {
            PrintUsage();
            return 0;
        }

        var kind = args[0];
        var passthrough = args.Skip(1).ToArray();

        if (!AgentBinaryResolver.SupportedKinds.Contains(kind))
        {
            Console.Error.WriteLine($"cortap: unknown agent kind '{kind}'.");
            PrintUsage();
            return 2;
        }

        // Worker injects CORTERM_ORIGINAL_PATH pointing at PATH minus the shim dir so we skip
        // our own wrapper. Independent mode has no Worker — fall back to the user's PATH so we
        // still find the real `claude` / `codex` / `opencode` they installed globally.
        var originalPath = Environment.GetEnvironmentVariable("CORTERM_ORIGINAL_PATH")
            ?? Environment.GetEnvironmentVariable("PATH");

        if (Environment.GetEnvironmentVariable("CORTERM_AGENT") == "0")
        {
            var escapeBinary = AgentBinaryResolver.Resolve(kind, originalPath);
            if (escapeBinary is null)
            {
                Console.Error.WriteLine($"cortap: escape hatch failed — '{kind}' not found in PATH.");
                Console.Error.WriteLine($"  {AgentBinaryResolver.GetInstallHint(kind)}");
                return 127;
            }
            return SpawnAndAwait(escapeBinary, passthrough, setup: null, sessionId: string.Empty);
        }

        var sessionId = Environment.GetEnvironmentVariable("CORTERM_SESSION_ID");
        var hookUrl = Environment.GetEnvironmentVariable("CORTERM_AGENT_HOOK_URL");

        var hasSession = !string.IsNullOrEmpty(sessionId);
        var hasHookUrl = !string.IsNullOrEmpty(hookUrl);

        if (hasSession && hasHookUrl)
        {
            // Worker mode — Worker injects both. Fall through.
        }
        else if (!hasSession && !hasHookUrl)
        {
            // Independent mode — generate a fresh session id and reap orphaned sessions.
            // Stay silent: cortap must look identical to running `claude` directly. Users
            // who care can find their session via `cortap sessions` / `cortap tail`.
            sessionId = GenerateSessionId();
            SessionLifecycle.ReapOrphanedSessions();
        }
        else
        {
            Console.Error.WriteLine("cortap: partial Corterm env (one of CORTERM_SESSION_ID / CORTERM_AGENT_HOOK_URL is missing).");
            Console.Error.WriteLine("  Worker mode requires both. For independent mode, unset both.");
            Console.Error.WriteLine("  Escape hatches:");
            Console.Error.WriteLine($"    - Use the absolute path to the real {kind} binary");
            Console.Error.WriteLine("    - Set CORTERM_AGENT=0 to skip interception");
            return 1;
        }

        var realBinary = AgentBinaryResolver.Resolve(kind, originalPath);
        if (realBinary is null)
        {
            Console.Error.WriteLine($"cortap: '{kind}' binary not found in PATH.");
            Console.Error.WriteLine("  Install the agent first:");
            Console.Error.WriteLine($"    {AgentBinaryResolver.GetInstallHint(kind)}");
            return 127;
        }

        // Claude kind only: start the local MCP server so Claude can call
        // mcp__corterm__change_title to report chat titles. The URL is threaded into
        // ClaudeCodeLaunchSetup so it ends up in the per-session --settings file.
        CortermMcpServer? mcpServer = null;
        string? mcpUrl = null;
        if (kind == "claude")
        {
            try
            {
                mcpServer = StartMcpServerForClaude(sessionId!);
                mcpUrl = mcpServer.Url;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"cortap: failed to start MCP server: {ex.Message}");
                Console.Error.WriteLine("  Title auto-update will not work; agent runs normally.");
                mcpServer = null;
                mcpUrl = null;
            }
        }

        var setup = CreateLaunchSetup(kind, sessionId!, mcpUrl);
        LaunchSetupResult? setupResult = null;
        if (setup is not null)
        {
            try
            {
                setupResult = setup.Prepare();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"cortap: failed to prepare {kind} hook config: {ex.Message}");
                Console.Error.WriteLine("  Falling back to no-hook spawn. Agent activity tracking will be limited.");
                setupResult = null;
            }
        }

        using var lifecycle = new SessionLifecycle(sessionId!, kind, cwd: Environment.CurrentDirectory);
        lifecycle.Start();

        try
        {
            return SpawnAndAwait(realBinary, passthrough, setupResult, sessionId!);
        }
        finally
        {
            lifecycle.Stop();
            if (setupResult is not null)
            {
                try { Directory.Delete(setupResult.TempConfigDir, recursive: true); } catch { }
            }
            if (mcpServer is not null)
            {
                try { mcpServer.StopAsync().GetAwaiter().GetResult(); } catch { }
            }
        }
    }

    /// <summary>
    /// Start the cortap MCP server and wire its <c>change_title</c> callback to forward a
    /// synthetic <c>AiTitleGenerated</c> event through the same sink chain HookForwarder uses
    /// (FileSink always, HttpSink when CORTERM_AGENT_HOOK_URL is set). The Worker's
    /// AgentEventEndpoint turns the envelope into an <see cref="AgentTitleUpdatedFrame"/>,
    /// which the Gateway broadcasts to the Console so the session list updates in real time.
    /// </summary>
    private static CortermMcpServer StartMcpServerForClaude(string sessionId)
    {
        var server = new CortermMcpServer();
        server.OnTitleChanged += (title, ct) => ForwardSyntheticTitleAsync(sessionId, title, ct);
        server.StartAsync(CancellationToken.None).GetAwaiter().GetResult();
        return server;
    }

    private static async Task ForwardSyntheticTitleAsync(string sessionId, string title, CancellationToken cancellationToken)
    {
        var sinks = new List<IAgentEventSink> { new FileSink(sessionId) };
        var hookUrl = Environment.GetEnvironmentVariable("CORTERM_AGENT_HOOK_URL");
        if (!string.IsNullOrEmpty(hookUrl))
        {
            sinks.Add(new HttpSink(hookUrl!));
        }
        var composite = new CompositeSink(sinks);

        await composite.ForwardAsync(BuildSyntheticTitleEnvelope(sessionId, title), cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Build the synthetic AiTitleGenerated envelope. Internal so the contract test in
    /// CortexTerminal.AgentRunner.Tests can pin the field names that CortexTerminal.Worker's
    /// AgentEventEndpoint + ClaudeCodeAdapter rely on — the two assemblies are tied together only
    /// by these literal strings, so a rename here must fail the test instead of silently breaking
    /// title updates end-to-end.
    /// </summary>
    internal static string BuildSyntheticTitleEnvelope(string sessionId, string title)
    {
        var envelope = new JsonObject
        {
            ["session_id"] = sessionId,
            ["agent_kind"] = "claude-code",
            ["event_type"] = "AiTitleGenerated",
            ["payload"] = new JsonObject { ["aiTitle"] = title },
        };
        return envelope.ToJsonString();
    }

    /// <summary>
    /// Independent mode session ids use the <c>i-</c> prefix so they are visually distinct from
    /// Worker-injected ids. 12 hex chars = enough entropy to avoid collisions in any single
    /// user's session history.
    /// </summary>
    private static string GenerateSessionId()
    {
        return "i-" + Guid.NewGuid().ToString("N")[..12];
    }

    /// <summary>
    /// Pick the per-agent launch setup. Returns null when no setup is needed (Codex/OpenCode
    /// until their adapters land in Phase 5/6, or escape hatch is used).
    /// </summary>
    private static IAgentLaunchSetup? CreateLaunchSetup(string kind, string sessionId, string? mcpUrl)
    {
        return kind switch
        {
            "claude" => new ClaudeCodeLaunchSetup(sessionId, mcpUrl),
            _ => null,
        };
    }

    private static void PrintUsage()
    {
        Console.Error.WriteLine("usage: cortap <kind> [args...]");
        Console.Error.WriteLine("       cortap hook <kind>");
        Console.Error.WriteLine("       cortap tail [--all|--latest|--current] [sessionId]");
        Console.Error.WriteLine("       cortap events [--session <id>] [--grep <pattern>] [--last N]");
        Console.Error.WriteLine("       cortap sessions");
        Console.Error.WriteLine("  Shim wrapper invoked from Corterm PTY sessions, or standalone in independent mode.");
        Console.Error.WriteLine($"  Supported kinds: {string.Join(", ", AgentBinaryResolver.SupportedKinds)}.");
    }

    private static int SpawnAndAwait(string binary, string[] args, LaunchSetupResult? setup, string sessionId)
    {
        var psi = new ProcessStartInfo
        {
            FileName = binary,
            UseShellExecute = false,
        };
        foreach (var a in setup?.PassthroughArgs ?? Array.Empty<string>()) psi.ArgumentList.Add(a);
        foreach (var a in args) psi.ArgumentList.Add(a);

        // Inject CORTERM_SESSION_ID so hook subprocesses (spawned by the real agent) inherit it.
        // In escape-hatch mode sessionId is empty — don't overwrite whatever the parent has.
        if (!string.IsNullOrEmpty(sessionId))
        {
            psi.Environment["CORTERM_SESSION_ID"] = sessionId;
        }

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
                Console.Error.WriteLine($"cortap: failed to start '{binary}'.");
                return 1;
            }
            process.WaitForExit();
            return process.ExitCode;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"cortap: failed to start '{binary}': {ex.Message}");
            return 1;
        }
    }
}
