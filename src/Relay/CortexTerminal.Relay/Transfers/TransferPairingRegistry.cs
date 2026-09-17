using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Threading.Channels;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Relay.Transfers;

/// <summary>
/// 一次传输的配对状态：Worker 先经 RPC 连入 transfer WS，客户端随后以 HTTP 接入。
/// Worker WS 的接收循环把帧推进 <see cref="FromWorker"/> 通道；HTTP 端点消费通道并泵写响应。
/// </summary>
public sealed class TransferPair
{
    public TransferPair(string transferId, DateTimeOffset expiresAtUtc)
    {
        TransferId = transferId;
        ExpiresAtUtc = expiresAtUtc;
    }

    public string TransferId { get; }
    public DateTimeOffset ExpiresAtUtc { get; }

    /// <summary>配对/传输全程的生命周期信号：超时、完成或任一端断开时触发。</summary>
    public CancellationTokenSource Lifetime { get; } = new();

    /// <summary>Worker transfer WS 就绪信号。</summary>
    public TaskCompletionSource<WebSocket> WorkerReady { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// <summary>Worker → Relay 的帧流（控制文本帧 + 文件数据二进制帧）。</summary>
    public Channel<RelayFrame> FromWorker { get; } =
        Channel.CreateBounded<RelayFrame>(new BoundedChannelOptions(128)
        {
            SingleReader = true,
            SingleWriter = true,
        });
}

/// <summary>内存传输配对表 + TTL 清扫。Relay 不落盘：配对消失即传输失败，客户端重发起即可。</summary>
public sealed class TransferPairingRegistry
{
    private readonly ConcurrentDictionary<string, TransferPair> _pairs = new(StringComparer.Ordinal);

    public TransferPair GetOrCreate(string transferId, DateTimeOffset expiresAtUtc)
        => _pairs.GetOrAdd(transferId, id => new TransferPair(id, expiresAtUtc));

    public void Remove(string transferId)
    {
        if (_pairs.TryRemove(transferId, out var pair))
        {
            pair.Lifetime.Cancel();
        }
    }

    /// <summary>清扫过期配对：关闭仍连着的 Worker WS，释放表项。由 <see cref="TransferSweeper"/> 周期调用。</summary>
    public void SweepExpired(DateTimeOffset now)
    {
        foreach (var (id, pair) in _pairs)
        {
            if (pair.ExpiresAtUtc > now) continue;
            if (!_pairs.TryRemove(id, out _)) continue;
            pair.Lifetime.Cancel();
            if (pair.WorkerReady.Task.IsCompletedSuccessfully)
            {
                var ws = pair.WorkerReady.Task.Result;
                if (ws.State == WebSocketState.Open)
                {
                    _ = ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "transfer expired", CancellationToken.None);
                }
            }
        }
    }
}

/// <summary>周期清扫过期传输配对的后台服务。</summary>
public sealed class TransferSweeper(TransferPairingRegistry registry, ILogger<TransferSweeper> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(15));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                registry.SweepExpired(DateTimeOffset.UtcNow);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Transfer sweep failed.");
            }
        }
    }
}
