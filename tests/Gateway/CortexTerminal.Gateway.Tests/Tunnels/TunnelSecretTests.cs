using CortexTerminal.Contracts.Streaming;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Tunnels;

public sealed class TunnelSecretTests
{
    [Fact]
    public void GenerateSecret_returns_url_safe_base64_of_32_bytes()
    {
        var a = TunnelSecret.GenerateSecret();
        var b = TunnelSecret.GenerateSecret();
        a.Should().NotBe(b);
        a.Length.Should().Be(43); // 32 bytes -> 43 base64url chars, no padding
        a.Should().MatchRegex(@"^[A-Za-z0-9_-]+$");
    }

    [Fact]
    public void GenerateTunnelKey_is_short_and_path_safe()
    {
        var key = TunnelSecret.GenerateTunnelKey();
        key.Length.Should().Be(10); // 5 bytes -> 10 lowercase hex chars
        key.Should().MatchRegex(@"^[0-9a-f]+$");
    }

    [Fact]
    public void Hash_is_deterministic_lowercase_hex_sha256()
    {
        var secret = "abc123";
        var h = TunnelSecret.Hash(secret);
        h.Should().Be(TunnelSecret.Hash(secret)); // deterministic
        h.Length.Should().Be(64); // sha256 hex
        h.Should().MatchRegex(@"^[0-9a-f]{64}$");
    }

    [Fact]
    public void Verify_matches_hash_only_for_correct_secret()
    {
        var secret = TunnelSecret.GenerateSecret();
        var hash = TunnelSecret.Hash(secret);
        TunnelSecret.Verify(secret, hash).Should().BeTrue();
        TunnelSecret.Verify(secret + "x", hash).Should().BeFalse();
        TunnelSecret.Verify("", hash).Should().BeFalse();
    }
}
