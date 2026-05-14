using Ixnas.AltchaNet;

namespace CortexTerminal.Gateway.Auth;

public sealed class AltchaChallengeStore : IAltchaChallengeStore
{
    private readonly List<StoredChallenge> _stored = [];

    public Task Store(string challenge, DateTimeOffset expiryUtc)
    {
        lock (_stored)
        {
            _stored.Add(new StoredChallenge(challenge, expiryUtc));
        }
        return Task.CompletedTask;
    }

    public Task<bool> Exists(string challenge)
    {
        lock (_stored)
        {
            _stored.RemoveAll(c => c.ExpiryUtc <= DateTimeOffset.UtcNow);
            return Task.FromResult(_stored.Exists(c => c.Challenge == challenge));
        }
    }

    private sealed record StoredChallenge(string Challenge, DateTimeOffset ExpiryUtc);
}
