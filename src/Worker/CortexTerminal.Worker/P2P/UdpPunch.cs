using System.Net;
using System.Net.Sockets;
using System.Diagnostics;

namespace CortexTerminal.Worker.P2P;

/// <summary>打洞成功后的 UDP 通道：socket 已与对端建立映射，Remote 是实测回包源。</summary>
public sealed class PunchChannel : IDisposable
{
    internal PunchChannel(UdpClient socket, IPEndPoint remote)
    {
        Socket = socket;
        Remote = remote;
    }

    public UdpClient Socket { get; }
    public IPEndPoint Remote { get; }

    public void Dispose() => Socket.Dispose();
}

/// <summary>打洞探包：payload = "PT" + 12B transactionId。对端按 txid 识别（NAT 可能改写源端口）。</summary>
public static class UdpPunch
{
    public const int ProbeLength = 2 + 12;

    public static byte[] BuildProbe(ReadOnlySpan<byte> transactionId)
    {
        if (transactionId.Length != 12)
        {
            throw new ArgumentException("transaction id must be 12 bytes", nameof(transactionId));
        }
        var probe = new byte[ProbeLength];
        probe[0] = 0x50; // 'P'
        probe[1] = 0x54; // 'T'
        transactionId.CopyTo(probe.AsSpan(2));
        return probe;
    }

    public static bool IsProbe(ReadOnlySpan<byte> datagram, ReadOnlySpan<byte> transactionId)
    {
        if (datagram.Length != ProbeLength || transactionId.Length != 12) return false;
        if (datagram[0] != 0x50 || datagram[1] != 0x54) return false;
        return datagram.Slice(2).SequenceEqual(transactionId);
    }

    /// <summary>
    /// 打洞窗口：向 peerHint 以固定间隔发探包，同时收包；收到 txid 匹配的探包即打通。
    /// peerHint 来自 Gateway 中介（对方 STUN 映射端点），实际来源可能不同，以回包源为准。
    /// </summary>
    public static async Task<PunchChannel> PunchAsync(
        UdpClient socket,
        IPEndPoint peerHint,
        byte[] transactionId,
        TimeSpan window,
        TimeSpan probeInterval,
        CancellationToken ct)
    {
        var probe = BuildProbe(transactionId);
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(ct);
        lifetime.CancelAfter(window);

        using var sendCts = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        var sendTask = SendProbesAsync(socket, peerHint, probe, probeInterval, sendCts.Token);

        try
        {
            while (true)
            {
                UdpReceiveResult result;
                try
                {
                    result = await socket.ReceiveAsync(lifetime.Token);
                }
                catch (SocketException ex)
                    when (!ct.IsCancellationRequested
                          && ex.SocketErrorCode is SocketError.ConnectionReset
                              or SocketError.IcmpUnreachablePortUnreachable
                              or SocketError.NetworkReset)
                {
                    // Windows：对端不可达的 ICMP 会让未完成的 ReceiveAsync 抛
                    // ConnectionReset/PortUnreachable——这是“没有回包”，不是失败。
                    // 吞掉继续等，直到打洞窗口耗尽由统一转为 TimeoutException。
                    continue;
                }
                if (!IsProbe(result.Buffer, transactionId))
                {
                    continue;
                }
                sendCts.Cancel();
                return new PunchChannel(socket, result.RemoteEndPoint);
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new TimeoutException($"UDP punch window elapsed after {window.TotalSeconds}s");
        }
        finally
        {
            sendCts.Cancel();
            try { await sendTask; } catch (OperationCanceledException) { }
        }
    }

    private static async Task SendProbesAsync(
        UdpClient socket, IPEndPoint peer, byte[] probe, TimeSpan interval, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            await socket.SendAsync(probe, peer, token);
            await Task.Delay(interval, token);
        }
    }
}
