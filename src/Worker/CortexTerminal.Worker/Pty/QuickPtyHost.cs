using Pty.Net;

namespace CortexTerminal.Worker.Pty;

public sealed class QuickPtyHost : IPtyHost
{
    public async Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        EnsureRuntimeSupport();
        var (app, commandLine) = ResolveShell();
        var options = new PtyOptions
        {
            Name = "CortexTerminal.Worker",
            Cols = columns,
            Rows = rows,
            Cwd = Environment.CurrentDirectory,
            App = app,
            CommandLine = commandLine,
            Environment = new Dictionary<string, string>
            {
                ["TERM"] = "xterm-256color",
                ["COLUMNS"] = columns.ToString(),
                ["LINES"] = rows.ToString(),
            },
        };

        try
        {
            var connection = await PtyProvider.SpawnAsync(options, cancellationToken);
            return new QuickPtyProcess(connection);
        }
        catch (Exception exception)
        {
            throw new PtySupportException("pty-start-failed", exception.Message);
        }
    }

    private static void EnsureRuntimeSupport()
    {
        if (OperatingSystem.IsLinux()
            && Environment.GetEnvironmentVariable("DOTNET_EnableWriteXorExecute") != "0")
        {
            throw new PtySupportException(
                "pty-not-supported-on-platform",
                "pty-not-supported-on-platform: DOTNET_EnableWriteXorExecute=0 is required on Linux");
        }
    }

    private static (string App, string[] CommandLine) ResolveShell()
    {
        if (OperatingSystem.IsWindows())
        {
            var shell = Environment.GetEnvironmentVariable("COMSPEC") ?? "powershell.exe";
            return (shell, Array.Empty<string>());
        }

        var shellPath = Environment.GetEnvironmentVariable("SHELL") ?? "/bin/sh";
        return (shellPath, Array.Empty<string>());
    }
}
