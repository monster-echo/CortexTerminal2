using System.Collections.Concurrent;
using System.Threading;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Workers;

namespace CortexTerminal.Gateway.Sessions;

public sealed class SessionLaunchCoordinator(
    ISessionCoordinator sessions,
    IWorkerCommandDispatcher workerCommands) : ISessionLaunchCoordinator
{
    private readonly ConcurrentDictionary<string, Lazy<Task<CreateSessionResult>>> _launches = new();

    public Task<CreateSessionResult> CreateSessionAsync(
        string userId,
        CreateSessionRequest request,
        string? clientConnectionId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.ClientRequestId))
        {
            return StartSessionAsync(userId, request, clientConnectionId, cancellationToken);
        }

        var launch = _launches.GetOrAdd(
            GetLaunchKey(userId, request.ClientRequestId),
            _ => new Lazy<Task<CreateSessionResult>>(
                () => StartSessionAsync(userId, request, clientConnectionId, CancellationToken.None),
                LazyThreadSafetyMode.ExecutionAndPublication));

        return AwaitLaunchAsync(
            GetLaunchKey(userId, request.ClientRequestId),
            launch,
            cancellationToken);
    }

    private async Task<CreateSessionResult> AwaitLaunchAsync(
        string launchKey,
        Lazy<Task<CreateSessionResult>> launch,
        CancellationToken cancellationToken)
    {
        var result = await launch.Value.WaitAsync(cancellationToken);
        if (!result.IsSuccess)
        {
            _launches.TryRemove(launchKey, out _);
        }

        return result;
    }

    private async Task<CreateSessionResult> StartSessionAsync(
        string userId,
        CreateSessionRequest request,
        string? clientConnectionId,
        CancellationToken cancellationToken)
    {
        var result = await sessions.CreateSessionAsync(
            userId,
            request,
            clientConnectionId,
            cancellationToken);

        if (!result.IsSuccess || result.Response is null ||
            !sessions.TryGetSession(result.Response.SessionId, out var session))
        {
            return result;
        }

        try
        {
            await workerCommands.StartSessionAsync(
                session.WorkerConnectionId,
                new StartSessionCommand(session.SessionId, session.Columns, session.Rows),
                cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            sessions.MarkSessionStartFailed(session.SessionId, "worker-start-dispatch-failed");
            return CreateSessionResult.Failure("worker-start-dispatch-failed");
        }

        return result;
    }

    private static string GetLaunchKey(string userId, string clientRequestId)
        => $"{userId}:{clientRequestId}";
}