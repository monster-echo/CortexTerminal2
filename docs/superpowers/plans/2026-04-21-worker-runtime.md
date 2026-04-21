# Worker Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real Worker runtime that stays connected to Gateway, executes PTY sessions, receives control commands, and forwards stdout/stderr/exit events so local end-to-end debugging works.

**Architecture:** Keep Gateway as the control plane and Worker as the execution plane. Gateway will dispatch start/input/resize/close commands to a specific worker connection, while Worker will host per-session runtimes that drive `PtySession` and forward terminal events back through the existing worker hub.

**Tech Stack:** .NET 10, ASP.NET Core SignalR, MessagePack, xUnit, FluentAssertions

---

## File structure

### Shared contracts

- Modify: `src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs` — add the worker start command used by Gateway to instruct a specific worker to start a PTY-backed session.
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs` — verify the new command round-trips through MessagePack.

### Gateway

- Create: `src/Gateway/CortexTerminal.Gateway/Workers/IWorkerCommandDispatcher.cs` — abstraction for sending start/input/resize/close commands to a concrete worker connection id.
- Create: `src/Gateway/CortexTerminal.Gateway/Workers/SignalRWorkerCommandDispatcher.cs` — SignalR-backed dispatcher that targets `IHubContext<WorkerHub>`.
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs` — dispatch start on create and forward input/resize/close commands to the owning worker.
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/WorkerHub.cs` — accept worker callbacks for session start failure and session exit, update session state, clear replay where appropriate, and notify the attached client.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs` — add lifecycle methods for start failure and session exit.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs` — implement exit/failure transitions and optionally update stored dimensions on resize.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs` — store terminal lifecycle details needed by runtime dispatch and cleanup.
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs` — register the dispatcher.
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Workers/SignalRWorkerCommandDispatcherTests.cs` — verify each command targets only the selected worker connection.
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/WorkerHubTests.cs` — verify worker exit/start-failure callbacks.
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/TerminalHubWorkerDispatchTests.cs` — verify create/input/resize/close dispatch behavior.

### Worker

- Create: `src/Worker/CortexTerminal.Worker/Registration/IWorkerGatewayClient.cs` — narrow outbound/inbound adapter that hides raw `HubConnection` details from the runtime host.
- Modify: `src/Worker/CortexTerminal.Worker/Registration/WorkerGatewayClient.cs` — implement registration, reconnect, outbound forward methods, and inbound command subscriptions.
- Create: `src/Worker/CortexTerminal.Worker/Runtime/WorkerSessionRuntime.cs` — own one PTY process, pump stdout/stderr, forward exit, and support input/resize/close.
- Create: `src/Worker/CortexTerminal.Worker/Runtime/WorkerRuntimeHost.cs` — maintain the worker connection and a thread-safe session map.
- Modify: `src/Worker/CortexTerminal.Worker/Program.cs` — bootstrap the runtime host instead of exiting immediately.
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Registration/WorkerGatewayClientTests.cs` — verify registration and callback wiring with a fake hub client abstraction.
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerSessionRuntimeTests.cs` — verify PTY orchestration and forwarding.
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerRuntimeHostTests.cs` — verify start/input/resize/close dispatch, reconnect re-registration, and session tracking.

## Task 1: Add the worker start command contract

**Files:**
- Modify: `src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs`
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs`

- [ ] **Step 1: Write the failing contract serialization test**

```csharp
[Fact]
public void StartSessionCommand_RoundTrips_WithMessagePack()
{
    var command = new StartSessionCommand("sess_123", 120, 40);
    var bytes = MessagePackSerializer.Serialize(command);
    var clone = MessagePackSerializer.Deserialize<StartSessionCommand>(bytes);

    clone.Should().BeEquivalentTo(command);
}
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter StartSessionCommand_RoundTrips_WithMessagePack`

Expected: FAIL with `StartSessionCommand` not found.

- [ ] **Step 3: Add the new command**

```csharp
[MessagePackObject]
public sealed record StartSessionCommand(
    [property: Key(0)] string SessionId,
    [property: Key(1)] int Columns,
    [property: Key(2)] int Rows);
```

- [ ] **Step 4: Run the contract test again**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter StartSessionCommand_RoundTrips_WithMessagePack`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs
git commit -m "feat: add worker start session command"
```

## Task 2: Add Gateway worker command dispatch and lifecycle transitions

