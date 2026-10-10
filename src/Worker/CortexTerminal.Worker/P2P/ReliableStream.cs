using System.Buffers.Binary;
using System.Diagnostics;
using System.Net.Sockets;

namespace CortexTerminal.Worker.P2P;

/// <summary>流帧类型（规格 §3.3）。</summary>
public static class P2PFrame
{
    public const byte Data = 0x00;
    public const byte Ack = 0x01;
    public const byte Fin = 0x02;
    public const byte Rst = 0x03;

    public const int HeaderSize = 7; // 1B type + 4B seq + 2B len
    public const int MaxPayload = 1150; // MTU 1200 - 7B 帧头 - GCM/nonce/版本开销
    public const int MaxFrameSize = HeaderSize + MaxPayload;

    public static void WriteHeader(Span<byte> dst, byte type, uint seq, ushort payloadLength)
    {
        dst[0] = type;
        BinaryPrimitives.WriteUInt32BigEndian(dst[1..], seq);
        BinaryPrimitives.WriteUInt16BigEndian(dst[5..], payloadLength);
    }

    public static bool TryParse(ReadOnlySpan<byte> frame, out byte type, out uint seq, out ReadOnlySpan<byte> payload)
    {
        type = 0;
        seq = 0;
        payload = default;
        if (frame.Length < HeaderSize)
        {
            return false;
        }
        type = frame[0];
        seq = BinaryPrimitives.ReadUInt32BigEndian(frame[1..]);
        var len = BinaryPrimitives.ReadUInt16BigEndian(frame[5..]);
        if (frame.Length < HeaderSize + len)
        {
            return false;
        }
        payload = frame.Slice(HeaderSize, len);
        return true;
    }

    /// <summary>构造 ACK 帧：payload = [4B cum][4B runCount][runs × (4B start,4B end)]（closed-run 缺失区间）。</summary>
    public static byte[] BuildAck(uint cumulativeAck, IReadOnlyList<(uint Start, uint End)> missingRuns)
    {
        var frame = new byte[HeaderSize + 8 + missingRuns.Count * 8];
        WriteHeader(frame, Ack, 0, (ushort)(8 + missingRuns.Count * 8));
        BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(HeaderSize), cumulativeAck);
        BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(HeaderSize + 4), (uint)missingRuns.Count);
        for (var i = 0; i < missingRuns.Count; i++)
        {
            BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(HeaderSize + 8 + i * 8), missingRuns[i].Start);
            BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(HeaderSize + 12 + i * 8), missingRuns[i].End);
        }
        return frame;
    }

    public static (uint CumulativeAck, List<(uint Start, uint End)> MissingRuns) ParseAck(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 8)
        {
            throw new InvalidDataException("ACK frame payload truncated");
        }
        var cum = BinaryPrimitives.ReadUInt32BigEndian(payload);
        var runCount = BinaryPrimitives.ReadUInt32BigEndian(payload[4..]);
        if (payload.Length < 8 + runCount * 8)
        {
            throw new InvalidDataException("ACK sack runs truncated");
        }
        var runs = new List<(uint, uint)>((int)runCount);
        for (var i = 0u; i < runCount; i++)
        {
            var start = BinaryPrimitives.ReadUInt32BigEndian(payload[(int)(8 + i * 8)..]);
            var end = BinaryPrimitives.ReadUInt32BigEndian(payload[(int)(12 + i * 8)..]);
            runs.Add((start, end));
        }
        return (cum, runs);
    }
}

