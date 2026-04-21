# Gateway Console Design

## Problem

The current project can authenticate in limited ways, create shell sessions, and run a Worker-backed terminal flow, but it does not yet provide a usable Gateway console for human testing. There is no React console that lets a user log in, browse their sessions, inspect their Workers, and enter a live terminal from a page-oriented UI.

## Goal

Add a React-based Gateway console that:

1. Lets a developer log into the Gateway with a simplified development-time login flow.
2. Uses a page-based UI instead of placing all behavior in a single terminal component.
3. Treats sessions as the main user-facing resource.
4. Lets a user inspect only their own Workers as a supporting management view.
5. Uses SignalR for live terminal session behavior and HTTP for list/detail queries.

## Non-Goals

1. Production-grade identity and role management.
2. Cross-user worker visibility.
3. Worker migration or advanced operational controls.
4. Replacing the current SignalR terminal transport.
5. Turning Workers into the primary entry point for normal users.

## Recommended Approach

Keep the Gateway as the control plane and build a React console on top of it with clear page boundaries:

- **HTTP** for login, session list/detail, and worker list/detail.
- **SignalR** for entering a terminal session, streaming output, sending input, and supporting detach/reattach/replay.

This keeps the current architecture intact, minimizes risk to the terminal path, and provides the fastest route to usable end-to-end manual testing.

## Alternatives Considered

### 1. Recommended: Session-first React console with Worker pages as supporting views

Users land on a session-oriented dashboard. Worker pages are available, but secondary.

- **Pros:** Matches current Gateway/session architecture, supports testing quickly, avoids leaking execution topology into the main UX.
- **Cons:** Requires adding both session pages and worker pages.

### 2. Session-only console

Build only login + session list + session detail terminal.

- **Pros:** Fastest implementation.
- **Cons:** Does not satisfy the need to inspect Workers.

### 3. Worker-first console

The dashboard is centered on Workers, and users drill down from Workers into sessions.

- **Pros:** Strong operational view.
- **Cons:** Conflicts with the confirmed requirement that session should remain the main entry point.

## User Model

The console should assume:

- A user may have **multiple Workers**
- A Worker may host **multiple sessions**
- A session belongs to a user and records which Worker currently hosts it

Normal navigation should remain session-first:

1. The user logs into Gateway
2. The user sees their sessions
3. The user enters or reconnects to a session

Worker views are supplemental:

1. The user can view **their own Workers only**
2. The user can inspect which sessions a Worker is hosting
3. The user can jump from a Worker detail page into a session detail page

## UI Architecture

The console should be implemented as a page-based React application with separated concerns.

### Pages

#### Login page

Responsibilities:

- Accept a development username
- Call the development login endpoint
- Store the returned token
- Redirect into the console

#### Session list page

Responsibilities:

- Default landing page after login
- Show the current user’s sessions
- Start a new session
- Enter an existing session
- Display basic status such as `live`, `detached`, `expired`, or `exited`

#### Session detail page

Responsibilities:

- Host the terminal UI
- Establish the SignalR terminal connection
- Display replay/reattach/expired state
- Support detach/reattach behavior

#### Worker list page

Responsibilities:

- Show only the current user’s Workers
- Display online/offline state and summary information

#### Worker detail page

Responsibilities:

- Show one Worker’s summary
- List sessions hosted on that Worker
- Link to session detail pages

### Frontend structure

Use clear page and feature boundaries:

- `pages/` for route-level pages
- `components/` for reusable UI building blocks
- `services/` for Gateway HTTP and SignalR clients
- `terminal/` for terminal-specific session model and view logic

The current terminal logic should remain isolated rather than becoming the place where all dashboard behavior accumulates.

## Backend Responsibilities

Gateway remains the owner of:

1. Authentication and authorization
2. Worker/session query authorization
3. Session routing to Workers
4. Terminal attach/detach/reattach policy

Worker remains the owner of:

1. PTY execution
2. Terminal byte streaming
3. Session runtime lifecycle on the execution node

