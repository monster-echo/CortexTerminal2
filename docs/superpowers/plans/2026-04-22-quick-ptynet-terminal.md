# Quick.PtyNet Worker Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Worker’s fake redirected-process terminal backend with a real `Quick.PtyNet` PTY backend so browser sessions get a real prompt, raw terminal input semantics, working resize, and support for full-screen terminal apps.

**Architecture:** Keep Gateway, SignalR, replay, and `xterm.js` boundaries intact. Swap the implementation under `src/Worker/CortexTerminal.Worker/Pty` to a `Quick.PtyNet`-backed `IPtyHost`/`IPtyProcess` adapter, then remove the temporary browser-side enter normalization that was only compensating for the old pipe backend.

**Tech Stack:** .NET 10, Quick.PtyNet, SignalR, xUnit, FluentAssertions, Vitest, xterm.js

---

## File Map

- **Modify:** `src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj` — add the `Quick.PtyNet` package reference.
- **Modify:** `src/Worker/CortexTerminal.Worker/Program.cs` — wire `IPtyHost` to the new `QuickPtyHost`.
- **Modify:** `src/Worker/CortexTerminal.Worker/Pty/UnixPtyHost.cs` — replace with the new real-PTY implementation or remove after moving the code into a new file.
- **Create:** `src/Worker/CortexTerminal.Worker/Pty/QuickPtyHost.cs` — own `Quick.PtyNet` session creation and environment/platform handling.
- **Create:** `src/Worker/CortexTerminal.Worker/Pty/QuickPtyProcess.cs` — adapt the `Quick.PtyNet` session/process object to `IPtyProcess`.
- **Create:** `src/Worker/CortexTerminal.Worker/Pty/PtySupportException.cs` — explicit PTY capability/start failures.
- **Modify:** `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts` — remove the temporary `\r -> \n` workaround after the Worker uses a real PTY.
- **Modify:** `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts` — restore raw input semantics tests.
- **Modify:** `tests/Worker/CortexTerminal.Worker.Tests/Pty/PtySessionTests.cs` — keep session abstraction tests green if PTY stream behavior changes.
- **Create:** `tests/Worker/CortexTerminal.Worker.Tests/Pty/QuickPtyHostTests.cs` — verify PTY launch, write/read, resize, and explicit unsupported-platform failure behavior.
- **Modify:** `tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerSessionRuntimeTests.cs` — verify PTY startup failures surface the right exit/start-failure path if needed.

### Task 1: Add package reference and red tests for the PTY backend

**Files:**
- Modify: `src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj`
- Create: `tests/Worker/CortexTerminal.Worker.Tests/Pty/QuickPtyHostTests.cs`
- Test: `tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`

- [ ] **Step 1: Add the failing Worker PTY tests**

```csharp
using System.Runtime.InteropServices;
using System.Text;
using CortexTerminal.Worker.Pty;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Pty;

public sealed class QuickPtyHostTests
{
    [Fact]
    public async Task StartAsync_LaunchesInteractiveShell_AndEchoRoundTrips()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var host = new QuickPtyHost();
        await using var process = await host.StartAsync(120, 40, CancellationToken.None);

        await process.WriteAsync("echo hello\n"u8.ToArray(), CancellationToken.None);
        var output = await ReadUntilAsync(process.ReadStdoutAsync(CancellationToken.None), "hello", CancellationToken.None);

        output.Should().Contain("hello");
    }

    [Fact]
    public async Task ResizeAsync_UpdatesRunningPty()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var host = new QuickPtyHost();
        await using var process = await host.StartAsync(120, 40, CancellationToken.None);

        await process.ResizeAsync(100, 30, CancellationToken.None);
        await process.WriteAsync("stty size\n"u8.ToArray(), CancellationToken.None);
        var output = await ReadUntilAsync(process.ReadStdoutAsync(CancellationToken.None), "30 100", CancellationToken.None);

        output.Should().Contain("30 100");
    }

    [Fact]
    public async Task StartAsync_ThrowsExplicitError_WhenLinuxRuntimeSupportIsMissing()
    {
        if (!OperatingSystem.IsLinux())
        {
            return;
        }

        Environment.SetEnvironmentVariable("DOTNET_EnableWriteXorExecute", null);
        var host = new QuickPtyHost();
        var start = () => host.StartAsync(120, 40, CancellationToken.None);

        await start.Should().ThrowAsync<PtySupportException>()
            .WithMessage("*pty-not-supported-on-platform*");
    }

    private static async Task<string> ReadUntilAsync(
        IAsyncEnumerable<byte[]> source,
        string expected,
        CancellationToken cancellationToken)
    {
        var builder = new StringBuilder();
        await foreach (var chunk in source.WithCancellation(cancellationToken))
        {
            builder.Append(Encoding.UTF8.GetString(chunk));
            if (builder.ToString().Contains(expected, StringComparison.Ordinal))
            {
                break;
            }
        }

        return builder.ToString();
    }
}
```

