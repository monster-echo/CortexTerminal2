# CortexTerminal Phase 1 Gateway Shell MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first end-to-end CortexTerminal slice: Device Flow login from mobile, Gateway-mediated session creation, and one interactive dual-stream PTY shell session on macOS and Linux workers.

**Architecture:** Use a Gateway-centered design with clear control-plane ownership. The Gateway handles auth, worker selection, session metadata, and SignalR routing; the Worker owns PTY execution and raw byte forwarding; the MAUI Hybrid mobile app owns token persistence, SignalR connectivity, and a React/xterm.js terminal UI behind a binary bridge.

**Tech Stack:** .NET 10, ASP.NET Core, OpenIddict, SignalR over HTTP/3, MessagePack, .NET MAUI HybridWebView, React, xterm.js, xUnit, Vitest

---

## File structure

### Solution and shared contracts

- Create: `CortexTerminal.sln` — solution root for Gateway, Worker, Mobile, and tests
- Create: `Directory.Build.props` — shared .NET settings and nullable/implicit using defaults
- Create: `.gitignore` — ignore .NET, MAUI, Node, and local brainstorm artifacts
- Create: `src/Shared/CortexTerminal.Contracts/CortexTerminal.Contracts.csproj` — shared protocol contracts
- Create: `src/Shared/CortexTerminal.Contracts/Auth/DeviceFlowDtos.cs` — device flow request/response types
- Create: `src/Shared/CortexTerminal.Contracts/Sessions/SessionDtos.cs` — session create/attach/close DTOs
- Create: `src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs` — stdout/stderr/input/message types and metadata events

### Gateway

- Create: `src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj`
- Create: `src/Gateway/CortexTerminal.Gateway/Program.cs` — app startup, OpenIddict, SignalR, MessagePack
- Create: `src/Gateway/CortexTerminal.Gateway/Auth/DeviceFlowController.cs` — device flow start and poll endpoints
- Create: `src/Gateway/CortexTerminal.Gateway/Auth/OpenIddictSetup.cs` — OpenIddict registration
- Create: `src/Gateway/CortexTerminal.Gateway/Workers/IWorkerRegistry.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Workers/InMemoryWorkerRegistry.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs` — authenticated session hub
- Create: `src/Gateway/CortexTerminal.Gateway/Hubs/WorkerHub.cs` — worker registration and worker stream channel

### Worker

- Create: `src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj`
- Create: `src/Worker/CortexTerminal.Worker/Program.cs` — worker startup and Gateway connection
- Create: `src/Worker/CortexTerminal.Worker/Registration/WorkerGatewayClient.cs` — worker registration and session attach
- Create: `src/Worker/CortexTerminal.Worker/Pty/IPtyHost.cs`
- Create: `src/Worker/CortexTerminal.Worker/Pty/PtySession.cs`
- Create: `src/Worker/CortexTerminal.Worker/Pty/UnixPtyHost.cs` — macOS/Linux PTY implementation

### Mobile

- Create: `src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj`
- Create: `src/Mobile/CortexTerminal.Mobile/MauiProgram.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/AppShell.xaml`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Auth/ITokenStore.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Auth/SecureTokenStore.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Auth/DeviceFlowService.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Terminal/TerminalGatewayClient.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Bridge/TerminalBridge.cs` — byte bridge between MAUI and web view
- Create: `src/Mobile/CortexTerminal.Mobile/Web/package.json`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/vite.config.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/main.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/App.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts`

### Tests

- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DeviceFlowControllerTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Sessions/SessionCoordinatorTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/TerminalHubTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/InteractiveSessionFlowTests.cs`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Pty/PtySessionTests.cs`
- Create: `tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj`
- Create: `tests/Mobile/CortexTerminal.Mobile.Tests/Auth/SecureTokenStoreTests.cs`
- Create: `tests/Mobile/CortexTerminal.Mobile.Tests/Bridge/TerminalBridgeTests.cs`
- Create: `tests/Web/terminal.spec.tsx`

## Task 1: Bootstrap the solution skeleton

**Files:**
- Create: `CortexTerminal.sln`
- Create: `Directory.Build.props`
- Create: `.gitignore`
- Create: `src/Shared/CortexTerminal.Contracts/CortexTerminal.Contracts.csproj`
- Create: `src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj`
- Create: `src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj`
- Create: `src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj`

