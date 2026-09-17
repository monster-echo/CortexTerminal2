using CortexTerminal.Contracts.Streaming;
using System.Linq;

namespace CortexTerminal.Worker.Pty;

public sealed class ScrollbackBuffer(int maxBytes)
{
    private readonly object _sync = new();
    private readonly LinkedList<(long Seq, TerminalChunk Chunk)> _chunks = [];
    private long _lastSeq;
    // Sequence of the oldest retained chunk (advances as the front is trimmed).
    private long _oldestSeq = 1;
    private int _currentBytes;

    public void Append(string sessionId, string stream, byte[] payload)
    {
        var copy = payload.ToArray();

        lock (_sync)
        {
            var seq = ++_lastSeq;
            _chunks.AddLast((seq, new TerminalChunk(sessionId, stream, copy)));
            _currentBytes += copy.Length;

            while (_currentBytes > maxBytes && _chunks.First is not null)
            {
                _currentBytes -= _chunks.First.Value.Chunk.Payload.Length;
                _oldestSeq = _chunks.First.Value.Seq + 1;
                _chunks.RemoveFirst();
            }
        }
    }

    public IReadOnlyList<TerminalChunk> Snapshot()
    {
        lock (_sync)
        {
            return _chunks.Select(c => c.Chunk).ToArray();
        }
    }

    /// <summary>
    /// Incremental answer for a client holding everything up to sinceSeq.
    /// Gap=true → sinceSeq predates the retained window (front trim or a
    /// restarted stream): Items carry the full retained buffer and the client
    /// must reset its screen before applying them. Gap=false → Items are
    /// strictly the chunks after sinceSeq (possibly none) and the client
    /// continues its cached stream seamlessly.
    /// </summary>
    public ScrollbackDelta CreateDelta(long sinceSeq)
    {
        lock (_sync)
        {
            var gap = sinceSeq + 1 < _oldestSeq || sinceSeq > _lastSeq;
            var items = _chunks
                .Where(c => c.Seq > sinceSeq)
                .Select(c => new ScrollbackItem(c.Seq, c.Chunk))
                .ToArray();
            return new ScrollbackDelta(Gap: gap, LastSeq: _lastSeq, Items: items);
        }
    }
}
