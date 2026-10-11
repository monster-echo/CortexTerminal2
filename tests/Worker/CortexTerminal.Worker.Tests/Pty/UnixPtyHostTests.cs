using System.Text;
using System.Text.RegularExpressions;
using CortexTerminal.Worker.Pty;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Pty;

[Trait("Category", "Integration")]
[Collection("UnixPtyHostIntegration")]
public sealed class UnixPtyHostTests
{
    private static readonly Regex TerminalSizeLineRegex = new(
        @"^(?<rows>\d+)\s+(?<columns>\d+)$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex TerminalEscapeSequenceRegex = new(
        @"(?:\x1B\][^\x07\x1B]*(?:\x07|\x1B\\))|(?:\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]))",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    [Fact]
    public async Task StartAsync_ExecutesRealShellCommands_LsThenPwd()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var tempDirectory = CreateTempDirectory();
        var listedFileName = $"ls-proof-{Guid.NewGuid():N}.txt";
        var listedFilePath = Path.Combine(tempDirectory, listedFileName);

        await File.WriteAllTextAsync(listedFilePath, "pty real command test");

        try
        {
            await WithPosixShellSessionAsync(async (shell, cancellationToken) =>
            {
                var lsOutput = await shell.ExecuteAsync($"cd {ShellQuote(tempDirectory)}; ls -1", cancellationToken);
                var pwdOutput = await shell.ExecuteAsync($"cd {ShellQuote(tempDirectory)}; pwd", cancellationToken);

                NormalizeOutput(lsOutput).Should().Contain(listedFileName);
                NormalizeOutput(pwdOutput).Should().Contain(NormalizeOutput(tempDirectory));
            });
        }
        finally
        {
            DeleteDirectoryIfPresent(tempDirectory);
        }
    }

    [Fact]
    public async Task StartAsync_ExecutesEchoAndCatCommands()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var tempDirectory = CreateTempDirectory();
        var catFilePath = Path.Combine(tempDirectory, "cat-proof.txt");
        await File.WriteAllTextAsync(catFilePath, "first line\nsecond line\n");