**Files:**
- Create: `src/Gateway/CortexTerminal.Gateway/Workers/IWorkerCommandDispatcher.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Workers/SignalRWorkerCommandDispatcher.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/WorkerHub.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Workers/SignalRWorkerCommandDispatcherTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/TerminalHubWorkerDispatchTests.cs`
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/WorkerHubTests.cs`

- [ ] **Step 1: Write the failing dispatcher test**

```csharp
[Fact]
public async Task StartSessionAsync_TargetsSelectedWorkerConnection()
{
    var clients = new RecordingHubClients();
    var dispatcher = new SignalRWorkerCommandDispatcher(new FakeHubContext<WorkerHub>(clients));

    await dispatcher.StartSessionAsync(
        "worker-conn-1",
        new StartSessionCommand("sess_123", 120, 40),
        CancellationToken.None);

    clients.Invocations.Should().ContainSingle();
    clients.Invocations[0].ConnectionId.Should().Be("worker-conn-1");
    clients.Invocations[0].Method.Should().Be("StartSession");
}
```

- [ ] **Step 2: Write the failing terminal hub dispatch test**

```csharp
[Fact]
public async Task CreateSession_DispatchesStartSessionToChosenWorker()
{
    var workers = new InMemoryWorkerRegistry();
    workers.Register("worker-1", "worker-conn-1");
    var sessions = new InMemorySessionCoordinator(workers);
    var replayCache = new ReplayCache(1024);
    var dispatcher = new RecordingWorkerCommandDispatcher();
    var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System, dispatcher);
    hub.Context = new TestHubCallerContext("client-1", "user-1");
    hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

    var result = await hub.CreateSession(new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

    result.IsSuccess.Should().BeTrue();
    dispatcher.StartCommands.Should().ContainSingle().Which.Should().BeEquivalentTo(
        new SentStartCommand("worker-conn-1", new StartSessionCommand(result.Response!.SessionId, 120, 40)));
}
```

- [ ] **Step 3: Write the failing worker callback test**

```csharp
[Fact]
public async Task SessionExited_ForAttachedSession_NotifiesClientAndMarksExited()
{
    var workers = new InMemoryWorkerRegistry();
    workers.Register("worker-1", "worker-conn-1");
    var sessions = new InMemorySessionCoordinator(workers);
    var replayCache = new ReplayCache(1024);
    var created = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
    var sessionId = created.Response!.SessionId;
    var client = new RecordingClientProxy();
    var hub = CreateWorkerHub(workers, sessions, replayCache);
    hub.Context = new TestHubCallerContext("worker-conn-1");
    hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
    {
        ["client-1"] = client
    });

    await hub.SessionExited(new SessionExited(sessionId, 0, "process-exited"));

    client.Invocations.Select(static x => x.Method).Should().Equal("SessionExited");
    sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
    session.AttachmentState.Should().Be(SessionAttachmentState.Exited);
}
```

- [ ] **Step 4: Run the focused gateway tests to verify they fail**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "StartSessionAsync_TargetsSelectedWorkerConnection|CreateSession_DispatchesStartSessionToChosenWorker|SessionExited_ForAttachedSession_NotifiesClientAndMarksExited"`

Expected: FAIL because `IWorkerCommandDispatcher`, `SignalRWorkerCommandDispatcher`, `TerminalHub` constructor overload, and `SessionExited` do not exist yet.

- [ ] **Step 5: Add the dispatcher abstraction**

```csharp
public interface IWorkerCommandDispatcher
{
    Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken);
    Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken);
    Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken);
    Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken);
}

public sealed class SignalRWorkerCommandDispatcher(IHubContext<WorkerHub> hubContext) : IWorkerCommandDispatcher
{
    public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("StartSession", command, cancellationToken);

    public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("WriteInput", frame, cancellationToken);

    public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("ResizeSession", request, cancellationToken);

    public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("CloseSession", request, cancellationToken);
}
```

- [ ] **Step 6: Thread dispatch through `TerminalHub`**

```csharp
public sealed class TerminalHub(
    ISessionCoordinator sessions,
    IReplayCache replayCache,
    TimeProvider timeProvider,
    IWorkerCommandDispatcher dispatcher) : Hub
{
    public async Task<CreateSessionResult> CreateSession(CreateSessionRequest request, CancellationToken cancellationToken)
    {
        var result = await sessions.CreateSessionAsync(Context.UserIdentifier ?? "unknown", request, Context.ConnectionId, cancellationToken);
        if (!result.IsSuccess || result.Response is null)
        {
            return result;
        }

        sessions.TryGetSession(result.Response.SessionId, out var session);
        await dispatcher.StartSessionAsync(
            session.WorkerConnectionId,
            new StartSessionCommand(result.Response.SessionId, request.Columns, request.Rows),
            cancellationToken);
        return result;
    }
}
```

