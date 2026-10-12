using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Security.Cryptography;
using System.Text.Json;
using CortexTerminal.Worker.RemoteFiles;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.P2P;

/// <summary>
/// P2P 打洞传输编排（规格 §1）：prepare 应答后后台启动 ——
/// 新建 UDP socket → 同一 socket 上 STUN Binding → 每 2s 向 Gateway
/// POST /api/transfers/{tid}/punch（role=worker，X-Corterm-Transfer-Token）→
/// 拿到 peerEndpoint 后 UdpPunch（任意 txid 探包，50ms 间隔，10s 窗口）→
/// 打通后进入加密可靠流上的精简 HTTP 服务循环。
/// 生命周期：打洞窗口（60s rendezvous TTL）/服务空闲上限到点、传输被其他通道认领
/// （认领 CAS 会让 p2p 上的请求得 409）、或服务停机 —— 均取消循环并释放 socket。
/// 打洞失败不是错误（客户端自动回落下一端点），只记信息日志。
/// </summary>
public sealed class PunchTransferService : IDisposable
{
    private static readonly TimeSpan RegisterInterval = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan RegisterWindow = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan PunchWindow = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan PunchProbeInterval = TimeSpan.FromMilliseconds(50);
    private static readonly TimeSpan StunTimeout = TimeSpan.FromSeconds(3);
    /// <summary>会话总寿命上限：punch 完成后若客户端一直不来，socket 不会永久悬挂。</summary>
    private static readonly TimeSpan SessionLifetime = TimeSpan.FromSeconds(120);

    private readonly string _gatewayBaseUrl;
    private readonly string _stunHost;
    private readonly int _stunPort;
    private readonly RelayTransferService _transfers;
    private readonly ILogger<PunchTransferService> _logger;
    private readonly CancellationTokenSource _shutdown = new();
    private readonly SemaphoreSlim _anchorStarted = new(1, 1);
    private volatile string? _anchorWorkerId;
    private volatile string? _anchorToken;
    private volatile string? _anchorEndpoint;
    private Task? _anchorLoop;

    public PunchTransferService(
        string gatewayBaseUrl,
        string stunServer,
        RelayTransferService transfers,
        ILogger<PunchTransferService> logger)
    {
        _gatewayBaseUrl = gatewayBaseUrl.TrimEnd('/');
        (_stunHost, _stunPort) = ParseStunServer(stunServer);
        _transfers = transfers;
        _logger = logger;
        transfers.TransferPrepared += OnTransferPrepared;
    }

    /// <summary>
    /// P2P 打洞锚点：worker online（收到 IssueRelayToken）即启动 —— 专用 UDP socket
    /// 上完成 STUN 后，以 key=workerId 每 2s 向 gateway 续约注册，保持 NAT 映射常驻
    /// 可达。客户端发起传输时经同一 rendezvous 立刻取到本端端点并发起探包，本循环
    /// 在下一次续约里取到 (transferId, relayToken) 信封后直接对客户端端点打洞并进入
    /// 精简 HTTP 服务。per-transfer 的加密/PunchHttp/认领逻辑与旧路径完全一致。
    /// </summary>
    public void StartAnchor(string workerId, string workerRelayToken)
    {
        _anchorWorkerId = workerId;
        _anchorToken = workerRelayToken;
        if (_anchorLoop != null)
        {
            return;
        }
        if (!_anchorStarted.Wait(0))
        {
            return;
        }
        _anchorLoop = Task.Run(() => AnchorLoopAsync(_shutdown.Token));
    }

