using Porta.Pty;

namespace CortexTerminal.Worker.Pty;

public sealed class UnixPtyHost : IPtyHost
{
    public async Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        var (app, commandLine) = ResolveShellLaunch();
        var options = new PtyOptions
        {
            Name = "CortexTerminal.Worker",
            Cols = columns,
            Rows = rows,
            Cwd = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            App = app,
            CommandLine = commandLine,
            Environment = new Dictionary<string, string>
            {
                ["TERM"] = "xterm-256color",
                ["COLUMNS"] = columns.ToString(),
                ["LINES"] = rows.ToString(),
                ["LANG"] = OperatingSystem.IsWindows() ? string.Empty : "en_US.UTF-8",
            },
        };

        try
        {
            var connection = await PtyProvider.SpawnAsync(options, cancellationToken);
            return new UnixPtyProcess(connection);
        }
        catch (PtySupportException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new PtySupportException("pty-start-failed", exception.Message);
        }
    }

    private static (string App, string[] CommandLine) ResolveShellLaunch()
    {
        if (OperatingSystem.IsWindows())
        {
            // Prefer PowerShell (pwsh) over cmd.exe
            var pwsh = FindOnPath("pwsh.exe");
            if (pwsh is not null)
                return (pwsh, Array.Empty<string>());

            var ps = FindOnPath("powershell.exe");
            if (ps is not null)
                return (ps, Array.Empty<string>());

            var comspec = Environment.GetEnvironmentVariable("COMSPEC");
            if (!string.IsNullOrWhiteSpace(comspec))
                return (comspec, Array.Empty<string>());

            return ("cmd.exe", Array.Empty<string>());
        }

        var shellPath = Environment.GetEnvironmentVariable("SHELL");
        if (!string.IsNullOrWhiteSpace(shellPath))
        {
            return (shellPath, Array.Empty<string>());
        }

        if (OperatingSystem.IsMacOS())
        {
            return ("/bin/zsh", Array.Empty<string>());
        }

        if (OperatingSystem.IsLinux())
        {
            return ("/bin/bash", Array.Empty<string>());
        }

        return ("/bin/sh", Array.Empty<string>());
    }

    private static string? FindOnPath(string fileName)
    {
        var pathExt = Environment.GetEnvironmentVariable("PATH") ?? "";
        var separator = OperatingSystem.IsWindows() ? ';' : ':';
        foreach (var dir in pathExt.Split(separator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var full = Path.Combine(dir, fileName);
                if (File.Exists(full))
                    return full;
            }
            catch
            {
                // skip inaccessible directories
            }
        }
        return null;
    }
}
