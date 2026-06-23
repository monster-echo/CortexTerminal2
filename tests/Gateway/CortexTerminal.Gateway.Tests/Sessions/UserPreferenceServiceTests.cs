using CortexTerminal.Gateway.Sessions;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class UserPreferenceServiceTests
{
    [Fact]
    public async Task GetScrollbackMaxBytesAsync_WhenNotSet_ReturnsNull()
    {
        var service = TestSessionFactory.CreatePreferenceService();

        var result = await service.GetScrollbackMaxBytesAsync("user-1", CancellationToken.None);

        result.Should().BeNull();
    }

    [Fact]
    public async Task SetScrollbackMaxBytesAsync_ThenGet_ReturnsValue()
    {
        var service = TestSessionFactory.CreatePreferenceService();
        var bytes = 2 * 1024 * 1024;

        await service.SetScrollbackMaxBytesAsync("user-1", bytes, CancellationToken.None);
        var result = await service.GetScrollbackMaxBytesAsync("user-1", CancellationToken.None);

        result.Should().Be(bytes);
    }

    [Fact]
    public async Task SetScrollbackMaxBytesAsync_Twice_UpdatesSameRow()
    {
        var service = TestSessionFactory.CreatePreferenceService();

        await service.SetScrollbackMaxBytesAsync("user-1", 1024 * 1024, CancellationToken.None);
        await service.SetScrollbackMaxBytesAsync("user-1", 2 * 1024 * 1024, CancellationToken.None);
        var result = await service.GetScrollbackMaxBytesAsync("user-1", CancellationToken.None);

        result.Should().Be(2 * 1024 * 1024);
    }

    [Fact]
    public async Task SetScrollbackMaxBytesAsync_DistinctUsers_AreIndependent()
    {
        var service = TestSessionFactory.CreatePreferenceService();

        await service.SetScrollbackMaxBytesAsync("user-a", 1024 * 1024, CancellationToken.None);
        await service.SetScrollbackMaxBytesAsync("user-b", 2 * 1024 * 1024, CancellationToken.None);

        var a = await service.GetScrollbackMaxBytesAsync("user-a", CancellationToken.None);
        var b = await service.GetScrollbackMaxBytesAsync("user-b", CancellationToken.None);

        a.Should().Be(1024 * 1024);
        b.Should().Be(2 * 1024 * 1024);
    }
}
