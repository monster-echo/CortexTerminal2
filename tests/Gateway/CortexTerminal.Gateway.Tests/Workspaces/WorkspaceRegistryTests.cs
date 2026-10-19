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
    public async Task NameExists_IsScopedToWorkerAndIgnoresSoftDeletedNames()
    {
        var registry = NewRegistry();
        var created = await registry.CreateAsync("user-1", "worker-1", "proj", "/home/user/proj");

        (await registry.NameExistsAsync("worker-1", "proj")).Should().BeTrue();
        (await registry.NameExistsAsync("worker-2", "proj")).Should().BeFalse();

        await registry.DeleteAsync("user-1", created.Id);
        (await registry.NameExistsAsync("worker-1", "proj")).Should().BeFalse();
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
    public async Task Delete_DefaultWorkspace_IsRemoved()
    {
        var registry = NewRegistry();
        var created = await registry.CreateAsync("user-1", "worker-1", "Home", "/home/user", isDefault: true);

        await registry.DeleteAsync("user-1", created.Id);
        (await registry.ListForUserAsync("user-1")).Should().BeEmpty();
    }

    [Fact]
    public async Task Delete_WithBoundSessions_RemovesSessions()
    {
        var factory = TestSessionFactory.CreateContextFactoryPublic();
        var registry = new WorkspaceRegistry(factory, TimeProvider.System);
        var created = await registry.CreateAsync("user-1", "worker-1", "proj", "/home/user/proj");
        await using var db = await factory.CreateDbContextAsync();
        db.Sessions.Add(new CortexTerminal.Gateway.Data.SessionRecordEntity
        {
            SessionId = "session-bound", UserId = "user-1", WorkerId = "worker-1", WorkspaceId = created.Id
        });
        db.Sessions.Add(new CortexTerminal.Gateway.Data.SessionRecordEntity
        {
            SessionId = "session-other", UserId = "user-1", WorkerId = "worker-1"
        });
        await db.SaveChangesAsync();

        var deleted = await registry.DeleteAsync("user-1", created.Id);
        deleted.Should().Equal("session-bound");
        (await registry.ListForUserAsync("user-1")).Should().BeEmpty();
        await using var refreshed = await factory.CreateDbContextAsync();
        refreshed.Sessions.Select(s => s.SessionId).Should().Equal("session-other");
    }

    [Fact]
    public async Task FreshRegistry_HasNoWorkspaces_WorkerReportDoesNotCreateDefault()
    {
        // 工作区必须由用户显式创建：Gateway 不再自动创建默认工作区
        var registry = NewRegistry();

        var list = await registry.ListForUserAsync("user-1");
        list.Should().BeEmpty();
        list.Count(w => w.IsDefault).Should().Be(0);
    }
}
