# Quick.PtyNet Worker Terminal Design

## Problem

The browser console now uses real `xterm.js`, but the Worker still launches shells through `Process + redirected stdin/stdout/stderr` instead of a real PTY. That breaks core terminal behavior:

1. no real interactive shell prompt
2. enter/input semantics differ from terminal expectations
3. resize is effectively a no-op
4. full-screen terminal programs like `vim` and `top` do not work correctly

The goal is to make the Worker provide a real PTY-backed shell while keeping the existing Gateway and browser integration stable.

## Goal

Replace the Worker’s current fake terminal backend with a real PTY backend built on `Quick.PtyNet` so that:

1. sessions open into a real interactive shell
2. prompt, input, and enter behavior match terminal expectations
3. resize affects the running shell correctly
4. full-screen terminal programs like `vim` and `top` work
5. macOS, Linux, and supported Windows environments share the same Worker-side design

## Non-Goals

1. Redesigning the Gateway session model, SignalR hub structure, or HTTP APIs.
2. Replacing `xterm.js` or the current console routing model.
3. Adding an automatic fallback to the old non-PTY pipe mode.
4. Introducing a broad cross-service capability negotiation redesign in this first pass.
5. Solving unrelated worker ownership or session visibility behavior.

## Recommended Approach

Keep the current architecture boundary intact and replace only the Worker-side PTY implementation.

- keep `IPtyHost` and `IPtyProcess` as the runtime abstraction
- keep `WorkerRuntimeHost` and `WorkerSessionRuntime` depending on those abstractions
- replace the current `UnixPtyHost`/`UnixPtyProcess` implementation with a `Quick.PtyNet`-backed real PTY implementation
- keep Gateway session dispatch, SignalR streaming, replay, and front-end terminal rendering unchanged unless a PTY-specific bug forces a small compatibility fix

This keeps the fix focused on the actual root cause: the Worker is not creating a PTY today.

## Alternatives Considered

### 1. Recommended: Replace only the Worker PTY backend

Use `Quick.PtyNet` behind the existing Worker PTY abstraction.

- **Pros:** minimal surface area, preserves known-good Gateway/front-end flow, directly solves the real PTY requirement
- **Cons:** capability visibility remains mostly Worker-local in the first pass

### 2. Add Worker capability reporting before PTY replacement

First add platform/capability metadata to Worker registration and expose it in Gateway, then switch PTY implementation.

- **Pros:** cleaner product-level visibility into PTY support
- **Cons:** bigger protocol and UI change before the real terminal problem is fixed

### 3. Replace the entire terminal protocol stack

Redesign Worker/Gateway/browser messaging around the new PTY backend.

- **Pros:** maximum long-term flexibility
- **Cons:** much larger and riskier than needed for the current goal

## Architecture

### Stable boundaries

These pieces remain the same in this design:

- Worker session orchestration in `WorkerRuntimeHost`
- session lifecycle logic in `WorkerSessionRuntime`
- Gateway dispatch through `SignalRWorkerCommandDispatcher`
- Gateway `TerminalHub` attach/replay/write/resize flow
- browser terminal integration through `terminalGateway.ts` and `TerminalView.tsx`

### Changed boundary

The implementation under `src/Worker/CortexTerminal.Worker/Pty` changes from a redirected child process to a real PTY session created by `Quick.PtyNet`.

The abstraction remains:

- `IPtyHost.StartAsync(columns, rows, cancellationToken)`
- `IPtyProcess.ReadStdoutAsync(...)`
- `IPtyProcess.ReadStderrAsync(...)`
- `IPtyProcess.WriteAsync(payload, cancellationToken)`
- `IPtyProcess.ResizeAsync(columns, rows, cancellationToken)`
- `IPtyProcess.WaitForExitAsync(cancellationToken)`
- `IPtyProcess.DisposeAsync()`

If `Quick.PtyNet` exposes a single merged PTY output stream rather than separate stdout/stderr semantics, the Worker should preserve compatibility by treating PTY output as `stdout` for terminal rendering. The current front-end terminal UX does not depend on shell stderr being visually separate in order to satisfy this feature.

## Worker Implementation Design

### PTY host

Introduce a `QuickPtyHost` implementation that owns `Quick.PtyNet` session creation.

Responsibilities:

1. choose the shell/command to launch
2. create the PTY with requested columns and rows
3. configure environment variables like `TERM`
4. return an `IPtyProcess` adapter around the underlying `Quick.PtyNet` process/session object

The existing `UnixPtyHost` should either be removed or replaced in DI so the Worker only uses the real PTY path.

### PTY process adapter