- [ ] **Step 1: Create the solution and baseline config**

```xml
<!-- Directory.Build.props -->
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <LangVersion>preview</LangVersion>
  </PropertyGroup>
</Project>
```

```gitignore
bin/
obj/
.vs/
.idea/
node_modules/
dist/
artifacts/
.superpowers/
```

Run:

```bash
dotnet new sln -n CortexTerminal
mkdir -p src/Shared/CortexTerminal.Contracts src/Gateway/CortexTerminal.Gateway src/Worker/CortexTerminal.Worker src/Mobile/CortexTerminal.Mobile
```

Expected: `The template "Solution File" was created successfully.`

- [ ] **Step 2: Verify the empty projects fail to build**

Run:

```bash
dotnet new classlib -n CortexTerminal.Contracts -o src/Shared/CortexTerminal.Contracts
dotnet new web -n CortexTerminal.Gateway -o src/Gateway/CortexTerminal.Gateway
dotnet new console -n CortexTerminal.Worker -o src/Worker/CortexTerminal.Worker
dotnet new maui -n CortexTerminal.Mobile -o src/Mobile/CortexTerminal.Mobile
dotnet sln CortexTerminal.sln add src/Shared/CortexTerminal.Contracts/CortexTerminal.Contracts.csproj src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj
dotnet build CortexTerminal.sln
```

Expected: FAIL if any generated templates still target the wrong framework or the MAUI workload is missing.

- [ ] **Step 3: Normalize project files to the shared conventions**

```xml
<!-- src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj -->
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\Shared\CortexTerminal.Contracts\CortexTerminal.Contracts.csproj" />
  </ItemGroup>
</Project>
```

```xml
<!-- src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\Shared\CortexTerminal.Contracts\CortexTerminal.Contracts.csproj" />
  </ItemGroup>
</Project>
```

```xml
<!-- src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net10.0-android;net10.0-ios</TargetFrameworks>
    <UseMaui>true</UseMaui>
    <SingleProject>true</SingleProject>
    <OutputType>Exe</OutputType>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\Shared\CortexTerminal.Contracts\CortexTerminal.Contracts.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 4: Run the build again until the baseline solution passes**

Run:

```bash
dotnet build CortexTerminal.sln
```

Expected: PASS with all four projects restored and compiled.

- [ ] **Step 5: Commit the scaffold**

```bash
git init
git add CortexTerminal.sln Directory.Build.props .gitignore src
git commit -m "chore: bootstrap CortexTerminal solution"
```

## Task 2: Define the shared protocol contracts first

**Files:**
- Modify: `src/Shared/CortexTerminal.Contracts/CortexTerminal.Contracts.csproj`
- Create: `src/Shared/CortexTerminal.Contracts/Auth/DeviceFlowDtos.cs`
- Create: `src/Shared/CortexTerminal.Contracts/Sessions/SessionDtos.cs`
- Create: `src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Contracts/ContractSerializationTests.cs`

- [ ] **Step 1: Write the failing serialization tests**

```csharp
public sealed class ContractSerializationTests
{
    [Fact]
    public void WriteInputFrame_RoundTrips_WithRawBytes()
    {
        var frame = new WriteInputFrame("s-123", new byte[] { 0x09, 0x03, 0x1B, 0x41 });
        var bytes = MessagePackSerializer.Serialize(frame);
        var clone = MessagePackSerializer.Deserialize<WriteInputFrame>(bytes);

        clone.SessionId.Should().Be("s-123");
        clone.Payload.Should().Equal(0x09, 0x03, 0x1B, 0x41);
    }
}
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run:

```bash
dotnet new xunit -n CortexTerminal.Gateway.Tests -o tests/Gateway/CortexTerminal.Gateway.Tests
dotnet add tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj package MessagePack
dotnet add tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj package FluentAssertions
dotnet add tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj reference src/Shared/CortexTerminal.Contracts/CortexTerminal.Contracts.csproj
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter ContractSerializationTests
```

Expected: FAIL with `WriteInputFrame` not found.

- [ ] **Step 3: Add the contract types and MessagePack annotations**

