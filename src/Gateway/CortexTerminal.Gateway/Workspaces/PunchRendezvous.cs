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

    private readonly ConcurrentDictionary<string, PunchEntry> _entries = new(StringComparer.Ordinal);

    /// <summary>单次打洞窗口。到期后条目作废（客户端自动回落 Relay）。</summary>
    public const int WindowSeconds = 60;

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
}
