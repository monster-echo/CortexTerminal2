# Mobile Virtual Keys for Terminal

## Problem

On mobile/touch devices, the terminal session detail page has no way to input control characters (Esc, Tab, arrow keys, Ctrl, Alt). The on-screen keyboard only produces printable characters, making terminal interaction severely limited.

## Solution

Add a floating, draggable virtual key panel to the terminal session detail page. The panel only appears on touch-capable devices and overlays the terminal viewport without affecting PTY size or layout.

## Data Flow

Virtual key clicks reuse the same input path as real keyboard input:

```
Virtual key click → control sequence string → onSendData callback
  → handleTerminalData (same callback as TerminalViewport's onData)
  → sessionRef.onTerminalData(data)
  → TextEncoder.encode(data) → writeInput(Uint8Array)
  → SignalR connection → server PTY
```

No modifications to `useTerminalSession`, `createBrowserTerminal`, `TerminalViewport`, or any stream processing logic.

## Component: `TerminalVirtualKeys`

**File:** `src/terminal/terminal-virtual-keys.tsx`

**Props:**
- `onSendData: (data: string) => void` — callback to inject terminal input (same as `handleTerminalData`)

**Keys (8 total):**

| Key   | Sequence    | Notes |
|-------|-------------|-------|
| Esc   | `\x1b`      | |
| Tab   | `\t`        | |
| Ctrl  | —           | Modifier: latched until next key press |
| Alt   | —           | Modifier: latched until next key press |
| ↑     | `\x1b[A`    | |
| ↓     | `\x1b[B`    | |
| ←     | `\x1b[D`    | |
| →     | `\x1b[C`    | |

**Ctrl modifier behavior:** When Ctrl is active (highlighted), pressing Esc sends `\x03` (Ctrl+C). Ctrl+letter combos are encoded as `String.fromCharCode(code & 0x1f)` where code is the letter's ASCII value. After sending, Ctrl automatically deactivates.

**Alt modifier behavior:** When Alt is active, the next key press prefixes the sequence with `\x1b`. After sending, Alt automatically deactivates.

**Layout:** Arrow keys in a cross/D-pad arrangement (↑ alone on top, ←↓→ on bottom row). Esc, Tab, Ctrl, Alt in a row above.

## Dragging

- A drag handle bar at the top of the panel (visually distinct, ~4px bar)
- Uses pointer events (`onPointerDown`, `onPointerMove`, `onPointerUp`) for cross-device compatibility
- Position tracked via `useState` with `{ x, y }` coordinates
- Applied via `position: fixed` + `transform: translate(x, y)`
- Initial position: bottom-center of viewport, 80px from bottom edge
- Drag constrained to viewport bounds (clamped)
- Panel does not move when tapping buttons (pointer move threshold of 3px to distinguish tap from drag)

## Visibility

- Only rendered when `'ontouchstart' in window` evaluates to true
- A toggle button (chevron icon) allows collapsing the panel to a small floating button
- Collapse state persisted in component state during session
- Collapsed button shows a keyboard icon, tapping it re-expands the panel at the same position

## Styling

- Semi-transparent dark background: `bg-slate-900/90 backdrop-blur-sm`
- Rounded corners: `rounded-xl`
- Keys: `rounded-lg bg-slate-700/80` with `active:bg-slate-600` press state
- Modifier keys (Ctrl, Alt) highlight with `bg-blue-600/80` when active
- Text: `text-slate-200 text-xs font-medium`
- Panel shadow: `shadow-lg`
- Touch targets: minimum 40x40px per button for usability

## Integration Point

In `TerminalView` (`src/terminal/terminal-view.tsx`), add after `TerminalViewport` and before `TerminalStatusBar`:

```tsx
<TerminalViewport ... />
<TerminalVirtualKeys onSendData={handleTerminalData} />
<TerminalStatusBar ... />
```

`handleTerminalData` is already defined in `TerminalView` and is the same callback passed as `onData` to `TerminalViewport`.

## Files Changed

| File | Action |
|------|--------|
| `src/terminal/terminal-virtual-keys.tsx` | **New** — virtual keys component |
| `src/terminal/terminal-view.tsx` | **Edit** — import and render `TerminalVirtualKeys` |

No changes to any other files. No changes to stream processing, session model, xterm configuration, or terminal viewport.