        try
        {
            await WithPosixShellSessionAsync(async (shell, cancellationToken) =>
            {
                var echoOutput = await shell.ExecuteAsync("echo real-pty-echo", cancellationToken);
                var catOutput = await shell.ExecuteAsync($"cat {ShellQuote(catFilePath)}", cancellationToken);

                NormalizeOutput(echoOutput).Should().Contain("real-pty-echo");
                NormalizeOutput(catOutput).Should().Contain("first line\nsecond line");
            });
        }
        finally
        {
            DeleteDirectoryIfPresent(tempDirectory);
        }
    }

    [Fact]
    public async Task StartAsync_ExecutesMkdirTouchAndRmCommands()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var tempDirectory = CreateTempDirectory();

        try
        {
            await WithPosixShellSessionAsync(async (shell, cancellationToken) =>
            {
                var createOutput = await shell.ExecuteAsync(
                    $"cd {ShellQuote(tempDirectory)}; mkdir nested && touch nested/item.txt && ls -1 nested",
                    cancellationToken);

                var cleanupOutput = await shell.ExecuteAsync(
                    $"cd {ShellQuote(tempDirectory)}; rm nested/item.txt && rmdir nested && [ ! -e nested ] && echo removed-ok",
                    cancellationToken);

                NormalizeOutput(createOutput).Should().Contain("item.txt");
                NormalizeOutput(cleanupOutput).Should().Contain("removed-ok");
                Directory.Exists(Path.Combine(tempDirectory, "nested")).Should().BeFalse();
            });
        }
        finally
        {
            DeleteDirectoryIfPresent(tempDirectory);
        }
    }

    [Fact]
    public async Task StartAsync_PreservesSequentialCommandOutputOrder()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var first = $"order-first-{Guid.NewGuid():N}";
        var second = $"order-second-{Guid.NewGuid():N}";
        var third = $"order-third-{Guid.NewGuid():N}";

        await WithPosixShellSessionAsync(async (shell, cancellationToken) =>
        {
            var output = NormalizeOutput(await shell.ExecuteAsync(
                $"echo {first}; echo {second}; echo {third}",
                cancellationToken));

            output.IndexOf(first, StringComparison.Ordinal).Should().BeGreaterThanOrEqualTo(0);
            output.IndexOf(second, StringComparison.Ordinal).Should().BeGreaterThan(output.IndexOf(first, StringComparison.Ordinal));
            output.IndexOf(third, StringComparison.Ordinal).Should().BeGreaterThan(output.IndexOf(second, StringComparison.Ordinal));
        });
    }

    [Fact]
    public async Task StartAsync_HandlesLargeOutputReliably()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        await WithPosixShellSessionAsync(async (shell, cancellationToken) =>
        {
            var output = NormalizeOutput(await shell.ExecuteAsync(
                "i=1; while [ $i -le 600 ]; do printf 'line-%03d\\n' \"$i\"; i=$((i+1)); done",
                cancellationToken));

            var lines = output
                .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                .Where(line => line.StartsWith("line-", StringComparison.Ordinal))
                .ToArray();

            lines.Should().HaveCount(600);
            lines[0].Should().Be("line-001");
            lines[299].Should().Be("line-300");
            lines[599].Should().Be("line-600");
        });
    }

    [Fact]
    public async Task StartAsync_ReportsInitialSttySize_AndKeepsRespondingAfterResize()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        await WithPosixShellSessionAsync(async (shell, cancellationToken) =>
        {
            var initialSize = await shell.ReadTerminalSizeAsync(cancellationToken);
            initialSize.Should().Be("40 120");

            await shell.ResizeAsync(132, 43, cancellationToken);

            var resizedSize = ParseTerminalSize(await shell.ReadTerminalSizeAsync(cancellationToken));
            var postResizeOutput = NormalizeOutput(await shell.ExecuteAsync("echo resize-ok", cancellationToken));

            resizedSize.rows.Should().BeGreaterThan(0);
            resizedSize.columns.Should().BeGreaterThan(0);
            postResizeOutput.Should().Contain("resize-ok");
        }, shellPath: ResolveInteractivePosixShell());
    }

    [Fact]
    public async Task ResizeAsync_HandlesMultipleTransitions_AndPreservesCommandExecution()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        await WithPosixShellSessionAsync(async (shell, cancellationToken) =>
        {
            await shell.ResizeAsync(100, 30, cancellationToken);
            var firstResizeSize = ParseTerminalSize(await shell.ReadTerminalSizeAsync(cancellationToken));

            await shell.ResizeAsync(140, 50, cancellationToken);
            var secondResizeSize = ParseTerminalSize(await shell.ReadTerminalSizeAsync(cancellationToken));

            var output = NormalizeOutput(await shell.ExecuteAsync(
                "echo resize-step-one; echo resize-step-two; echo resize-still-alive",
                cancellationToken));

            firstResizeSize.rows.Should().BeGreaterThan(0);
            firstResizeSize.columns.Should().BeGreaterThan(0);
            secondResizeSize.rows.Should().BeGreaterThan(0);
            secondResizeSize.columns.Should().BeGreaterThan(0);
            output.IndexOf("resize-step-one", StringComparison.Ordinal).Should().BeGreaterThanOrEqualTo(0);
            output.IndexOf("resize-step-two", StringComparison.Ordinal).Should().BeGreaterThan(output.IndexOf("resize-step-one", StringComparison.Ordinal));
            output.Should().Contain("resize-still-alive");
        }, columns: 80, rows: 24, shellPath: ResolveInteractivePosixShell());
    }

    [Fact(Timeout = 15000)]
    public async Task StartAsync_LaunchesLocalShell_AndCanBeDisposed()
    {
        var variableName = OperatingSystem.IsWindows() ? "COMSPEC" : "SHELL";
        var previous = Environment.GetEnvironmentVariable(variableName);

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        try
        {
            if (!OperatingSystem.IsWindows())
            {
                Environment.SetEnvironmentVariable("SHELL", "/bin/sh");
            }

            var host = new UnixPtyHost();
            var process = await host.StartAsync(120, 40, cts.Token);

            process.Should().NotBeNull();
            var dispose = async () => await process.DisposeAsync();

            await dispose.Should().NotThrowAsync();
        }
        finally
        {
            Environment.SetEnvironmentVariable(variableName, previous);
        }
    }

    [Fact(Timeout = 15000)]
    public async Task StartAsync_FallsBackToPlatformDefaultShell_WhenEnvironmentVariableMissing()
    {
        var variableName = OperatingSystem.IsWindows() ? "COMSPEC" : "SHELL";
        var previous = Environment.GetEnvironmentVariable(variableName);

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));

        try
        {
            Environment.SetEnvironmentVariable(variableName, null);
            var host = new UnixPtyHost();
            var process = await host.StartAsync(120, 40, cts.Token);

            var dispose = async () => await process.DisposeAsync();

            await dispose.Should().NotThrowAsync();
        }
        finally
        {
            Environment.SetEnvironmentVariable(variableName, previous);
        }
    }

    private static async Task WithPosixShellSessionAsync(
        Func<PosixShellSession, CancellationToken, Task> assertion,
        int columns = 120,
        int rows = 40,
        int timeoutSeconds = 45,
        string? shellPath = null)
    {
        var previousShell = Environment.GetEnvironmentVariable("SHELL");
        PosixShellSession? session = null;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));

        try
        {
            Environment.SetEnvironmentVariable("SHELL", shellPath ?? "/bin/sh");

            var host = new UnixPtyHost();
            var process = await host.StartAsync(columns, rows, cts.Token);
            session = await PosixShellSession.StartAsync(process, cts.Token);

            await assertion(session, cts.Token);
            await session.ExitAsync(cts.Token);
        }
        finally
        {
            if (session is not null)
            {
                await session.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
            }

            Environment.SetEnvironmentVariable("SHELL", previousShell);
        }
    }

    private static Task SendCommandAsync(IPtyProcess process, string command, CancellationToken cancellationToken)
        => process.WriteAsync(Encoding.UTF8.GetBytes(command + "\r"), cancellationToken);

    private static string ShellQuote(string text)
        => $"'{text.Replace("'", "'\\''")}'";

    private static string ResolveInteractivePosixShell()
        => File.Exists("/bin/zsh") ? "/bin/zsh" : "/bin/sh";

    private static string MarkerCommand(string marker)
        => $"printf '{ToPosixOctalEscapes(marker)}\\n'";

    private static string ToPosixOctalEscapes(string text)
        => string.Concat(text.Select(character => $"\\{Convert.ToString(character, 8)!.PadLeft(3, '0')}"));

    private static string NormalizeOutput(string text)
        => text.Replace("\r", string.Empty).Trim();

    private static (int rows, int columns) ParseTerminalSize(string output)
    {
        var cleanedLines = StripTerminalNoise(output)
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var sizeLine = cleanedLines.LastOrDefault(line => TerminalSizeLineRegex.IsMatch(line));

        sizeLine.Should().NotBeNullOrEmpty($"expected a terminal size line in '{output}'");

        var match = TerminalSizeLineRegex.Match(sizeLine!);
        return (
            int.Parse(match.Groups["rows"].Value),
            int.Parse(match.Groups["columns"].Value));
    }

    private static string StripTerminalNoise(string output)
    {
        var withoutEscapeSequences = TerminalEscapeSequenceRegex.Replace(output, string.Empty)
            .Replace("\r", string.Empty);

        return new string(withoutEscapeSequences
            .Where(character => character == '\n' || character == '\t' || !char.IsControl(character))
            .ToArray());
    }

    private static string CreateTempDirectory()
    {
        var tempDirectory = Path.Combine(Path.GetTempPath(), $"cortexterminal-pty-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);
        return tempDirectory;
    }

    private static void DeleteDirectoryIfPresent(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }

    private sealed class PosixShellSession : IAsyncDisposable
    {
        private readonly IPtyProcess _process;
        private readonly LiveShellOutput _output;

        private PosixShellSession(IPtyProcess process, LiveShellOutput output)
        {
            _process = process;
            _output = output;
        }

        public static async Task<PosixShellSession> StartAsync(IPtyProcess process, CancellationToken cancellationToken)
        {
            var output = await LiveShellOutput.StartAsync(process, cancellationToken);
            var session = new PosixShellSession(process, output);

            TaskCanceledException? lastCanceled = null;
            for (var attempt = 0; attempt < 4; attempt++)
            {
                try
                {
                    await SendCommandAsync(process, string.Empty, cancellationToken);
                    _ = await session.ExecuteAsync(":", cancellationToken);
                    return session;
                }
                catch (TaskCanceledException exception) when (!cancellationToken.IsCancellationRequested && attempt < 3)
                {
                    lastCanceled = exception;
                    await Task.Delay(200, cancellationToken);
                }
            }

            throw lastCanceled ?? new TaskCanceledException("Timed out waiting for the shell to become ready.");
        }

        public async Task<string> ExecuteAsync(string command, CancellationToken cancellationToken)
        {
            var startMarker = $"__CORTEX_BEGIN_{Guid.NewGuid():N}__";
            var endMarker = $"__CORTEX_END_{Guid.NewGuid():N}__";

            using var commandCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            commandCts.CancelAfter(TimeSpan.FromSeconds(10));

            await SendCommandAsync(
                _process,
                $"{MarkerCommand(startMarker)}; {command}; {MarkerCommand(endMarker)}",
                commandCts.Token);

            return await _output.WaitForSliceAsync(startMarker, endMarker, commandCts.Token);
        }

        public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
            => _process.ResizeAsync(columns, rows, cancellationToken);

        public async Task<string> ReadTerminalSizeAsync(CancellationToken cancellationToken)
        {
            TaskCanceledException? lastCanceled = null;

            for (var attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    return NormalizeOutput(await ExecuteAsync("stty size", cancellationToken));
                }
                catch (TaskCanceledException exception) when (!cancellationToken.IsCancellationRequested && attempt < 2)
                {
                    lastCanceled = exception;
                    await Task.Delay(100, cancellationToken);
                }
            }

            throw lastCanceled ?? new TaskCanceledException("Timed out reading terminal size.");
        }

        public async Task<int> ExitAsync(CancellationToken cancellationToken)
        {
            await SendCommandAsync(_process, "exit", cancellationToken);
            var exitCode = await _process.WaitForExitAsync(cancellationToken);
            await _output.WaitForCompletionAsync(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(3));
            return exitCode;
        }

        public ValueTask DisposeAsync()
            => _process.DisposeAsync();
    }

    private sealed class LiveShellOutput
    {
        private readonly Task _pumpTask;
        private readonly object _gate = new();
        private readonly StringBuilder _buffer = new();

        private LiveShellOutput(IPtyProcess process, CancellationToken cancellationToken)
        {
            _pumpTask = Task.Run(async () =>
            {
                await foreach (var chunk in process.ReadStdoutAsync(CancellationToken.None))
                {
                    var text = Encoding.UTF8.GetString(chunk).Replace("\r", string.Empty);
                    lock (_gate)
                    {
                        _buffer.Append(text);
                    }
                }
            }, cancellationToken);
        }

        public static Task<LiveShellOutput> StartAsync(IPtyProcess process, CancellationToken cancellationToken)
            => Task.FromResult(new LiveShellOutput(process, cancellationToken));

        public async Task<string> WaitForSliceAsync(string startMarker, string endMarker, CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                string snapshot;
                lock (_gate)
                {
                    snapshot = _buffer.ToString();
                }

                var startIndex = snapshot.IndexOf(startMarker, StringComparison.Ordinal);
                if (startIndex >= 0)
                {
                    var contentStart = startIndex + startMarker.Length;
                    var endIndex = snapshot.IndexOf(endMarker, contentStart, StringComparison.Ordinal);
                    if (endIndex >= 0)
                    {
                        return snapshot.Substring(contentStart, endIndex - contentStart);
                    }
                }

                await Task.Delay(50, cancellationToken);
            }

            throw new TaskCanceledException(
                $"Timed out waiting for markers '{startMarker}' and '{endMarker}'. Output tail: {GetSnapshotTail()}");
        }

        public Task WaitForCompletionAsync(CancellationToken cancellationToken)
            => _pumpTask.WaitAsync(cancellationToken);

        public string GetSnapshotTail(int maximumCharacters = 500)
        {
            lock (_gate)
            {
                var snapshot = _buffer.ToString();
                return snapshot.Length <= maximumCharacters
                    ? snapshot
                    : snapshot[^maximumCharacters..];
            }
        }
    }
}

[CollectionDefinition("UnixPtyHostIntegration", DisableParallelization = true)]
public sealed class UnixPtyHostIntegrationCollection;
