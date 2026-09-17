using CortexTerminal.Gateway.Workspaces;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workspaces;

public sealed class WorkspaceRegistryTests
{
    private static WorkspaceRegistry NewRegistry()
        => new(TestSessionFactory.CreateContextFactoryPublic(), TimeProvider.System);

    [Fact]
    public async Task Create_ThenGetOwned_ReturnsEntity()
    {
        var registry = NewRegistry();
        var created = await registry.CreateAsync("user-1", "worker-1", "proj", "/home/user/proj");

        var fetched = await registry.GetOwnedAsync("user-1", created.Id);
        fetched.Name.Should().Be("proj");
        fetched.RootPath.Should().Be("/home/user/proj");
    }

    [Fact]
    public async Task GetOwned_WithForeignUser_ThrowsForbidden()
    {
        var registry = NewRegistry();
        var created = await registry.CreateAsync("user-1", "worker-1", "proj", "/home/user/proj");

        var act = () => registry.GetOwnedAsync("user-2", created.Id);
        await act.Should().ThrowAsync<WorkspaceForbiddenException>();
    }

    [Fact]
    public async Task GetOwned_MissingId_ThrowsNotFound()
    {
        var registry = NewRegistry();
        var act = () => registry.GetOwnedAsync("user-1", "ws_missing");
        await act.Should().ThrowAsync<WorkspaceNotFoundException>();
    }

    [Fact]
    public async Task Delete_DefaultWorkspace_IsRejected()
    {
        var registry = NewRegistry();
        var created = await registry.CreateAsync("user-1", "worker-1", "Home", "/home/user", isDefault: true);

        var act = () => registry.DeleteAsync("user-1", created.Id, boundSessionCount: 0);
        await act.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task Delete_WithBoundSessions_IsRejected()
    {
        var registry = NewRegistry();
        var created = await registry.CreateAsync("user-1", "worker-1", "proj", "/home/user/proj");

        var act = () => registry.DeleteAsync("user-1", created.Id, boundSessionCount: 2);
        await act.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task EnsureDefault_SeedsHomeOnce_PerWorker()
    {
        var registry = NewRegistry();
        await registry.EnsureDefaultAsync("user-1", "worker-1", "/home/user");

        // 第二次上报 home：该 worker 已有工作区，不再重复建
        await registry.EnsureDefaultAsync("user-1", "worker-1", "/home/user");

        // 另一台 worker：建自己的默认工作区
        await registry.EnsureDefaultAsync("user-1", "worker-2", "/home/user");

        var list = await registry.ListForUserAsync("user-1");
        list.Where(w => w.IsDefault).Should().HaveCount(2);
        list.Count(w => w.WorkerId == "worker-1").Should().Be(1);
    }
}
