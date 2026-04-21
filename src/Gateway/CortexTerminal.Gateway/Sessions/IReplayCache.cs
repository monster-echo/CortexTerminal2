using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Sessions;

public interface IReplayCache
{
    void Append(ReplayChunk chunk);
    Task AppendAsync(ReplayChunk chunk, CancellationToken cancellationToken);
    IReadOnlyList<ReplayChunk> GetSnapshot(string sessionId);
    Task ReplayWhileLockedAsync(string sessionId, Func<IReadOnlyList<ReplayChunk>, Task> replayAction, CancellationToken cancellationToken);
    void Clear(string sessionId);
}