- [ ] **Step 7: Add resize and close hub methods**

```csharp
public async Task ResizeSession(ResizePtyRequest request, CancellationToken cancellationToken)
{
    var session = RequireAttachedSession(request.SessionId);
    await dispatcher.ResizeSessionAsync(session.WorkerConnectionId, request, cancellationToken);
}

public async Task CloseSession(CloseSessionRequest request, CancellationToken cancellationToken)
{
    var session = RequireAttachedSession(request.SessionId);
    await dispatcher.CloseSessionAsync(session.WorkerConnectionId, request, cancellationToken);
}
```

- [ ] **Step 8: Add session lifecycle transitions**

```csharp
public interface ISessionCoordinator
{
    void MarkReplayCompleted(string sessionId, string clientConnectionId);
    bool TryMarkStartFailed(string sessionId, string workerConnectionId);
    bool TryMarkExited(string sessionId, string workerConnectionId, int exitCode, string reason, out SessionRecord session);
}
```

```csharp
public sealed record SessionRecord(
    string SessionId,
    string UserId,
    string WorkerId,
    string WorkerConnectionId,
    int Columns,
    int Rows,
    SessionAttachmentState AttachmentState = SessionAttachmentState.Attached,
    string? AttachedClientConnectionId = null,
    DateTimeOffset? LeaseExpiresAtUtc = null,
    bool ReplayPending = false,
    int? ExitCode = null,
    string? ExitReason = null);
```

- [ ] **Step 9: Add worker callback hub methods**

```csharp
public async Task SessionStartFailed(SessionStartFailedEvent frame)
{
    if (!sessions.TryMarkStartFailed(frame.SessionId, Context.ConnectionId))
    {
        return;
    }
}

public async Task SessionExited(SessionExited frame)
{
    if (!sessions.TryMarkExited(frame.SessionId, Context.ConnectionId, frame.ExitCode, frame.Reason, out var session))
    {
        return;
    }

    replayCache.Clear(frame.SessionId);
    if (session.AttachedClientConnectionId is not null)
    {
        await Clients.Client(session.AttachedClientConnectionId).SendAsync("SessionExited", frame, Context.ConnectionAborted);
    }
}
```

- [ ] **Step 10: Register the dispatcher**

```csharp
builder.Services.AddSingleton<IWorkerCommandDispatcher, SignalRWorkerCommandDispatcher>();
```

- [ ] **Step 11: Run the focused gateway tests again**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "StartSessionAsync_TargetsSelectedWorkerConnection|CreateSession_DispatchesStartSessionToChosenWorker|SessionExited_ForAttachedSession_NotifiesClientAndMarksExited"`

Expected: PASS.

- [ ] **Step 12: Run the full gateway suite**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`

Expected: PASS.

- [ ] **Step 13: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway src/Shared/CortexTerminal.Contracts tests/Gateway/CortexTerminal.Gateway.Tests
git commit -m "feat: dispatch worker session commands"
```

## Task 3: Implement the Worker runtime host and session runtime

**Files:**
- Create: `src/Worker/CortexTerminal.Worker/Registration/IWorkerGatewayClient.cs`
- Modify: `src/Worker/CortexTerminal.Worker/Registration/WorkerGatewayClient.cs`
- Create: `src/Worker/CortexTerminal.Worker/Runtime/WorkerSessionRuntime.cs`
- Create: `src/Worker/CortexTerminal.Worker/Runtime/WorkerRuntimeHost.cs`
- Modify: `src/Worker/CortexTerminal.Worker/Program.cs`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Registration/WorkerGatewayClientTests.cs`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerSessionRuntimeTests.cs`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerRuntimeHostTests.cs`

- [ ] **Step 1: Write the failing worker session runtime test**

```csharp
[Fact]
public async Task StartAsync_ForwardsStdoutStderrAndExit()
{
    var gateway = new RecordingWorkerGatewayClient();
    var host = new FakePtyHost(stdout: [0x6F, 0x6B], stderr: [0x62], exitCode: 7);
    var runtime = new WorkerSessionRuntime(
        "sess_1",
        new PtySession(host, new ScrollbackBuffer(1024)),
        gateway);

    await runtime.StartAsync(120, 40, CancellationToken.None);
    await runtime.Completion;

    gateway.Stdout.Should().ContainSingle();
    gateway.Stderr.Should().ContainSingle();
    gateway.Exits.Should().ContainSingle().Which.Should().BeEquivalentTo(new SessionExited("sess_1", 7, "process-exited"));
}
```