```csharp
// src/Shared/CortexTerminal.Contracts/Streaming/TerminalFrames.cs
using MessagePack;

namespace CortexTerminal.Contracts.Streaming;

[MessagePackObject]
public sealed record WriteInputFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] byte[] Payload);

[MessagePackObject]
public sealed record TerminalChunk(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Stream,
    [property: Key(2)] byte[] Payload);

[MessagePackObject]
public sealed record SessionStarted(
    [property: Key(0)] string SessionId,
    [property: Key(1)] int Columns,
    [property: Key(2)] int Rows);

[MessagePackObject]
public sealed record SessionExited(
    [property: Key(0)] string SessionId,
    [property: Key(1)] int ExitCode,
    [property: Key(2)] string Reason);

[MessagePackObject]
public sealed record WorkerUnavailableEvent(
    [property: Key(0)] string RequestId,
    [property: Key(1)] string Reason);

[MessagePackObject]
public sealed record AuthExpiredEvent(
    [property: Key(0)] string RequestId);

[MessagePackObject]
public sealed record SessionStartFailedEvent(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Reason);
```

```csharp
// src/Shared/CortexTerminal.Contracts/Sessions/SessionDtos.cs
namespace CortexTerminal.Contracts.Sessions;

public sealed record CreateSessionRequest(string Runtime, int Columns, int Rows);
public sealed record CreateSessionResponse(string SessionId, string WorkerId);
public sealed record ResizePtyRequest(string SessionId, int Columns, int Rows);
public sealed record CloseSessionRequest(string SessionId);
public sealed record CreateSessionResult(bool IsSuccess, CreateSessionResponse? Response, string? ErrorCode)
{
    public static CreateSessionResult Success(CreateSessionResponse response) => new(true, response, null);
    public static CreateSessionResult Failure(string errorCode) => new(false, null, errorCode);
}
```

```csharp
// src/Shared/CortexTerminal.Contracts/Auth/DeviceFlowDtos.cs
namespace CortexTerminal.Contracts.Auth;

public sealed record DeviceFlowStartResponse(string DeviceCode, string UserCode, string VerificationUri, int ExpiresInSeconds, int PollIntervalSeconds);
public sealed record DeviceFlowTokenResponse(string AccessToken, string RefreshToken, int ExpiresInSeconds);
```

- [ ] **Step 4: Run the tests again and then add the contracts project dependency**

Run:

```bash
dotnet add src/Shared/CortexTerminal.Contracts/CortexTerminal.Contracts.csproj package MessagePack
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter ContractSerializationTests
```

Expected: PASS.

- [ ] **Step 5: Commit the contracts**

```bash
git add src/Shared/CortexTerminal.Contracts tests/Gateway/CortexTerminal.Gateway.Tests
git commit -m "feat: add shared terminal protocol contracts"
```

