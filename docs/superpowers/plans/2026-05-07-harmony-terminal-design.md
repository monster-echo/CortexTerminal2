# HarmonyOS Terminal Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Stitch HarmonyOS prototype in `~/Downloads/stitch_remote_terminal_manager` into an implementation-ready mobile terminal design spec for the future ArkTS/ArkUI client.

**Architecture:** The HarmonyOS app is terminal-first. ArkUI owns app navigation and native state, ArkWeb owns xterm.js rendering, and ArkTS owns the WebSocket terminal transport. The UI must make reconnect, replay, and live terminal state visible because HarmonyOS backgrounding can suspend or break WebView/network work.

**Tech Stack:** HarmonyOS 6 / NEXT, ArkTS, ArkUI, ArkWeb, xterm.js, native ArkTS WebSocket, JSON + base64 terminal frames.

**Prototype References:**
- Design system: `~/Downloads/stitch_remote_terminal_manager/source_code_pro/DESIGN.md`
- Activate worker: `~/Downloads/stitch_remote_terminal_manager/_3/screen.png`
- Terminal empty: `~/Downloads/stitch_remote_terminal_manager/_4/screen.png`
- Drawer: `~/Downloads/stitch_remote_terminal_manager/more/screen.png`
- Worker list: `~/Downloads/stitch_remote_terminal_manager/worker_1/screen.png`
- Worker detail: `~/Downloads/stitch_remote_terminal_manager/worker_2/screen.png`
- Settings: `~/Downloads/stitch_remote_terminal_manager/_1/screen.png`

---

## Decisions Locked

| Area | Decision |
|------|----------|
| Primary app path | Terminal-first. Opening the app prioritizes recent/restorable sessions and new terminal creation. |
| Navigation | Keep the left drawer pattern from the prototype. Do not switch to bottom tabs. |
| Terminal status | Use a full state strip: `connected`, `reconnecting`, `detached`, `replaying`, `live`, `expired`, `exited`. |
| Mobile input | Use a collapsible virtual key bar for terminal control keys. |
| Shape language | Use a consistent `4px` corner radius for controls and containers; round only avatars/status dots. |
| Web transport | Do not run SignalR in ArkWeb. ArkTS connects to Gateway through pure WebSocket. |

---

### Task 1: Define the Terminal-First Information Architecture

- [ ] **Step 1: Replace generic empty terminal content with terminal actions**

The Terminal home screen must not lead with desktop keyboard shortcuts. It should show:

1. Most recent restorable session, if one exists.
2. Primary action: `New Terminal`.
3. Secondary action: `Select Worker`.
4. Recovery status if the last session is detached or replaying.

Recommended hierarchy:

```text
Top bar: menu | TERMINAL | command/search | new

Terminal Home
  Recent session
    status chip: live / detached / expired
    worker name
    last activity
    primary action: Resume

  New terminal
    primary action: Start on best worker
    secondary action: Choose worker

  Worker availability strip
    online count
    degraded/offline count
```

- [ ] **Step 2: Keep Workers as the diagnostic path**

The worker list and worker detail screens remain secondary, used when the user needs to choose a specific node, inspect health, or join another session.

- [ ] **Step 3: Update drawer IA**

Drawer sections:

```text
Sessions
  Recent session rows with live/detached/expired markers
Workers
Settings
```

The drawer footer keeps account/server information, but the version label should move below the account area and never compete with primary navigation.

---

### Task 2: Specify Terminal Connection States

- [ ] **Step 1: Add a persistent terminal state strip**

The state strip appears above the virtual key bar or directly below the top app bar when the keyboard is hidden.

| State | What user sees | Input behavior |
|-------|----------------|----------------|
| `connected` | `Connected. Preparing terminal...` | Disabled until xterm is ready |
| `reconnecting` | `Reconnecting to gateway...` with spinner | Disabled |
| `detached` | `Session kept alive. Reconnect to resume.` | Disabled |
| `replaying` | `Restoring output...` with progress/animated indicator | Disabled or buffered only if explicitly supported |
| `live` | `Live` with latency if available | Enabled |
| `expired` | `Session expired` with `Start new terminal` | Read-only |
| `exited` | `Session exited` with exit code/reason | Read-only |

- [ ] **Step 2: Map lifecycle transitions**

```text
open terminal -> connected -> replaying -> live
app background -> detached or reconnecting
app foreground -> reconnecting -> replaying -> live
server lease expired -> expired
PTY exits -> exited
network fails -> reconnecting
auth fails -> login required
```

- [ ] **Step 3: Make replay visible**

Replay output must be visually distinct from live output through the state strip. Do not rely on toast messages for replay/live status.

---

### Task 3: Design the xterm Terminal Screen

- [ ] **Step 1: Define the terminal page layout**

```text
Top app bar
  back/menu
  session name or worker name
  status/action icons

Terminal status strip

ArkWeb xterm viewport

Collapsible virtual key bar
  Esc Ctrl Alt Tab Paste
  arrow cluster
  optional shortcut row
```

- [ ] **Step 2: Preserve terminal space**

The drawer, command palette, and virtual key bar must not permanently reduce xterm space. When the keyboard appears, recompute xterm rows/columns and send `resize` through ArkTS.

- [ ] **Step 3: Define readonly terminal states**

Expired/exited sessions keep scrollback visible but disable input. Provide one primary action: `Start new terminal`.

---

### Task 4: Specify the Virtual Key Bar

- [ ] **Step 1: Use a collapsible bar**

Default visible keys:

