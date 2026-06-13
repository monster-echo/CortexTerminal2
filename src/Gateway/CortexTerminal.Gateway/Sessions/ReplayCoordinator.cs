using System.Collections.Concurrent;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Sessions;

public sealed class ReplayCoordinator
{
    private readonly ConcurrentDictionary<string, PendingReplay> _pending = new();

    public void BeginReplay(string sessionId, string connectionId)
    {
        _pending[sessionId] = new PendingReplay(connectionId);
    }

    public bool TryEnqueue(string sessionId, TerminalChunk chunk)
    {
        if (!_pending.TryGetValue(sessionId, out var pending)) return false;
        lock (pending.Gate)
        {
            pending.Queue.Enqueue(chunk);
        }
        return true;
    }

    public async Task FlushPendingAsync(string sessionId, string connectionId, Func<TerminalChunk, Task> send, CancellationToken cancellationToken)
    {
        if (!_pending.TryRemove(sessionId, out var pending)) return;
        if (pending.ConnectionId != connectionId) return;

        List<TerminalChunk> drained;
        lock (pending.Gate)
        {
            drained = [.. pending.Queue];
        }

        foreach (var chunk in drained)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await send(chunk);
        }
    }

    public void AbortReplay(string sessionId)
    {
        _pending.TryRemove(sessionId, out _);
    }

    private sealed class PendingReplay(string connectionId)
    {
        public string ConnectionId { get; } = connectionId;
        public Queue<TerminalChunk> Queue { get; } = new();
        public object Gate { get; } = new();
    }
}
