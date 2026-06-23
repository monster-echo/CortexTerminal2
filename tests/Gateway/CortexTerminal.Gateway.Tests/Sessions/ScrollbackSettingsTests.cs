using CortexTerminal.Gateway.Sessions;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class ScrollbackSettingsTests
{
    [Fact]
    public void Defaults_ToFiveMegabytes()
    {
        var settings = new ScrollbackSettings();

        settings.MaxMegabytes.Should().Be(5);
        settings.MaxBytesOverride.Should().BeNull();
        settings.MaxBytes.Should().Be(5 * 1024 * 1024);
    }

    [Fact]
    public void MaxBytes_DerivesFromMaxMegabytes()
    {
        var settings = new ScrollbackSettings { MaxMegabytes = 10 };

        settings.MaxBytes.Should().Be(10 * 1024 * 1024);
    }

    [Fact]
    public void MaxBytesOverride_TakesPrecedenceOverMaxMegabytes()
    {
        var settings = new ScrollbackSettings { MaxMegabytes = 5, MaxBytesOverride = 200 };

        settings.MaxBytes.Should().Be(200);
    }

    [Fact]
    public void ClearingMaxBytesOverride_FallsBackToMaxMegabytes()
    {
        var settings = new ScrollbackSettings { MaxMegabytes = 3, MaxBytesOverride = 200 };
        settings.MaxBytesOverride = null;

        settings.MaxBytes.Should().Be(3 * 1024 * 1024);
    }

    [Fact]
    public void Defaults_AllowedRangeIsSixteenKbToFiveMb()
    {
        var settings = new ScrollbackSettings();

        settings.MinAllowedBytes.Should().Be(16 * 1024);
        settings.MaxAllowedBytes.Should().Be(5 * 1024 * 1024);
    }
}
