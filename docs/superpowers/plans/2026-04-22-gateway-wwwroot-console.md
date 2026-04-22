# Gateway wwwroot console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve the Gateway console directly from `http://localhost:5045` by building the Web app into Gateway `wwwroot` and letting the Gateway host the SPA shell.

**Architecture:** Keep the existing React/Vite console as a separate source project, but publish its compiled assets into the Gateway's static-file directory. Update the Gateway pipeline so `/api/*` and `/hubs/*` stay backend endpoints while `/` and other browser routes return the console shell.

**Tech Stack:** ASP.NET Core minimal APIs, SignalR, React, Vite, TypeScript, xUnit, Vitest

---

### Task 1: Add Gateway-hosted static file coverage

**Files:**
- Modify: `tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DeviceFlowControllerTests.cs`
- Test: `tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DeviceFlowControllerTests.cs`

- [ ] **Step 1: Write the failing test**

```csharp
[Fact]
public async Task RootPath_ServesGatewayConsoleShell()
{
    using var client = _factory.CreateClient();

    using var response = await client.GetAsync("/");

    response.StatusCode.Should().Be(HttpStatusCode.OK);
    response.Content.Headers.ContentType?.MediaType.Should().Be("text/html");
    var html = await response.Content.ReadAsStringAsync();
    html.Should().Contain("<title>Gateway Console</title>");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter RootPath_ServesGatewayConsoleShell --nologo --verbosity minimal`
Expected: FAIL because `/` currently returns JSON instead of HTML.

- [ ] **Step 3: Write minimal implementation**

No production code in this task. Keep the failing test in place as the proof that hosting work is still missing.

- [ ] **Step 4: Run test to verify it still fails for the intended reason**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter RootPath_ServesGatewayConsoleShell --nologo --verbosity minimal`
Expected: FAIL with an assertion showing the content type is JSON rather than `text/html`.

- [ ] **Step 5: Commit**

```bash
git add tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DeviceFlowControllerTests.cs
git commit -m "test: cover gateway console shell hosting"
```

### Task 2: Build the console into Gateway `wwwroot`

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/vite.config.ts`
- Create: `src/Gateway/CortexTerminal.Gateway/wwwroot/.gitkeep`
- Test: `src/Mobile/CortexTerminal.Mobile/Web/package.json`

- [ ] **Step 1: Write the failing build expectation**

Use the existing build as the executable failing check: the plan requires the build to produce `src/Gateway/CortexTerminal.Gateway/wwwroot/index.html`, which does not happen yet.

- [ ] **Step 2: Run build to verify the expected output is missing**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm run build && test -f ../../Gateway/CortexTerminal.Gateway/wwwroot/index.html`
Expected: FAIL on the `test -f` check because Vite currently emits to the default `dist` directory.

- [ ] **Step 3: Write minimal implementation**

```ts
import { defineConfig } from "vite"
import { resolve } from "node:path"

export default defineConfig({
  build: {
    emptyOutDir: true,
    outDir: resolve(__dirname, "../../Gateway/CortexTerminal.Gateway/wwwroot"),
  },
  test: {
    environment: "jsdom",
    globals: true,
  },
})
```

Also create the target directory in git:

```text
src/Gateway/CortexTerminal.Gateway/wwwroot/.gitkeep
```

- [ ] **Step 4: Run build to verify it passes**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm run build && test -f ../../Gateway/CortexTerminal.Gateway/wwwroot/index.html`
Expected: PASS, and `wwwroot/index.html` exists.

- [ ] **Step 5: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/vite.config.ts src/Gateway/CortexTerminal.Gateway/wwwroot/.gitkeep src/Gateway/CortexTerminal.Gateway/wwwroot
git commit -m "build: emit gateway console to wwwroot"
```

### Task 3: Serve the console shell from Gateway

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/Program.cs`
- Test: `tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DeviceFlowControllerTests.cs`

- [ ] **Step 1: Keep the failing test from Task 1**

Use `RootPath_ServesGatewayConsoleShell` as the red test. Do not add a second overlapping root-route test.

- [ ] **Step 2: Run test to verify it fails before the pipeline change**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter RootPath_ServesGatewayConsoleShell --nologo --verbosity minimal`
Expected: FAIL because the Gateway still maps `/` to `Results.Ok(new { Name = "CortexTerminal.Gateway" })`.

- [ ] **Step 3: Write minimal implementation**

```csharp
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment())
{
    app.MapPost("/api/dev/login", (DevLoginRequest request) =>
        Results.Ok(new DevLoginResponse(CreateAccessToken(request.Username)))).AllowAnonymous();
}

app.MapPost("/api/auth/device-flow", () => /* existing code */);
app.MapPost("/api/sessions", /* existing code */).RequireAuthorization();
app.MapGet("/api/me/sessions", /* existing code */).RequireAuthorization();
app.MapGet("/api/me/sessions/{sessionId}", /* existing code */).RequireAuthorization();
app.MapGet("/api/me/workers", /* existing code */).RequireAuthorization();
app.MapGet("/api/me/workers/{workerId}", /* existing code */).RequireAuthorization();

app.MapHub<TerminalHub>("/hubs/terminal");
app.MapHub<WorkerHub>("/hubs/worker");

app.MapFallbackToFile("index.html");
```

Remove:

```csharp
app.MapGet("/", () => Results.Ok(new { Name = "CortexTerminal.Gateway" }));
```

- [ ] **Step 4: Run focused tests to verify they pass**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --filter "RootPath_ServesGatewayConsoleShell|DevLoginEndpointTests|ConsoleQueryEndpointTests" --nologo --verbosity minimal`
Expected: PASS, proving root-hosting works and API routes still behave.

- [ ] **Step 5: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway/Program.cs tests/Gateway/CortexTerminal.Gateway.Tests/Auth/DeviceFlowControllerTests.cs
git commit -m "feat: serve gateway console from static files"
```

### Task 4: Verify merged runtime behavior end-to-end

**Files:**
- Modify: none
- Test: `tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`
- Test: `tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`
- Test: `tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj`
- Test: `src/Mobile/CortexTerminal.Mobile/Web/package.json`

- [ ] **Step 1: Run the Gateway suite**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --nologo --verbosity minimal`
Expected: PASS.

- [ ] **Step 2: Run the Worker suite**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --nologo --verbosity minimal`
Expected: PASS.

- [ ] **Step 3: Run the Mobile suite**

Run: `dotnet test tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj --nologo --verbosity minimal`
Expected: PASS.

- [ ] **Step 4: Run Web tests and build**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run && npm run build`
Expected: PASS, and build artifacts remain in `src/Gateway/CortexTerminal.Gateway/wwwroot`.

- [ ] **Step 5: Restart local services and verify the shell loads**

Run:

```bash
curl -I http://localhost:5045/
curl -s http://localhost:5045/ | grep "<title>Gateway Console</title>"
```

Expected: the root path returns HTML and contains the console title.

- [ ] **Step 6: Commit**

```bash
git add src/Gateway/CortexTerminal.Gateway/wwwroot
git commit -m "chore: refresh hosted gateway console assets"
```
