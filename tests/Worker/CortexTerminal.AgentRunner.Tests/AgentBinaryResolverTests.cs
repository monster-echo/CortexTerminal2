using System.Runtime.InteropServices;
using CortexTerminal.AgentRunner;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests;

/// <summary>
/// Verifies the wrapper's binary-resolution logic — finding the real agent binary on the
/// original (shim-free) PATH. Resolution must skip non-executable files on Unix and consider
/// the .cmd/.bat/.exe variants on Windows. These tests do not exercise Process.Start;
/// that path is covered by end-to-end smoke tests in the release pipeline.
/// </summary>
public sealed class AgentBinaryResolverTests
{
    [Fact]
    public void SupportedKinds_AreClaudeCodexOpenCode()
    {
        AgentBinaryResolver.SupportedKinds.Should().BeEquivalentTo(new[] { "claude", "codex", "opencode" });
    }

    [Theory]
    [InlineData("claude")]
    [InlineData("codex")]
    [InlineData("opencode")]
    public void Resolve_FindsExecutableOnUnixPath(string kind)
    {
        if (OperatingSystem.IsWindows()) return;

        var dir = Path.Combine(Path.GetTempPath(), "corterm-resolver-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var binaryPath = Path.Combine(dir, kind);
            File.WriteAllText(binaryPath, "#!/bin/sh\necho hi\n");
            File.SetUnixFileMode(binaryPath, UnixFileMode.UserRead | UnixFileMode.UserExecute);

            var path = kind + "=" + dir;
            AgentBinaryResolver.Resolve(kind, dir).Should().Be(binaryPath);
        }
        finally
        {
            try { Directory.Delete(dir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Resolve_SkipsNonExecutableFilesOnUnix()
    {
        if (OperatingSystem.IsWindows()) return;

        var dir = Path.Combine(Path.GetTempPath(), "corterm-resolver-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var binaryPath = Path.Combine(dir, "claude");
            File.WriteAllText(binaryPath, "#!/bin/sh\necho hi\n");
            // Read but not execute — should be skipped.
            File.SetUnixFileMode(binaryPath, UnixFileMode.UserRead);

            AgentBinaryResolver.Resolve("claude", dir).Should().BeNull();
        }
        finally
        {
            try { Directory.Delete(dir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Resolve_PrefersFirstDirectoryInPath()
    {
        var dirA = Path.Combine(Path.GetTempPath(), "corterm-resolver-a-" + Guid.NewGuid().ToString("N"));
        var dirB = Path.Combine(Path.GetTempPath(), "corterm-resolver-b-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dirA);
        Directory.CreateDirectory(dirB);
        try
        {
            var binA = Path.Combine(dirA, "claude");
            var binB = Path.Combine(dirB, "claude");
            File.WriteAllText(binA, "");
            File.WriteAllText(binB, "");
            if (!OperatingSystem.IsWindows())
            {
                File.SetUnixFileMode(binA, UnixFileMode.UserRead | UnixFileMode.UserExecute);
                File.SetUnixFileMode(binB, UnixFileMode.UserRead | UnixFileMode.UserExecute);
            }

            var separator = OperatingSystem.IsWindows() ? ';' : ':';
            var combined = dirA + separator + dirB;
            AgentBinaryResolver.Resolve("claude", combined).Should().Be(binA);
        }
        finally
        {
            try { Directory.Delete(dirA, recursive: true); } catch { }
            try { Directory.Delete(dirB, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Resolve_ReturnsNullWhenBinaryMissing()
    {
        var dir = Path.Combine(Path.GetTempPath(), "corterm-resolver-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            AgentBinaryResolver.Resolve("claude", dir).Should().BeNull();
        }
        finally
        {
            try { Directory.Delete(dir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void Resolve_ReturnsNullForUnknownKind()
    {
        AgentBinaryResolver.Resolve("gemini", "/usr/local/bin").Should().BeNull();
    }

    [Fact]
    public void Resolve_HandlesNullOrEmptyPath()
    {
        AgentBinaryResolver.Resolve("claude", null).Should().BeNull();
        AgentBinaryResolver.Resolve("claude", "").Should().BeNull();
    }

    [Fact]
    public void GetCandidateNames_ReturnsBareNameOnUnix()
    {
        if (OperatingSystem.IsWindows()) return;
        AgentBinaryResolver.GetCandidateNames("claude").Should().Equal(new[] { "claude" });
    }

    [Fact]
    public void GetCandidateNames_ReturnsWindowsExtensionsOnWindows()
    {
        if (!OperatingSystem.IsWindows()) return;
        AgentBinaryResolver.GetCandidateNames("claude").Should().BeEquivalentTo(new[] { "claude.exe", "claude.cmd", "claude.bat" });
    }

    [Fact]
    public void GetInstallHint_ReturnsNpmCommand()
    {
        AgentBinaryResolver.GetInstallHint("claude").Should().Contain("@anthropic-ai/claude-code");
        AgentBinaryResolver.GetInstallHint("codex").Should().Contain("@openai/codex");
        AgentBinaryResolver.GetInstallHint("opencode").Should().Contain("opencode-ai");
    }
}
