namespace CortexTerminal.Gateway.Membership;

public sealed record Entitlement(
    string UserId,
    string Tier,
    string PlanCode,
    int MaxWorkers,
    int MaxArtifactsPerSession,
    long MaxArtifactSizeBytes,
    int MaxArtifactAgeDays,
    int MaxScrollbackMegabytes,
    DateTimeOffset? ExpiresAtUtc)
{
    public bool IsPro => Tier == MembershipTiers.Pro;
    public bool IsActive => Tier == MembershipTiers.Pro
        && (ExpiresAtUtc is null || ExpiresAtUtc > DateTimeOffset.UtcNow);
}