## Task 3: Build Gateway auth and session creation guards

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj`
- Create: `src/Gateway/CortexTerminal.Gateway/Program.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Auth/OpenIddictSetup.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Auth/DeviceFlowController.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DeviceFlowControllerTests.cs`

- [ ] **Step 1: Write the failing auth tests**

```csharp
public sealed class DeviceFlowControllerTests
{
    [Fact]
    public async Task CreateSession_WithoutBearerToken_ReturnsUnauthorized()
    {
        using var app = new WebApplicationFactory<Program>();
        var client = app.CreateClient();

        var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

- [ ] **Step 2: Run the tests and verify auth is not configured yet**

Run:

```bash
dotnet add tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj package Microsoft.AspNetCore.Mvc.Testing
dotnet add tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj reference src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter DeviceFlowControllerTests
```

Expected: FAIL because `/api/sessions` does not exist or is not protected.

- [ ] **Step 3: Add OpenIddict, auth middleware, and a protected session endpoint**

```csharp
// src/Gateway/CortexTerminal.Gateway/Auth/OpenIddictSetup.cs
public static class OpenIddictSetup
{
    public static IServiceCollection AddCortexOpenIddict(this IServiceCollection services)
    {
        services.AddOpenIddict()
            .AddCore(options => options.UseInMemoryStores())
            .AddServer(options =>
            {
                options.AllowDeviceAuthorizationFlow();
                options.SetDeviceEndpointUris("/connect/device");
                options.SetTokenEndpointUris("/connect/token");
                options.AcceptAnonymousClients();
                options.UseAspNetCore().EnableTokenEndpointPassthrough();
            });

        return services;
    }
}
```

```csharp
// src/Gateway/CortexTerminal.Gateway/Program.cs
using CortexTerminal.Contracts.Sessions;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddAuthorization();
builder.Services.AddAuthentication("Bearer").AddJwtBearer("Bearer", options =>
{
    options.Authority = builder.Configuration["Auth:Authority"] ?? "https://localhost:5001";
    options.Audience = "cortex-mobile";
    options.RequireHttpsMetadata = false;
});
builder.Services.AddCortexOpenIddict();
builder.Services.AddSignalR().AddMessagePackProtocol();

var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();

app.MapPost("/api/sessions", [Authorize] (CreateSessionRequest request) =>
{
    if (!string.Equals(request.Runtime, "shell", StringComparison.Ordinal))
    {
        return Results.BadRequest("Only shell runtime is allowed in phase 1.");
    }

    return Results.Accepted();
});

app.MapControllers();
app.Run();

public partial class Program;
```

```csharp
// src/Gateway/CortexTerminal.Gateway/Auth/DeviceFlowController.cs
[ApiController]
[Route("api/auth/device")]
public sealed class DeviceFlowController : ControllerBase
{
    [HttpPost("start")]
    public ActionResult<DeviceFlowStartResponse> Start()
        => Ok(new DeviceFlowStartResponse("device-code", "ABCD-EFGH", "https://localhost:5001/activate", 900, 5));
}
```

- [ ] **Step 4: Run the auth tests again**

Run:

```bash
dotnet add src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj package Microsoft.AspNetCore.Authentication.JwtBearer
dotnet add src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj package OpenIddict.AspNetCore
dotnet add src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj package Microsoft.AspNetCore.SignalR.Protocols.MessagePack
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter DeviceFlowControllerTests
```

Expected: PASS.

- [ ] **Step 5: Commit the auth guard**

```bash
git add src/Gateway/CortexTerminal.Gateway tests/Gateway/CortexTerminal.Gateway.Tests/Auth
git commit -m "feat: protect gateway session creation with auth"
```

## Task 4: Add worker registry, session coordination, and terminal hub

**Files:**
- Create: `src/Gateway/CortexTerminal.Gateway/Workers/IWorkerRegistry.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Workers/InMemoryWorkerRegistry.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs`
- Create: `src/Gateway/CortexTerminal.Gateway/Hubs/WorkerHub.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Sessions/SessionCoordinatorTests.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Hubs/TerminalHubTests.cs`

- [ ] **Step 1: Write the failing registry and no-worker tests**

```csharp
public sealed class SessionCoordinatorTests
{
    [Fact]
    public async Task CreateSessionAsync_WithoutAnyRegisteredWorker_ReturnsWorkerUnavailable()
    {
        var workers = new InMemoryWorkerRegistry();
        var coordinator = new InMemorySessionCoordinator(workers);

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("WorkerUnavailable");
    }
}
```

- [ ] **Step 2: Run the tests and verify the coordinator is missing**

Run:

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter SessionCoordinatorTests
```

Expected: FAIL with `InMemorySessionCoordinator` not found.

- [ ] **Step 3: Implement the registry, coordinator, and SignalR hub methods**

```csharp
// src/Gateway/CortexTerminal.Gateway/Workers/IWorkerRegistry.cs
namespace CortexTerminal.Gateway.Workers;

public interface IWorkerRegistry
{
    void Register(string workerId, string connectionId);
    bool TryGetLeastBusy(out RegisteredWorker worker);
}

public sealed record RegisteredWorker(string WorkerId, string ConnectionId);
```

```csharp
// src/Gateway/CortexTerminal.Gateway/Sessions/ISessionCoordinator.cs
public interface ISessionCoordinator
{
    Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, CancellationToken cancellationToken);
    bool TryGetSession(string sessionId, out SessionRecord session);
}
```

```csharp
// src/Gateway/CortexTerminal.Gateway/Sessions/SessionRecord.cs
public sealed record SessionRecord(
    string SessionId,
    string UserId,
    string WorkerId,
    string WorkerConnectionId,
    int Columns,
    int Rows);
```

```csharp
// src/Gateway/CortexTerminal.Gateway/Sessions/InMemorySessionCoordinator.cs
public sealed class InMemorySessionCoordinator(IWorkerRegistry workers) : ISessionCoordinator
{
    private readonly ConcurrentDictionary<string, SessionRecord> _sessions = new();

