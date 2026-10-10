using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using CortexTerminal.Worker.P2P;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Worker.Tests.P2P;

/// <summary>基于既有 socket 的 STUN 重载：打洞必须同一 socket。</summary>
public sealed class StunSocketOverloadTests
{
    [Fact]
    public async Task DiscoverAsync_OverExistingSocket_ReturnsMappedEndpointAndKeepsSocketUsable()
    {
        using var fakeStun = new UdpClient(AddressFamily.InterNetwork);
        fakeStun.Client.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        var stunPort = ((IPEndPoint)fakeStun.Client.LocalEndPoint!).Port;

        _ = Task.Run(async () =>
        {
            while (true)
            {
                var received = await fakeStun.ReceiveAsync();
                if (received.Buffer.Length != 20)
                {
                    continue;
                }
                var txid = received.Buffer[8..20];
                var remote = (IPEndPoint)received.RemoteEndPoint;
                fakeStun.Send(BuildXorMappedResponse(txid, remote.Address, (ushort)remote.Port), remote);
            }
        });

        using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        socket.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        var boundPort = ((IPEndPoint)socket.LocalEndPoint!).Port;

        var result = await StunClient.DiscoverAsync(
            socket, new IPEndPoint(IPAddress.Loopback, stunPort),
            RandomNumberGenerator.GetBytes(12), TimeSpan.FromSeconds(5), CancellationToken.None);

        result.Mapped.Address.Should().Be(IPAddress.Loopback);
        result.Mapped.Port.Should().Be(boundPort); // 同一 socket，端口未变
        socket.IsBound.Should().BeTrue();          // socket 归调用方所有，未被关闭
    }

    private static byte[] BuildXorMappedResponse(byte[] txid, IPAddress address, ushort port)
    {
        var magic = new byte[] { 0x21, 0x12, 0xA4, 0x42 };
        var addr = address.GetAddressBytes();
        var response = new byte[32];
        response[0] = 0x01;
        response[1] = 0x01; // Binding Success Response
        response[3] = 0x0C;
        magic.CopyTo(response, 4);
        txid.CopyTo(response, 8);
        response[21] = 0x20;
        response[23] = 0x08;
        response[25] = 0x01;
        response[26] = (byte)((port >> 8) ^ 0x21);
        response[27] = (byte)((port & 0xFF) ^ 0x12);
        for (var i = 0; i < 4; i++)
        {
            response[28 + i] = (byte)(addr[i] ^ magic[i]);
        }
        return response;
    }
}

/// <summary>规格 §7 loopback 集成：两个本机 socket 互发探包 → 打通 → 完整 PUT/GET 传输。</summary>
public sealed class PunchLoopbackIntegrationTests : IDisposable
{
    private readonly string _root;