- [ ] **Step 2: Write the failing worker host test**

```csharp
[Fact]
public async Task StartAsync_RegistersWorkerAndHandlesInboundCommands()
{
    var gateway = new FakeWorkerGatewayClient();
    var ptyHost = new FakePtyHost(stdout: [], stderr: [], exitCode: 0);
    var runtimeHost = new WorkerRuntimeHost("worker-1", gateway, () => ptyHost);

    await runtimeHost.StartAsync(CancellationToken.None);
    await gateway.RaiseStartSessionAsync(new StartSessionCommand("sess_1", 120, 40));
    await gateway.RaiseWriteInputAsync(new WriteInputFrame("sess_1", [0x41]));
    await gateway.RaiseResizeSessionAsync(new ResizePtyRequest("sess_1", 140, 50));
    await gateway.RaiseCloseSessionAsync(new CloseSessionRequest("sess_1"));

    gateway.RegisteredWorkerIds.Should().Equal("worker-1");
    ptyHost.CreatedProcesses.Should().ContainSingle();
    ptyHost.CreatedProcesses[0].WrittenData.Should().ContainSingle().Which.Should().Equal([0x41]);
    ptyHost.CreatedProcesses[0].LastColumns.Should().Be(140);
    ptyHost.CreatedProcesses[0].LastRows.Should().Be(50);
}
```

- [ ] **Step 3: Run the focused worker tests to verify they fail**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter "StartAsync_ForwardsStdoutStderrAndExit|StartAsync_RegistersWorkerAndHandlesInboundCommands"`

Expected: FAIL because `WorkerSessionRuntime`, `WorkerRuntimeHost`, and the richer gateway client contract do not exist yet.

- [ ] **Step 4: Add the runtime-facing gateway client abstraction**

```csharp
public interface IWorkerGatewayClient : IAsyncDisposable
{
    Task StartAsync(CancellationToken cancellationToken);
    Task RegisterAsync(string workerId, CancellationToken cancellationToken);
    void OnStartSession(Func<StartSessionCommand, CancellationToken, Task> handler);
    void OnWriteInput(Func<WriteInputFrame, CancellationToken, Task> handler);
    void OnResizeSession(Func<ResizePtyRequest, CancellationToken, Task> handler);
    void OnCloseSession(Func<CloseSessionRequest, CancellationToken, Task> handler);
    Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken);
    Task ForwardStderrAsync(TerminalChunk chunk, CancellationToken cancellationToken);
    Task ForwardExitedAsync(SessionExited exited, CancellationToken cancellationToken);
    Task ForwardStartFailedAsync(SessionStartFailedEvent failed, CancellationToken cancellationToken);
}
```

- [ ] **Step 5: Implement `WorkerGatewayClient` on top of `HubConnection`**

```csharp
public sealed class WorkerGatewayClient(HubConnection connection) : IWorkerGatewayClient
{
    public Task StartAsync(CancellationToken cancellationToken) => connection.StartAsync(cancellationToken);

    public Task RegisterAsync(string workerId, CancellationToken cancellationToken)
        => connection.InvokeAsync("RegisterWorker", workerId, cancellationToken);

    public void OnStartSession(Func<StartSessionCommand, CancellationToken, Task> handler)
        => connection.On<StartSessionCommand>("StartSession", command => handler(command, CancellationToken.None));

    public Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken)
        => connection.InvokeAsync("ForwardStdout", chunk, cancellationToken);
}
```

- [ ] **Step 6: Implement `WorkerSessionRuntime`**

```csharp
public sealed class WorkerSessionRuntime
{
    public Task Completion => _completion.Task;

    public async Task StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        _process = await _session.StartAsync(_sessionId, columns, rows, cancellationToken);
        _stdoutTask = PumpAsync(_session.ReadStdoutChunksAsync(_sessionId, cancellationToken), gateway.ForwardStdoutAsync, cancellationToken);
        _stderrTask = PumpAsync(_session.ReadStderrChunksAsync(_sessionId, cancellationToken), gateway.ForwardStderrAsync, cancellationToken);
        _exitTask = WatchExitAsync(cancellationToken);
    }
}
```

- [ ] **Step 7: Implement `WorkerRuntimeHost`**

```csharp
public sealed class WorkerRuntimeHost
{
    private readonly ConcurrentDictionary<string, WorkerSessionRuntime> _sessions = new();

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        gateway.OnStartSession(HandleStartSessionAsync);
        gateway.OnWriteInput(HandleWriteInputAsync);
        gateway.OnResizeSession(HandleResizeSessionAsync);
        gateway.OnCloseSession(HandleCloseSessionAsync);

