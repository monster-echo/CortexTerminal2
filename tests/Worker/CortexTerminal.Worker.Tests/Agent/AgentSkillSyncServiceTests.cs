using System.Net;
using CortexTerminal.Worker.Agent;
using CortexTerminal.Worker.Tests.Artifacts.Fakes;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Agent;

/// <summary>
/// The sync service must fetch on first run, skip the reinstall when the fetched sha matches the
/// cache (the no-op path that makes a 6h poll cheap), and survive a flappy remote without throwing
/// or wiping the cache. Uses RecordingHttpMessageHandler to stub the network and a temp HOME so the
/// installer writes nowhere real.
/// </summary>
public sealed class AgentSkillSyncServiceTests
{
    [Fact]
    public async Task RefreshOnceAsync_NoCache_FetchesBothFilesAndInstalls()
    {
        using var home = new TempHome();
        var installer = new AgentSkillInstaller(NullLogger<AgentSkillInstaller>.Instance, home.Path);
        var handler = new RecordingHttpMessageHandler
        {
            Responder = _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("BODY") }
        };
        var service = new AgentSkillSyncService(
            new AgentSkillSource(), installer, new HttpClient(handler), NullLogger<AgentSkillSyncService>.Instance);

        await service.RefreshOnceAsync("test", CancellationToken.None);

        handler.Requests.Should().HaveCount(2); // SKILL.md + CODEX.md
        File.Exists(Path.Combine(installer.ClaudeSkillDir, "SKILL.md")).Should().BeTrue();
        (await installer.GetCachedShaAsync(CancellationToken.None)).Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task RefreshOnceAsync_ShaMatchesCache_DoesNotReinstall()
    {
        using var home = new TempHome();
        var installer = new AgentSkillInstaller(NullLogger<AgentSkillInstaller>.Instance, home.Path);
        const string Body = "STABLE";
        // Pre-seed the cache with content whose sha matches what fetch will return.
        Directory.CreateDirectory(installer.CacheDir);
        await File.WriteAllTextAsync(Path.Combine(installer.CacheDir, "SKILL.md"), Body);
        await File.WriteAllTextAsync(Path.Combine(installer.CacheDir, "CODEX.md"), Body);
        await File.WriteAllTextAsync(Path.Combine(installer.CacheDir, ".sha256"),
            AgentSkillInstaller.ComputeContentSha(Body, Body));

        var handler = new RecordingHttpMessageHandler
        {
            Responder = _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Body) }
        };
        var service = new AgentSkillSyncService(
            new AgentSkillSource(), installer, new HttpClient(handler), NullLogger<AgentSkillSyncService>.Instance);

        await service.RefreshOnceAsync("test", CancellationToken.None);

        handler.Requests.Should().HaveCount(2);                       // still fetched to compute sha
        Directory.Exists(installer.ClaudeSkillDir).Should().BeFalse(); // but install was skipped
    }

    [Fact]
    public async Task RefreshOnceAsync_FetchFails_LogsAndLeavesCacheUntouched()
    {
        using var home = new TempHome();
        var installer = new AgentSkillInstaller(NullLogger<AgentSkillInstaller>.Instance, home.Path);
        var handler = new RecordingHttpMessageHandler
        {
            Responder = _ => new HttpResponseMessage(HttpStatusCode.InternalServerError)
        };
        var service = new AgentSkillSyncService(
            new AgentSkillSource(), installer, new HttpClient(handler), NullLogger<AgentSkillSyncService>.Instance);

        var act = () => service.RefreshOnceAsync("test", CancellationToken.None);

        await act.Should().NotThrowAsync();
        Directory.Exists(installer.ClaudeSkillDir).Should().BeFalse();
        (await installer.GetCachedShaAsync(CancellationToken.None)).Should().BeNull();
    }

    private sealed class TempHome : IDisposable
    {
        public string Path { get; }
        public TempHome()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "corterm-sync-home-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path);
        }
        public void Dispose()
        {
            try { if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true); } catch { }
        }
    }
}
