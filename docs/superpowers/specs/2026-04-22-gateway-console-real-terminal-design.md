# Gateway Console Real Terminal Design

## Problem

The Gateway console is now hosted from the Gateway itself, but the terminal experience is still a placeholder. The current `TerminalView` renders streamed output into a `<pre>` and sends only a trivial test input action. This is sufficient to prove the SignalR path exists, but it is not a real console for PTY interaction.

At the same time, the current page shell does not yet present the Worker information tightly enough alongside terminal interaction for real debugging and manual integration work.

## Goal

Upgrade the Gateway console into a real browser console that:

1. Uses `shadcn/ui` and Tailwind CSS across the existing Gateway console pages.
2. Replaces the placeholder terminal view with a real `xterm.js` terminal in Session detail.
3. Lets a user interact with the Worker-hosted PTY through the browser console.
4. Shows the current session’s Worker information clearly in the same console experience.
5. Preserves the current Gateway/Worker protocol and session-first information architecture.

## Non-Goals

1. Replacing the current Gateway SignalR protocol.
2. Redesigning the backend authorization model.
3. Turning Workers into the primary navigation model.
4. Implementing every advanced terminal feature that `xterm.js` can support.
5. Doing a broad backend refactor unrelated to the console UX.

## Recommended Approach

Keep the current Gateway API contracts, SignalR session flow, and session-first routing model. Replace the front-end shell and terminal presentation layer:

- introduce `Tailwind CSS + shadcn/ui` as the UI system
- restyle the existing Gateway console pages on that foundation
- upgrade `SessionDetailPage` to host a real `xterm.js` terminal
- show the current Worker’s real information beside the live terminal

This delivers a real console without destabilizing the Gateway/Worker protocol path that is already working.

## Alternatives Considered

### 1. Recommended: Full console UI upgrade + real terminal

Upgrade all existing console pages to `shadcn/ui` and implement a real `xterm.js` terminal in Session detail.

- **Pros:** consistent UX, real terminal interaction, best path for continued console development
- **Cons:** larger front-end change set than a single-page patch

### 2. Terminal-only upgrade

Upgrade only `SessionDetailPage` to use `xterm.js`, leaving the rest of the console UI as-is.

- **Pros:** fastest route to a real PTY terminal
- **Cons:** leaves the console visually inconsistent and still requires a later UI consolidation pass

### 3. Infrastructure-first UI migration

Introduce Tailwind and `shadcn/ui`, but defer real terminal work to a later step.

- **Pros:** lowers immediate UI migration risk
- **Cons:** does not solve the actual “real console” requirement yet

## Information Architecture

The console remains **session-first**.

Normal flow:

1. User opens the Gateway console.
2. User logs in.
3. User lands on Sessions.
4. User enters a Session.
5. User interacts with the PTY through the browser terminal.

Worker views remain supplemental:

1. User can view only their own Workers.
2. User can inspect one Worker’s details and hosted sessions.
3. User can jump from a Worker detail view to the corresponding Session detail view.

The Worker is therefore visible and inspectable, but it does not replace Session as the main entry point.

## UI System

### Styling foundation

The Web project will adopt:

- `Tailwind CSS`
- `shadcn/ui`
- the standard utility stack needed by `shadcn/ui`

This provides a stable component vocabulary for:

- forms
- buttons
- cards
- tables
- badges
- alerts
- layout containers

### Scope of UI migration

This migration covers the existing Gateway console pages, not just the terminal screen:

- `AppLayout`
- `LoginPage`
- `SessionListPage`
- `SessionDetailPage`
- `WorkerListPage`
- `WorkerDetailPage`

The goal is a single coherent console UI rather than a mixed old/new shell.

## Real Terminal Design

### Terminal host

`SessionDetailPage` remains the route that hosts terminal interaction, but `TerminalView` changes from a text dump to a real `xterm.js` instance.

The browser terminal must support:

1. live PTY output rendering
2. keyboard input
3. terminal resize
4. replay rendering after reattach
5. expired/disconnected state handling
6. selection and copy-friendly behavior
7. scrollback-oriented reading