public sealed class PunchStreamOptions
{
    /// <summary>接收/发送窗口（包数，规格 §3.3：32）。</summary>
    public int WindowPackets { get; init; } = 32;
    /// <summary>初始 RTO（规格：300ms，指数退避）。</summary>
    public TimeSpan InitialRto { get; init; } = TimeSpan.FromMilliseconds(300);
    public TimeSpan MaxRto { get; init; } = TimeSpan.FromSeconds(2);
    /// <summary>冗余 ACK 数达到该值触发快速重传（规格：3）。</summary>
    public int FastRetransmitDupAcks { get; init; } = 3;
    /// <summary>单包最大重传次数，超过即 RST 断开（链路不可用）。</summary>
    public int MaxRetransmits { get; init; } = 30;
    public TimeSpan RetransmitScanInterval { get; init; } = TimeSpan.FromMilliseconds(25);
}

/// <summary>
/// 打洞 UDP 之上的加密可靠字节流（规格 §3.2/§3.3）：
/// - 数据报 = P2PCipher.Encrypt(帧)；本类只处理帧（明文）层，加解密在 DecodeDatagram/发送处。
/// - ARQ：窗口 32 包，RTO 指数退避，3 冗余 ACK 快速重传，累积 ACK + SACK（closed-run 缺失区间）。
/// - FIN 半关闭（对端读侧 EOF）；RST 异常中止（对端 Read/Write 抛 IOException）。
/// </summary>
public sealed class PunchStream : Stream
{
    private readonly P2PCipher _cipher;
    private readonly Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> _sendDatagram;
    private readonly PunchStreamOptions _options;
    private readonly CancellationTokenSource _cts = new();

    private readonly object _sync = new();

    private sealed class InFlight
    {
        public required byte Type { get; init; }
        public uint Seq { get; set; }
        public required byte[] Payload { get; init; }
        public DateTimeOffset LastSend { get; set; }
        public TimeSpan Rto { get; set; }
        public int Retries { get; set; }
    }

    // 发送侧
    private readonly Dictionary<uint, InFlight> _inFlight = new();
    private uint _nextSeq;
    private bool _hasCumAck;
    private uint _lastCumAck;
    private int _dupAckCount;
    private bool _fastRtxPending;
    private uint _fastRtxSeq;
    private TaskCompletionSource? _windowSignal;
    private readonly TaskCompletionSource _written = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private bool _finQueued;

    // 接收侧
    private readonly SortedDictionary<uint, byte[]> _recvPending = new();
    private readonly Queue<byte[]> _recvQueue = new();
    private byte[]? _activeChunk;
    private int _activeOffset;
    private readonly SemaphoreSlim _recvAvailable = new(0);
    private uint _recvExpected;
    private uint? _remoteFinSeq;
    private bool _eofReached;

    private Exception? _failure;
    private readonly Task _retransmitLoop;

    public PunchStream(
        P2PCipher cipher,
        Func<ReadOnlyMemory<byte>, CancellationToken, ValueTask> sendDatagram,
        PunchStreamOptions? options = null)
    {
        _cipher = cipher;
        _sendDatagram = sendDatagram;
        _options = options ?? new PunchStreamOptions();
        _retransmitLoop = Task.Run(() => RetransmitLoopAsync(_cts.Token));
    }

    /// <summary>在打洞成功的 UDP 通道上建立加密可靠流（数据收发同 socket）。</summary>
    public static PunchStream OverChannel(PunchChannel channel, byte[] key, PunchStreamOptions? options = null)
    {
        var stream = new PunchStream(
            new P2PCipher(key),
            async (datagram, ct) => await channel.Socket.SendAsync(datagram, channel.Remote, ct),
            options);
        _ = Task.Run(() => ReceiveLoopAsync(channel, stream));
        return stream;
    }