    public Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, CancellationToken cancellationToken)
    {
        if (!workers.TryGetLeastBusy(out var worker))
        {
            return Task.FromResult(CreateSessionResult.Failure("WorkerUnavailable"));
        }

        var sessionId = $"sess_{Guid.NewGuid():N}";
        var record = new SessionRecord(sessionId, userId, worker.WorkerId, worker.ConnectionId, request.Columns, request.Rows);
        _sessions[sessionId] = record;
        return Task.FromResult(CreateSessionResult.Success(new CreateSessionResponse(sessionId, worker.WorkerId)));
    }

    public bool TryGetSession(string sessionId, out SessionRecord session)
        => _sessions.TryGetValue(sessionId, out session);
}
```

```csharp
// src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs
[Authorize]
public sealed class TerminalHub(ISessionCoordinator sessions) : Hub
{
    public Task<CreateSessionResult> CreateSession(CreateSessionRequest request, CancellationToken cancellationToken)
        => sessions.CreateSessionAsync(Context.UserIdentifier!, request, cancellationToken);

    public async Task WriteInput(WriteInputFrame frame)
    {
        if (!sessions.TryGetSession(frame.SessionId, out var session))
        {
            throw new HubException("Unknown session.");
        }

        await Clients.Client(session.WorkerConnectionId).SendAsync("WriteInput", frame);
    }
}
```

- [ ] **Step 4: Re-run the coordinator and hub tests**

Run:

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "SessionCoordinatorTests|TerminalHubTests"
```

Expected: PASS with a worker-unavailable failure case and a successful session allocation case.

- [ ] **Step 5: Commit session coordination**

```bash
git add src/Gateway/CortexTerminal.Gateway/Workers src/Gateway/CortexTerminal.Gateway/Sessions src/Gateway/CortexTerminal.Gateway/Hubs tests/Gateway/CortexTerminal.Gateway.Tests
git commit -m "feat: add gateway worker registry and session coordination"
```

## Task 5: Implement the Worker PTY host and dual-stream forwarding

**Files:**
- Create: `src/Worker/CortexTerminal.Worker/Program.cs`
- Create: `src/Worker/CortexTerminal.Worker/Registration/WorkerGatewayClient.cs`
- Create: `src/Worker/CortexTerminal.Worker/Pty/IPtyHost.cs`
- Create: `src/Worker/CortexTerminal.Worker/Pty/PtySession.cs`
- Create: `src/Worker/CortexTerminal.Worker/Pty/UnixPtyHost.cs`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Pty/PtySessionTests.cs`

- [ ] **Step 1: Write the failing PTY tests**

```csharp
public sealed class PtySessionTests
{
    [Fact]
    public async Task StartAsync_ForwardsStdoutAndStderrSeparately()
    {
        var fakeHost = new FakePtyHost(stdout: "ok\n", stderr: "bad\n");
        var session = new PtySession(fakeHost);

        var events = await session.StartAsync("sess_1", 120, 40, CancellationToken.None);

        events.Should().ContainSingle(x => x.Stream == "stdout");
        events.Should().ContainSingle(x => x.Stream == "stderr");
    }
}
```

- [ ] **Step 2: Run the worker tests and verify the PTY classes are missing**

Run:

```bash
dotnet new xunit -n CortexTerminal.Worker.Tests -o tests/Worker/CortexTerminal.Worker.Tests
dotnet add tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj package FluentAssertions
dotnet add tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj reference src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj
dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter PtySessionTests
```

Expected: FAIL with `PtySession` not found.

- [ ] **Step 3: Implement the PTY abstraction and session forwarding**

```csharp
// src/Worker/CortexTerminal.Worker/Pty/IPtyHost.cs
namespace CortexTerminal.Worker.Pty;