### Terminal boundaries

The existing architecture should be preserved where it already works:

- `terminalGateway.ts` remains the SignalR boundary
- `useTerminalSession.ts` remains the session-state model for replay/reattach/expired semantics
- `TerminalView.tsx` becomes the xterm host and adapter layer

This keeps protocol handling separate from visual terminal implementation.

### Xterm addons

At minimum, use the fit/resize path needed to keep the browser terminal aligned with its container. Other addons are optional and should be added only when they directly serve the required UX.

The required baseline behavior is:

- the terminal visually fits the available panel
- resize events propagate back to Gateway
- the terminal can be used for real manual PTY interaction

## Session Detail Layout

`SessionDetailPage` should become a two-part console view:

### Primary area

- the real `xterm.js` terminal
- terminal status information such as `live`, `reattached`, `replaying`, or `expired`
- session-level error or expired messaging

### Supporting Worker information panel

The same page should display the session’s current Worker information, at least:

- `workerId`
- online/offline status
- `lastSeen`
- current session count

This gives the user the ability to confirm where the PTY is running without leaving the live terminal page.

## Worker Views

The Worker pages remain in the console and should also be upgraded to `shadcn/ui`.

### Worker list page

- show only the current user’s Workers
- show summary data in a cleaner management view
- allow navigating to Worker detail

### Worker detail page

- show Worker summary information
- show sessions hosted by that Worker
- allow jumping into Session detail

The Worker pages provide context and drill-down, but the live PTY interaction still belongs in Session detail.

## Data Flow

### HTTP

Continue using HTTP for:

- development login
- sessions list/detail
- workers list/detail

### SignalR

Continue using SignalR for:

- session attach
- output streaming
- input sending
- detach/reattach
- replay flow
- expiration / start-failure / exit notifications

### Terminal flow

The front-end terminal flow should be:

1. `SessionDetailPage` loads session detail through HTTP.
2. The page renders Worker summary information from the session/worker query path.
3. `TerminalView` creates an `xterm.js` instance.
4. `terminalGateway` connects to `/hubs/terminal`.
5. Stream events write bytes into the terminal.
6. User keystrokes send input frames back to Gateway.
7. Terminal resize updates flow back through `ResizeSession`.

## Error Handling

### Login

- show a visible inline login error
- do not silently drop the user back to the page

### Terminal connection failure

- show a terminal-specific error state
- do not leave an empty terminal panel with no explanation

### Session expired or exited

- clearly mark the session as expired/exited
- preserve enough page context for the user to navigate back to Sessions

### Worker unavailable

- show a clear session detail error state if the session cannot be attached or the Worker is unavailable

## Testing Strategy

### Front-end component tests

Add or update coverage for:

1. `shadcn/ui`-backed page rendering still respecting current routes
2. `SessionDetailPage` rendering Worker info and terminal container together
3. terminal mount/dispose behavior around `xterm.js`
4. session state transitions (`live`, `reattached`, `replaying`, `expired`)
5. key input flowing from terminal UI into the existing session model

`xterm.js` itself should be mocked at the boundary where appropriate. The goal is to verify the app’s integration logic, not to test the third-party library internals.

### Existing backend tests

Preserve and rerun the current Gateway/Worker/Mobile test suites. This work should not require protocol redesign, so regression protection matters more than new backend surface area.

### Manual verification target

The expected manual flow after implementation is:

1. Open the Gateway console from the Gateway root URL.
2. Log in with a development username.
3. View Sessions.
4. Create or enter a Session.
5. Interact with the Worker PTY through the real browser terminal.
6. Observe the current Worker information in the same session page.
7. Detach and reattach with replay.
8. Navigate to Worker pages and drill down back into Sessions.

## Implementation Notes

1. Keep protocol-layer changes to a minimum.
2. Prefer focused front-end adapters over rewriting the SignalR client.
3. Keep Session as the primary terminal entry point.
4. Treat Worker information as adjacent operational context, not the main interaction model.
