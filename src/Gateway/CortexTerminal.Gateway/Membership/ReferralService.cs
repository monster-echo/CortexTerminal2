using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Membership;

public sealed record ReferralSummary(
    string Code, int InvitedCount, int TotalRewardDays, IReadOnlyList<ReferralReward> Rewards);

public sealed class ReferralService(
    IDbContextFactory<AppDbContext> dbFactory,
    ReferralOptions options,
    ILogger<ReferralService> logger)
{
    private const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    public async Task<ReferralCode> GetOrCreateCodeAsync(string userId, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var existing = await db.ReferralCodes.FirstOrDefaultAsync(c => c.UserId == userId, ct);
        if (existing is not null) return existing;

        var code = new ReferralCode { UserId = userId, Code = await GenerateUniqueCodeAsync(db, ct) };
        db.ReferralCodes.Add(code);
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Referral code {Code} created for user {UserId}", code.Code, userId);
        return code;
    }

    public async Task<ReferralSummary> GetSummaryAsync(string userId, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var code = await GetOrCreateCodeAsync(userId, ct);
        var rewards = await db.ReferralRewards
            .Where(r => r.ReferrerUserId == userId)
            .OrderByDescending(r => r.CreatedAtUtc)
            .ToListAsync(ct);
        return new ReferralSummary(
            code.Code,
            rewards.Count,
            rewards.Sum(r => r.RewardDays),
            rewards);
    }

    /// <summary>Binds the calling user to a referrer. One-shot: a user can only ever be referred once.</summary>
    public async Task ApplyAsync(string userId, string codeInput, CancellationToken ct)
    {
        var code = codeInput.Trim().ToUpperInvariant();
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var referrer = await db.ReferralCodes.FirstOrDefaultAsync(c => c.Code == code, ct)
            ?? throw new ReferralCodeInvalidException("Referral code not found.");
        if (referrer.UserId == userId)
            throw new ReferralCodeInvalidException("You cannot use your own referral code.");

        var user = await db.Users.FindAsync(new object?[] { userId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct)
            ?? throw new ArgumentException($"User not found: {userId}");
        if (user.ReferredByUserId is not null)
            throw new ReferralAlreadyAppliedException("You have already applied a referral code.");

        user.ReferredByUserId = referrer.UserId;
        user.UpdatedAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        logger.LogInformation("User {UserId} applied referral code {Code} from {ReferrerId}", userId, code, referrer.UserId);
    }

    /// <summary>
    /// Called after an invited user activates membership for the first time. Grants the referrer
    /// extra membership days (extending an active expiry, or starting a fresh Pro period) and
    /// records the reward. No-op when the user was not referred or was already rewarded.
    /// </summary>
    public async Task RewardIfEligibleAsync(string invitedUserId, string source, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var invited = await db.Users.FindAsync(new object?[] { invitedUserId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == invitedUserId, ct);
        if (invited?.ReferredByUserId is null) return;

        var alreadyRewarded = await db.ReferralRewards.AnyAsync(r => r.InvitedUserId == invitedUserId, ct);
        if (alreadyRewarded) return;

        var referrerId = invited.ReferredByUserId;
        var referrer = await db.Users.FindAsync(new object?[] { referrerId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == referrerId, ct);
        if (referrer is null) return;

        var now = DateTimeOffset.UtcNow;
        referrer.MembershipTier = MembershipTiers.Pro;
        referrer.MembershipExpiresAtUtc =
            referrer.MembershipExpiresAtUtc is { } existing && existing > now
                ? existing.AddDays(options.RewardDaysToReferrer)
                : now.AddDays(options.RewardDaysToReferrer);
        referrer.UpdatedAtUtc = now;

        db.ReferralRewards.Add(new ReferralReward
        {
            ReferrerUserId = referrerId, InvitedUserId = invitedUserId,
            InvitedUsername = invited.Username, RewardDays = options.RewardDaysToReferrer, Source = source,
        });
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Referral reward: {Days} days granted to {ReferrerId} for {InvitedId}",
            options.RewardDaysToReferrer, referrerId, invitedUserId);
    }

    private static async Task<string> GenerateUniqueCodeAsync(AppDbContext db, CancellationToken ct)
    {
        while (true)
        {
            var code = GenerateCode();
            var clash = await db.ReferralCodes.AnyAsync(c => c.Code == code, ct);
            if (!clash) return code;
        }
    }

    private static string GenerateCode()
    {
        var chars = new char[8];
        for (var i = 0; i < chars.Length; i++)
            chars[i] = CodeAlphabet[Random.Shared.Next(CodeAlphabet.Length)];
        return new string(chars);
    }
}