- [ ] **Step 2: Add the package reference needed for the future implementation**

```xml
<ItemGroup>
  <ProjectReference Include="..\..\Shared\CortexTerminal.Contracts\CortexTerminal.Contracts.csproj" />
</ItemGroup>
<ItemGroup>
  <PackageReference Include="Microsoft.AspNetCore.SignalR.Client" Version="10.0.6" />
  <PackageReference Include="Microsoft.AspNetCore.SignalR.Protocols.MessagePack" Version="10.0.6" />
  <PackageReference Include="Microsoft.Extensions.Hosting" Version="10.0.0" />
  <PackageReference Include="Quick.PtyNet" Version="1.0.4" />
</ItemGroup>
```

- [ ] **Step 3: Run the Worker PTY test to verify it fails for the expected reason**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter QuickPtyHostTests`

Expected: FAIL because `QuickPtyHost` / `PtySupportException` do not exist yet.

- [ ] **Step 4: Commit the red test and package reference**

```bash
git add src/Worker/CortexTerminal.Worker/CortexTerminal.Worker.csproj \
  tests/Worker/CortexTerminal.Worker.Tests/Pty/QuickPtyHostTests.cs
git commit -m "test: cover Quick.PtyNet worker pty startup" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 2: Implement the Quick.PtyNet-backed PTY host and process adapter

**Files:**
- Create: `src/Worker/CortexTerminal.Worker/Pty/QuickPtyHost.cs`
- Create: `src/Worker/CortexTerminal.Worker/Pty/QuickPtyProcess.cs`
- Create: `src/Worker/CortexTerminal.Worker/Pty/PtySupportException.cs`
- Modify: `src/Worker/CortexTerminal.Worker/Pty/UnixPtyHost.cs`
- Test: `tests/Worker/CortexTerminal.Worker.Tests/Pty/QuickPtyHostTests.cs`

- [ ] **Step 1: Add the explicit PTY failure type**

```csharp
namespace CortexTerminal.Worker.Pty;

public sealed class PtySupportException(string errorCode, string message)
    : InvalidOperationException(message)
{
    public string ErrorCode { get; } = errorCode;
}
```

- [ ] **Step 2: Implement `QuickPtyHost` with platform-aware shell selection**

```csharp
using Pty.Net;

namespace CortexTerminal.Worker.Pty;

public sealed class QuickPtyHost : IPtyHost
{
    public async Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        EnsureRuntimeSupport();
        var (app, commandLine) = ResolveShell();
        var options = new PtyOptions
        {
            Name = "CortexTerminal.Worker",
            Cols = columns,
            Rows = rows,
            Cwd = Environment.CurrentDirectory,
            App = app,
            CommandLine = commandLine,
            Environment = new Dictionary<string, string>
            {
                ["TERM"] = "xterm-256color",
                ["COLUMNS"] = columns.ToString(),
                ["LINES"] = rows.ToString(),
            },
        };

        try
        {
            var connection = await PtyProvider.SpawnAsync(options, cancellationToken);
            return new QuickPtyProcess(connection);
        }
        catch (Exception exception)
        {
            throw new PtySupportException("pty-start-failed", exception.Message);
        }
    }

    private static void EnsureRuntimeSupport()
    {
        if (OperatingSystem.IsLinux()
            && Environment.GetEnvironmentVariable("DOTNET_EnableWriteXorExecute") != "0")
        {
            throw new PtySupportException(
                "pty-not-supported-on-platform",
                "pty-not-supported-on-platform: DOTNET_EnableWriteXorExecute=0 is required on Linux");
        }
    }

    private static (string App, string[] CommandLine) ResolveShell()
    {
        if (OperatingSystem.IsWindows())
        {
            var shell = Environment.GetEnvironmentVariable("COMSPEC") ?? "powershell.exe";
            return (shell, Array.Empty<string>());
        }

        var shellPath = Environment.GetEnvironmentVariable("SHELL") ?? "/bin/sh";
        return (shellPath, Array.Empty<string>());
    }
}
```

