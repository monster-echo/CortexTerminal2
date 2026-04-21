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
        lock (buffer.Sync)
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

    public IReadOnlyList<ReplayChunk> GetSnapshot(string sessionId)
    {
        if (!_buffers.TryGetValue(sessionId, out var buffer))
        {
            return [];
        }

        lock (buffer.Sync)
        {
            return buffer.Chunks.ToArray();
        }
    }

    public void Clear(string sessionId)
    {
        if (!_buffers.TryGetValue(sessionId, out var buffer))
        {
            return;
        }

        lock (buffer.Sync)
        {
            buffer.Chunks.Clear();
            buffer.TotalBytes = 0;
        }
    }

    private sealed class SessionReplayBuffer
    {
        public Queue<ReplayChunk> Chunks { get; } = new();
        public object Sync { get; } = new();
        public int TotalBytes { get; set; }
    }
}
