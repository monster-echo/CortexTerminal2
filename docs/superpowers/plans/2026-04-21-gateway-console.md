# Gateway Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a React-based Gateway console with development login, session-first navigation, worker inspection pages, and SignalR-backed terminal session entry for local end-to-end testing.

**Architecture:** Keep Gateway as the control plane and add development-only HTTP endpoints for login and user-scoped session/worker queries. Keep live terminal behavior on `TerminalHub` over SignalR, while reorganizing the Web frontend into page-level React routes with isolated services, pages, and terminal logic.

**Tech Stack:** .NET 10, ASP.NET Core, SignalR, xUnit, FluentAssertions, React, TypeScript, Vitest

---

## File structure

### Shared contracts

- Create: `src/Shared/CortexTerminal.Contracts/Auth/DevLoginDtos.cs` — request/response DTOs for development login.
- Create: `src/Shared/CortexTerminal.Contracts/Console/ConsoleDtos.cs` — session summary, worker summary, and detail DTOs used by the console HTTP APIs.

### Gateway

- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs` — register development login endpoint and user-scoped session/worker query endpoints.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs` — persist timestamps needed by the console summaries.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs` — expose user-scoped session query methods.
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs` — implement session summary/detail queries and timestamp updates.
- Modify: `src/Gateway/CortexTerminal.Gateway/Workers/IWorkerRegistry.cs` — expose user-scoped worker query methods.
- Modify: `src/Gateway/CortexTerminal.Gateway/Workers/InMemoryWorkerRegistry.cs` — track worker ownership, online state, and last-seen timestamps.
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DevLoginEndpointTests.cs` — cover development login behavior.
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Console/ConsoleQueryEndpointTests.cs` — cover `/api/me/sessions`, `/api/me/workers`, and worker/session ownership boundaries.

### Web frontend

- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/App.tsx` — replace single terminal view with routed page shell.
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionListPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionDetailPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerListPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerDetailPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/AppLayout.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/SessionList.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerList.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/services/auth.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/services/consoleApi.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/services/terminalGateway.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx` — consume routed session state instead of being the entire app.
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts` — support routed session bootstrap while preserving replay/reattach semantics.
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/console/consoleApp.ts` — token storage, route helpers, and page bootstrap wiring.
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/console/consoleApp.spec.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionPages.spec.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerPages.spec.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx`

## Task 1: Add development login and console query contracts

**Files:**
- Create: `src/Shared/CortexTerminal.Contracts/Auth/DevLoginDtos.cs`
- Create: `src/Shared/CortexTerminal.Contracts/Console/ConsoleDtos.cs`
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs`

- [ ] **Step 1: Write the failing contract serialization tests**

```csharp
[Fact]
public void DevLoginRequest_RoundTrips()
{
    var frame = new DevLoginRequest("alice");
    var clone = RoundTrip(frame);

    clone.Should().Be(frame);
}

[Fact]
public void SessionSummaryDto_RoundTrips()
{
    var frame = new SessionSummaryDto("sess-1", "worker-1", "live", DateTimeOffset.Parse("2026-04-21T00:00:00Z"), DateTimeOffset.Parse("2026-04-21T00:05:00Z"));
    var clone = RoundTrip(frame);

    clone.Should().Be(frame);
}
```

- [ ] **Step 2: Run the contract tests to verify they fail**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "DevLoginRequest_RoundTrips|SessionSummaryDto_RoundTrips"`

Expected: FAIL with `DevLoginRequest` and `SessionSummaryDto` not found.

- [ ] **Step 3: Add the auth and console DTOs**

```csharp
[MessagePackObject]
public sealed record DevLoginRequest(
    [property: Key(0)] string Username);

[MessagePackObject]
public sealed record DevLoginResponse(
    [property: Key(0)] string AccessToken,
    [property: Key(1)] string Username);

[MessagePackObject]
public sealed record SessionSummaryDto(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string WorkerId,
    [property: Key(2)] string Status,
    [property: Key(3)] DateTimeOffset CreatedAt,
    [property: Key(4)] DateTimeOffset LastActivityAt);
```

```csharp
[MessagePackObject]
public sealed record WorkerSummaryDto(
    [property: Key(0)] string WorkerId,
    [property: Key(1)] string DisplayName,
    [property: Key(2)] bool IsOnline,
    [property: Key(3)] int SessionCount,
    [property: Key(4)] DateTimeOffset? LastSeenAt);