## Login Strategy

For this phase, use a **development-time simplified login** rather than Device Flow.

### Why not Device Flow here

Device Flow is acceptable for device-oriented or external activation scenarios, but it is too awkward for a local React console whose immediate goal is end-to-end testing.

### Development login flow

1. The Login page accepts a development username.
2. Gateway exposes a development login endpoint in development mode only.
3. Gateway returns a token for that development user.
4. The frontend stores that token and reuses it for both HTTP and SignalR connections.

### Future compatibility

This keeps the console loosely coupled to authentication:

- The login page can later switch to a production auth mechanism.
- Session and Worker pages do not need to change their core information architecture.

## Data Contracts and API Shape

### Worker summaries

The console needs a Worker summary shape containing:

- `workerId`
- `displayName`
- `isOnline`
- `sessionCount`
- `lastSeenAt`

### Session summaries

The console needs a Session summary shape containing:

- `sessionId`
- `workerId`
- `status`
- `createdAt`
- `lastActivityAt`

### Recommended HTTP endpoints

#### `POST /api/dev/login`

Development-only login endpoint.

Input:

- `username`

Output:

- bearer token payload for the console

#### `GET /api/me/sessions`

Returns only the current user’s sessions.

#### `GET /api/me/sessions/{sessionId}`

Returns one session detail record if owned by the current user.

#### `GET /api/me/workers`

Returns only the current user’s Workers.

#### `GET /api/me/workers/{workerId}`

Returns one Worker detail plus its hosted session summaries if the Worker belongs to the current user.

#### `POST /api/sessions`

Continue using the existing session creation endpoint.

## SignalR Usage

SignalR remains required for the live terminal path.

### Use SignalR for

1. Session attach
2. Session input/output
3. Detach
4. Reattach
5. Replay lifecycle events
6. Expiration events

### Do not require SignalR for

1. Session list queries
2. Worker list queries
3. Worker detail queries

This keeps the dashboard simpler and more robust while preserving the live terminal path exactly where real-time behavior matters.

## Authorization Rules

The backend must enforce:

1. A user can see only **their own sessions**
2. A user can see only **their own Workers**
3. Accessing another user’s Worker or session returns `403`
4. Session entry always resolves by `sessionId`, not by trusting a client-selected Worker route

This preserves Gateway ownership of routing and prevents the frontend from becoming the source of truth for session placement.

## Error Handling

### Login failures

- Return a clear invalid-login response from the development login endpoint
- Show a clear login error in the UI

### Worker offline or unavailable

- Session creation or entry should surface a clear error
- Do not leave the user with a silently dead terminal page

### Expired session

- Session detail page should present expired state clearly
- User should be able to return to the session list and start or enter a different session

### Unauthorized access

- Worker or session routes that are not owned by the current user should fail with `403`
- Frontend should redirect or show an access-denied state

## Testing Strategy

### Gateway tests

Add coverage for:

1. Development login endpoint behavior
2. `/api/me/sessions` returning only the current user’s sessions
3. `/api/me/workers` returning only the current user’s Workers
4. Worker detail access restrictions

### React tests

Add coverage for:

1. Login flow and token persistence
2. Session list rendering and navigation
3. Worker list rendering and Worker detail navigation
4. Session detail page entering the terminal route
5. Routing between session and Worker pages

### Integration / manual testing target

After implementation, the expected manual flow is:

1. Log into the Gateway console with a development username
2. View the current user’s sessions
3. Create or enter a session
4. Interact with the terminal through SignalR
5. Detach and reattach with replay
6. View the current user’s Workers
7. Drill down from a Worker to one of its sessions

## Implementation Notes

1. Keep the current `terminal/` module focused on terminal behavior only.
2. Introduce pages and routing instead of continuing to grow a single terminal view.
3. Prefer adding Gateway query endpoints over leaking Worker internals into the frontend.
4. Keep the development login explicitly scoped to development/test workflows.
