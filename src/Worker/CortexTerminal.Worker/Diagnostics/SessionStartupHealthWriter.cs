using System.Text.Json.Nodes;
using CortexTerminal.Worker.Runtime;

namespace CortexTerminal.Worker.Diagnostics;

/// <summary>Local desktop warning feed; contains no terminal text or credentials.</summary>
internal static class SessionStartupHealthWriter
{
    internal static async Task RunAsync(Func<WorkerSessionRuntime[]> sessions, CancellationToken cancellationToken)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var path = Path.Combine(home, ".corterm", "session-startup-health.json");
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(2));
        try
        {
            do
            {
                var now = DateTimeOffset.UtcNow;
                var alerts = new JsonArray();
                foreach (var session in sessions())
                {
                    if (session.HasOutput || now - session.StartedAtUtc < TimeSpan.FromSeconds(12)) continue;
                    alerts.Add((JsonNode)new JsonObject
                    {
                        ["sessionId"] = session.SessionId,
                        ["directory"] = session.Directory,
                        ["waitingSeconds"] = (long)(now - session.StartedAtUtc).TotalSeconds,
                    });
                }
                var document = new JsonObject
                {
                    ["pid"] = Environment.ProcessId,
                    ["updatedAt"] = now.ToUnixTimeSeconds(),
                    ["sessions"] = alerts,
                };
                var stage = path + "." + Guid.NewGuid().ToString("N");
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                    var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write };
                    if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
                    await using (var file = new FileStream(stage, options))
                    await using (var writer = new StreamWriter(file))
                        await writer.WriteAsync(document.ToJsonString());
                    File.Move(stage, path, overwrite: true);
                }
                catch (IOException) { /* A desktop warning must never stop a terminal. */ }
                catch (UnauthorizedAccessException) { }
                finally { try { File.Delete(stage); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
            } while (await timer.WaitForNextTickAsync(cancellationToken));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
    }
}