[MessagePackObject]
public sealed record WorkerDetailDto(
    [property: Key(0)] WorkerSummaryDto Worker,
    [property: Key(1)] IReadOnlyList<SessionSummaryDto> Sessions);
```

- [ ] **Step 4: Run the contract tests again**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "DevLoginRequest_RoundTrips|SessionSummaryDto_RoundTrips"`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Shared/CortexTerminal.Contracts/Auth/DevLoginDtos.cs src/Shared/CortexTerminal.Contracts/Console/ConsoleDtos.cs tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs
git commit -m "feat: add gateway console contracts"
```

## Task 2: Add Gateway development login and user-scoped console APIs

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Workers/IWorkerRegistry.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Workers/InMemoryWorkerRegistry.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DevLoginEndpointTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Console/ConsoleQueryEndpointTests.cs`

- [ ] **Step 1: Write the failing development login test**

```csharp
[Fact]
public async Task DevLogin_InDevelopment_ReturnsBearerTokenForNamedUser()
{
    using var factory = new GatewayApplicationFactory();
    using var client = factory.CreateClient();

    using var response = await client.PostAsJsonAsync("/api/dev/login", new DevLoginRequest("alice"));

    response.StatusCode.Should().Be(HttpStatusCode.OK);
    var payload = await response.Content.ReadFromJsonAsync<DevLoginResponse>();
    payload!.Username.Should().Be("alice");
    payload.AccessToken.Should().NotBeNullOrWhiteSpace();
}
```

- [ ] **Step 2: Write the failing session query ownership test**

```csharp
[Fact]
public async Task GetMySessions_ReturnsOnlyCurrentUsersSessions()
{
    using var factory = new GatewayApplicationFactory();
    var sessions = factory.Services.GetRequiredService<ISessionCoordinator>();
    var registry = factory.Services.GetRequiredService<IWorkerRegistry>();
    registry.Register("worker-1", "worker-conn-1", "alice");
    registry.Register("worker-2", "worker-conn-2", "bob");
    await sessions.CreateSessionAsync("alice", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None);
    await sessions.CreateSessionAsync("bob", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None);

    using var client = factory.CreateAuthenticatedClient("alice");
    var result = await client.GetFromJsonAsync<IReadOnlyList<SessionSummaryDto>>("/api/me/sessions");

    result.Should().HaveCount(1);
    result![0].WorkerId.Should().Be("worker-1");
}
```

- [ ] **Step 3: Run the focused Gateway tests to verify they fail**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "DevLogin_InDevelopment_ReturnsBearerTokenForNamedUser|GetMySessions_ReturnsOnlyCurrentUsersSessions"`

Expected: FAIL because `/api/dev/login`, `/api/me/sessions`, and user-scoped registry/query APIs do not exist yet.

- [ ] **Step 4: Extend worker and session storage for console queries**

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
    string? ExitReason = null,
    DateTimeOffset CreatedAtUtc = default,
    DateTimeOffset LastActivityAtUtc = default);
```

```csharp
public interface IWorkerRegistry
{
    void Register(string workerId, string connectionId, string ownerUserId);
    bool TryGetLeastBusy(string ownerUserId, out RegisteredWorker worker);
    IReadOnlyList<RegisteredWorker> GetWorkersForUser(string ownerUserId);
}
```

- [ ] **Step 5: Add development login and console query endpoints**

```csharp
app.MapPost("/api/dev/login", (DevLoginRequest request) =>
{
    var username = request.Username.Trim();
    if (string.IsNullOrWhiteSpace(username))
    {
        return Results.BadRequest();
    }

    var token = tokenIssuer.Create(username);
    return Results.Ok(new DevLoginResponse(token, username));
});
```

```csharp
app.MapGet("/api/me/sessions", (ISessionCoordinator sessions, ClaimsPrincipal user) =>
    Results.Ok(sessions.GetSessionsForUser(user.Identity!.Name!)))
    .RequireAuthorization();

app.MapGet("/api/me/workers", (IWorkerRegistry workers, ClaimsPrincipal user) =>
    Results.Ok(workers.GetWorkersForUser(user.Identity!.Name!).Select(ConsoleProjection.ToSummary)))
    .RequireAuthorization();
```