- [ ] **Step 3: Implement the `IPtyProcess` adapter around the Quick.PtyNet session**

```csharp
using Pty.Net;

namespace CortexTerminal.Worker.Pty;

internal sealed class QuickPtyProcess(IPtyConnection connection) : IPtyProcess
{
    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        while (true)
        {
            var count = await connection.ReaderStream.ReadAsync(buffer, 0, buffer.Length, cancellationToken);
            if (count == 0)
            {
                yield break;
            }

            var chunk = new byte[count];
            Buffer.BlockCopy(buffer, 0, chunk, 0, count);
            yield return chunk;
        }
    }

    public async IAsyncEnumerable<byte[]> ReadStderrAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        yield break;
    }

    public Task WriteAsync(byte[] payload, CancellationToken cancellationToken)
        => connection.WriterStream.WriteAsync(payload, 0, payload.Length, cancellationToken);

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        connection.Resize(columns, rows);
        return Task.CompletedTask;
    }

    public Task<int> WaitForExitAsync(CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        connection.ProcessExited += (_, _) => completion.TrySetResult(connection.ExitCode);
        using var _ = cancellationToken.Register(() => completion.TrySetCanceled(cancellationToken));
        return completion.Task;
    }

    public ValueTask DisposeAsync()
    {
        connection.Dispose();
        return ValueTask.CompletedTask;
    }
}
```

- [ ] **Step 4: Replace the old redirected-process implementation**

```csharp
// Remove the ProcessStartInfo + redirected stream implementation entirely.
// Keep `UnixPtyHost.cs` only if it becomes a thin forwarding file:
namespace CortexTerminal.Worker.Pty;

public sealed class UnixPtyHost : QuickPtyHost;
```

- [ ] **Step 5: Run the Worker PTY test to verify the new backend passes**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter QuickPtyHostTests`

Expected: PASS on PTY-capable environments; explicit unsupported-platform assertion path passes only when the environment genuinely cannot start a PTY.

- [ ] **Step 6: Commit the Worker PTY implementation**

```bash
git add src/Worker/CortexTerminal.Worker/Pty/QuickPtyHost.cs \
  src/Worker/CortexTerminal.Worker/Pty/QuickPtyProcess.cs \
  src/Worker/CortexTerminal.Worker/Pty/PtySupportException.cs \
  src/Worker/CortexTerminal.Worker/Pty/UnixPtyHost.cs \
  tests/Worker/CortexTerminal.Worker.Tests/Pty/QuickPtyHostTests.cs
git commit -m "feat: add Quick.PtyNet worker backend" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 3: Wire the Worker runtime to the new backend and preserve explicit failures

**Files:**
- Modify: `src/Worker/CortexTerminal.Worker/Program.cs`
- Modify: `src/Worker/CortexTerminal.Worker/Runtime/WorkerRuntimeHost.cs`
- Modify: `tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerSessionRuntimeTests.cs`
- Test: `tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerSessionRuntimeTests.cs`

- [ ] **Step 1: Add a failing runtime test for explicit PTY startup failure**

```csharp
[Fact]
public async Task StartAsync_ForwardsStartFailure_WhenPtyHostThrowsPtySupportException()
{
    var gateway = new FakeWorkerGatewayClient();
    var runtime = new WorkerSessionRuntime(
        "sess-1",
        new ThrowingPtyHost(new PtySupportException("pty-not-supported-on-platform", "pty-not-supported-on-platform")),
        gateway,
        NullLogger<WorkerSessionRuntime>.Instance);

    var start = () => runtime.StartAsync(120, 40, CancellationToken.None);

    await start.Should().ThrowAsync<PtySupportException>();
}

internal sealed class ThrowingPtyHost(Exception exception) : IPtyHost
{
    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
        => Task.FromException<IPtyProcess>(exception);
}
```

