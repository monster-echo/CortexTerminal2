namespace CortexTerminal.Gateway.Stats;

public interface ISessionStatsService
{
    void RecordBytes(string sessionId, string userId, int byteCount);
    long GetSessionBytes(string sessionId);
    long GetUserBytes(string userId);
    IReadOnlyDictionary<string, long> GetAllSessionBytes();
    IReadOnlyDictionary<string, long> GetAllUserBytes();
    Task FlushAsync(CancellationToken cancellationToken);
}
