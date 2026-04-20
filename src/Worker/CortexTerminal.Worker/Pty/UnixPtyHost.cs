using System.Diagnostics;
using System.Runtime.CompilerServices;

namespace CortexTerminal.Worker.Pty;

public sealed class UnixPtyHost : IPtyHost
{
    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        var shell = Environment.GetEnvironmentVariable("SHELL") ?? "/bin/sh";
        var psi = new ProcessStartInfo(shell)
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            Environment =
            {
                ["TERM"] = "xterm-256color",
                ["COLUMNS"] = columns.ToString(),
                ["LINES"] = rows.ToString()
            }
        };

        var process = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start shell process.");
        return Task.FromResult<IPtyProcess>(new UnixPtyProcess(process));
    }
}

internal sealed class UnixPtyProcess(Process process) : IPtyProcess
{
    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        var stream = process.StandardOutput.BaseStream;
        int bytesRead;
        while ((bytesRead = await stream.ReadAsync(buffer, cancellationToken)) > 0)
        {
            var chunk = new byte[bytesRead];
            Buffer.BlockCopy(buffer, 0, chunk, 0, bytesRead);
            yield return chunk;
        }
    }

    public async IAsyncEnumerable<byte[]> ReadStderrAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        var stream = process.StandardError.BaseStream;
        int bytesRead;
        while ((bytesRead = await stream.ReadAsync(buffer, cancellationToken)) > 0)
        {
            var chunk = new byte[bytesRead];
            Buffer.BlockCopy(buffer, 0, chunk, 0, bytesRead);
            yield return chunk;
        }
    }

    public async Task WriteAsync(byte[] payload, CancellationToken cancellationToken)
    {
        await process.StandardInput.BaseStream.WriteAsync(payload, cancellationToken);
        await process.StandardInput.BaseStream.FlushAsync(cancellationToken);
    }

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        // Real PTY resize requires ioctl - in Phase 1 with Process, this is a no-op
        return Task.CompletedTask;
    }

    public async Task<int> WaitForExitAsync(CancellationToken cancellationToken)
    {
        await process.WaitForExitAsync(cancellationToken);
        return process.ExitCode;
    }

    public ValueTask DisposeAsync()
    {
        if (!process.HasExited)
        {
            process.Kill(entireProcessTree: true);
        }
        process.Dispose();
        return ValueTask.CompletedTask;
    }
}
