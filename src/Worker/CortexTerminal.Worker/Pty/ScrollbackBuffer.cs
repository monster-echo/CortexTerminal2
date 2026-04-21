using CortexTerminal.Contracts.Streaming;
using System.Linq;

namespace CortexTerminal.Worker.Pty;

public sealed class ScrollbackBuffer(int maxBytes)
{
    private readonly LinkedList<TerminalChunk> _chunks = [];
    private int _currentBytes;

    public void Append(string sessionId, string stream, byte[] payload)
    {
        var copy = payload.ToArray();
        _chunks.AddLast(new TerminalChunk(sessionId, stream, copy));
        _currentBytes += copy.Length;

        while (_currentBytes > maxBytes && _chunks.First is not null)
        {
            _currentBytes -= _chunks.First.Value.Payload.Length;
            _chunks.RemoveFirst();
        }
    }

    public IReadOnlyList<TerminalChunk> Snapshot() => _chunks.ToList();
}
