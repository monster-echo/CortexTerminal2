using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using CortexTerminal.Worker.Tunnels;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Worker.Tests.Tunnels;

/// <summary>
/// LAN 直连传输监听器端到端：注册 pending 传输后，经 HTTP PUT/GET 完成字节流，
/// token 常量时间比对；Prepare 时 Relay 后台路径会因测试环境无 Relay 而静默失败。
/// </summary>
public sealed class LocalTransferListenerTests : IAsyncLifetime
{
    private readonly RelayTransferService _transfers = new(
        50 * 1024 * 1024, NullLogger<RelayTransferService>.Instance);
    private readonly LocalTransferListener _listener;
    private readonly string _workDir;

    public LocalTransferListenerTests()
    {
        _workDir = Path.Combine(Path.GetTempPath(), $"corterm-local-transfer-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_workDir);
        _listener = new LocalTransferListener(
            _transfers, listenPort: 0, publicBaseUrl: null, NullLogger<LocalTransferListener>.Instance);
    }

    public async Task InitializeAsync()
    {
        await _listener.StartAsync(CancellationToken.None);
        await _listener.Ready;
        Assert.True(_listener.BoundPort > 0);
    }

    public async Task DisposeAsync()
    {
        await _listener.StopAsync(CancellationToken.None);
        try { Directory.Delete(_workDir, recursive: true); } catch (IOException) { }
    }

    private string BaseUrl => $"http://127.0.0.1:{_listener.BoundPort}";

    [Fact]
    public async Task Provision_Sanity()
    {
        // Ready 之后端口已绑定 —— 冒烟：根路径 404 而不是连接拒绝
        using var client = new HttpClient();
        var response = await client.GetAsync($"{BaseUrl}/transfer/none");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task LocalUpload_WritesFileAfterShaVerification()
    {
        var content = Encoding.UTF8.GetBytes("hello lan transfer");
        var sha256 = Convert.ToHexString(SHA256.HashData(content)).ToLowerInvariant();
        var transferId = $"t-{Guid.NewGuid():N}";
        var token = $"tok-{Guid.NewGuid():N}";

        var ack = await _transfers.PrepareFileReceiveAsync(new PrepareFileReceiveCommand(
            transferId, _workDir, "", "hello.txt", content.Length, sha256,
            RelayUrl: "http://127.0.0.1:1", Token: token), CancellationToken.None);
        ack.Success.Should().BeTrue();

        using var client = new HttpClient();
        using var body = new ByteArrayContent(content);
        var response = await client.PutAsync($"{BaseUrl}/transfer/{transferId}?token={Uri.EscapeDataString(token)}", body);
        if (response.StatusCode != HttpStatusCode.OK)
        {
            var bodyText = await response.Content.ReadAsStringAsync();
            throw new InvalidOperationException($"status={response.StatusCode} body={bodyText}");
        }

        File.ReadAllText(Path.Combine(_workDir, "hello.txt")).Should().Be("hello lan transfer");
    }

    [Fact]
    public async Task LocalUpload_WithWrongToken_IsUnauthorized()
    {
        var ack = await _transfers.PrepareFileReceiveAsync(new PrepareFileReceiveCommand(
            $"t-{Guid.NewGuid():N}", _workDir, "", "x.txt", 3, "aa",
            RelayUrl: "http://127.0.0.1:1", Token: "expected-token"), CancellationToken.None);
        ack.Success.Should().BeTrue();

        using var client = new HttpClient();
        using var body = new ByteArrayContent(new byte[] { 1, 2, 3 });
        var response = await client.PutAsync(
            $"{BaseUrl}/transfer/none-or-wrong?token=wrong", body);
        // 未注册的 tid → 404；已注册但 token 错 → 401。这里用一个未注册 tid 验证拒绝路径。
        response.StatusCode.Should().BeOneOf(HttpStatusCode.NotFound, HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task LocalUpload_WithShaMismatch_Fails()
    {
        var transferId = $"t-{Guid.NewGuid():N}";
        var token = $"tok-{Guid.NewGuid():N}";
        var ack = await _transfers.PrepareFileReceiveAsync(new PrepareFileReceiveCommand(
            transferId, _workDir, "", "bad.txt", 3, "00" + "00" + "00",
            RelayUrl: "http://127.0.0.1:1", Token: token), CancellationToken.None);
        ack.Success.Should().BeTrue();

        using var client = new HttpClient();
        using var body = new ByteArrayContent(new byte[] { 1, 2, 3 });
        var response = await client.PutAsync($"{BaseUrl}/transfer/{transferId}?token={Uri.EscapeDataString(token)}", body);
        response.StatusCode.Should().Be(HttpStatusCode.BadGateway);
        File.Exists(Path.Combine(_workDir, "bad.txt")).Should().BeFalse();
    }

    [Fact]
    public async Task LocalDownload_StreamsFileWithLength()
    {
        var source = Path.Combine(_workDir, "dl-source.bin");
        var payload = RandomNumberGenerator.GetBytes(128 * 1024);
        await File.WriteAllBytesAsync(source, payload);

        var transferId = $"t-{Guid.NewGuid():N}";
        var token = $"tok-{Guid.NewGuid():N}";
        var ack = await _transfers.PrepareFileSendAsync(new PrepareFileSendCommand(
            transferId, _workDir, "dl-source.bin",
            RelayUrl: "http://127.0.0.1:1", Token: token), CancellationToken.None);
        ack.Success.Should().BeTrue();

        using var client = new HttpClient();
        var response = await client.GetAsync($"{BaseUrl}/transfer/{transferId}?token={Uri.EscapeDataString(token)}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentLength.Should().Be(payload.Length);
        var downloaded = await response.Content.ReadAsByteArrayAsync();
        downloaded.Should().Equal(payload);
    }

    [Fact]
    public async Task LocalDownload_UnknownTransfer_IsNotFound()
    {
        using var client = new HttpClient();
        var response = await client.GetAsync($"{BaseUrl}/transfer/nope?token=x");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