    private async Task AnchorLoopAsync(CancellationToken ct)
    {
        var workerId = _anchorWorkerId ?? "";
        _logger.LogInformation("P2P anchor started for worker {WorkerId}.", workerId);
        using var socket = new UdpClient(AddressFamily.InterNetwork);
        var stunEp = await ResolveStunServerAsync(ct);
        var needStun = true;
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var token = _anchorToken;
                if (string.IsNullOrEmpty(token))
                {
                    await Task.Delay(RegisterInterval, ct);
                    continue;
                }
                if (needStun)
                {
                    var txid = RandomNumberGenerator.GetBytes(12);
                    var mapped = (await StunClient.DiscoverAsync(socket.Client, stunEp, txid, StunTimeout, ct)).Mapped;
                    _logger.LogInformation("P2P anchor {WorkerId}: socket {Local} mapped to {Mapped}.",
                        workerId, socket.Client.LocalEndPoint, mapped);
                    _anchorEndpoint = mapped.ToString();
                    needStun = false;
                }
                if (string.IsNullOrEmpty(_anchorEndpoint))
                {
                    needStun = true;
                    continue;
                }

                var offer = await AnchorRegisterAsync(workerId, token, _anchorEndpoint, ct);
                if (offer.Ready && !string.IsNullOrEmpty(offer.TransferId) && !string.IsNullOrEmpty(offer.RelayToken))
                {
                    _logger.LogInformation("P2P anchor {WorkerId}: client attached, punching {Peer} for {TransferId}.",
                        workerId, offer.PeerEndpoint, offer.TransferId);
                    var peer = ParseIPEndPoint(offer.PeerEndpoint!);
                    var channel = await UdpPunch.PunchAsync(
                        socket, peer, RandomNumberGenerator.GetBytes(12), PunchWindow, PunchProbeInterval, ct);
                    using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(ct);
                    lifetime.CancelAfter(SessionLifetime);
                    var key = P2PCrypto.DeriveKey(offer.RelayToken, offer.TransferId);
                    using var stream = PunchStream.OverChannel(channel, key);
                    await PunchHttp.ServeAsync(stream, _transfers, _logger, lifetime.Token);
                    _logger.LogInformation("P2P anchor {WorkerId}: p2p session closed, re-anchoring.", workerId);
                    // 服务过一次会话后 NAT 映射可能已轮换，重新 STUN。
                    needStun = true;
                }
                else
                {
                    await Task.Delay(RegisterInterval, ct);
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                break;
            }
            catch (TimeoutException ex)
            {
                _logger.LogInformation("P2P anchor {WorkerId}: punch failed ({Message}), waiting for next client.", workerId, ex.Message);
            }
            catch (Exception ex)
            {
                // 含续约 401（令牌到期）：IssueRelayToken 会在重注册时带来新令牌。
                _logger.LogWarning(ex, "P2P anchor {WorkerId}: iteration failed.", workerId);
                needStun = true;
                try { await Task.Delay(RegisterInterval * 5, ct); } catch (OperationCanceledException) { break; }
            }
        }
        _logger.LogInformation("P2P anchor {WorkerId} stopped.", workerId);
    }

    private async Task<AnchorOffer> AnchorRegisterAsync(string workerId, string token, string endpoint, CancellationToken ct)
    {
        using var http = new HttpClient();
        using var request = new HttpRequestMessage(
            HttpMethod.Post, $"{_gatewayBaseUrl}/api/p2p/workers/{Uri.EscapeDataString(workerId)}/punch")
        {
            Content = new ByteArrayContent(JsonSerializer.SerializeToUtf8Bytes(
                new PunchRegisterBody(PunchRoleWorker, endpoint))),
        };
        request.Headers.TryAddWithoutValidation("X-Corterm-Worker-Relay-Token", token);
        using var response = await http.SendAsync(request, ct);
        var payload = await response.Content.ReadAsByteArrayAsync(ct);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"anchor register rejected: HTTP {(int)response.StatusCode} {Encoding.UTF8.GetString(payload)}");
        }
        using var doc = JsonDocument.Parse(payload);
        var ready = doc.RootElement.GetProperty("ready").GetBoolean();
        string? peer = doc.RootElement.TryGetProperty("peerEndpoint", out var peerEl) && peerEl.ValueKind == JsonValueKind.String
            ? peerEl.GetString() : null;
        string? transferId = doc.RootElement.TryGetProperty("transferId", out var tidEl) && tidEl.ValueKind == JsonValueKind.String
            ? tidEl.GetString() : null;
        string? relayToken = doc.RootElement.TryGetProperty("relayToken", out var tokEl) && tokEl.ValueKind == JsonValueKind.String
            ? tokEl.GetString() : null;
        return new AnchorOffer(ready, peer, transferId, relayToken);
    }

    private sealed record AnchorOffer(bool Ready, string? PeerEndpoint, string? TransferId, string? RelayToken);

    private const string PunchRoleWorker = "worker";

    internal static (string Host, int Port) ParseStunServer(string stunServer)
    {
        var sep = stunServer.LastIndexOf(':');
        if (sep <= 0 || !int.TryParse(stunServer[(sep + 1)..], out var port))
        {
            throw new ArgumentException($"invalid P2P:StunServer '{stunServer}', expected host:port", nameof(stunServer));
        }
        return (stunServer[..sep], port);
    }

    private Task OnTransferPrepared(string transferId, string token, bool isReceive)
    {
        _ = Task.Run(() => RunSessionAsync(transferId, token, isReceive, _shutdown.Token));
        return Task.CompletedTask;
    }

    private async Task RunSessionAsync(string transferId, string token, bool isReceive, CancellationToken ct)
    {
        using var socket = new UdpClient(AddressFamily.InterNetwork);
        try
        {
            var txid = RandomNumberGenerator.GetBytes(12);
            var stunEp = await ResolveStunServerAsync(ct);
            var mapped = (await StunClient.DiscoverAsync(socket.Client, stunEp, txid, StunTimeout, ct)).Mapped;
            _logger.LogInformation(
                "P2P transfer {TransferId}: socket {Local} mapped to {Mapped}, registering with gateway.",
                transferId, socket.Client.LocalEndPoint, mapped);

            var peerEndpoint = await RegisterUntilReadyAsync(transferId, token, mapped.ToString(), ct);
            if (peerEndpoint is null)
            {
                _logger.LogInformation(
                    "P2P transfer {TransferId}: rendezvous window elapsed without peer, giving up (client falls back).",
                    transferId);
                return;
            }
            var peer = ParseIPEndPoint(peerEndpoint);

            var channel = await UdpPunch.PunchAsync(
                socket, peer, RandomNumberGenerator.GetBytes(12), PunchWindow, PunchProbeInterval, ct);
            _logger.LogInformation(
                "P2P transfer {TransferId}: punched through to {Peer} from {Local}.",
                transferId, channel.Remote, socket.Client.LocalEndPoint);

            using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(ct);
            lifetime.CancelAfter(SessionLifetime);
            var key = P2PCrypto.DeriveKey(token, transferId);
            using var stream = PunchStream.OverChannel(channel, key);
            await PunchHttp.ServeAsync(stream, _transfers,
                _logger, lifetime.Token);
            _logger.LogInformation("P2P transfer {TransferId}: p2p session closed normally.", transferId);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            // 服务停机或会话寿命到点
        }
        catch (TimeoutException ex)
        {
            // 打洞窗口无回包：协商逻辑落到下一端点，不是错误。
            _logger.LogInformation("P2P transfer {TransferId}: punch failed ({Message}), client falls back.", transferId, ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "P2P transfer {TransferId}: p2p channel failed.", transferId);
        }
    }

    private async Task<IPEndPoint> ResolveStunServerAsync(CancellationToken ct)
    {
        if (IPAddress.TryParse(_stunHost, out var literal))
        {
            return new IPEndPoint(literal, _stunPort);
        }
        var addresses = await Dns.GetHostAddressesAsync(_stunHost, ct);
        var ipv4 = addresses.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork)
                   ?? throw new InvalidOperationException($"STUN server {_stunHost} has no IPv4 address");
        return new IPEndPoint(ipv4, _stunPort);
    }

    /// <summary>每 2s 注册本端端点并查对方；ready 即返回 peerEndpoint，窗口耗尽返回 null。</summary>
    private async Task<string?> RegisterUntilReadyAsync(
        string transferId, string token, string endpoint, CancellationToken ct)
    {
        using var http = new HttpClient();
        using var window = CancellationTokenSource.CreateLinkedTokenSource(ct);
        window.CancelAfter(RegisterWindow);
        var body = JsonSerializer.SerializeToUtf8Bytes(new PunchRegisterBody("worker", endpoint));
        while (true)
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Post, $"{_gatewayBaseUrl}/api/transfers/{transferId}/punch")
            {
                Content = new ByteArrayContent(body),
            };
            request.Headers.TryAddWithoutValidation("X-Corterm-Transfer-Token", token);
            using var response = await http.SendAsync(request, window.Token);
            var payload = await response.Content.ReadAsByteArrayAsync(window.Token);
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(
                    $"punch register rejected: HTTP {(int)response.StatusCode} {Encoding.UTF8.GetString(payload)}");
            }
            using var doc = JsonDocument.Parse(payload);
            var ready = doc.RootElement.GetProperty("ready").GetBoolean();
            if (ready
                && doc.RootElement.TryGetProperty("peerEndpoint", out var peer)
                && peer.ValueKind == JsonValueKind.String)
            {
                return peer.GetString();
            }
            await Task.Delay(RegisterInterval, window.Token);
        }
    }

    private static IPEndPoint ParseIPEndPoint(string text)
    {
        // "ip:port"；IPv6 字面量含多个冒号，取最后一个冒号分割
        var sep = text.LastIndexOf(':');
        if (sep <= 0 || !int.TryParse(text[(sep + 1)..], out var port))
        {
            throw new FormatException($"invalid peer endpoint '{text}'");
        }
        return new IPEndPoint(IPAddress.Parse(text[..sep]), port);
    }

    private sealed record PunchRegisterBody(string Role, string Endpoint);

    public void Dispose()
    {
        _shutdown.Cancel();
    }
}