    private static async Task ReceiveLoopAsync(PunchChannel channel, PunchStream stream)
    {
        var buffer = new byte[P2PCrypto.MaxDatagramSize];
        var plaintext = new byte[P2PFrame.MaxFrameSize];
        while (!stream._cts.IsCancellationRequested)
        {
            UdpReceiveResult received;
            try
            {
                received = await channel.Socket.ReceiveAsync(stream._cts.Token);
            }
            catch (SocketException ex) when (ex.SocketErrorCode is SocketError.ConnectionReset or SocketError.NetworkReset)
            {
                // Windows：对端不可达 ICMP → “暂时没有回包”，继续收。
                continue;
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (SocketException)
            {
                // socket 已释放/不可用：终结本端流。
                stream.Abort(new IOException("UDP socket became unusable"));
                return;
            }
            if (UdpPunch.IsProbe(received.Buffer))
            {
                continue; // 打洞后迟到的探包不是数据
            }
            stream.DecodeDatagram(received.Buffer, plaintext);
        }
    }

    /// <summary>解密并处理一个数据报；解密失败（tag 不过）按规格丢弃。</summary>
    public void DecodeDatagram(ReadOnlySpan<byte> datagram, Span<byte> plaintextScratch)
    {
        if (!_cipher.TryDecrypt(datagram, plaintextScratch, out var written))
        {
            return;
        }
        HandleFrame(plaintextScratch[..written].ToArray());
    }

    // ── 接收 ──────────────────────────────────────────────

    private void HandleFrame(byte[] frame)
    {
        if (!P2PFrame.TryParse(frame, out var type, out var seq, out var payload))
        {
            return; // 残包丢弃
        }

        List<byte[]>? acks = null;
        lock (_sync)
        {
            switch (type)
            {
                case P2PFrame.Data:
                    OnDataLocked(seq, payload);
                    (acks ??= []).Add(BuildAckLocked());
                    break;
                case P2PFrame.Ack:
                    OnAckLocked(seq, payload);
                    break;
                case P2PFrame.Fin:
                    if (_remoteFinSeq is null || seq < _remoteFinSeq)
                    {
                        _remoteFinSeq = seq;
                    }
                    OnDataLocked(seq, payload);
                    (acks ??= []).Add(BuildAckLocked());
                    break;
                case P2PFrame.Rst:
                    _failure = new IOException("connection reset by peer");
                    WakeAllLocked();
                    return;
            }
        }

        foreach (var ack in acks ?? [])
        {
            _ = SendEncryptedAsync(ack, CancellationToken.None);
        }
    }

    private void OnDataLocked(uint seq, ReadOnlySpan<byte> payload)
    {
        if (seq < _recvExpected || seq >= _recvExpected + (uint)_options.WindowPackets)
        {
            // 已确认过的重复包，或超出接收窗口（等重传）——都不缓存
            return;
        }
        _recvPending[seq] = payload.ToArray();
        // 按序上交 + 吸收连续的乱序缓存（FIN 以空 payload 入缓存，吞掉即 EOF）
        while (_recvPending.Remove(_recvExpected, out var next))
        {
            if (next.Length > 0)
            {
                _recvQueue.Enqueue(next);
                _recvAvailable.Release();
            }
            _recvExpected++;
            if (_remoteFinSeq == _recvExpected - 1)
            {
                _eofReached = true;
            }
        }
    }

    private byte[] BuildAckLocked()
    {
        var runs = new List<(uint Start, uint End)>();
        var i = _recvExpected;
        using var enumerator = _recvPending.GetEnumerator();
        while (enumerator.MoveNext())
        {
            var (seq, _) = enumerator.Current;
            if (seq == i)
            {
                i++;
                continue;
            }
            runs.Add((i, seq)); // [i, seq) 缺失（closed-run：不含 end）
            i = seq + 1;
        }
        return P2PFrame.BuildAck(_recvExpected, runs);
    }

    private void OnAckLocked(uint seq, ReadOnlySpan<byte> payload)
    {
        _ = seq;
        var (cum, runs) = P2PFrame.ParseAck(payload);
        List<InFlight>? rtx = null;

        // 累积 ACK：< cum 的全部确认
        var acked = new List<uint>();
        // 缺失区间只覆盖到接收方已缓存的最大 seq；最后一个缺失区间之上的 seq
        // 状态未知（可能已收到也可能丢了），只能留给累积 ACK 或 RTO，不能当已收到删除。
        var sackTop = runs.Count > 0 ? runs[^1].End : cum;
        foreach (var (packetSeq, _) in _inFlight)
        {
            if (packetSeq < cum)
            {
                acked.Add(packetSeq);
                continue;
            }
            if (packetSeq >= sackTop)
            {
                continue;
            }
            // SACK（closed-run 缺失区间）：sackTop 之下不在任何缺失区间内的 seq 即已收到
            var missing = false;
            foreach (var (start, end) in runs)
            {
                if (packetSeq >= start && packetSeq < end)
                {
                    missing = true;
                    break;
                }
            }
            if (!missing)
            {
                acked.Add(packetSeq);
            }
        }
        foreach (var s in acked)
        {
            _inFlight.Remove(s);
        }

        // 冗余 ACK 计数与快速重传
        if (_hasCumAck && cum == _lastCumAck)
        {
            _dupAckCount++;
        }
        else
        {
            _hasCumAck = true;
            _lastCumAck = cum;
            _dupAckCount = 0;
            _fastRtxPending = false;
        }
        if (_dupAckCount >= _options.FastRetransmitDupAcks
            && _inFlight.TryGetValue(cum, out var lost)
            && (!_fastRtxPending || _fastRtxSeq != cum))
        {
            _fastRtxPending = true;
            _fastRtxSeq = cum;
            _dupAckCount = 0;
            lost.LastSend = DateTimeOffset.UtcNow;
            (rtx ??= []).Add(lost);
        }

        if (_inFlight.Count < _options.WindowPackets)
        {
            _windowSignal?.TrySetResult();
            _windowSignal = null;
        }
        if (_finQueued && _inFlight.Count == 0)
        {
            _written.TrySetResult();
        }
        foreach (var packet in rtx ?? [])
        {
            _ = SendEncryptedAsync(BuildFrame(packet), CancellationToken.None);
        }
    }

    // ── 发送 ──────────────────────────────────────────────

    private byte[] BuildFrame(InFlight packet)
    {
        var frame = new byte[P2PFrame.HeaderSize + packet.Payload.Length];
        P2PFrame.WriteHeader(frame, packet.Type, packet.Seq, (ushort)packet.Payload.Length);
        packet.Payload.CopyTo(frame, P2PFrame.HeaderSize);
        return frame;
    }

    private async ValueTask SendEncryptedAsync(byte[] frame, CancellationToken ct)
    {
        var datagram = _cipher.Encrypt(frame);
        await _sendDatagram(datagram, ct);
    }

    public override async ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var chunk = Math.Min(P2PFrame.MaxPayload, buffer.Length - offset);
            var packet = new InFlight
            {
                Type = P2PFrame.Data,
                Seq = 0,
                Payload = buffer.Span.Slice(offset, chunk).ToArray(),
            };

            while (true)
            {
                Task? wait = null;
                lock (_sync)
                {
                    if (_failure is not null)
                    {
                        throw new IOException("punch stream failed", _failure);
                    }
                    if (_inFlight.Count < _options.WindowPackets)
                    {
                        packet.Seq = _nextSeq++;
                        packet.LastSend = DateTimeOffset.UtcNow;
                        packet.Rto = _options.InitialRto;
                        _inFlight[packet.Seq] = packet;
                    }
                    else
                    {
                        wait = (_windowSignal ??= new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)).Task;
                    }
                }
                if (wait is null)
                {
                    break;
                }
                await wait.WaitAsync(cancellationToken);
            }