Introduce a `QuickPtyProcess` adapter implementing `IPtyProcess`.

Responsibilities:

1. read PTY output and yield chunks for Gateway forwarding
2. write raw terminal input bytes into the PTY
3. resize the PTY through the library API
4. observe process exit and surface exit code where available
5. dispose/terminate the PTY and its child process tree safely

`WorkerSessionRuntime` should not need to know it is now talking to `Quick.PtyNet`.

### Shell launch behavior

The launched shell remains environment-driven:

- prefer `SHELL` on Unix-like platforms when present
- use a sensible platform default when missing
- on Windows, use the default command shell or PowerShell choice already established by environment/config if present; otherwise pick one explicit default and document it in code

The PTY launch path must be explicit and deterministic, not inferred by fragile runtime heuristics beyond platform detection and environment overrides.

## Platform Behavior

### macOS and Linux

macOS and Linux should use the `Quick.PtyNet` PTY path by default.

Expected behavior:

1. interactive shell prompt is visible
2. enter/input works without browser-side hacks
3. resize propagates to the PTY
4. full-screen terminal applications function

### Windows

Windows should also use `Quick.PtyNet`, but only when the environment satisfies its PTY requirements.

If the environment does not support the required PTY path, the Worker must fail explicitly instead of silently falling back to the old non-PTY implementation.

### Unsupported PTY environments

This design does **not** permit automatic fallback to the old pipe mode.

Required behavior:

1. if PTY support is unavailable, session start fails explicitly
2. the failure reason is stable and recognizable
3. the user sees a real error instead of an empty terminal

Recommended error codes:

- `pty-not-supported-on-platform`
- `pty-start-failed`

## Input Semantics

Once the Worker uses a real PTY, the browser terminal should send raw terminal input semantics instead of compensating for the old pipe-based backend.

That means the current front-end workaround that normalizes `\r` to `\n` should be removed as part of this PTY migration. A real terminal path should preserve xterm input semantics rather than rewriting them for shell pipes.

## Data Flow

The end-to-end flow remains:

1. user creates a session through Gateway
2. Gateway dispatches `StartSession` to the Worker
3. Worker creates a real PTY through `Quick.PtyNet`
4. Worker streams PTY output back through the existing SignalR flow
5. browser `xterm.js` renders output and sends keystrokes back
6. resize events flow from browser to Gateway to Worker PTY
7. exit/failure signals flow back through the current session lifecycle path

The important change is step 3: the session now runs inside a real PTY rather than a plain redirected process.

## Error Handling

### Session start failures

If PTY creation fails, the Worker should emit `SessionStartFailed` with an explicit reason. Gateway should preserve that reason through the current error path so the UI can surface it.

### Runtime failures

If the PTY dies after successful session start:

1. Worker emits the existing exit event
2. Gateway marks the session exited
3. browser terminal shows the session end reason through the existing `SessionExited`/expired handling path

### Resource cleanup

On session close or Worker shutdown:

1. the PTY must be disposed
2. the child process tree must be terminated if still running
3. reader loops must stop cleanly
4. the Worker session runtime must not leak background tasks

## Testing Strategy

### Worker PTY tests

Add tests around the new PTY implementation that prove:

1. a PTY session can start
2. writing input produces observable output
3. resize can be invoked successfully
4. exit is detected
5. unsupported platform/environment paths produce explicit failure

Where full PTY behavior cannot be unit tested reliably, use focused integration-style Worker tests.

### Gateway/Worker integration verification

Verify:

1. session creation succeeds with a PTY-capable Worker
2. session detail no longer lands in an empty terminal
3. terminal input executes commands
4. session close tears down the PTY correctly

### Real interaction verification

Manual verification for this feature must include:

1. visible shell prompt
2. `echo hello`
3. `stty size` or equivalent resize verification
4. interactive use of `vim` or `top`

## Implementation Notes

1. Add the `Quick.PtyNet` package only in the Worker project.
2. Keep the change focused on the Worker PTY boundary unless a compatibility issue forces a small paired front-end fix.
3. Remove the temporary browser-side `\r -> \n` input workaround once the real PTY backend is in place.
4. Prefer explicit platform guards and explicit failure messages over silent fallback logic.

## Success Criteria

This work is successful when:

1. Worker sessions run inside a real PTY backed by `Quick.PtyNet`
2. macOS and Linux provide a normal interactive shell experience
3. supported Windows environments also provide a real PTY experience
4. unsupported PTY environments fail explicitly instead of pretending to work
5. `vim` and `top` can run through the browser terminal
6. the existing Gateway and front-end architecture remain intact aside from targeted compatibility changes
