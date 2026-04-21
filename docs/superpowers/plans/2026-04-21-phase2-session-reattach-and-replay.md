# Phase 2 Session Reattach and Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a shell session alive for 5 minutes after client disconnect, allow the same user to reattach to the same session, and replay a bounded recent scrollback before resuming live terminal streaming.

**Architecture:** Keep the existing Gateway-centered topology. The Gateway owns detach leases, single-client attach policy, and reattach authorization; the Worker keeps the PTY process alive; the Gateway mirrors a bounded replay cache from already-forwarded worker output so reattach does not require a new server-to-worker RPC shape in this first slice. Reattach remains authenticated and single-client, and all live terminal traffic continues over SignalR.

**Tech Stack:** .NET 10, ASP.NET Core SignalR, MessagePack, xUnit, FluentAssertions, Vitest, React, MAUI

---

## File structure

### Shared contracts

- Modify: `src/Shared/CortexTerminal.Contracts/Sessions/SessionDtos.cs` — add reattach request/result DTOs with MessagePack keys.
- Modify: `src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs` — add detach, reattach, replay, and expiry event frames.
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs` — extend serialization coverage for the new contracts.

### Gateway

- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionAttachmentState.cs` — explicit state enum for `Attached`, `DetachedGracePeriod`, `Expired`, `Exited`.
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/ReplayCache.cs` — bounded in-memory replay cache keyed by `sessionId`.
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/IReplayCache.cs` — abstraction for appending and reading replay chunks.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs` — add attachment state, lease expiration, and attached connection id.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs` — add detach, reattach, and expiry methods.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs` — implement lease lifecycle and single-client reattach checks.
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs` — add `DetachSession` and `ReattachSession`.
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/WorkerHub.cs` — append forwarded stdout/stderr to replay cache before fan-out.
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs` — register replay cache and lease expiration background service.
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/DetachedSessionExpiryService.cs` — periodically expires detached sessions older than 5 minutes.

### Worker

- Create: `src/Worker/CortexTerminal.Worker/Pty/ScrollbackBuffer.cs` — bounded FIFO chunk buffer that preserves raw bytes and stream identity.
- Modify: `src/Worker/CortexTerminal.Worker/Pty/PtySession.cs` — feed the scrollback buffer while enumerating stdout/stderr.
- Modify: `tests/Worker/CortexTerminal.Worker.Tests/Pty/PtySessionTests.cs` — add replay buffer assertions.
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Pty/ScrollbackBufferTests.cs` — eviction and ordering tests.

### Mobile / web

- Modify: `src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj` — add SignalR client package for detach / reattach hub calls.
- Modify: `src/Mobile/CortexTerminal.Mobile/Services/Terminal/TerminalGatewayClient.cs` — add detach and reattach helpers for the authenticated control surface.
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts` — add replay lifecycle handling and reconnect state transitions.
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx` — surface reconnecting / replaying UI state.
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts` — add reconnect and replay tests.

### Gateway integration tests

- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Sessions/ReplayCacheTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Sessions/ReattachSessionCoordinatorTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/TerminalHubReconnectTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/ReattachSessionFlowTests.cs`

## Task 1: Add shared detach / reattach / replay contracts

**Files:**
- Modify: `src/Shared/CortexTerminal.Contracts/Sessions/SessionDtos.cs`
- Modify: `src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs`
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs`

- [ ] **Step 1: Write the failing contract serialization tests**

```csharp
[Fact]
public void ReattachSessionRequest_RoundTrips_WithMessagePack()
{
    var request = new ReattachSessionRequest("sess_123");
    var bytes = MessagePackSerializer.Serialize(request);
    var clone = MessagePackSerializer.Deserialize<ReattachSessionRequest>(bytes);

    clone.SessionId.Should().Be("sess_123");
}