public interface IPtyHost
{
    Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken);
}

public interface IPtyProcess
{
    IAsyncEnumerable<byte[]> ReadStdoutAsync(CancellationToken cancellationToken);
    IAsyncEnumerable<byte[]> ReadStderrAsync(CancellationToken cancellationToken);
    Task WriteAsync(byte[] payload, CancellationToken cancellationToken);
    Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken);
    Task<int> WaitForExitAsync(CancellationToken cancellationToken);
}
```

```csharp
// src/Worker/CortexTerminal.Worker/Pty/PtySession.cs
public sealed class PtySession(IPtyHost host)
{
    public async Task<IReadOnlyList<TerminalChunk>> StartAsync(string sessionId, int columns, int rows, CancellationToken cancellationToken)
    {
        var process = await host.StartAsync(columns, rows, cancellationToken);
        var chunks = new List<TerminalChunk>();

        await foreach (var stdout in process.ReadStdoutAsync(cancellationToken))
        {
            chunks.Add(new TerminalChunk(sessionId, "stdout", stdout));
        }

        await foreach (var stderr in process.ReadStderrAsync(cancellationToken))
        {
            chunks.Add(new TerminalChunk(sessionId, "stderr", stderr));
        }

        return chunks;
    }
}
```

- [ ] **Step 4: Run the worker tests**

Run:

```bash
dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter PtySessionTests
```

Expected: PASS.

- [ ] **Step 5: Commit the worker runtime**

```bash
git add src/Worker/CortexTerminal.Worker tests/Worker/CortexTerminal.Worker.Tests
git commit -m "feat: add worker pty runtime and dual stream forwarding"
```

## Task 6: Build the mobile auth and SignalR bridge layer

**Files:**
- Create: `src/Mobile/CortexTerminal.Mobile/MauiProgram.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/AppShell.xaml`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Auth/ITokenStore.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Auth/SecureTokenStore.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Auth/DeviceFlowService.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Services/Terminal/TerminalGatewayClient.cs`
- Create: `src/Mobile/CortexTerminal.Mobile/Bridge/TerminalBridge.cs`
- Create: `tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj`
- Create: `tests/Mobile/CortexTerminal.Mobile.Tests/Auth/SecureTokenStoreTests.cs`
- Create: `tests/Mobile/CortexTerminal.Mobile.Tests/Bridge/TerminalBridgeTests.cs`

- [ ] **Step 1: Write the failing mobile tests**

```csharp
public sealed class TerminalBridgeTests
{
    [Fact]
    public void ForwardInput_PreservesByteOrder()
    {
        var bridge = new TerminalBridge();
        var payload = new byte[] { 0x09, 0x03, 0x1B, 0x5B, 0x41 };

        var forwarded = bridge.ForwardInput(payload);

        forwarded.Should().Equal(payload);
    }
}
```

- [ ] **Step 2: Run the mobile tests and verify the bridge does not exist yet**

Run:

```bash
dotnet new xunit -n CortexTerminal.Mobile.Tests -o tests/Mobile/CortexTerminal.Mobile.Tests
dotnet add tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj package FluentAssertions
dotnet add tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj reference src/Mobile/CortexTerminal.Mobile/CortexTerminal.Mobile.csproj
dotnet test tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj --filter TerminalBridgeTests
```

Expected: FAIL with `TerminalBridge` not found.

- [ ] **Step 3: Implement token storage, device flow polling, and the byte bridge**

```csharp
// src/Mobile/CortexTerminal.Mobile/Bridge/TerminalBridge.cs
namespace CortexTerminal.Mobile.Bridge;

public sealed class TerminalBridge
{
    public byte[] ForwardInput(byte[] payload) => payload.ToArray();
    public byte[] ForwardStdout(byte[] payload) => payload.ToArray();
    public byte[] ForwardStderr(byte[] payload) => payload.ToArray();
}
```

```csharp
// src/Mobile/CortexTerminal.Mobile/Services/Auth/ITokenStore.cs
namespace CortexTerminal.Mobile.Services.Auth;

public interface ITokenStore
{
    Task SaveRefreshTokenAsync(string refreshToken, CancellationToken cancellationToken);
    Task<string?> GetRefreshTokenAsync(CancellationToken cancellationToken);
}
```

