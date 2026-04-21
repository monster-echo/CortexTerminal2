using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Sessions;

public interface IReplayCache
{
    void Append(ReplayChunk chunk);
    IReadOnlyList<ReplayChunk> GetSnapshot(string sessionId);
    void Clear(string sessionId);
}