- [ ] **Step 6: Run the focused Gateway tests again**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "DevLogin_InDevelopment_ReturnsBearerTokenForNamedUser|GetMySessions_ReturnsOnlyCurrentUsersSessions"`

Expected: PASS.

- [ ] **Step 7: Run the full Gateway suite**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway src/Shared/CortexTerminal.Contracts tests/Gateway/CortexTerminal.Gateway.Tests
git commit -m "feat: add gateway console query APIs"
```

## Task 3: Build the React console shell and page routing

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/App.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionListPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionDetailPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerListPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerDetailPage.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/AppLayout.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/SessionList.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerList.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/services/auth.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/services/consoleApi.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/console/consoleApp.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/console/consoleApp.spec.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionPages.spec.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerPages.spec.tsx`

- [ ] **Step 1: Write the failing console routing test**

```tsx
it("routes authenticated users to the session list page", () => {
  const app = createConsoleApp({
    tokenStore: { get: () => "token", set: vi.fn(), clear: vi.fn() },
    authApi: { login: vi.fn() },
    consoleApi: fakeConsoleApi(),
    terminalGateway: fakeTerminalGateway(),
  })

  render(app.render("/sessions"))

  expect(screen.getByRole("heading", { name: "My Sessions" })).toBeInTheDocument()
})
```

- [ ] **Step 2: Write the failing login-page test**

```tsx
it("logs in with a username and redirects to sessions", async () => {
  const login = vi.fn().mockResolvedValue({ accessToken: "token", username: "alice" })
  const app = createConsoleApp({
    tokenStore: memoryTokenStore(),
    authApi: { login },
    consoleApi: fakeConsoleApi(),
    terminalGateway: fakeTerminalGateway(),
  })

  render(app.render("/login"))
  await userEvent.type(screen.getByLabelText("Username"), "alice")
  await userEvent.click(screen.getByRole("button", { name: "Sign in" }))

  expect(login).toHaveBeenCalledWith("alice")
  expect(await screen.findByRole("heading", { name: "My Sessions" })).toBeInTheDocument()
})
```

- [ ] **Step 3: Run the focused web tests to verify they fail**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run LoginPage.spec.tsx consoleApp.spec.ts SessionPages.spec.tsx WorkerPages.spec.tsx`

Expected: FAIL because the routing shell, pages, and services do not exist yet.

- [ ] **Step 4: Add the console shell and service boundaries**

```ts
export function createConsoleApp(deps: ConsoleAppDeps) {
  return {
    render(initialPath = "/sessions") {
      return (
        <MemoryRouter initialEntries={[initialPath]}>
          <AppRoutes deps={deps} />
        </MemoryRouter>
      )
    },
  }
}
```

```tsx
export function App() {
  return createConsoleApp(defaultConsoleDeps()).render()
}
```

- [ ] **Step 5: Add the page components**

```tsx
export function SessionListPage({ sessions, onOpenSession }: SessionListPageProps) {
  return (
    <AppLayout>
      <h1>My Sessions</h1>
      <SessionList sessions={sessions} onOpenSession={onOpenSession} />
    </AppLayout>
  )
}
```

```tsx
export function WorkerListPage({ workers, onOpenWorker }: WorkerListPageProps) {
  return (
    <AppLayout>
      <h1>My Workers</h1>
      <WorkerList workers={workers} onOpenWorker={onOpenWorker} />
    </AppLayout>
  )
}
```

- [ ] **Step 6: Run the focused web tests again**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run LoginPage.spec.tsx consoleApp.spec.ts SessionPages.spec.tsx WorkerPages.spec.tsx`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/App.tsx src/Mobile/CortexTerminal.Mobile/Web/src/pages src/Mobile/CortexTerminal.Mobile/Web/src/components src/Mobile/CortexTerminal.Mobile/Web/src/services src/Mobile/CortexTerminal.Mobile/Web/src/console
git commit -m "feat: add gateway console page shell"
```

