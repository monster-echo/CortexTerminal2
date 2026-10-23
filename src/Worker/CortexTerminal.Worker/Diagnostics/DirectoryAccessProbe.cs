using System.Diagnostics;
using System.Text;

namespace CortexTerminal.Worker.Diagnostics;

public sealed record DirectoryAccessResult(string State, string? Detail = null);

/// <summary>Probe the actual directory under the app's privacy attribution. Never read TCC databases.</summary>
public static class DirectoryAccessProbe
{
    public static async Task<DirectoryAccessResult> CheckAsync(string directory, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        // Start in a safe directory, then access the target after exec. A blocked cd/pwd
        // must not block Process.Start itself. The path is an argument, never shell code.
        var start = new ProcessStartInfo("/bin/sh")
        {
            WorkingDirectory = "/private/tmp",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        if (!OperatingSystem.IsMacOS()) start.WorkingDirectory = "/tmp";
        start.ArgumentList.Add("-c");
        start.ArgumentList.Add("cd -- \"$1\" && /bin/pwd -P");
        start.ArgumentList.Add("corterm-directory-check");
        start.ArgumentList.Add(directory);
        start.Environment["LC_ALL"] = "C";
        if (OperatingSystem.IsWindows())
        {
            start.FileName = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            start.WorkingDirectory = Environment.SystemDirectory;
            start.ArgumentList.Clear();
            start.ArgumentList.Add("-NoProfile");
            start.ArgumentList.Add("-NonInteractive");
            start.ArgumentList.Add("-EncodedCommand");
            const string script = """
                try {
                  $p = $env:CORTERM_CHECK_DIRECTORY
                  $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop
                  if (-not $item.PSIsContainer) { exit 2 }
                  Get-ChildItem -LiteralPath $p -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null
                  exit 0
                } catch {
                  [Console]::Error.WriteLine($_.Exception.Message)
                  if ($_.CategoryInfo.Category -eq 'PermissionDenied') { exit 13 }
                  exit 2
                }
                """;
            start.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(script)));
            start.Environment["CORTERM_CHECK_DIRECTORY"] = directory;
        }

        try
        {
            using var process = Process.Start(start);
            if (process is null) return new("unavailable");
            var output = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(OperatingSystem.IsWindows() ? 8 : 3));
            try { await process.WaitForExitAsync(timeout.Token); }
            catch (OperationCanceledException)
            {
                try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
                cancellationToken.ThrowIfCancellationRequested();
                return new("timed-out");
            }
            var detail = (await error).Trim();
            _ = await output;
            if (process.ExitCode == 0) return new("accessible");
            var denied = process.ExitCode == 13 || detail.Contains("Permission denied", StringComparison.OrdinalIgnoreCase)
                || detail.Contains("Operation not permitted", StringComparison.OrdinalIgnoreCase);
            return new(denied ? "permission-denied" : "unavailable", detail.Length > 512 ? detail[..512] : detail);
        }
        catch (UnauthorizedAccessException ex) { return new("permission-denied", ex.Message); }
        catch (System.ComponentModel.Win32Exception ex) { return new("unavailable", ex.Message); }
    }
}
