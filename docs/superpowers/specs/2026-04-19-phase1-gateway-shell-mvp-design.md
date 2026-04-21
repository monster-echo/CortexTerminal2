# CortexTerminal Phase 1 Gateway Shell MVP Design

## Problem

CortexTerminal needs a first implementation slice that proves the core product claim: a user can authenticate from a mobile client, bind to a desktop execution node through the Gateway, and interact with a real desktop shell from mobile with low-latency, byte-transparent terminal I/O.

The full PRD spans authentication, mesh routing, worker lifecycle, environment injection, reconnect flows, audit tooling, updates, E2EE, and MCP. That scope is too broad for a single implementation cycle. This design narrows the first slice to a Phase 1 MVP that validates the platform foundation without taking on the higher-risk deferred capabilities.

## Scope

### In scope

- OAuth2 Device Flow login through the Gateway
- Secure token storage on mobile
- A single active interactive shell session per mobile client
- Gateway-mediated session creation and stream routing
- Generic PTY-backed shell execution on macOS and Linux workers
- Byte-transparent terminal input from mobile to worker
- Separate stdout and stderr binary streams from worker back to mobile
- iOS and Android mobile clients through the MAUI Hybrid + React stack
- Structured startup and termination errors surfaced to the terminal UI

### Out of scope

- Application-layer E2EE
- Session persistence after mobile disconnect
- Reconnect and reattach flows
- Log replay and scrollback recovery
- Windows worker support
- Entrypoint injection and runtime environment discovery
- AI-agent-specific session semantics for Claude Code, Aider, or MCP
- Desktop audit TUI and update pipeline
- Multi-session concurrency

## Recommended approach

Use a **Gateway-centered architecture** for Phase 1.

The Gateway owns authentication, worker selection, session metadata, and stream routing. The Worker is a thin PTY execution node that starts a generic shell and forwards raw byte streams. The mobile app handles login, token persistence, SignalR connectivity, and terminal rendering through a binary bridge into the React terminal UI.

This approach is preferred over worker-direct or agent-specific designs because it matches the long-term mesh architecture, keeps trust and orchestration boundaries explicit, and leaves room for the deferred reconnect, audit, and encryption work without redesigning the system spine.

## Architecture

### Mobile client

The mobile client is a .NET MAUI Hybrid application with a React terminal UI hosted through HybridWebView.

Responsibilities:

- Initiate Device Flow through the Gateway
- Store refresh tokens in native secure storage
- Establish authenticated SignalR connections
- Bridge binary frames between native code and the React terminal
- Render stdout and stderr with distinct treatment in the terminal experience

The React layer must remain transport-agnostic. It produces raw input bytes and consumes binary output frames. It must not interpret user input as command strings or introduce terminal-specific command abstractions.

### Gateway

The Gateway is the control-plane authority for Phase 1.

Responsibilities:

- Expose Device Flow endpoints through OpenIddict
- Validate access tokens for interactive session operations
- Track available workers and allocate one worker per new session
- Create and own session metadata and state transitions
- Relay input and output frames through SignalR without interpreting shell content
- Emit terminal metadata events such as session started, session exited, auth expired, and worker unavailable

The Gateway must not parse shell semantics or rewrite terminal payloads. It routes frames and owns orchestration, not command understanding.

### Worker

The Worker is a Native AOT runner on macOS and Linux.

Responsibilities:

- Register availability with the Gateway
- Start a generic login shell in a PTY
- Bind stdin, stdout, and stderr
- Forward stdout and stderr as separate binary channels
- Accept raw byte input frames and write them to the PTY
- Report PTY startup failures and process exit status

The Worker does not own authentication UX, device identity, reconnect policies, or environment injection in Phase 1.

## Session lifecycle

### 1. Device Flow start

The mobile app requests a device code from the Gateway and sends the user to the verification URI in the browser.

### 2. Token exchange

After the user approves the login, the mobile app exchanges the device flow grant for access and refresh tokens. The refresh token is stored in native secure storage.

### 3. Session creation

The mobile app requests `CreateSession(runtime=shell)` over an authenticated channel. The Gateway validates the caller, selects an available worker, creates a session record, and instructs the worker to initialize a shell session.

### 4. PTY startup

The worker launches a generic login shell and binds PTY I/O streams. If startup fails, the worker returns a structured startup failure and the Gateway marks the session as failed.

### 5. Stream attach

