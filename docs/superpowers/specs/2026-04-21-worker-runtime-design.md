# Worker Runtime Design

## Problem

The codebase has Gateway, Worker PTY primitives, and reconnect behavior, but it does not yet have a live worker runtime that can participate in real end-to-end debugging. `src/Worker/CortexTerminal.Worker/Program.cs` still exits immediately, and the current Worker code only exposes reusable PTY and registration pieces instead of a long-lived runtime that can receive Gateway commands and stream terminal output back.

## Goal

Add a real Worker runtime that:

1. Connects to the Gateway worker hub and registers itself.
2. Receives Gateway control commands for session start, input, resize, and close.
3. Hosts PTY sessions locally and forwards stdout, stderr, and exit events back to Gateway.
4. Preserves the existing Gateway-centered detach, reattach, and replay behavior.
5. Supports local end-to-end debugging without introducing cross-worker migration or durable worker-side recovery.

## Non-Goals

1. Cross-worker session migration.
2. Persisting worker sessions across worker process restarts.
3. Replacing SignalR with a different control plane.
4. Moving replay ownership away from Gateway.

## Recommended Approach

Keep the current architecture split:

- **Gateway remains the control plane** for worker selection, authorization, attach/detach policy, and replay.
- **Worker becomes the execution plane** for PTY lifecycle and terminal byte streaming.

This is the smallest change that enables real integration debugging while staying aligned with the existing Phase 1 and Phase 2 topology.

## Alternatives Considered

### 1. Recommended: SignalR worker runtime with Gateway command dispatch

The Worker opens a long-lived `HubConnection` to `/hubs/worker`, registers itself, subscribes to Gateway control messages, and manages PTY sessions in-process.

- **Pros:** Reuses current contracts and hubs, keeps reconnect semantics centralized, smallest architectural change.
- **Cons:** Requires adding bidirectional hub orchestration and runtime lifecycle code.

### 2. Separate worker RPC service

The Worker exposes a separate HTTP/RPC command surface and the Gateway dispatches commands outside SignalR.

- **Pros:** Clear execution/control separation.
- **Cons:** Adds another transport and diverges from the current architecture.

### 3. Gateway-hosted PTY runtime

The Gateway directly hosts PTYs and the Worker becomes optional.

- **Pros:** Fastest path to a demo.
- **Cons:** Breaks the existing design and invalidates current Worker-oriented work.

## Architecture

### Gateway components

#### `IWorkerCommandDispatcher`

A focused abstraction that sends control commands to a specific worker connection. It does not own session state.

Responsibilities:

- Send `StartSession`
- Send `WriteInput`
- Send `ResizeSession`
- Send `CloseSession`

#### `TerminalHub`

Responsibilities:

- Continue to create, detach, reattach, and authorize sessions.
- Forward input to the correct worker through `IWorkerCommandDispatcher`.
- Add explicit resize and close methods if they are not already exposed.

#### Session creation flow

When a session is created:

1. Gateway selects a worker using the existing coordinator/registry flow.
2. Gateway persists the `SessionRecord`.
3. Gateway dispatches `StartSession` to that worker connection with session id and initial terminal size.
4. If worker startup fails, Gateway receives a failure event and marks the session unavailable/exited.

### Worker components

#### `WorkerRuntimeHost`

A long-lived host started by `Program.cs`.

Responsibilities:

- Build and maintain the `HubConnection`.
- Register the worker after each successful connection.
- Subscribe to incoming control messages from Gateway.
- Own a thread-safe map of active session runtimes.

#### `WorkerSessionRuntime`

A per-session runtime wrapper around `PtySession` and `IPtyProcess`.

Responsibilities:

- Start the PTY with requested dimensions.
- Forward stdout and stderr back to Gateway as `TerminalChunk`.
- Forward process exit as `SessionExited`.
- Accept input, resize, and close commands.
- Dispose resources exactly once.

#### Session map

The Worker stores active sessions in a `ConcurrentDictionary<string, WorkerSessionRuntime>`.

Rules:

- `StartSession` is rejected or reported as failed if the session id already exists.
- `CloseSession` is idempotent.
- `WriteInput` and `ResizeSession` for unknown or exited sessions are ignored with logging.

## Data Flow

### Start session

1. Client calls Gateway create session API/hub.
2. Gateway selects worker and records session ownership.
3. Gateway dispatches `StartSession(sessionId, columns, rows)` to the chosen worker connection.
4. Worker starts PTY and begins output pumps.
5. Worker forwards stdout/stderr to `WorkerHub.ForwardStdout/ForwardStderr`.
6. Gateway fans out live output and mirrors replay cache as it does today.

### Input / resize / close

1. Client sends control message to Gateway.
2. Gateway validates ownership and session state.
3. Gateway dispatches the control message to the owning worker.
4. Worker applies the command to the in-memory session runtime.

### Exit

1. PTY exits on Worker.
2. Worker emits `SessionExited(sessionId, exitCode, reason)`.
3. Gateway marks the session exited and surfaces the event to the attached client.

## Connection and Recovery Strategy

### Worker to Gateway connection

- Use one long-lived SignalR connection with automatic reconnect.
- Re-register the worker after reconnect.
- Do not tear down local PTY sessions just because the Gateway connection temporarily drops.

### Client reconnect behavior

Client-side detach/reattach/replay behavior remains Gateway-owned and unchanged.

### Worker restart behavior

Worker process restart loses in-memory session runtimes. This is acceptable for this slice and is explicitly out of scope for persistence recovery.

## Error Handling

### Start failures

- If PTY start fails, Worker emits `SessionStartFailedEvent`.
- Gateway treats the session as failed instead of silently leaving it attached.

### Unknown session commands

- `WriteInput`, `ResizeSession`, and `CloseSession` against a missing session do not crash the runtime.
- The Worker ignores them and logs the condition.

### Duplicate start

- A second `StartSession` for an existing session id is rejected as a start failure.

### Exit and cleanup

- Session exit triggers a single cleanup path.
- Cleanup removes the session from the active map and disposes process resources once.

## Testing Strategy

### Worker tests

Add focused tests for:

1. Worker runtime registers on connect.
2. `StartSession` creates a tracked runtime.
3. `WriteInput`, `ResizeSession`, and `CloseSession` hit the underlying PTY process.
4. stdout/stderr/exit are forwarded back through the gateway client.
5. reconnect triggers re-registration without duplicating active session entries.

### Gateway tests

Add focused tests for:

1. Session creation dispatches `StartSession` to the chosen worker.
2. Input, resize, and close dispatch to the owning worker only.
3. Worker start failure transitions the session out of the normal attached flow.
4. Worker exit is surfaced to the client and updates session state.

### End-to-end debugging baseline

After implementation, local debugging should support:

1. Start Gateway.
2. Start Worker.
3. Create a shell session.
4. Type input and receive live output.
5. Detach and reattach within the existing 5-minute lease.
6. See replay and continue live streaming.

## Implementation Notes

1. Reuse existing contracts where possible and add the minimum new worker control frames needed.
2. Keep orchestration code out of `Program.cs`; `Program.cs` should only bootstrap the host.
3. Keep `WorkerGatewayClient` as the narrow outbound adapter for registration and output/exit callbacks.
4. Keep replay ownership in Gateway; do not add worker-side replay APIs in this slice.