[Fact]
public void ReplayChunk_RoundTrips_WithRawBytes()
{
    var frame = new ReplayChunk("sess_123", "stdout", new byte[] { 0x1B, 0x5B, 0x41 });
    var bytes = MessagePackSerializer.Serialize(frame);
    var clone = MessagePackSerializer.Deserialize<ReplayChunk>(bytes);

    clone.SessionId.Should().Be("sess_123");
    clone.Stream.Should().Be("stdout");
    clone.Payload.Should().Equal(0x1B, 0x5B, 0x41);
}
```

- [ ] **Step 2: Run the contract tests to verify they fail**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "ReattachSessionRequest_RoundTrips_WithMessagePack|ReplayChunk_RoundTrips_WithRawBytes"`

Expected: FAIL with `ReattachSessionRequest` and `ReplayChunk` not found.

- [ ] **Step 3: Add the new session DTOs**

```csharp
[MessagePackObject]
public sealed record ReattachSessionRequest(
    [property: Key(0)] string SessionId);

[MessagePackObject]
public sealed record ReattachSessionResult(
    [property: Key(0)] bool IsSuccess,
    [property: Key(1)] string? ErrorCode)
{
    public static ReattachSessionResult Success() => new(true, null);
    public static ReattachSessionResult Failure(string errorCode) => new(false, errorCode);
}
```

- [ ] **Step 4: Add the new streaming frames**

```csharp
[MessagePackObject]
public sealed record SessionDetachedEvent(
    [property: Key(0)] string SessionId,
    [property: Key(1)] DateTimeOffset LeaseExpiresAtUtc);

[MessagePackObject]
public sealed record SessionReattachedEvent(
    [property: Key(0)] string SessionId);

[MessagePackObject]
public sealed record SessionExpiredEvent(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Reason);

[MessagePackObject]
public sealed record ReplayChunk(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Stream,
    [property: Key(2)] byte[] Payload);

[MessagePackObject]
public sealed record ReplayCompleted(
    [property: Key(0)] string SessionId);
```

- [ ] **Step 5: Run the contract tests again**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "ReattachSessionRequest_RoundTrips_WithMessagePack|ReplayChunk_RoundTrips_WithRawBytes"`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/Shared/CortexTerminal.Contracts tests/Gateway/CortexTerminal.Gateway.Tests/Contracts
git commit -m $'feat: add reconnect session contracts\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

## Task 2: Add gateway lease state and bounded replay cache

**Files:**
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionAttachmentState.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/IReplayCache.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/ReplayCache.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Sessions/ReplayCacheTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Sessions/ReattachSessionCoordinatorTests.cs`

- [ ] **Step 1: Write the failing replay cache tests**

```csharp
[Fact]
public void Append_WhenMaxBytesExceeded_EvictsOldestChunks()
{
    var cache = new ReplayCache(maxBytesPerSession: 4);

    cache.Append(new ReplayChunk("sess_1", "stdout", new byte[] { 0x41, 0x42 }));
    cache.Append(new ReplayChunk("sess_1", "stdout", new byte[] { 0x43, 0x44 }));
    cache.Append(new ReplayChunk("sess_1", "stderr", new byte[] { 0x45, 0x46 }));

    cache.GetSnapshot("sess_1")
        .Should()
        .ContainSingle()
        .Which.Payload.Should().Equal(0x45, 0x46);
}
```

- [ ] **Step 2: Write the failing coordinator tests**

```csharp
[Fact]
public async Task ReattachSessionAsync_WithValidLease_ReattachesSameUser()
{
    var workers = new InMemoryWorkerRegistry();
    workers.Register("worker-1", "worker-conn");
    var coordinator = new InMemorySessionCoordinator(workers);

    var create = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
    await coordinator.DetachSessionAsync("user-1", create.Response!.SessionId, DateTimeOffset.Parse("2026-04-21T00:00:00Z"), CancellationToken.None);

    var result = await coordinator.ReattachSessionAsync(
        "user-1",
        new ReattachSessionRequest(create.Response.SessionId),
        "mobile-conn-2",
        DateTimeOffset.Parse("2026-04-21T00:04:59Z"),
        CancellationToken.None);

    result.Should().Be(ReattachSessionResult.Success());
}
```

