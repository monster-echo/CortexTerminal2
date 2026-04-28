using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Auth;

public sealed class OAuthStateService
{
    private readonly ConcurrentDictionary<string, OAuthStateEntry> _states = new();
    private static readonly TimeSpan Expiry = TimeSpan.FromMinutes(10);

    public string Create(string redirectUrl)
    {
        RemoveExpired();
        var state = Guid.NewGuid().ToString("N");
        _states[state] = new OAuthStateEntry(redirectUrl, DateTimeOffset.UtcNow.Add(Expiry));
        return state;
    }

    public string? Consume(string state)
    {
        if (!_states.TryRemove(state, out var entry))
            return null;

        if (entry.ExpiresAtUtc < DateTimeOffset.UtcNow)
            return null;

        return entry.RedirectUrl;
    }

    private void RemoveExpired()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var kvp in _states)
        {
            if (kvp.Value.ExpiresAtUtc < now)
                _states.TryRemove(kvp.Key, out _);
        }
    }

    private sealed record OAuthStateEntry(string RedirectUrl, DateTimeOffset ExpiresAtUtc);
}
