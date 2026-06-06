using CortexTerminal.Gateway.Auth;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class FailedAttemptTrackerTests
{
    private static FailedAttemptTracker CreateTracker(int threshold = 3, int windowMinutes = 15)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Captcha:FailedThreshold"] = threshold.ToString(),
                ["Captcha:WindowMinutes"] = windowMinutes.ToString(),
            })
            .Build();
        return new FailedAttemptTracker(config);
    }

    [Fact]
    public void IsCaptchaRequired_NoFailures_ReturnsFalse()
    {
        var tracker = CreateTracker();
        tracker.IsCaptchaRequired("1.2.3.4").Should().BeFalse();
    }

    [Fact]
    public void IsCaptchaRequired_BelowThreshold_ReturnsFalse()
    {
        var tracker = CreateTracker(threshold: 3);
        tracker.RecordFailure("1.2.3.4");
        tracker.RecordFailure("1.2.3.4");
        tracker.IsCaptchaRequired("1.2.3.4").Should().BeFalse("only 2 failures, threshold is 3");
    }

    [Fact]
    public void IsCaptchaRequired_AtThreshold_ReturnsTrue()
    {
        var tracker = CreateTracker(threshold: 3);
        tracker.RecordFailure("1.2.3.4");
        tracker.RecordFailure("1.2.3.4");
        tracker.RecordFailure("1.2.3.4");
        tracker.IsCaptchaRequired("1.2.3.4").Should().BeTrue("3 failures reached threshold");
    }

    [Fact]
    public void RecordSuccess_ClearsAttempts()
    {
        var tracker = CreateTracker(threshold: 3);
        tracker.RecordFailure("1.2.3.4");
        tracker.RecordFailure("1.2.3.4");
        tracker.RecordFailure("1.2.3.4");
        tracker.IsCaptchaRequired("1.2.3.4").Should().BeTrue();

        tracker.RecordSuccess("1.2.3.4");
        tracker.IsCaptchaRequired("1.2.3.4").Should().BeFalse("success should clear failures");
    }

    [Fact]
    public void DifferentKeysTrackedSeparately()
    {
        var tracker = CreateTracker(threshold: 2);
        tracker.RecordFailure("1.1.1.1");
        tracker.RecordFailure("1.1.1.1");
        tracker.RecordFailure("2.2.2.2");

        tracker.IsCaptchaRequired("1.1.1.1").Should().BeTrue("2 failures = threshold");
        tracker.IsCaptchaRequired("2.2.2.2").Should().BeFalse("only 1 failure");
        tracker.IsCaptchaRequired("3.3.3.3").Should().BeFalse("no failures");
    }

    [Fact]
    public void RecordFailure_ExceedingThreshold_ContinuesTracking()
    {
        var tracker = CreateTracker(threshold: 2);
        tracker.RecordFailure("1.1.1.1");
        tracker.RecordFailure("1.1.1.1");
        tracker.RecordFailure("1.1.1.1");
        tracker.RecordFailure("1.1.1.1");

        tracker.IsCaptchaRequired("1.1.1.1").Should().BeTrue("still above threshold after more failures");
    }

    [Fact]
    public void RecordSuccess_DoesNotAffectOtherKeys()
    {
        var tracker = CreateTracker(threshold: 2);
        tracker.RecordFailure("1.1.1.1");
        tracker.RecordFailure("1.1.1.1");
        tracker.RecordFailure("2.2.2.2");
        tracker.RecordFailure("2.2.2.2");

        tracker.RecordSuccess("1.1.1.1");

        tracker.IsCaptchaRequired("1.1.1.1").Should().BeFalse("success cleared this key");
        tracker.IsCaptchaRequired("2.2.2.2").Should().BeTrue("other key unaffected");
    }
}
