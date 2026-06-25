using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Tests.Hubs;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Tests.Sessions.Fakes;

/// <summary>
/// IHubContext&lt;TerminalHub&gt; fake that exposes per-user RecordingClientProxy instances.
/// ArtifactService.BroadcastArtifactChangeAsync calls Clients.User(ownerUserId).SendAsync,
/// so tests look up the user proxy and assert on Invocations.
/// </summary>
internal sealed class ArtifactTestHubContext : IHubContext<TerminalHub>
{
    private readonly Dictionary<string, RecordingClientProxy> _users;

    public IReadOnlyDictionary<string, RecordingClientProxy> Users => _users;

    public ArtifactTestHubContext(params string[] userIds)
    {
        _users = new Dictionary<string, RecordingClientProxy>(StringComparer.Ordinal);
        foreach (var id in userIds)
        {
            _users[id] = new RecordingClientProxy();
        }
    }

    public IHubClients Clients => new UserHubClients(_users);
    public IGroupManager Groups => new NoOpGroupManager();

    private sealed class UserHubClients(Dictionary<string, RecordingClientProxy> users) : IHubClients
    {
        public IClientProxy All => throw new NotSupportedException();
        public IClientProxy Caller => throw new NotSupportedException();
        public IClientProxy Others => throw new NotSupportedException();
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();
        public IClientProxy Client(string connectionId) => throw new NotSupportedException();
        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => throw new NotSupportedException();
        public IClientProxy Group(string groupName) => throw new NotSupportedException();
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => throw new NotSupportedException();
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => throw new NotSupportedException();
        public IClientProxy OthersInGroup(string groupName) => throw new NotSupportedException();

        public IClientProxy User(string userId)
            => users.TryGetValue(userId, out var proxy)
                ? proxy
                : throw new InvalidOperationException($"Fake has no user '{userId}'. Pass it to the ArtifactTestHubContext constructor.");

        public IClientProxy Users(IReadOnlyList<string> userIds) => throw new NotSupportedException();
    }

    private sealed class NoOpGroupManager : IGroupManager
    {
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
