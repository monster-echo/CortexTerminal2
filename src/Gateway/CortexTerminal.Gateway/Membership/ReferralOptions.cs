namespace CortexTerminal.Gateway.Membership;

public class ReferralOptions
{
    public const string SectionName = "Referral";

    /// <summary>Membership days granted to the referrer when an invited user activates membership.</summary>
    public int RewardDaysToReferrer { get; set; } = 7;
}
