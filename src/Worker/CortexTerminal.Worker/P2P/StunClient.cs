using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace CortexTerminal.Worker.P2P;

/// <summary>STUN Binding 结果：NAT 映射后的公网端点。</summary>
public sealed record StunResult(IPEndPoint Mapped, TimeSpan RoundTripTime);

/// <summary>
/// 最小 STUN 客户端（RFC 5389 Binding）：发 20 字节 Binding Request，解析
/// XOR-MAPPED-ADDRESS 得到本 socket 的公网映射。只做 UDP、只支持 IPv4 映射。
/// </summary>
public static class StunClient
{
    public const ushort BindingRequest = 0x0001;
    public const ushort BindingSuccessResponse = 0x0101;
    public const uint MagicCookie = 0x2112A442;
    public const ushort AttrXorMappedAddress = 0x0020;
    public const int HeaderSize = 20;

    /// <summary>构造 Binding Request（20 字节：type+len+magic+12B 随机 txid）。</summary>
    public static byte[] BuildBindingRequest(ReadOnlySpan<byte> transactionId)
    {
        if (transactionId.Length != 12)
        {
            throw new ArgumentException("transaction id must be 12 bytes", nameof(transactionId));
        }
        var packet = new byte[HeaderSize];
        packet[0] = 0x00;
        packet[1] = 0x01; // Binding Request
        packet[2] = 0x00;
        packet[3] = 0x00; // message length
        var magic = BitConverter.GetBytes(MagicCookie);
        if (BitConverter.IsLittleEndian)
        {
            Array.Reverse(magic);
        }
        for (var i = 0; i < 4; i++)
        {
            packet[4 + i] = magic[i];
        }
        for (var i = 0; i < 12; i++)
        {
            packet[8 + i] = transactionId[i];
        }
        return packet;
    }

    /// <summary>
    /// 从 Binding 响应解析 XOR-MAPPED-ADDRESS。返回 false 表示不是该 txid 的成功响应或格式不符。
    /// </summary>
    public static bool TryParseXorMappedAddress(ReadOnlySpan<byte> response, ReadOnlySpan<byte> transactionId, out IPEndPoint mapped)
    {
        mapped = new IPEndPoint(IPAddress.None, 0);
        if (response.Length < HeaderSize) return false;
        var messageType = (ushort)((response[0] << 8) | response[1]);
        if (messageType != BindingSuccessResponse) return false;
        for (var i = 8; i < 20; i++)
        {
            if (response[i] != transactionId[i - 8]) return false;
        }

        var messageLength = (ushort)((response[2] << 8) | response[3]);
        var offset = HeaderSize;
        var end = HeaderSize + messageLength;
        while (offset + 4 <= end && end <= response.Length)
        {
            var attrType = (ushort)((response[offset] << 8) | response[offset + 1]);
            var attrLength = (ushort)((response[offset + 2] << 8) | response[offset + 3]);
            if (attrType != AttrXorMappedAddress)
            {
                offset += 4 + attrLength;
                continue;
            }
            if (attrLength != 8 || offset + 4 + 8 > response.Length) return false;

            var valueStart = offset + 4;
            var family = (ushort)((response[valueStart] << 8) | response[valueStart + 1]);
            if (family != 0x01) return false;

            var xPort = (ushort)(((response[valueStart + 2] << 8) | response[valueStart + 3]) ^ (MagicCookie >> 16));
            var xAddr = new byte[4];
            var magicBytes = BitConverter.GetBytes(MagicCookie);
            if (BitConverter.IsLittleEndian)
            {
                Array.Reverse(magicBytes);
            }
            for (var i = 0; i < 4; i++)
            {
                xAddr[i] = (byte)(response[valueStart + 4 + i] ^ magicBytes[i]);
            }
            mapped = new IPEndPoint(new IPAddress(xAddr), xPort);
            return true;
        }
        return false;
    }

    /// <summary>对本机指定 UDP socket 做 Binding，返回公网映射端点。</summary>
    public static async Task<StunResult> DiscoverAsync(
        string stunServerHost, int stunServerPort, byte[] transactionId, TimeSpan timeout, CancellationToken ct)
    {
        using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        socket.Bind(new IPEndPoint(IPAddress.Any, 0));

        var serverAddresses = await Dns.GetHostAddressesAsync(stunServerHost, ct);
        var server = serverAddresses.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork)
                     ?? throw new InvalidOperationException($"STUN server {stunServerHost} has no IPv4 address");

        var request = BuildBindingRequest(transactionId);
        var started = Stopwatch.GetTimestamp();
        await socket.SendToAsync(request, SocketFlags.None, new IPEndPoint(server, stunServerPort), ct);

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(timeout);

        var buffer = new byte[1024];
        while (true)
        {
            var result = await socket.ReceiveFromAsync(
                buffer, SocketFlags.None, new IPEndPoint(IPAddress.Any, 0), timeoutCts.Token);
            var received = result.ReceivedBytes;
            if (TryParseXorMappedAddress(buffer.AsSpan(0, received), transactionId, out var mapped))
            {
                return new StunResult(mapped, Stopwatch.GetElapsedTime(started));
            }
            // 不是匹配的响应（乱入包）：继续收直到超时
        }
    }
}