```csharp
// src/Mobile/CortexTerminal.Mobile/Services/Auth/SecureTokenStore.cs
public sealed class SecureTokenStore : ITokenStore
{
    private const string RefreshTokenKey = "auth.refresh_token";

    public Task SaveRefreshTokenAsync(string refreshToken, CancellationToken cancellationToken)
        => SecureStorage.Default.SetAsync(RefreshTokenKey, refreshToken);

    public Task<string?> GetRefreshTokenAsync(CancellationToken cancellationToken)
        => SecureStorage.Default.GetAsync(RefreshTokenKey);
}
```

```csharp
// src/Mobile/CortexTerminal.Mobile/Services/Auth/DeviceFlowService.cs
public sealed class DeviceFlowService(HttpClient httpClient, ITokenStore tokenStore)
{
    public async Task<DeviceFlowStartResponse?> StartAsync(CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsync("/api/auth/device/start", content: null, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<DeviceFlowStartResponse>(cancellationToken: cancellationToken);
    }

    public async Task<DeviceFlowTokenResponse?> PollAsync(string deviceCode, CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsJsonAsync("/connect/token", new Dictionary<string, string?>
        {
            ["grant_type"] = "urn:ietf:params:oauth:grant-type:device_code",
            ["device_code"] = deviceCode
        }, cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        var token = await response.Content.ReadFromJsonAsync<DeviceFlowTokenResponse>(cancellationToken: cancellationToken);
        if (token is not null)
        {
            await tokenStore.SaveRefreshTokenAsync(token.RefreshToken, cancellationToken);
        }

        return token;
    }
}
```

- [ ] **Step 4: Run the mobile tests**

Run:

```bash
dotnet test tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj --filter "TerminalBridgeTests|SecureTokenStoreTests"
```

Expected: PASS.

- [ ] **Step 5: Commit the mobile native layer**

```bash
git add src/Mobile/CortexTerminal.Mobile tests/Mobile/CortexTerminal.Mobile.Tests
git commit -m "feat: add mobile device flow and byte bridge services"
```

## Task 7: Build the React terminal adapter with xterm.js

**Files:**
- Create: `src/Mobile/CortexTerminal.Mobile/Web/package.json`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/vite.config.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/main.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/App.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts`
- Create: `tests/Web/terminal.spec.tsx`

- [ ] **Step 1: Write the failing web terminal test**

```tsx
it("forwards xterm input as raw bytes", () => {
  const writeInput = vi.fn()
  const { result } = renderHook(() => useTerminalSession(writeInput))

  result.current.onTerminalData("\t")

  expect(writeInput).toHaveBeenCalledWith(Uint8Array.from([0x09]))
})
```

- [ ] **Step 2: Run the web test to verify it fails**

Run:

```bash
mkdir -p src/Mobile/CortexTerminal.Mobile/Web/src/terminal tests/Web
cd src/Mobile/CortexTerminal.Mobile/Web
npm init -y
npm install react react-dom xterm
npm install -D vite vitest @testing-library/react @testing-library/react-hooks jsdom typescript @types/react @types/react-dom
npx vitest run ../../../../tests/Web/terminal.spec.tsx
```

Expected: FAIL with `useTerminalSession` not found.

- [ ] **Step 3: Implement the hook and terminal view**

```tsx
// src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts
export function useTerminalSession(writeInput: (payload: Uint8Array) => void) {
  return {
    onTerminalData(data: string) {
      writeInput(new TextEncoder().encode(data))
    },
    onStdout(payload: Uint8Array) {
      return new TextDecoder().decode(payload)
    },
    onStderr(payload: Uint8Array) {
      return new TextDecoder().decode(payload)
    }
  }
}
```

```tsx
// src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx
export function TerminalView({ writeInput }: { writeInput: (payload: Uint8Array) => void }) {
  const session = useTerminalSession(writeInput)
  return <button onClick={() => session.onTerminalData("\t")}>send-tab</button>
}
```

- [ ] **Step 4: Run the web test**

Run:

```bash
cd src/Mobile/CortexTerminal.Mobile/Web
npx vitest run ../../../../tests/Web/terminal.spec.tsx
```

Expected: PASS.

- [ ] **Step 5: Commit the web terminal**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web tests/Web
git commit -m "feat: add hybrid web terminal adapter"
```