## Task 4: Wire session detail to SignalR terminal flow and worker drill-down

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/services/terminalGateway.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionDetailPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerDetailPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/GatewayConsoleFlowTests.cs`

- [ ] **Step 1: Write the failing session-detail flow test**

```tsx
it("loads a session detail page and forwards terminal input through the terminal gateway", async () => {
  const terminalGateway = fakeTerminalGateway()
  const app = createConsoleApp({
    tokenStore: { get: () => "token", set: vi.fn(), clear: vi.fn() },
    authApi: { login: vi.fn() },
    consoleApi: fakeConsoleApi({
      getSession: vi.fn().mockResolvedValue({ sessionId: "sess-1", workerId: "worker-1", status: "live", createdAt: "", lastActivityAt: "" }),
    }),
    terminalGateway,
  })

  render(app.render("/sessions/sess-1"))
  await userEvent.click(await screen.findByRole("button", { name: "send-tab" }))

  expect(terminalGateway.connect).toHaveBeenCalledWith("sess-1", "token")
  expect(terminalGateway.writeInput).toHaveBeenCalled()
})
```

- [ ] **Step 2: Write the failing worker-detail drill-down test**

```tsx
it("shows worker sessions and links to session detail", async () => {
  const app = createConsoleApp({
    tokenStore: { get: () => "token", set: vi.fn(), clear: vi.fn() },
    authApi: { login: vi.fn() },
    consoleApi: fakeConsoleApi({
      getWorker: vi.fn().mockResolvedValue({
        worker: { workerId: "worker-1", displayName: "worker-1", isOnline: true, sessionCount: 1, lastSeenAt: "2026-04-21T00:00:00Z" },
        sessions: [{ sessionId: "sess-1", workerId: "worker-1", status: "live", createdAt: "", lastActivityAt: "" }],
      }),
    }),
    terminalGateway: fakeTerminalGateway(),
  })

  render(app.render("/workers/worker-1"))

  expect(await screen.findByRole("link", { name: "sess-1" })).toHaveAttribute("href", "/sessions/sess-1")
})
```

- [ ] **Step 3: Run the focused web tests to verify they fail**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run useTerminalSession.spec.ts SessionPages.spec.tsx WorkerPages.spec.tsx`

Expected: FAIL because session detail terminal gateway wiring and worker drill-down do not exist yet.

- [ ] **Step 4: Add terminal gateway wiring**

```ts
export interface TerminalGateway {
  connect(sessionId: string, accessToken: string): Promise<void>
  writeInput(payload: Uint8Array): void
  detach(sessionId: string): Promise<void>
  reattach(sessionId: string): Promise<void>
}
```

```tsx
export function SessionDetailPage({ session, terminalGateway, accessToken }: SessionDetailPageProps) {
  useEffect(() => {
    void terminalGateway.connect(session.sessionId, accessToken)
  }, [session.sessionId, accessToken, terminalGateway])

  return <TerminalView writeInput={terminalGateway.writeInput} />
}
```

- [ ] **Step 5: Add the Gateway integration flow test**

```csharp
[Fact]
public async Task GetMyWorkersAndSessions_ReturnsOnlyOwnedResources()
{
    using var factory = new GatewayApplicationFactory();
    var workers = factory.Services.GetRequiredService<IWorkerRegistry>();
    var sessions = factory.Services.GetRequiredService<ISessionCoordinator>();
    workers.Register("worker-a", "conn-a", "alice");
    workers.Register("worker-b", "conn-b", "bob");
    await sessions.CreateSessionAsync("alice", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None);
    await sessions.CreateSessionAsync("bob", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None);

    using var client = factory.CreateAuthenticatedClient("alice");
    var workerDtos = await client.GetFromJsonAsync<IReadOnlyList<WorkerSummaryDto>>("/api/me/workers");
    var sessionDtos = await client.GetFromJsonAsync<IReadOnlyList<SessionSummaryDto>>("/api/me/sessions");

    workerDtos.Should().ContainSingle(x => x.WorkerId == "worker-a");
    sessionDtos.Should().ContainSingle();
}
```

- [ ] **Step 6: Run the focused tests again**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run useTerminalSession.spec.ts SessionPages.spec.tsx WorkerPages.spec.tsx && cd /Volumes/MacMiniDisk/workspace/CortexTerminal2 && dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter GatewayConsoleFlowTests`

Expected: PASS.

- [ ] **Step 7: Run the full verification matrix**

Run: `cd /Volumes/MacMiniDisk/workspace/CortexTerminal2 && dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj && dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj && dotnet test tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj && cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/terminal src/Mobile/CortexTerminal.Mobile/Web/src/services/terminalGateway.ts src/Mobile/CortexTerminal.Mobile/Web/src/pages tests/Gateway/CortexTerminal.Gateway.Tests/Integration/GatewayConsoleFlowTests.cs
git commit -m "feat: wire gateway console session flows"
```