| Key | Purpose |
|-----|---------|
| Esc | Shell/vim escape |
| Ctrl | Latched modifier |
| Alt | Latched modifier |
| Tab | Completion |
| Paste | Clipboard paste |
| Arrows | History and cursor movement |

- [ ] **Step 2: Define behavior**

Ctrl and Alt latch for one key press, then reset. The expanded bar may be dragged or collapsed, but it must keep touch targets at least `44px`.

- [ ] **Step 3: Trigger resize**

Every change that affects terminal viewport height must trigger a debounced xterm fit and ArkTS `resize` message:

```text
keyboard shown/hidden
orientation changed
virtual key bar expanded/collapsed
drawer opened/closed if it changes viewport size
```

---

### Task 5: Apply the Visual System

- [ ] **Step 1: Use the prototype design tokens**

Base tokens come from `source_code_pro/DESIGN.md`:

- Background: deep charcoal surfaces.
- Accent: blue for primary actions.
- Success: green for live/active.
- Error: red for expired/error.
- Typography: Space Grotesk for headings/technical labels, Inter for body text.
- Spacing: 4px baseline, 16px edge margin.

- [ ] **Step 2: Override shape rules for mobile**

Use `4px` radius consistently for:

- buttons
- inputs
- session rows
- worker cards
- drawer active rows
- status chips
- bottom/sheet surfaces

Only avatars and status dots may be fully round.

- [ ] **Step 3: Avoid decorative UI**

Do not add generic SaaS feature grids, oversized cards, decorative blobs, or hero sections. This is a task tool, not a landing page.

---

### Task 6: Define Worker Screens as Terminal Support

- [ ] **Step 1: Worker list screen**

Worker cards show only decision-making data:

- worker name
- online/offline/degraded state
- CPU
- memory
- uptime
- active session count
- primary action: `Open` or `Manage`

- [ ] **Step 2: Worker detail screen**

Worker detail prioritizes:

1. worker health summary
2. active sessions with `Join`
3. pending/exited sessions
4. logs/diagnostics below the fold

- [ ] **Step 3: Session rows**

Each session row must show:

- session id/name
- user/process metadata
- status chip
- last activity or uptime
- primary action: `Join`, `Resume`, `Wait`, or `Read only`

---

### Task 7: Accessibility and HarmonyOS Fit

- [ ] **Step 1: Touch targets**

All tappable controls must be at least `44px` high/wide. Small icon buttons in the prototype need larger hit areas even when the visual icon stays small.

- [ ] **Step 2: Contrast**

Body text must meet 4.5:1 contrast. Dim metadata may be visually quiet but cannot become unreadable on OLED dark mode.

- [ ] **Step 3: Labels**

Inputs must have visible labels. Placeholder-only labels are not allowed, especially on the activate worker code input.

- [ ] **Step 4: Screen reader semantics**

ArkUI pages must expose:

- page title
- drawer navigation labels
- terminal state strip
- disabled reason for inactive buttons
- worker/session state labels, not color-only dots

---

## Gateway WebSocket Contract Required by This Design

The HarmonyOS design assumes Gateway provides:

```text
wss://<gateway-host>/terminal/ws?sessionId=<sessionId>
Authorization: Bearer <token>
```

Client frames:

```json
{ "type": "input", "sessionId": "sess_xxx", "payload": "base64" }
{ "type": "resize", "sessionId": "sess_xxx", "columns": 120, "rows": 32 }
{ "type": "detach", "sessionId": "sess_xxx" }
{ "type": "close", "sessionId": "sess_xxx" }
{ "type": "ping", "timestamp": 1710000000000 }
```

Server frames:

```json
{ "type": "replaying", "sessionId": "sess_xxx" }
{ "type": "replay", "sessionId": "sess_xxx", "stream": "stdout", "payload": "base64" }
{ "type": "replayCompleted", "sessionId": "sess_xxx" }
{ "type": "output", "sessionId": "sess_xxx", "stream": "stdout", "payload": "base64" }
{ "type": "live", "sessionId": "sess_xxx" }
{ "type": "expired", "sessionId": "sess_xxx", "reason": "session-expired" }
{ "type": "exited", "sessionId": "sess_xxx", "exitCode": 0, "reason": "completed" }
{ "type": "error", "sessionId": "sess_xxx", "code": "session-not-found", "message": "..." }
```

---

## Acceptance Tests

- [ ] App opens to a terminal-first screen where the user can resume or create a terminal in one obvious action.
- [ ] Empty state never shows desktop-only shortcuts as the primary content on mobile.
- [ ] Terminal page distinguishes `replaying` from `live`.
- [ ] Background/foreground returns to `reconnecting -> replaying -> live` without blank terminal confusion.
- [ ] Expired/exited sessions remain readable and disable input.
- [ ] Virtual key bar supports Esc, Ctrl, Alt, Tab, arrows, and paste.
- [ ] Keyboard, orientation, and virtual-key changes trigger xterm resize and Gateway resize.
- [ ] Drawer shows Sessions, Workers, Settings with clear selected state.
- [ ] Worker list and worker detail help the terminal task instead of becoming a separate dashboard-first experience.
- [ ] Every tappable item meets 44px touch target requirements.
- [ ] State is not expressed by color alone.

---

## Out of Scope

- Building the HarmonyOS project skeleton.
- Implementing Gateway WebSocket endpoint.
- Replacing the existing MAUI mobile client.
- Running AppGallery/HarmonyOS signing or store submission.
- Designing a marketing/landing page.