- [ ] **Step 2: Switch DI to the new PTY host**

```csharp
builder.Services.AddSingleton<IPtyHost, QuickPtyHost>();
```

- [ ] **Step 3: Keep startup failure propagation explicit in the Worker runtime**

```csharp
catch (Exception exception)
{
    _sessions.TryRemove(command.SessionId, out _);
    await runtime.CloseAsync(CancellationToken.None);
    await runtime.DisposeAsync();
    _logger.LogError(exception, "Failed to start session {SessionId}.", command.SessionId);

    var reason = exception is PtySupportException ptyFailure
        ? ptyFailure.ErrorCode
        : "pty-start-failed";

    await _gatewayClient.ForwardStartFailedAsync(
        new SessionStartFailedEvent(command.SessionId, reason),
        CancellationToken.None);
}
```

- [ ] **Step 4: Run the runtime-focused Worker tests**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --filter WorkerSessionRuntimeTests`

Expected: PASS, including explicit PTY startup failure behavior.

- [ ] **Step 5: Commit the runtime wiring**

```bash
git add src/Worker/CortexTerminal.Worker/Program.cs \
  src/Worker/CortexTerminal.Worker/Runtime/WorkerRuntimeHost.cs \
  tests/Worker/CortexTerminal.Worker.Tests/Runtime/WorkerSessionRuntimeTests.cs
git commit -m "fix: preserve explicit Quick.PtyNet startup failures" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 4: Remove the temporary browser input workaround

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts`
- Test: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts`

- [ ] **Step 1: Restore the front-end test that expects raw xterm input**

```ts
it("forwards xterm enter as raw carriage return bytes", () => {
  const writeInput = vi.fn()
  const session = useTerminalSession(writeInput)

  session.onTerminalData("echo hello\r")

  expect(writeInput).toHaveBeenCalledOnce()
  expect(Array.from(writeInput.mock.calls[0]![0] as Uint8Array)).toEqual(
    Array.from(new TextEncoder().encode("echo hello\r"))
  )
})
```

- [ ] **Step 2: Remove the browser-side `\r -> \n` rewrite**

```ts
onTerminalData(data: string) {
  deps.writeInput(new TextEncoder().encode(data))
},
```

- [ ] **Step 3: Run the targeted Web test to verify the browser terminal model passes again**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- src/terminal/useTerminalSession.spec.ts`

Expected: PASS with raw xterm input semantics restored.

- [ ] **Step 4: Commit the front-end compatibility cleanup**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts \
  src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts
git commit -m "fix: restore raw terminal input semantics" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 5: Run full verification and refresh hosted assets

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/wwwroot/index.html`
- Modify: `src/Gateway/CortexTerminal.Gateway/wwwroot/assets/*`
- Test: `tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`
- Test: `tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`
- Test: `src/Mobile/CortexTerminal.Mobile/Web`

- [ ] **Step 1: Run Worker tests**

Run: `dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`

Expected: PASS

- [ ] **Step 2: Run Gateway tests**

Run: `dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`

Expected: PASS

- [ ] **Step 3: Run Web tests and rebuild hosted assets**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run && npm run build`

Expected: PASS; `src/Gateway/CortexTerminal.Gateway/wwwroot` receives fresh assets.

- [ ] **Step 4: Do manual terminal verification against a live Gateway + Worker**

Run:

```bash
dotnet run --project src/Gateway/CortexTerminal.Gateway
```

In a second shell:

```bash
DOTNET_EnableWriteXorExecute=0 \
CORTEX_GATEWAY_URL=http://localhost:5045 \
CORTEX_WORKER_ID=worker-local \
dotnet run --project src/Worker/CortexTerminal.Worker
```

Manual checks in the browser:

1. open `http://localhost:5045/`
2. log in as the worker-owning user
3. create a session
4. confirm shell prompt is visible
5. run `echo hello`
6. run `stty size`
7. open `vim` or `top`

Expected: prompt appears, commands execute, resize is reflected, and interactive terminal apps work.

- [ ] **Step 5: Commit the final hosted asset refresh**

```bash
git add src/Gateway/CortexTerminal.Gateway/wwwroot
git commit -m "chore: refresh Quick.PtyNet console assets" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
