using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Tunnels;

/// <summary>每 tunnel 固定窗口 QPS 限流。内存计数,单一实例。</summary>
public sealed class TunnelQuota(TunnelOptions options, TimeProvider timeProvider)
{
    private readonly ConcurrentDictionary<string, Counter> _counters = new();

    /// <summary>尝试获取一次配额。超限返回 false(调用方返回 429)。</summary>
    public bool TryAcquire(string tunnelId)
    {
        var now = timeProvider.GetUtcNow().ToUnixTimeSeconds();
        var counter = _counters.GetOrAdd(tunnelId, _ => new Counter());
        lock (counter)
        {
            if (counter.Window != now)
            {
                counter.Window = now;
                counter.Count = 0;
            }
            counter.Count++;
            return counter.Count <= options.MaxQpsPerTunnel;
        }
    }

    private sealed class Counter
    {
        public long Window;
        public int Count;
    }
}