    public PunchLoopbackIntegrationTests()
    {
        _root = Path.Combine(Path.GetTempPath(), $"corterm-p2p-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch (IOException) { }
    }

    /// <summary>一对 socket 互发探包（双方各自生成 txid，依赖 §1.3 任意 txid 规则），返回两端的可靠流。</summary>
    private static async Task<(PunchStream Client, PunchStream Worker)> PunchPairAsync(UdpClient client, UdpClient worker, byte[] key)
    {
        var clientPunch = UdpPunch.PunchAsync(
            client, (IPEndPoint)worker.Client.LocalEndPoint!, RandomNumberGenerator.GetBytes(12),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(20), CancellationToken.None);
        var workerPunch = UdpPunch.PunchAsync(
            worker, (IPEndPoint)client.Client.LocalEndPoint!, RandomNumberGenerator.GetBytes(12),
            TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(20), CancellationToken.None);
        var clientChannel = await clientPunch.WaitAsync(TimeSpan.FromSeconds(10));
        var workerChannel = await workerPunch.WaitAsync(TimeSpan.FromSeconds(10));
        return (PunchStream.OverChannel(clientChannel, key), PunchStream.OverChannel(workerChannel, key));
    }

    [Fact]
    public async Task PunchThenUploadUploadsViaMinimalHttp()
    {
        const string token = "p2p-transfer-token";
        var transferId = Guid.NewGuid().ToString("N");
        var payload = RandomNumberGenerator.GetBytes(300 * 1024); // > 单窗口，多包多 RTT
        var sha = Convert.ToHexString(SHA256.HashData(payload)).ToLowerInvariant();

        var transfers = new RelayTransferService(50L * 1024 * 1024, NullLogger<RelayTransferService>.Instance);
        var ack = await transfers.PrepareFileReceiveAsync(new(
            TransferId: transferId,
            RootDir: _root,
            DirPath: ".",
            Filename: "uploaded.bin",
            SizeBytes: payload.Length,
            Sha256: sha,
            RelayUrl: "http://127.0.0.1:9", // Relay 路径在本测试中无人对端，失败即被认领逻辑取消
            Token: token), CancellationToken.None);
        ack.Success.Should().BeTrue();

        var key = P2PCrypto.DeriveKey(token, transferId);
        using var clientSide = BindLoopback();
        using var workerSide = BindLoopback();
        var (clientStream, workerStream) = await PunchPairAsync(clientSide, workerSide, key);
        // clientStream 与 workerStream 实际共用 workerSide/clientSide 两条打通链路。
        // （两条 PunchAsync 互为对端已各自打通，OverChannel 各用各的 channel。）

        var serve = PunchHttp.ServeAsync(workerStream, transfers, NullLogger.Instance, CancellationToken.None);
        var response = await PunchHttpClient.PutAsync(
            clientStream, transferId, token, payload, CancellationToken.None)
            .WaitAsync(TimeSpan.FromSeconds(30));

        response.Status.Should().Be(200);
        await serve.WaitAsync(TimeSpan.FromSeconds(5));
        File.ReadAllBytes(Path.Combine(_root, "uploaded.bin")).Should().Equal(payload);
    }

    [Fact]
    public async Task PunchThenDownload_StreamsFileBack()
    {
        const string token = "p2p-download-token";
        var transferId = Guid.NewGuid().ToString("N");
        var content = RandomNumberGenerator.GetBytes(200 * 1024);
        var filePath = Path.Combine(_root, "source.bin");
        await File.WriteAllBytesAsync(filePath, content);

        var transfers = new RelayTransferService(50L * 1024 * 1024, NullLogger<RelayTransferService>.Instance);
        var prepare = await transfers.PrepareFileSendAsync(new(
            TransferId: transferId,
            RootDir: _root,
            RelativePath: "source.bin",
            RelayUrl: "http://127.0.0.1:9",
            Token: token), CancellationToken.None);
        prepare.Success.Should().BeTrue();

        var key = P2PCrypto.DeriveKey(token, transferId);
        using var clientSide = BindLoopback();
        using var workerSide = BindLoopback();
        var (clientStream, workerStream) = await PunchPairAsync(clientSide, workerSide, key);
        var serve = PunchHttp.ServeAsync(workerStream, transfers, NullLogger.Instance, CancellationToken.None);
        var response = await PunchHttpClient.GetAsync(clientStream, transferId, token, CancellationToken.None)
            .WaitAsync(TimeSpan.FromSeconds(30));

        response.Status.Should().Be(200);
        response.Body.Should().Equal(content);
        await serve.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task WrongToken_UploadIsRejected401()
    {
        const string token = "real-token";
        var transferId = Guid.NewGuid().ToString("N");
        var transfers = new RelayTransferService(50L * 1024 * 1024, NullLogger<RelayTransferService>.Instance);
        (await transfers.PrepareFileReceiveAsync(new(
            TransferId: transferId, RootDir: _root, DirPath: ".", Filename: "x.bin",
            SizeBytes: 8, Sha256: new string('0', 64), RelayUrl: "http://127.0.0.1:9",
            Token: token), CancellationToken.None)).Success.Should().BeTrue();

        var key = P2PCrypto.DeriveKey(token, transferId);
        using var clientSide = BindLoopback();
        using var workerSide = BindLoopback();
        var (clientStream, workerStream) = await PunchPairAsync(clientSide, workerSide, key);
        var serve = PunchHttp.ServeAsync(workerStream, transfers, NullLogger.Instance, CancellationToken.None);
        var response = await PunchHttpClient.PutAsync(
            clientStream, transferId, "wrong-token", new byte[8], CancellationToken.None)
            .WaitAsync(TimeSpan.FromSeconds(30));

        response.Status.Should().Be(401);
        Encoding.UTF8.GetString(response.Body).Should().Contain("invalid_token");
        await serve.WaitAsync(TimeSpan.FromSeconds(5));
    }

    private static UdpClient BindLoopback()
    {
        var socket = new UdpClient(AddressFamily.InterNetwork);
        socket.Client.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        return socket;
    }
}
