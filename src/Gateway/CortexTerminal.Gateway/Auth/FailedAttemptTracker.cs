using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Auth;

public sealed class FailedAttemptTracker
{
    private readonly ConcurrentDictionary<string, AttemptRecord> _attempts = new();
    private readonly int _threshold;
    private readonly TimeSpan _window;

    public FailedAttemptTracker(IConfiguration configuration)
    {
        _threshold = configuration.GetValue("Captcha:FailedThreshold", 3);
        _window = TimeSpan.FromMinutes(configuration.GetValue("Captcha:WindowMinutes", 15));
    }

    public void RecordFailure(string key)
    {
        _attempts.AddOrUpdate(key,
            _ => new AttemptRecord(1, DateTimeOffset.UtcNow),
            (_, existing) =>
            {
                if (DateTimeOffset.UtcNow - existing.LastAttemptAt > _window)
                    return new AttemptRecord(1, DateTimeOffset.UtcNow);
                return new AttemptRecord(existing.Count + 1, DateTimeOffset.UtcNow);
            });
    }

    public void RecordSuccess(string key)
    {
        _attempts.TryRemove(key, out _);
    }

    public bool IsCaptchaRequired(string key)
    {
        Cleanup();
        if (!_attempts.TryGetValue(key, out var record))
            return false;
        if (DateTimeOffset.UtcNow - record.LastAttemptAt > _window)
            return false;
        return record.Count >= _threshold;
    }

    public int GetTrackedIpCount()
    {
        Cleanup();
        return _attempts.Count;
    }

    private void Cleanup()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var kvp in _attempts)
        {
            if (now - kvp.Value.LastAttemptAt > _window)
                _attempts.TryRemove(kvp.Key, out _);
        }
    }

    private sealed record AttemptRecord(int Count, DateTimeOffset LastAttemptAt);
}
