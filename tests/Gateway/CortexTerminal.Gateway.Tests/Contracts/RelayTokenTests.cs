using CortexTerminal.Contracts.Streaming;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Contracts;

public sealed class RelayTokenTests
{
    private const string Secret = "test-shared-secret-for-relay-tokens";

    [Fact]
    public void Mint_ThenValidate_RoundTrips()
    {
        var expires = DateTimeOffset.UtcNow.AddMinutes(10);
        var token = RelayToken.Mint(Secret, RelayToken.AudienceTransfer, "tid-1", expires);

        var ok = RelayToken.TryValidate(Secret, token, RelayToken.AudienceTransfer, "tid-1", out var payload);

        ok.Should().BeTrue();
        payload.Sub.Should().Be("tid-1");
        payload.Aud.Should().Be(RelayToken.AudienceTransfer);
        payload.Exp.Should().Be(expires.ToUnixTimeSeconds());
    }

    [Fact]
    public void Validate_WithWrongSecret_Fails()
    {
        var token = RelayToken.Mint(Secret, RelayToken.AudienceTransfer, "tid-1", DateTimeOffset.UtcNow.AddMinutes(10));
        RelayToken.TryValidate("other-secret", token, RelayToken.AudienceTransfer, "tid-1", out _).Should().BeFalse();
    }

    [Fact]
    public void Validate_WithWrongAudience_Fails()
    {
        var token = RelayToken.Mint(Secret, RelayToken.AudienceTransfer, "tid-1", DateTimeOffset.UtcNow.AddMinutes(10));
        RelayToken.TryValidate(Secret, token, RelayToken.AudienceWorkerRelay, "tid-1", out _).Should().BeFalse();
    }

    [Fact]
    public void Validate_WithWrongSubject_Fails()
    {
        var token = RelayToken.Mint(Secret, RelayToken.AudienceTransfer, "tid-1", DateTimeOffset.UtcNow.AddMinutes(10));
        RelayToken.TryValidate(Secret, token, RelayToken.AudienceTransfer, "tid-2", out _).Should().BeFalse();
    }

    [Fact]
    public void Validate_ExpiredToken_Fails()
    {
        var token = RelayToken.Mint(Secret, RelayToken.AudienceTransfer, "tid-1", DateTimeOffset.UtcNow.AddSeconds(-1));
        RelayToken.TryValidate(Secret, token, RelayToken.AudienceTransfer, "tid-1", out _).Should().BeFalse();
    }

    [Fact]
    public void Validate_TamperedPayload_Fails()
    {
        var token = RelayToken.Mint(Secret, RelayToken.AudienceTransfer, "tid-1", DateTimeOffset.UtcNow.AddMinutes(10));
        var tampered = token.Substring(0, token.Length - 2) + "xx";
        RelayToken.TryValidate(Secret, tampered, RelayToken.AudienceTransfer, "tid-1", out _).Should().BeFalse();
    }

    [Fact]
    public void Validate_MalformedToken_Fails()
    {
        RelayToken.TryValidate(Secret, "no-dot", RelayToken.AudienceTransfer, "tid-1", out _).Should().BeFalse();
        RelayToken.TryValidate(Secret, ".sig", RelayToken.AudienceTransfer, "tid-1", out _).Should().BeFalse();
        RelayToken.TryValidate(Secret, "", RelayToken.AudienceTransfer, "tid-1", out _).Should().BeFalse();
    }
}