            await SendEncryptedAsync(BuildFrame(packet), cancellationToken);
            offset += chunk;
        }
    }

    /// <summary>本端写完：发送 FIN（对端读侧读到 EOF）。FIN 走与 DATA 相同的 ARQ。</summary>
    public void CompleteWriting()
    {
        InFlight fin;
        lock (_sync)
        {
            if (_finQueued)
            {
                return;
            }
            _finQueued = true;
            fin = new InFlight
            {
                Type = P2PFrame.Fin,
                Seq = _nextSeq++,
                Payload = [],
                LastSend = DateTimeOffset.UtcNow,
                Rto = _options.InitialRto,
            };
            _inFlight[fin.Seq] = fin;
            if (_inFlight.Count == 0)
            {
                _written.TrySetResult();
            }
        }
        _ = SendEncryptedAsync(BuildFrame(fin), CancellationToken.None);
    }

    /// <summary>FIN 已被对端确认（写侧完成）。</summary>
    public Task Written => _written.Task;

    private async Task RetransmitLoopAsync(CancellationToken ct)
    {
        var scan = _options.RetransmitScanInterval;
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(scan, ct);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            List<InFlight>? due = null;
            var now = DateTimeOffset.UtcNow;
            lock (_sync)
            {
                foreach (var packet in _inFlight.Values)
                {
                    if (now - packet.LastSend < packet.Rto)
                    {
                        continue;
                    }
                    packet.Retries++;
                    if (packet.Retries > _options.MaxRetransmits)
                    {
                        _failure = new IOException(
                            $"packet seq {packet.Seq} exceeded {_options.MaxRetransmits} retransmits; link dead");
                        WakeAllLocked();
                        return;
                    }
                    packet.Rto = TimeSpan.FromMilliseconds(
                        Math.Min(_options.MaxRto.TotalMilliseconds, packet.Rto.TotalMilliseconds * 2));
                    packet.LastSend = now;
                    (due ??= []).Add(packet);
                }
            }
            foreach (var packet in due ?? [])
            {
                _ = SendEncryptedAsync(BuildFrame(packet), CancellationToken.None);
            }
        }
    }

    /// <summary>内部错误终结：日志由调用方负责，本端所有等待者失败。</summary>
    public void Abort(Exception failure)
    {
        lock (_sync)
        {
            _failure ??= failure;
            WakeAllLocked();
        }
    }

    private void WakeAllLocked()
    {
        _windowSignal?.TrySetException(new IOException("punch stream failed", _failure!));
        _windowSignal = null;
        _written.TrySetException(new IOException("punch stream failed", _failure!));
        _recvAvailable.Release();
    }

    // ── Stream 读取面 ─────────────────────────────────────

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        if (buffer.Length == 0)
        {
            return 0;
        }
        while (true)
        {
            int n;
            lock (_sync)
            {
                if (_failure is not null)
                {
                    throw new IOException("punch stream failed", _failure);
                }
                if (_activeChunk is null || _activeOffset == _activeChunk.Length)
                {
                    _activeChunk = _recvQueue.Count > 0 ? _recvQueue.Dequeue() : null;
                    _activeOffset = 0;
                }
                if (_activeChunk is null)
                {
                    if (_eofReached)
                    {
                        return 0;
                    }
                    n = -1; // 无数据：等待信号后重查
                }
                else
                {
                    n = Math.Min(_activeChunk.Length - _activeOffset, buffer.Length);
                    _activeChunk.AsSpan(_activeOffset, n).CopyTo(buffer.Span);
                    _activeOffset += n;
                }
            }
            if (n >= 0)
            {
                return n;
            }
            try
            {
                await _recvAvailable.WaitAsync(cancellationToken);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                // WakeAll 释放信号量以唤醒本循环 → 重新检查 _failure
            }
        }
    }

    // ── Stream 必需成员 ───────────────────────────────────

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => true;
    public override long Length => throw new NotSupportedException();
    public override long Position
    {
        get => throw new NotSupportedException();
        set => throw new NotSupportedException();
    }
    public override void Flush() { }
    public override int Read(byte[] buffer, int offset, int count)
        => ReadAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();
    public override void Write(byte[] buffer, int offset, int count)
        => WriteAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
}
