using System.Security.Claims;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.SignalR;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Workers;

namespace CortexTerminal.Gateway.Tests.Hubs;

internal sealed record ClientInvocation(string Method, IReadOnlyList<object?> Arguments);

internal sealed class RecordingClientProxy(Action<string, object?[]>? onSend = null) : IClientProxy
{
    private readonly List<ClientInvocation> _invocations = [];

    public IReadOnlyList<ClientInvocation> Invocations => _invocations;

    public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
    {
        onSend?.Invoke(method, args);
        _invocations.Add(new ClientInvocation(method, args));
        return Task.CompletedTask;
    }
}

internal sealed class TestHubCallerClients(IClientProxy caller, IReadOnlyDictionary<string, IClientProxy>? clients = null) : IHubCallerClients
{
    private readonly IReadOnlyDictionary<string, IClientProxy> _clients = clients ?? new Dictionary<string, IClientProxy>();

    public IClientProxy All => NullClientProxy.Instance;
    public IClientProxy Caller => caller;
    public IClientProxy Others => NullClientProxy.Instance;

    public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => NullClientProxy.Instance;

    public IClientProxy Client(string connectionId)
        => _clients.TryGetValue(connectionId, out var client)
            ? client
            : NullClientProxy.Instance;

    public IClientProxy Clients(IReadOnlyList<string> connectionIds) => NullClientProxy.Instance;
    public IClientProxy Group(string groupName) => NullClientProxy.Instance;
    public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => NullClientProxy.Instance;
    public IClientProxy Groups(IReadOnlyList<string> groupNames) => NullClientProxy.Instance;
    public IClientProxy OthersInGroup(string groupName) => NullClientProxy.Instance;
    public IClientProxy User(string userId) => NullClientProxy.Instance;
    public IClientProxy Users(IReadOnlyList<string> userIds) => NullClientProxy.Instance;

    private sealed class NullClientProxy : IClientProxy
    {
        public static NullClientProxy Instance { get; } = new();

        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
            => Task.CompletedTask;
    }
}

internal sealed class TestHubCallerContext(string connectionId, string? userIdentifier = null) : HubCallerContext
{
    private readonly ClaimsPrincipal _user = new(new ClaimsIdentity(
    [
        new Claim(ClaimTypes.NameIdentifier, userIdentifier ?? "unknown")
    ], "Test"));
    private readonly IDictionary<object, object?> _items = new Dictionary<object, object?>();

    public override string ConnectionId => connectionId;
    public override string? UserIdentifier => userIdentifier;
    public override ClaimsPrincipal? User => _user;
    public override IDictionary<object, object?> Items => _items;
    public override IFeatureCollection Features { get; } = new FeatureCollection();
    public override CancellationToken ConnectionAborted => CancellationToken.None;

    public override void Abort()
    {
    }
}

internal sealed class FixedTimeProvider(DateTimeOffset utcNow) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => utcNow;
}

internal sealed class NoOpWorkerCommandDispatcher : IWorkerCommandDispatcher
{
    public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken) => Task.CompletedTask;
    public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken) => Task.CompletedTask;
}

internal sealed class ThrowingWorkerCommandDispatcher(string message) : IWorkerCommandDispatcher
{
    public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken)
        => Task.FromException(new InvalidOperationException(message));

    public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken)
        => Task.CompletedTask;

    public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
        => Task.CompletedTask;

    public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
        => Task.CompletedTask;
}
