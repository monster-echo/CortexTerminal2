using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using CortexTerminal.Worker.P2P;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.P2P;

public sealed class ReliableStreamTests
{
    /// <summary>
    /// 可控"空口"：两端 PunchStream 之间的数据报经过
    /// 丢包率 / 随机延迟（造成乱序）管道。确定性种子便于回归。
    /// </summary>
    private sealed class LossyAir
    {
        private readonly Random _random;
        private readonly double _lossRate;
        private readonly int _maxDelayMs;

        public LossyAir(int seed, double lossRate, int maxDelayMs)
        {
            _random = new Random(seed);
            _lossRate = lossRate;
            _maxDelayMs = maxDelayMs;
        }

        public PunchStream A { get; private set; } = null!;
        public PunchStream B { get; private set; } = null!;

        public (PunchStream A, PunchStream B) Build()
        {
            // 两端共享同一会话密钥（规格 §3.1）
            var key = RandomNumberGenerator.GetBytes(32);
            A = new PunchStream(
                new P2PCipher(key),
                (datagram, _) => Deliver(datagram, B));
            B = new PunchStream(
                new P2PCipher(key),
                (datagram, _) => Deliver(datagram, A));
            return (A, B);
        }

        private async ValueTask Deliver(ReadOnlyMemory<byte> datagram, PunchStream to)
        {
            if (_random.NextDouble() < _lossRate)
            {
                return; // 丢包，等 RTO/快速重传
            }
            var delay = _random.Next(_maxDelayMs + 1);
            if (delay > 0)
            {
                await Task.Delay(delay); // 延迟即乱序
            }
            to.DecodeDatagram(datagram.Span, new byte[P2PFrame.MaxFrameSize]);
        }
    }

    private static (PunchStream A, PunchStream B) BuildPerfect() => new LossyAir(1, 0.0, 0).Build();

    [Fact]
    public async Task InOrder_LargePayload_ArrivesIntact()
    {
        var (a, b) = BuildPerfect();
        var payload = RandomNumberGenerator.GetBytes(64 * 1024 + 123); // 多窗口多包

        var write = a.WriteAsync(payload).AsTask();
        var received = new byte[payload.Length];
        var read = 0;
        while (read < received.Length)
        {
            var n = await b.ReadAsync(received.AsMemory(read));
            n.Should().BePositive();
            read += n;
        }
        await write;
        a.CompleteWriting();
        (await b.ReadAsync(new byte[1])).Should().Be(0); // EOF after FIN
        received.Should().Equal(payload);
    }

    [Fact]
    public async Task LossAndReorder_AllDataRecovered()
    {
        // 20% 丢包 + 最多 20ms 乱序：RTO 300ms 退避覆盖重传
        var air = new LossyAir(seed: 7, lossRate: 0.2, maxDelayMs: 20);
        var (a, b) = air.Build();
        var payload = RandomNumberGenerator.GetBytes(48 * 1024);

        var write = a.WriteAsync(payload).AsTask();
        var received = new byte[payload.Length];
        var read = 0;
        while (read < received.Length)
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            var n = await b.ReadAsync(received.AsMemory(read), timeout.Token);
            n.Should().BePositive();
            read += n;
        }
        await write;
        received.Should().Equal(payload);
    }

    [Fact]
    public async Task Reader_WaitsWithoutSpinning_WhenIdle()
    {
        var (a, b) = BuildPerfect();
        var readTask = b.ReadAsync(new byte[100]).AsTask();
        await Task.Delay(100);
        readTask.IsCompleted.Should().BeFalse();

        await a.WriteAsync("ping"u8.ToArray());
        var n = await readTask.WaitAsync(TimeSpan.FromSeconds(5));
        n.Should().Be(4);
    }

    [Fact]
    public async Task Fin_CompletesAfterAllDataDelivered()
    {
        var (a, b) = BuildPerfect();
        await a.WriteAsync(new byte[] { 1, 2, 3 });
        a.CompleteWriting();
        await a.Written.WaitAsync(TimeSpan.FromSeconds(5));

        var buffer = new byte[16];
        (await b.ReadAsync(buffer)).Should().Be(3);
        (await b.ReadAsync(buffer)).Should().Be(0); // EOF
    }

    [Fact]
    public async Task Bidirectional_Streams_AreIndependent()
    {
        var (a, b) = BuildPerfect();
        var tx = a.WriteAsync(Enumerable.Repeat((byte)0xAA, 4096).ToArray()).AsTask();
        var rx = b.WriteAsync(Enumerable.Repeat((byte)0xBB, 4096).ToArray()).AsTask();

        var gotA = await ReadExactlyAsync(b, 4096);
        var gotB = await ReadExactlyAsync(a, 4096);
        await Task.WhenAll(tx, rx);
        gotA.Should().OnlyContain(x => x == 0xAA);
        gotB.Should().OnlyContain(x => x == 0xBB);
    }

    private static async Task<byte[]> ReadExactlyAsync(Stream stream, int count)
    {
        var buffer = new byte[count];
        var read = 0;
        while (read < count)
        {
            read += await stream.ReadAsync(buffer.AsMemory(read));
        }
        return buffer;
    }
}
