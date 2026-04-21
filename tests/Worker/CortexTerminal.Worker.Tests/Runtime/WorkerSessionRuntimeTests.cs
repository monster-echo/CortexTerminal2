using System.Runtime.CompilerServices;
using System.Threading.Channels;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Runtime;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Runtime;

public sealed class WorkerSessionRuntimeTests
{
    [Fact]
    public async Task StartAsync_PumpsStdoutStderrAndExitToGateway()
    {
        var process = new ControlledPtyProcess();
        var gateway = new FakeWorkerGatewayClient();
        var runtime = new WorkerSessionRuntime("sess-1", new ControlledPtyHost(process), gateway, NullLogger<WorkerSessionRuntime>.Instance);

        await runtime.StartAsync(120, 40, CancellationToken.None);
        await process.EmitStdoutAsync([0x6F, 0x6B]);
        await process.EmitStderrAsync([0x62, 0x61, 0x64]);
        await process.CompleteAsync(7);
        await gateway.WaitForExitAsync("sess-1");

        gateway.StdoutChunks.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new TerminalChunk("sess-1", "stdout", [0x6F, 0x6B]));
        gateway.StderrChunks.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new TerminalChunk("sess-1", "stderr", [0x62, 0x61, 0x64]));
        gateway.ExitedEvents.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new SessionExited("sess-1", 7, "process-exited"));
    }

    [Fact]
    public async Task WriteResizeAndClose_AreForwardedAndCloseIsIdempotent()
    {
        var process = new ControlledPtyProcess();
        var gateway = new FakeWorkerGatewayClient();
        var runtime = new WorkerSessionRuntime("sess-1", new ControlledPtyHost(process), gateway, NullLogger<WorkerSessionRuntime>.Instance);

        await runtime.StartAsync(120, 40, CancellationToken.None);
        await runtime.WriteInputAsync([0x03], CancellationToken.None);
        await runtime.ResizeAsync(140, 50, CancellationToken.None);
        await runtime.CloseAsync(CancellationToken.None);
        await runtime.CloseAsync(CancellationToken.None);

        process.WrittenPayloads.Should().ContainSingle().Which.Should().Equal([0x03]);
        process.ResizeRequests.Should().ContainSingle().Which.Should().Be((140, 50));
        process.DisposeCount.Should().Be(1);
    }
}

internal sealed class ControlledPtyHost(ControlledPtyProcess process) : IPtyHost
{
    public List<(int Columns, int Rows)> StartRequests { get; } = [];

    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        StartRequests.Add((columns, rows));
        return Task.FromResult<IPtyProcess>(process);
    }
}

internal sealed class QueuePtyHost(params ControlledPtyProcess[] processes) : IPtyHost
{
    private readonly Queue<ControlledPtyProcess> _processes = new(processes);

    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        if (_processes.Count == 0)
        {
            throw new InvalidOperationException("No PTY processes queued.");
        }

        return Task.FromResult<IPtyProcess>(_processes.Dequeue());
    }
}

internal sealed class ControlledPtyProcess : IPtyProcess
{
    private readonly Channel<byte[]> _stdout = Channel.CreateUnbounded<byte[]>();
    private readonly Channel<byte[]> _stderr = Channel.CreateUnbounded<byte[]>();
    private readonly TaskCompletionSource<int> _exitCode = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public List<byte[]> WrittenPayloads { get; } = [];
    public List<(int Columns, int Rows)> ResizeRequests { get; } = [];
    public int DisposeCount { get; private set; }

    public async Task EmitStdoutAsync(byte[] payload)
        => await _stdout.Writer.WriteAsync(payload);

    public async Task EmitStderrAsync(byte[] payload)
        => await _stderr.Writer.WriteAsync(payload);

    public Task CompleteAsync(int exitCode)
    {
        _stdout.Writer.TryComplete();
        _stderr.Writer.TryComplete();
        _exitCode.TrySetResult(exitCode);
        return Task.CompletedTask;
    }

    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await foreach (var payload in _stdout.Reader.ReadAllAsync(cancellationToken))
        {
            yield return payload;
        }
    }

    public async IAsyncEnumerable<byte[]> ReadStderrAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await foreach (var payload in _stderr.Reader.ReadAllAsync(cancellationToken))
        {
            yield return payload;
        }
    }

    public Task WriteAsync(byte[] payload, CancellationToken cancellationToken)
    {
        WrittenPayloads.Add(payload.ToArray());
        return Task.CompletedTask;
    }

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        ResizeRequests.Add((columns, rows));
        return Task.CompletedTask;
    }

    public async Task<int> WaitForExitAsync(CancellationToken cancellationToken)
    {
        using var _ = cancellationToken.Register(() => _exitCode.TrySetCanceled(cancellationToken));
        return await _exitCode.Task;
    }

    public ValueTask DisposeAsync()
    {
        DisposeCount++;
        _stdout.Writer.TryComplete();
        _stderr.Writer.TryComplete();
        return ValueTask.CompletedTask;
    }
}
