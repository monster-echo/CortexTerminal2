using System.Collections.Concurrent;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Sessions;

public sealed class ReplayCache(int maxBytesPerSession) : IReplayCache
{
    private readonly ConcurrentDictionary<string, SessionReplayBuffer> _buffers = new();
    private readonly int _maxBytesPerSession = maxBytesPerSession >= 0
        ? maxBytesPerSession
        : throw new ArgumentOutOfRangeException(nameof(maxBytesPerSession));

    public void Append(ReplayChunk chunk)
    {
        ArgumentNullException.ThrowIfNull(chunk);

        var buffer = _buffers.GetOrAdd(chunk.SessionId, static _ => new SessionReplayBuffer());
        buffer.Gate.Wait();
        try
        {
            AppendCore(buffer, chunk);
        }
        finally
        {
            buffer.Gate.Release();
        }
    }

    public async Task AppendAsync(ReplayChunk chunk, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(chunk);

        var buffer = _buffers.GetOrAdd(chunk.SessionId, static _ => new SessionReplayBuffer());
        await buffer.Gate.WaitAsync(cancellationToken);
        try
        {
            AppendCore(buffer, chunk);
        }
        finally
        {
            buffer.Gate.Release();
        }
    }

    public IReadOnlyList<ReplayChunk> GetSnapshot(string sessionId)
    {
        if (!_buffers.TryGetValue(sessionId, out var buffer))
        {
            return [];
        }

        buffer.Gate.Wait();
        try
        {
            return buffer.Chunks.ToArray();
        }
        finally
        {
            buffer.Gate.Release();
        }
    }

    public async Task ReplayWhileLockedAsync(string sessionId, Func<IReadOnlyList<ReplayChunk>, Task> replayAction, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(replayAction);

        var buffer = _buffers.GetOrAdd(sessionId, static _ => new SessionReplayBuffer());
        await buffer.Gate.WaitAsync(cancellationToken);
        try
        {
            await replayAction(buffer.Chunks.ToArray());
        }
        finally
        {
            buffer.Gate.Release();
        }
    }

    public void Clear(string sessionId)
    {
        if (!_buffers.TryGetValue(sessionId, out var buffer))
        {
            return;
        }

        buffer.Gate.Wait();
        try
        {
            buffer.Chunks.Clear();
            buffer.TotalBytes = 0;
        }
        finally
        {
            buffer.Gate.Release();
        }
    }

    private sealed class SessionReplayBuffer
    {
        public Queue<ReplayChunk> Chunks { get; } = new();
        public SemaphoreSlim Gate { get; } = new(1, 1);
        public int TotalBytes { get; set; }
    }

    private void AppendCore(SessionReplayBuffer buffer, ReplayChunk chunk)
    {
        buffer.Chunks.Enqueue(chunk);
        buffer.TotalBytes += chunk.Payload.Length;

        while (buffer.TotalBytes > _maxBytesPerSession && buffer.Chunks.Count > 0)
        {
            var evicted = buffer.Chunks.Dequeue();
            buffer.TotalBytes -= evicted.Payload.Length;
        }

        if (buffer.Chunks.Count == 0)
        {
            buffer.TotalBytes = 0;
        }
    }
}
