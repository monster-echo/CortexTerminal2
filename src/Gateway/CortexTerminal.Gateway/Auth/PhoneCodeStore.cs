using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Auth;

public sealed class PhoneCodeStore
{
    private readonly ConcurrentDictionary<string, PhoneCodeEntry> _codes = new();

    public string Create(string phone)
    {
        RemoveExpired();

        if (_codes.TryGetValue(phone, out var existing) && existing.ExpiresAtUtc > DateTimeOffset.UtcNow)
        {
            var remaining = 60 - (int)(DateTimeOffset.UtcNow - existing.CreatedAtUtc).TotalSeconds;
            if (remaining > 0)
                throw new InvalidOperationException($"RATE_LIMITED:{remaining}");
        }

        var code = Random.Shared.Next(100000, 999999).ToString();
        _codes[phone] = new PhoneCodeEntry(code, phone, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddMinutes(5));
        return code;
    }

    public bool Verify(string phone, string inputCode)
    {
        if (!_codes.TryRemove(phone, out var entry))
            return false;

        if (entry.ExpiresAtUtc < DateTimeOffset.UtcNow)
            return false;

        return entry.Code == inputCode;
    }

    private void RemoveExpired()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var kvp in _codes)
        {
            if (kvp.Value.ExpiresAtUtc < now)
                _codes.TryRemove(kvp.Key, out _);
        }
    }

    private sealed record PhoneCodeEntry(string Code, string Phone, DateTimeOffset CreatedAtUtc, DateTimeOffset ExpiresAtUtc);
}