- [ ] **Step 3: Run the new gateway session tests to verify they fail**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "Append_WhenMaxBytesExceeded_EvictsOldestChunks|ReattachSessionAsync_WithValidLease_ReattachesSameUser"`

Expected: FAIL with `ReplayCache`, `DetachSessionAsync`, and `ReattachSessionAsync` not found.

- [ ] **Step 4: Add the attachment state enum and replay cache**

```csharp
public enum SessionAttachmentState
{
    Attached = 0,
    DetachedGracePeriod = 1,
    Expired = 2,
    Exited = 3
}

public interface IReplayCache
{
    void Append(ReplayChunk chunk);
    IReadOnlyList<ReplayChunk> GetSnapshot(string sessionId);
    void Clear(string sessionId);
}
```

```csharp
public sealed class ReplayCache(int maxBytesPerSession) : IReplayCache
{
    private readonly ConcurrentDictionary<string, LinkedList<ReplayChunk>> _chunks = new();
    private readonly ConcurrentDictionary<string, int> _sizes = new();

    public void Append(ReplayChunk chunk)
    {
        var list = _chunks.GetOrAdd(chunk.SessionId, _ => new LinkedList<ReplayChunk>());
        list.AddLast(chunk);
        _sizes.AddOrUpdate(chunk.SessionId, chunk.Payload.Length, (_, current) => current + chunk.Payload.Length);

        while (_sizes[chunk.SessionId] > maxBytesPerSession && list.First is not null)
        {
            var removed = list.First.Value;
            list.RemoveFirst();
            _sizes[chunk.SessionId] -= removed.Payload.Length;
        }
    }

    public IReadOnlyList<ReplayChunk> GetSnapshot(string sessionId)
        => _chunks.TryGetValue(sessionId, out var list) ? list.ToList() : [];

    public void Clear(string sessionId)
    {
        _chunks.TryRemove(sessionId, out _);
        _sizes.TryRemove(sessionId, out _);
    }
}
```

- [ ] **Step 5: Extend the session record and coordinator**

```csharp
public sealed record SessionRecord(
    string SessionId,
    string UserId,
    string WorkerId,
    string WorkerConnectionId,
    int Columns,
    int Rows,
    SessionAttachmentState AttachmentState,
    string? AttachedClientConnectionId,
    DateTimeOffset? LeaseExpiresAtUtc);
```

```csharp
Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken);
Task<ReattachSessionResult> ReattachSessionAsync(string userId, ReattachSessionRequest request, string clientConnectionId, DateTimeOffset nowUtc, CancellationToken cancellationToken);
IReadOnlyList<string> ExpireDetachedSessions(DateTimeOffset nowUtc);
```

```csharp
public async Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken)
{
    if (_sessions.TryGetValue(sessionId, out var session) && session.UserId == userId)
    {
        _sessions[sessionId] = session with
        {
            AttachmentState = SessionAttachmentState.DetachedGracePeriod,
            AttachedClientConnectionId = null,
            LeaseExpiresAtUtc = detachedAtUtc.AddMinutes(5)
        };
    }

    await Task.CompletedTask;
}
```

- [ ] **Step 6: Add the reattach / expiry rules**

```csharp
public Task<ReattachSessionResult> ReattachSessionAsync(string userId, ReattachSessionRequest request, string clientConnectionId, DateTimeOffset nowUtc, CancellationToken cancellationToken)
{
    if (!_sessions.TryGetValue(request.SessionId, out var session) || session.UserId != userId)
    {
        return Task.FromResult(ReattachSessionResult.Failure("session-not-found"));
    }

    if (session.AttachmentState == SessionAttachmentState.Attached)
    {
        return Task.FromResult(ReattachSessionResult.Failure("session-already-attached"));
    }

    if (session.LeaseExpiresAtUtc is null || session.LeaseExpiresAtUtc <= nowUtc)
    {
        _sessions[request.SessionId] = session with { AttachmentState = SessionAttachmentState.Expired };
        return Task.FromResult(ReattachSessionResult.Failure("session-expired"));
    }

    _sessions[request.SessionId] = session with
    {
        AttachmentState = SessionAttachmentState.Attached,
        AttachedClientConnectionId = clientConnectionId,
        LeaseExpiresAtUtc = null
    };

    return Task.FromResult(ReattachSessionResult.Success());
}
```

- [ ] **Step 7: Run the gateway session tests**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "Append_WhenMaxBytesExceeded_EvictsOldestChunks|ReattachSessionAsync_WithValidLease_ReattachesSameUser"`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway/Sessions tests/Gateway/CortexTerminal.Gateway.Tests/Sessions
git commit -m $'feat: add gateway detach lease state\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