## Task 8: Wire end-to-end session creation and integration tests

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/TerminalHub.cs`
- Modify: `src/Gateway/CortexTerminal.Gateway/Hubs/WorkerHub.cs`
- Modify: `src/Worker/CortexTerminal.Worker/Registration/WorkerGatewayClient.cs`
- Modify: `src/Mobile/CortexTerminal.Mobile/Services/Terminal/TerminalGatewayClient.cs`
- Create: `tests/Gateway/CortexTerminal.Gateway.Tests/Integration/InteractiveSessionFlowTests.cs`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Pty/PtyResizeTests.cs`

- [ ] **Step 1: Write the failing integration tests**

```csharp
public sealed class InteractiveSessionFlowTests
{
    [Fact]
    public async Task CreateSession_WithRegisteredWorker_ReturnsSessionStarted()
    {
        using var app = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureTestServices(services =>
                {
                    services.AddAuthentication("Test")
                        .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { });
                    services.PostConfigure<AuthenticationOptions>(options =>
                    {
                        options.DefaultAuthenticateScheme = "Test";
                        options.DefaultChallengeScheme = "Test";
                    });
                });
            });
        var client = app.CreateClient();

        var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<CreateSessionResponse>();
        payload!.SessionId.Should().StartWith("sess_");
    }

    private sealed class TestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
        : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            var identity = new ClaimsIdentity(new[] { new Claim(ClaimTypes.Name, "user-1") }, Scheme.Name);
            var principal = new ClaimsPrincipal(identity);
            return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme.Name)));
        }
    }
}
```

```csharp
public sealed class PtyResizeTests
{
    [Fact]
    public async Task ResizeAsync_ForwardsNewTerminalSizeToTheProcess()
    {
        var fakeProcess = new FakePtyProcess();
        await fakeProcess.ResizeAsync(140, 50, CancellationToken.None);

        fakeProcess.LastColumns.Should().Be(140);
        fakeProcess.LastRows.Should().Be(50);
    }
}
```

- [ ] **Step 2: Run the integration tests and verify the flow still fails**

Run:

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter InteractiveSessionFlowTests
```

Expected: FAIL because the API still returns `202 Accepted` instead of a concrete session payload.

- [ ] **Step 3: Wire the real session flow across Gateway, Worker, and Mobile**

```csharp
// src/Gateway/CortexTerminal.Gateway/Program.cs
app.MapPost("/api/sessions", [Authorize] async (
    ClaimsPrincipal user,
    CreateSessionRequest request,
    ISessionCoordinator sessions,
    CancellationToken cancellationToken) =>
{
    var result = await sessions.CreateSessionAsync(user.Identity!.Name ?? "unknown", request, cancellationToken);
    return result.IsSuccess
        ? Results.Ok(result.Response)
        : Results.StatusCode(StatusCodes.Status503ServiceUnavailable);
});
```

```csharp
// src/Mobile/CortexTerminal.Mobile/Services/Terminal/TerminalGatewayClient.cs
public sealed class TerminalGatewayClient(HttpClient httpClient)
{
    public async Task<CreateSessionResponse?> CreateSessionAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", columns, rows), cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<CreateSessionResponse>(cancellationToken: cancellationToken);
    }
}
```

```csharp
// src/Worker/CortexTerminal.Worker/Registration/WorkerGatewayClient.cs
public sealed class WorkerGatewayClient(HubConnection connection)
{
    public Task RegisterAsync(string workerId, CancellationToken cancellationToken)
        => connection.InvokeAsync("RegisterWorker", workerId, cancellationToken);
}
```

- [ ] **Step 4: Run all Phase 1 tests**

Run:

```bash
dotnet test CortexTerminal.sln
cd src/Mobile/CortexTerminal.Mobile/Web && npx vitest run ../../../../tests/Web/terminal.spec.tsx
```

Expected: PASS with Gateway, Worker, Mobile, and web terminal suites green.

- [ ] **Step 5: Commit the end-to-end MVP**

```bash
git add src tests
git commit -m "feat: wire phase1 gateway shell mvp end to end"
```