        await gateway.StartAsync(cancellationToken);
        await gateway.RegisterAsync(workerId, cancellationToken);
    }
}
```

- [ ] **Step 8: Replace the Program stub with runtime bootstrap**

```csharp
await WorkerHost.RunAsync();

static class WorkerHost
{
    public static async Task RunAsync()
    {
        var gatewayUrl = Environment.GetEnvironmentVariable("CORTEX_GATEWAY_URL") ?? "http://localhost:5000";
        var workerId = Environment.GetEnvironmentVariable("CORTEX_WORKER_ID") ?? Environment.MachineName;
        var connection = new HubConnectionBuilder()
            .WithUrl($"{gatewayUrl.TrimEnd('/')}/hubs/worker")
            .AddMessagePackProtocol()
            .WithAutomaticReconnect()
            .Build();

        await using var gatewayClient = new WorkerGatewayClient(connection);
        var runtimeHost = new WorkerRuntimeHost(workerId, gatewayClient, () => new UnixPtyHost());
        await runtimeHost.StartAsync(CancellationToken.None);
        await Task.Delay(Timeout.InfiniteTimeSpan);
    }
}
```

- [ ] **Step 9: Run the focused worker tests again**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter "StartAsync_ForwardsStdoutStderrAndExit|StartAsync_RegistersWorkerAndHandlesInboundCommands"`

Expected: PASS.

- [ ] **Step 10: Run the full worker suite**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add src/Worker/CortexTerminal.Worker tests/Worker/CortexTerminal.Worker.Tests
git commit -m "feat: add worker runtime host"
```

## Task 4: Verify Gateway and Worker work together for local debugging

**Files:**
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/ReattachSessionFlowTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/WorkerRuntimeDispatchFlowTests.cs`

- [ ] **Step 1: Write the failing integration test for create-to-exit flow**

```csharp
[Fact]
public async Task CreateSession_WorkerExitAndClientNotification_FlowThroughGateway()
{
    var services = _factory.Services;
    var registry = services.GetRequiredService<IWorkerRegistry>();
    registry.Register("worker-1", "worker-conn-1");
    var dispatcher = services.GetRequiredService<RecordingWorkerCommandDispatcher>();
    var hub = ActivatorUtilities.CreateInstance<TerminalHub>(services);
    hub.Context = new TestHubCallerContext("client-1", "user-1");
    hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

    var created = await hub.CreateSession(new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

    dispatcher.StartCommands.Should().ContainSingle();
    created.IsSuccess.Should().BeTrue();
}
```

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter CreateSession_WorkerExitAndClientNotification_FlowThroughGateway`

Expected: FAIL until the new dispatcher is wired into the application test host.

- [ ] **Step 3: Wire the test host and integration assertions**

```csharp
services.RemoveAll<IWorkerCommandDispatcher>();
services.AddSingleton<RecordingWorkerCommandDispatcher>();
services.AddSingleton<IWorkerCommandDispatcher>(sp => sp.GetRequiredService<RecordingWorkerCommandDispatcher>());
```

```csharp
dispatcher.StartCommands.Should().ContainSingle();
await workerHub.SessionExited(new SessionExited(sessionId, 0, "process-exited"));
client.Invocations.Select(static x => x.Method).Should().Contain("SessionExited");
```

- [ ] **Step 4: Run the full Gateway and Worker suites**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj && dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`

Expected: PASS.

- [ ] **Step 5: Perform the local debugging smoke run**

Run:

```bash
CORTEX_GATEWAY_URL=http://localhost:5000 dotnet run --project src/Gateway/CortexTerminal.Gateway &
CORTEX_GATEWAY_URL=http://localhost:5000 CORTEX_WORKER_ID=worker-local dotnet run --project src/Worker/CortexTerminal.Worker &
```

Then verify:

1. Worker process stays alive.
2. Gateway logs worker registration.
3. Creating a session dispatches `StartSession`.
4. Typing input produces `StdoutChunk`.
5. Detach/reattach still replays buffered output.

- [ ] **Step 6: Commit**

```bash
git add tests/Gateway/CortexTerminal.Gateway.Tests
git commit -m "test: verify worker runtime gateway flow"
```
