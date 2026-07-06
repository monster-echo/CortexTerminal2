using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.Worker.Agent;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Agent;

/// <summary>
/// Validates the Claude Code UserPromptSubmit hook response builder. When the user uploads
/// files via Console, the Worker lists them in additionalContext so Claude Code "sees" them
/// without the user having to @-reference the path. Tests cover the file-scan logic, JSON
/// shape, Unicode handling, file-size formatting, and the empty/missing dir guards.
/// </summary>
public sealed class AgentEventHookResponseTests
{
    [Fact]
    public void BuildHookResponseForDir_WithFiles_ReturnsValidJsonListingAllFiles()
    {
        using var dir = new TempArtifactsDir();
        File.WriteAllBytes(Path.Combine(dir.Path, "alpha.txt"), new byte[512]);
        File.WriteAllBytes(Path.Combine(dir.Path, "beta.png"), new byte[1024 * 1024]);

        var json = AgentEventEndpoint.BuildHookResponseForDir(dir.Path);

        json.Should().NotBeNull();
        using var doc = JsonDocument.Parse(json!);
        var hookOutput = doc.RootElement.GetProperty("hookSpecificOutput");
        hookOutput.GetProperty("hookEventName").GetString().Should().Be("UserPromptSubmit");
        var context = hookOutput.GetProperty("additionalContext").GetString()!;
        context.Should().Contain("[Corterm] 2 file(s) uploaded via Console in");
        context.Should().Contain(dir.Path);
        context.Should().Contain("- alpha.txt (512 B)");
        context.Should().Contain("- beta.png (1.0 MB)");
    }

    [Fact]
    public void BuildHookResponseForDir_EmptyDir_ReturnsNull()
    {
        using var dir = new TempArtifactsDir();

        AgentEventEndpoint.BuildHookResponseForDir(dir.Path).Should().BeNull();
    }

    [Fact]
    public void BuildHookResponseForDir_MissingDir_ReturnsNull()
    {
        var ghost = Path.Combine(Path.GetTempPath(), "corterm-missing-" + Guid.NewGuid().ToString("N"));

        AgentEventEndpoint.BuildHookResponseForDir(ghost).Should().BeNull();
    }

    [Fact]
    public void BuildHookResponseForDir_UnicodeFilename_NotEscaped()
    {
        using var dir = new TempArtifactsDir();
        File.WriteAllBytes(Path.Combine(dir.Path, "截图.png"), new byte[1024]);
        File.WriteAllBytes(Path.Combine(dir.Path, "笔记.txt"), new byte[512]);

        var json = AgentEventEndpoint.BuildHookResponseForDir(dir.Path)!;

        // UnsafeRelaxedJsonEscaping must let non-ASCII through as UTF-8 instead of \uXXXX.
        json.Should().Contain("截图.png");
        json.Should().Contain("笔记.txt");
        json.Should().NotContain("\\u");

        // Round-trip through a JSON parser must yield the original characters.
        using var doc = JsonDocument.Parse(json);
        var context = doc.RootElement.GetProperty("hookSpecificOutput").GetProperty("additionalContext").GetString()!;
        context.Should().Contain("截图.png");
        context.Should().Contain("笔记.txt");
    }

    [Fact]
    public void BuildHookResponseForDir_LimitsToTenFiles_NewestFirst()
    {
        using var dir = new TempArtifactsDir();
        // Create 12 files with strictly increasing mtimes so ordering is deterministic.
        for (var i = 0; i < 12; i++)
        {
            var path = Path.Combine(dir.Path, $"f{i:D2}.txt");
            File.WriteAllBytes(path, new byte[10]);
            File.SetLastWriteTimeUtc(path, new DateTime(2026, 1, 1, 0, 0, i, DateTimeKind.Utc));
        }

        var json = AgentEventEndpoint.BuildHookResponseForDir(dir.Path)!;
        using var doc = JsonDocument.Parse(json);
        var context = doc.RootElement.GetProperty("hookSpecificOutput").GetProperty("additionalContext").GetString()!;

        // Expect 10 files (the cap), sorted newest first → f11, f10, f09, ... f02.
        context.Should().Contain("- f11.txt");
        context.Should().Contain("- f02.txt");
        context.Should().NotContain("- f01.txt");
        context.Should().NotContain("- f00.txt");

        var idx11 = context.IndexOf("- f11.txt", StringComparison.Ordinal);
        var idx02 = context.IndexOf("- f02.txt", StringComparison.Ordinal);
        idx11.Should().BeLessThan(idx02, "newest file (f11) must appear before older files");
    }

    [Fact]
    public void BuildHookResponseForDir_IgnoresSubdirectories()
    {
        using var dir = new TempArtifactsDir();
        File.WriteAllBytes(Path.Combine(dir.Path, "real.txt"), new byte[10]);
        Directory.CreateDirectory(Path.Combine(dir.Path, "subdir"));

        var json = AgentEventEndpoint.BuildHookResponseForDir(dir.Path)!;
        json.Should().Contain("real.txt");
        json.Should().NotContain("subdir");
    }

    [Theory]
    [InlineData(0, "0 B")]
    [InlineData(512, "512 B")]
    [InlineData(1023, "1023 B")]
    [InlineData(1024, "1.0 KB")]
    [InlineData(1536, "1.5 KB")]
    [InlineData(1024 * 1024, "1.0 MB")]
    [InlineData(1024L * 1024 * 1024, "1.0 GB")]
    [InlineData(1024L * 1024 * 1024 * 5, "5.0 GB")]
    public void FormatFileSize_ReturnsHumanReadable(long bytes, string expected)
    {
        AgentEventEndpoint.FormatFileSize(bytes).Should().Be(expected);
    }

    [Fact]
    public void BuildHookResponseForDir_ReturnsJsonParseableByStdJsonObjectReader()
    {
        // Claude Code parses hook stdout via its own JSON parser; ensure our output is plain
        // JSON (no BOM, no comments, valid object literal).
        using var dir = new TempArtifactsDir();
        File.WriteAllBytes(Path.Combine(dir.Path, "x.txt"), new byte[1]);

        var json = AgentEventEndpoint.BuildHookResponseForDir(dir.Path)!;
        var node = JsonNode.Parse(json);
        node.Should().NotBeNull();
        node!["hookSpecificOutput"]!["hookEventName"]!.GetValue<string>().Should().Be("UserPromptSubmit");
        node["hookSpecificOutput"]!["additionalContext"]!.GetValue<string>().Should().Contain("x.txt");
    }

    private sealed class TempArtifactsDir : IDisposable
    {
        public string Path { get; }

        public TempArtifactsDir()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "corterm-artifacts-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path);
        }

        public void Dispose()
        {
            try { if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true); } catch { }
        }
    }
}