Once the PTY is ready, the mobile app attaches to the interactive session. Input flows from xterm.js as raw bytes through the MAUI binary bridge, over SignalR, and into the worker PTY writer. Output flows back as separate stdout and stderr binary frames.

### 6. Session end

The session ends when the user explicitly closes it, the shell exits, the PTY fails, or the Gateway terminates the session. The terminal UI receives a final exit event and stops accepting live input for that session.

## Message contract

Phase 1 uses SignalR over HTTP/3 with MessagePack-encoded control messages and binary payload frames. The transport contract in this phase is fixed at the interface level even if internal handler organization changes during implementation.

### Control messages

- `CreateSession(runtime=shell)`
- `AttachSession(sessionId)`
- `ResizePty(sessionId, cols, rows)`
- `CloseSession(sessionId)`

### Input message

- `WriteInput(sessionId, byte[])`

This is the only interactive input primitive. There is no string command API.

### Output messages

- `StdoutChunk(sessionId, byte[])`
- `StderrChunk(sessionId, byte[])`

These streams stay independent end to end so stderr is not delayed behind stdout buffering behavior.

### Metadata events

- `SessionStarted(sessionId, ptyInfo)`
- `SessionExited(sessionId, exitCode, reason)`
- `WorkerUnavailable(requestId, reason)`
- `AuthExpired(requestId)`
- `SessionStartFailed(sessionId, reason)`

## Security model

Phase 1 relies on:

- OAuth2 Device Flow for user authentication
- Access and refresh tokens for session authorization
- Native secure storage for refresh token persistence on mobile
- TLS-protected transport between mobile, Gateway, and worker-linked services

Phase 1 explicitly does **not** include application-layer E2EE. That work is deferred to a separate security design covering key generation, rotation, trust binding, and reconnect semantics.

The Gateway must never receive or derive shell meaning from terminal content. In Phase 1 this is mostly a separation-of-concerns requirement rather than a cryptographic guarantee.

## Failure model

Phase 1 chooses explicit failure over silent recovery.

### Authentication failure

If the access token is expired or invalid, session creation is rejected and the client is prompted to re-authenticate or refresh the session.

### Worker unavailable

If no eligible worker is available, session creation fails fast with a structured `WorkerUnavailable` error. The Gateway does not silently loop on retries.

### PTY startup failure

If the worker cannot create the shell, the client receives a terminal-visible startup error explaining that the session never became interactive.

### Gateway disconnect

If the Gateway connection is lost during an active session, the session is treated as ended for Phase 1. There is no keepalive-backed detached execution or reattach flow in this milestone.

## Component boundaries

The system should be implemented as small, isolated units with explicit interfaces:

- **Auth API**: device code issuance, token exchange, token validation
- **Worker registry**: track worker presence and selection eligibility
- **Session coordinator**: create sessions and own state transitions
- **Stream hub**: route binary frames between mobile and worker
- **PTY host**: start shell, bind streams, report process lifecycle
- **Mobile bridge**: map binary data between native and web terminal layers
- **Terminal adapter**: connect xterm.js input and output to the binary bridge

Boundary rules:

- Gateway does not interpret shell content
- Worker does not own mobile auth state or token logic
- Mobile does not fabricate command strings
- React UI does not depend on SignalR-specific details

## Testing strategy

### Automated tests

The implementation must include coverage for:

- Unauthorized and expired-token session creation
- No-worker-available flow
- PTY startup success and failure
- Separation of stdout and stderr channels
- Exit propagation from shell to mobile UI
- Byte transparency for terminal control sequences such as tab, ctrl-c, arrows, and escape
- Binary bridge integrity between native MAUI and the React layer

### Integration validation

The implementation must prove:

- Device Flow works on both iOS and Android
- A mobile client can open one interactive shell session on macOS and Linux workers
- A command that emits both stdout and stderr preserves channel separation
- PTY resize events change shell dimensions correctly

## Deferred follow-on work

Once this MVP is stable, the next major expansions can build on the same spine:

1. Session persistence after disconnect
2. Reconnect and log replay
3. Entrypoint injection and environment discovery
4. Windows worker support
5. Application-layer E2EE
6. Agent-aware runtime experiences and MCP integration

## Decision summary

Phase 1 is a **Gateway-centered, single-session, generic-shell MVP** for iOS, Android, macOS, and Linux. It proves mobile authentication and desktop shell interactivity first, while deliberately deferring reconnect, E2EE, environment injection, and platform expansion.
