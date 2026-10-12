using System.Collections.Concurrent;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Workspaces;

/// <summary>打洞角色：worker 或 client（手机）。</summary>
public static class PunchRole
{
    public const string Worker = "worker";
    public const string Client = "client";
}

/// <summary>对方的公网映射端点。</summary>
public sealed record PunchPeerInfo(string Role, string Endpoint);

/// <summary>注册结果：ready=true 表示双方都已到场（Peer 为对方端点）。</summary>
public sealed record PunchRendezvousResult(bool Ready, PunchPeerInfo? Peer, DateTimeOffset ExpiresAtUtc);

/// <summary>Worker 锚点注册结果：HasClient=客户端已到场并附带传输信封。</summary>
public sealed record WorkerAnchorResult(bool HasClient, PunchPeerInfo? Client, string? TransferId, string? RelayToken, DateTimeOffset ExpiresAtUtc);

/// <summary>
/// UDP 打洞的中介名册：一次传输的两端各自上报自己经 STUN 得到的公网映射端点，
/// Gateway 互换给对方。不参与实际打洞（两端对发探包），条目 TTL 到期作废。
/// </summary>
public sealed class PunchRendezvous(TimeProvider timeProvider)
{
    private sealed class PunchEntry
    {
        public PunchPeerInfo? Worker;
        public PunchPeerInfo? Client;
        public DateTimeOffset ExpiresAtUtc;
    }

    /// <summary>
    /// Worker 常驻锚点条目（key=workerId）：worker online 时开始以 2s 周期续约，
    /// 保持 STUN 映射端点可被客户端即时取用；客户端到场时附带 transferId+relayToken
    /// 信封，worker 下一次续约即取走并打洞。条目由 worker 续约驱动过期（30s），
    /// 客户端信封另有 15s 新鲜度（客户端可能早已离开）。
    /// </summary>
    private sealed class WorkerAnchorEntry
    {
        public PunchPeerInfo? Worker;
        public PunchPeerInfo? Client;
        public string? TransferId;
        public string? RelayToken;
        public DateTimeOffset ClientRegisteredAtUtc;
        public DateTimeOffset ExpiresAtUtc;
    }

    private readonly ConcurrentDictionary<string, PunchEntry> _entries = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, WorkerAnchorEntry> _anchors = new(StringComparer.Ordinal);

    /// <summary>单次打洞窗口。到期后条目作废（客户端自动回落 Relay）。</summary>
    public const int WindowSeconds = 60;

    /// <summary>Worker 锚点条目寿命；worker 以 2s 周期续约，远小于该值。</summary>
    public const int AnchorTtlSeconds = 30;

    /// <summary>客户端信封的新鲜度上限（超过视为客户端已离开，anchor 忽略）。</summary>
    public const int AnchorClientFreshSeconds = 15;

    /// <summary>上报本端端点并查询对方。role 必须是 worker/client；重复上报刷新条目。</summary>
    public PunchRendezvousResult Register(string transferId, string role, string endpoint)
    {
        if (role != PunchRole.Worker && role != PunchRole.Client)
        {
            throw new ArgumentException("role must be worker or client", nameof(role));
        }
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            throw new ArgumentException("endpoint is required", nameof(endpoint));
        }

        var now = timeProvider.GetUtcNow();
        var entry = _entries.AddOrUpdate(
            transferId,
            _ => new PunchEntry { ExpiresAtUtc = now.AddSeconds(WindowSeconds) },
            (_, existing) => existing);
        if (entry.ExpiresAtUtc < now)
        {
            entry = new PunchEntry { ExpiresAtUtc = now.AddSeconds(WindowSeconds) };
            _entries[transferId] = entry;
        }

        if (role == PunchRole.Worker)
        {
            entry.Worker = new PunchPeerInfo(role, endpoint);
        }
        else
        {
            entry.Client = new PunchPeerInfo(role, endpoint);
        }

        var peer = role == PunchRole.Worker ? entry.Client : entry.Worker;
        return new PunchRendezvousResult(peer is not null, peer, entry.ExpiresAtUtc);
    }

    /// <summary>Worker 锚点是否在线（30s 内有续约）——离线时客户端可立即放弃 p2p 回落 Relay。</summary>
    public bool HasLiveAnchor(string workerId)
    {
        return _anchors.TryGetValue(workerId, out var entry) && entry.ExpiresAtUtc >= timeProvider.GetUtcNow();
    }

    /// <summary>
    /// Worker 锚点续约：登记/刷新 worker 的公网映射端点，返回已到场的客户端信封
    /// （端点 + transferId + relayToken）。条目 30s 无续约即作废。
    /// </summary>
    public WorkerAnchorResult RegisterAnchor(string workerId, string endpoint)
    {
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            throw new ArgumentException("endpoint is required", nameof(endpoint));
        }

        var now = timeProvider.GetUtcNow();
        var entry = _anchors.AddOrUpdate(
            workerId,
            _ => new WorkerAnchorEntry { ExpiresAtUtc = now.AddSeconds(AnchorTtlSeconds) },
            (_, existing) => existing);
        if (entry.ExpiresAtUtc < now)
        {
            // 过期重开：worker 端点换新，客户端信封也一并作废
            entry = new WorkerAnchorEntry { ExpiresAtUtc = now.AddSeconds(AnchorTtlSeconds) };
            _anchors[workerId] = entry;
        }
        entry.Worker = new PunchPeerInfo(PunchRole.Worker, endpoint);

        var clientFresh = entry.Client is not null
            && now <= entry.ClientRegisteredAtUtc.AddSeconds(AnchorClientFreshSeconds);
        return new WorkerAnchorResult(
            clientFresh,
            clientFresh ? entry.Client : null,
            clientFresh ? entry.TransferId : null,
            clientFresh ? entry.RelayToken : null,
            entry.ExpiresAtUtc);
    }

    /// <summary>
    /// 客户端到场：登记端点并留下 transfer 信封（worker 下一次续约取走）。worker
    /// 锚点不存在/已过期 → Ready=false（客户端立即回落 Relay，不创建空条目）。
    /// </summary>
    public WorkerAnchorResult RegisterAnchorClient(
        string workerId, string endpoint, string transferId, string relayToken)
    {
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            throw new ArgumentException("endpoint is required", nameof(endpoint));
        }
        if (string.IsNullOrWhiteSpace(transferId) || string.IsNullOrWhiteSpace(relayToken))
        {
            throw new ArgumentException("transferId and relayToken are required");
        }

        var now = timeProvider.GetUtcNow();
        if (!_anchors.TryGetValue(workerId, out var entry) || entry.ExpiresAtUtc < now)
        {
            return new WorkerAnchorResult(false, null, null, null, now);
        }
        entry.Client = new PunchPeerInfo(PunchRole.Client, endpoint);
        entry.TransferId = transferId;
        entry.RelayToken = relayToken;
        entry.ClientRegisteredAtUtc = now;
        return new WorkerAnchorResult(
            entry.Worker is not null, entry.Worker, transferId, relayToken, entry.ExpiresAtUtc);
    }
}