## Task 3: Add SignalR detach / reattach flow in the gateway

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/WorkerHub.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/DetachedSessionExpiryService.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/TerminalHubReconnectTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/ReattachSessionFlowTests.cs`

- [ ] **Step 1: Write the failing hub reconnect test**

```csharp
[Fact]
public async Task ReattachSession_WhenLeaseIsValid_ReplaysBufferedChunks()
{
    var replay = new ReplayCache(4096);
    replay.Append(new ReplayChunk("sess_1", "stdout", new byte[] { 0x6C, 0x73 }));
    var workers = new InMemoryWorkerRegistry();
    workers.Register("worker-1", "worker-conn");
    var sessions = new InMemorySessionCoordinator(workers);
    var create = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
    await sessions.DetachSessionAsync("user-1", create.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);

    var hub = new TerminalHub(sessions, replay, TimeProvider.System);
    var caller = new RecordingClientProxy();
    hub.Context = TestHubContext.For(userIdentifier: "user-1", connectionId: "mobile-conn-2");
    hub.Clients = TestHubClients.WithCaller(caller);

    var result = await hub.ReattachSession(new ReattachSessionRequest(create.Response.SessionId), CancellationToken.None);

    result.Should().Be(ReattachSessionResult.Success());
    caller.Messages.Should().Contain(x => x.Method == "SessionReattached");
    caller.Messages.Should().Contain(x => x.Method == "ReplayChunk");
    caller.Messages.Should().Contain(x => x.Method == "ReplayCompleted");
}
```

- [ ] **Step 2: Write the failing integration test**

```csharp
[Fact]
public async Task ReattachSession_AfterDetach_ReturnsOkBeforeLeaseExpiry()
{
    using var app = new GatewayApplicationFactory();
    var registry = app.Services.GetRequiredService<IWorkerRegistry>();
    registry.Register("worker-integration-1", "worker-conn-1");

    var sessions = app.Services.GetRequiredService<ISessionCoordinator>();
    var create = await sessions.CreateSessionAsync("test-user", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
    await sessions.DetachSessionAsync("test-user", create.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);

    var result = await sessions.ReattachSessionAsync("test-user", new ReattachSessionRequest(create.Response.SessionId), "mobile-conn-2", DateTimeOffset.UtcNow.AddMinutes(1), CancellationToken.None);

    result.Should().Be(ReattachSessionResult.Success());
}
```

- [ ] **Step 3: Run the reconnect tests to verify they fail**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "ReattachSession_WhenLeaseIsValid_ReplaysBufferedChunks|ReattachSession_AfterDetach_ReturnsOkBeforeLeaseExpiry"`

Expected: FAIL because `TerminalHub` does not accept replay cache / time provider dependencies and does not expose detach / reattach methods.

- [ ] **Step 4: Extend the terminal hub**

```csharp
[Authorize]
public sealed class TerminalHub(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider) : Hub
{
    public async Task DetachSession(string sessionId, CancellationToken cancellationToken)
    {
        await sessions.DetachSessionAsync(Context.UserIdentifier ?? "unknown", sessionId, timeProvider.GetUtcNow(), cancellationToken);
        await Clients.Caller.SendAsync("SessionDetached", new SessionDetachedEvent(sessionId, timeProvider.GetUtcNow().AddMinutes(5)), cancellationToken);
    }

    public async Task<ReattachSessionResult> ReattachSession(ReattachSessionRequest request, CancellationToken cancellationToken)
    {
        var result = await sessions.ReattachSessionAsync(
            Context.UserIdentifier ?? "unknown",
            request,
            Context.ConnectionId,
            timeProvider.GetUtcNow(),
            cancellationToken);

        if (!result.IsSuccess)
        {
            return result;
        }

        await Clients.Caller.SendAsync("SessionReattached", new SessionReattachedEvent(request.SessionId), cancellationToken);

        foreach (var chunk in replayCache.GetSnapshot(request.SessionId))
        {
            await Clients.Caller.SendAsync("ReplayChunk", chunk, cancellationToken);
        }

        await Clients.Caller.SendAsync("ReplayCompleted", new ReplayCompleted(request.SessionId), cancellationToken);
        return result;
    }
}
```

- [ ] **Step 5: Mirror worker output into the replay cache**

```csharp
public sealed class WorkerHub(IWorkerRegistry workers, ISessionCoordinator sessions, IReplayCache replayCache) : Hub
{
    public async Task ForwardStdout(TerminalChunk chunk)
    {
        replayCache.Append(new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload));

        if (sessions.TryGetSession(chunk.SessionId, out var session) && session.AttachedClientConnectionId is not null)
        {
            await Clients.Client(session.AttachedClientConnectionId).SendAsync("StdoutChunk", chunk);
        }
    }

    public async Task ForwardStderr(TerminalChunk chunk)
    {
        replayCache.Append(new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload));

        if (sessions.TryGetSession(chunk.SessionId, out var session) && session.AttachedClientConnectionId is not null)
        {
            await Clients.Client(session.AttachedClientConnectionId).SendAsync("StderrChunk", chunk);
        }
    }
}
```

- [ ] **Step 6: Add detached session expiry service and DI**

```csharp
public sealed class DetachedSessionExpiryService(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            foreach (var sessionId in sessions.ExpireDetachedSessions(timeProvider.GetUtcNow()))
            {
                replayCache.Clear(sessionId);
            }

            await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken);
        }
    }
}
```

```csharp
builder.Services.AddSingleton<IReplayCache>(_ => new ReplayCache(64 * 1024));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddHostedService<DetachedSessionExpiryService>();
```

- [ ] **Step 7: Run the full gateway test suite**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`

Expected: PASS with the existing auth/session tests plus the new reconnect coverage.

- [ ] **Step 8: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway tests/Gateway/CortexTerminal.Gateway.Tests
git commit -m $'feat: add signalr session reattach flow\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

## Task 4: Add worker-side bounded scrollback buffering

**Files:**
- Create: `src/Worker/CortexTerminal.Worker/Pty/ScrollbackBuffer.cs`
- Modify: `src/Worker/CortexTerminal.Worker/Pty/PtySession.cs`
- Modify: `tests/Worker/CortexTerminal.Worker.Tests/Pty/PtySessionTests.cs`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Pty/ScrollbackBufferTests.cs`

- [ ] **Step 1: Write the failing scrollback buffer tests**

```csharp
[Fact]
public void Snapshot_PreservesOrderAcrossStreams()
{
    var buffer = new ScrollbackBuffer(maxBytes: 8);

    buffer.Append("stdout", new byte[] { 0x31, 0x0A });
    buffer.Append("stderr", new byte[] { 0x45, 0x31 });

    buffer.Snapshot().Select(x => x.Stream).Should().Equal("stdout", "stderr");
}
```

- [ ] **Step 2: Run the worker tests to verify they fail**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter Snapshot_PreservesOrderAcrossStreams`

Expected: FAIL with `ScrollbackBuffer` not found.

- [ ] **Step 3: Add the buffer implementation**

```csharp
public sealed class ScrollbackBuffer(int maxBytes)
{
    private readonly LinkedList<TerminalChunk> _chunks = [];
    private int _currentBytes;

    public void Append(string sessionId, string stream, byte[] payload)
    {
        var copy = payload.ToArray();
        _chunks.AddLast(new TerminalChunk(sessionId, stream, copy));
        _currentBytes += copy.Length;

        while (_currentBytes > maxBytes && _chunks.First is not null)
        {
            _currentBytes -= _chunks.First.Value.Payload.Length;
            _chunks.RemoveFirst();
        }
    }

    public IReadOnlyList<TerminalChunk> Snapshot() => _chunks.ToList();
}
```

- [ ] **Step 4: Feed the scrollback buffer from PtySession**

```csharp
public sealed class PtySession(IPtyHost host, ScrollbackBuffer scrollbackBuffer)
{
    public async IAsyncEnumerable<TerminalChunk> ReadStdoutChunksAsync(string sessionId, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        if (_process is null) yield break;

        await foreach (var data in _process.ReadStdoutAsync(cancellationToken))
        {
            scrollbackBuffer.Append(sessionId, "stdout", data);
            yield return new TerminalChunk(sessionId, "stdout", data);
        }
    }
}
```

- [ ] **Step 5: Extend the existing worker tests**

```csharp
[Fact]
public async Task StartAsync_CopiesStdoutIntoScrollbackBuffer()
{
    var fakeHost = new FakePtyHost(stdout: [0x6F, 0x6B], stderr: []);
    var buffer = new ScrollbackBuffer(1024);
    var session = new PtySession(fakeHost, buffer);

    await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
    await foreach (var _ in session.ReadStdoutChunksAsync("sess_1", CancellationToken.None)) { }

    buffer.Snapshot().Should().ContainSingle(x => x.Stream == "stdout" && x.SessionId == "sess_1");
}
```

- [ ] **Step 6: Run the worker test suite**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/Worker/CortexTerminal.Worker tests/Worker/CortexTerminal.Worker.Tests
git commit -m $'feat: add worker scrollback buffering\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

## Task 5: Add mobile and web reconnect behavior

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj`
- Modify: `src/Mobile/CortexTerminal.Mobile/Services/Terminal/TerminalGatewayClient.cs`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts`

- [ ] **Step 1: Write the failing web reconnect tests**

```ts
it("marks the terminal as replaying until replay completes", () => {
  const events: string[] = []
  const session = createTerminalSessionModel({
    writeInput: () => {},
    onStateChange: (value) => events.push(value),
  })

  session.onSessionReattached("sess_1")
  session.onReplayChunk(new Uint8Array([0x6C, 0x73]), "stdout")
  session.onReplayCompleted()

  expect(events).toEqual(["reattached", "replaying", "live"])
})
```

- [ ] **Step 2: Run the web tests to verify they fail**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npx vitest run src/terminal/useTerminalSession.spec.ts`

Expected: FAIL with `createTerminalSessionModel` or replay handlers not found.

- [ ] **Step 3: Add the SignalR client dependency**

```xml
<ItemGroup>
  <PackageReference Include="Microsoft.AspNetCore.SignalR.Client" Version="10.0.6" />
</ItemGroup>
```

- [ ] **Step 4: Extend the MAUI terminal client**

```csharp
public sealed class TerminalGatewayClient(HttpClient httpClient, HubConnection hubConnection)
{
    public async Task<CreateSessionResponse?> CreateSessionAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", columns, rows), cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<CreateSessionResponse>(cancellationToken: cancellationToken);
    }

    public Task DetachSessionAsync(string sessionId, CancellationToken cancellationToken)
        => hubConnection.InvokeAsync("DetachSession", sessionId, cancellationToken);

    public Task<ReattachSessionResult> ReattachSessionAsync(string sessionId, CancellationToken cancellationToken)
        => hubConnection.InvokeAsync<ReattachSessionResult>("ReattachSession", new ReattachSessionRequest(sessionId), cancellationToken);
}
```

- [ ] **Step 5: Add reconnect state to the web terminal hook**

```ts
type TerminalSessionState = "live" | "reattached" | "replaying" | "expired"

export function createTerminalSessionModel(deps: {
  writeInput: (payload: Uint8Array) => void
  onStateChange?: (state: TerminalSessionState) => void
}) {
  let state: TerminalSessionState = "live"

  return {
    onSessionReattached(sessionId: string) {
      state = "reattached"
      deps.onStateChange?.(state)
      return sessionId
    },
    onReplayChunk(payload: Uint8Array, stream: "stdout" | "stderr") {
      state = "replaying"
      deps.onStateChange?.(state)
      return { payload, stream }
    },
    onReplayCompleted() {
      state = "live"
      deps.onStateChange?.(state)
    },
    onSessionExpired() {
      state = "expired"
      deps.onStateChange?.(state)
    }
  }
}
```

- [ ] **Step 6: Surface reconnect status in the view**

```tsx
export function TerminalView({ writeInput }: { writeInput: (payload: Uint8Array) => void }) {
  const [status, setStatus] = useState<"live" | "reattached" | "replaying" | "expired">("live")
  const session = createTerminalSessionModel({ writeInput, onStateChange: setStatus })

  return (
    <div id="terminal-container">
      <div data-testid="terminal-status">{status}</div>
      <button onClick={() => session.onTerminalData("\t")}>send-tab</button>
    </div>
  )
}
```

- [ ] **Step 7: Run the web test suite**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npx vitest run`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj src/Mobile/CortexTerminal.Mobile/Services/Terminal src/Mobile/CortexTerminal.Mobile/Web/src/terminal
git commit -m $'feat: add client reconnect replay state\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

## Task 6: Run end-to-end reconnect verification

**Files:**
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/ReattachSessionFlowTests.cs`
- Modify: `tests/Worker/CortexTerminal.Worker.Tests/Pty/PtySessionTests.cs`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts`

- [ ] **Step 1: Write the final end-to-end reconnect assertions**

```csharp
[Fact]
public async Task DetachedSession_ReattachesWithinFiveMinutes_AndKeepsSameSessionId()
{
    using var app = new GatewayApplicationFactory();
    var workers = app.Services.GetRequiredService<IWorkerRegistry>();
    workers.Register("worker-integration-1", "worker-conn-1");

    var sessions = app.Services.GetRequiredService<ISessionCoordinator>();
    var create = await sessions.CreateSessionAsync("test-user", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

    await sessions.DetachSessionAsync("test-user", create.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);

    var result = await sessions.ReattachSessionAsync("test-user", new ReattachSessionRequest(create.Response.SessionId), "mobile-conn-2", DateTimeOffset.UtcNow.AddMinutes(2), CancellationToken.None);

    result.Should().Be(ReattachSessionResult.Success());
    sessions.TryGetSession(create.Response.SessionId, out var session).Should().BeTrue();
    session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
    session.AttachedClientConnectionId.Should().Be("mobile-conn-2");
}
```

- [ ] **Step 2: Run the full test matrix before the last implementation polish**

Run:

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj
dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj
dotnet test tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj
cd src/Mobile/CortexTerminal.Mobile/Web && npx vitest run
```

Expected: PASS.

- [ ] **Step 3: Apply the final consistency fixes**

```csharp
// Keep the same error codes everywhere:
// "session-not-found"
// "session-already-attached"
// "session-expired"
// "no-worker-available"
```

```ts
// Keep terminal states consistent across the hook and view:
// "live" | "reattached" | "replaying" | "expired"
```

- [ ] **Step 4: Run the full test matrix again**

Run:

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj
dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj
dotnet test tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj
cd src/Mobile/CortexTerminal.Mobile/Web && npx vitest run
```

Expected: PASS with gateway, worker, mobile, and web suites all green.

- [ ] **Step 5: Commit**

```bash
git add src tests
git commit -m $'feat: add phase2 session reattach and replay\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```
