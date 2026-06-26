using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Concrete <see cref="IAgentIntegration"/>. Owns:
///  - the loopback HTTP URL the hook events POST to
///  - the shim directory prepended to every PTY PATH
///  - the original PATH snapshot so the wrapper binary can locate the real agent
///
/// The HookUrl is filled in by <see cref="AgentEventEndpoint"/> once Kestrel binds
/// to a random loopback port. Until that happens, <see cref="Enabled"/> stays false
/// and PTY spawns skip the agent-tracking env vars.
/// </summary>
public sealed class AgentIntegration : IAgentIntegration
{
    private static readonly string[] AgentKinds = { "claude", "codex", "opencode" };

    private readonly ILogger<AgentIntegration> _logger;
    private readonly string _installDir;
    private readonly string _shimsDir;
    private readonly string _originalPath;
    private volatile string? _hookUrl;
    private volatile bool _enabled;

    public AgentIntegration(string installDir, ILogger<AgentIntegration> logger)
    {
        _logger = logger;
        _installDir = installDir;
        _shimsDir = Path.Combine(installDir, "shims");
        _originalPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
    }

    public bool Enabled => _enabled && _hookUrl is not null;

    public string HookUrl =>
        _hookUrl ?? throw new InvalidOperationException("Agent event endpoint has not started yet.");

    public string ShimsDir => _shimsDir;

    public string OriginalPath => _originalPath;

    /// <summary>Called by <see cref="AgentEventEndpoint"/> after Kestrel has bound its loopback port.</summary>
    public void MarkReady(string hookUrl)
    {
        if (string.IsNullOrWhiteSpace(hookUrl))
            throw new ArgumentException("Hook URL must not be empty.", nameof(hookUrl));
        _hookUrl = hookUrl;
        _enabled = true;
        _logger.LogInformation("Agent integration ready: hook URL = {HookUrl}, shims = {ShimsDir}.", hookUrl, _shimsDir);
    }

    /// <summary>
    /// Write the claude/codex/opencode shims into <see cref="ShimsDir"/>. Idempotent — overwrites
    /// every startup so a Worker upgrade picks up script changes. The shims exec &lt;install&gt;/corterm-agent
    /// (corterm-agent.exe on Windows), which the wrapper project produces in Phase 3.
    /// </summary>
    public void EnsureShimsInstalled()
    {
        Directory.CreateDirectory(_shimsDir);
        var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
        var wrapperName = isWindows ? "corterm-agent.exe" : "corterm-agent";
        var wrapperPath = Path.Combine(_installDir, wrapperName);

        foreach (var kind in AgentKinds)
        {
            if (isWindows)
            {
                var scriptPath = Path.Combine(_shimsDir, kind + ".cmd");
                File.WriteAllText(scriptPath, WindowsShimBody(wrapperPath, kind));
            }
            else
            {
                var scriptPath = Path.Combine(_shimsDir, kind);
                File.WriteAllText(scriptPath, UnixShimBody(wrapperPath, kind));
                try
                {
                    File.SetUnixFileMode(scriptPath, UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute | UnixFileMode.UserRead | UnixFileMode.GroupRead | UnixFileMode.OtherRead);
                }
                catch (IOException ioEx)
                {
                    _logger.LogWarning(ioEx, "Failed to set executable mode on shim {Path}.", scriptPath);
                }
            }
        }

        _logger.LogInformation("Agent shims installed at {ShimsDir} (wrapper = {Wrapper}).", _shimsDir, wrapperPath);
    }

    private static string UnixShimBody(string wrapperPath, string kind)
    {
        return $"#!/bin/sh\n" +
               $"# Corterm shim. Forwards `{kind}` to corterm-agent so the agent tracking\n" +
               $"# wrapper can inject hooks, name the session, and stream activity frames.\n" +
               $"# Escape hatches: CORTERM_AGENT=0 {kind}, `command {kind}`, or use the\n" +
               $"# absolute path to the real binary.\n" +
               $"exec \"{wrapperPath}\" {kind} \"$@\"\n";
    }

    private static string WindowsShimBody(string wrapperPath, string kind)
    {
        return "@echo off\n" +
               "rem Corterm shim. Forwards `" + kind + "` to corterm-agent.\n" +
               "rem Escape hatches: set CORTERM_AGENT=0, or call the absolute path.\n" +
               "setlocal\n" +
               $"\"{wrapperPath}\" {kind} %*\n";
    }
}
