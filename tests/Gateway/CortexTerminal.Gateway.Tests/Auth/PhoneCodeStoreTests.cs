using CortexTerminal.Gateway.Auth;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class PhoneCodeStoreTests
{
    private readonly PhoneCodeStore _store = new();

    [Fact]
    public void Verify_CorrectCode_ReturnsTrue()
    {
        var code = _store.Create("13800001111");
        _store.Verify("13800001111", code).Should().BeTrue();
    }

    [Fact]
    public void Verify_WrongCode_ReturnsFalse()
    {
        _store.Create("13800002222");
        _store.Verify("13800002222", "000000").Should().BeFalse();
    }

    [Fact]
    public void Verify_WrongCode_DoesNotConsumeEntry()
    {
        var code = _store.Create("13800003333");
        _store.Verify("13800003333", "000000").Should().BeFalse();
        _store.Verify("13800003333", code).Should().BeTrue("code should still be available after wrong attempt");
    }

    [Fact]
    public void Verify_CorrectCode_ConsumesEntry()
    {
        var code = _store.Create("13800004444");
        _store.Verify("13800004444", code).Should().BeTrue();
        _store.Verify("13800004444", code).Should().BeFalse("code should be consumed after successful verification");
    }

    [Fact]
    public void Verify_UnknownPhone_ReturnsFalse()
    {
        _store.Verify("13800009999", "123456").Should().BeFalse();
    }

    [Fact]
    public void Create_RateLimits_Within60Seconds()
    {
        _store.Create("13800005555");
        var act = () => _store.Create("13800005555");
        act.Should().Throw<InvalidOperationException>()
            .Which.Message.Should().StartWith("RATE_LIMITED:");
    }
}
