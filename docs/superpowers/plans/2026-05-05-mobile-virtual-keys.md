# Mobile Virtual Keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a floating, draggable virtual key panel to the terminal session page that only appears on touch devices, allowing mobile users to input Esc, Tab, Ctrl, Alt, and arrow keys.

**Architecture:** A new `TerminalVirtualKeys` React component renders a fixed-position panel with 8 virtual keys. Pointer events handle dragging. Touch detection gates visibility. Data flows through the same `handleTerminalData` callback used by real keyboard input — zero changes to stream processing.

**Tech Stack:** React 19, TypeScript, Tailwind CSS v4, xterm.js escape sequences

---

### Task 1: Create `terminal-virtual-keys.tsx` component

**Files:**
- Create: `src/Gateway/CortexTerminal.Console/src/terminal/terminal-virtual-keys.tsx`

- [ ] **Step 1: Create the component file**

```tsx
import { useCallback, useEffect, useRef, useState } from 'react'

interface VirtualKey {
  label: string
  sequence: string
  isModifier?: boolean
}

const VIRTUAL_KEYS: VirtualKey[] = [
  { label: 'Esc', sequence: '\x1b' },
  { label: 'Tab', sequence: '\t' },
  { label: 'Ctrl', sequence: '', isModifier: true },
  { label: 'Alt', sequence: '', isModifier: true },
]

const ARROW_KEYS: VirtualKey[] = [
  { label: '↑', sequence: '\x1b[A' },
  { label: '←', sequence: '\x1b[D' },
  { label: '↓', sequence: '\x1b[B' },
  { label: '→', sequence: '\x1b[C' },
]

const DRAG_THRESHOLD = 3

function applyModifier(modifier: 'ctrl' | 'alt', sequence: string): string {
  if (modifier === 'ctrl') {
    // For Esc (0x1b), Ctrl+Esc = Ctrl+C (0x03)
    // For printable ASCII letters, Ctrl+letter = code & 0x1f
    const code = sequence.charCodeAt(0)
    if (code === 0x1b) return '\x03' // Ctrl+Esc → Ctrl+C
    if (code >= 0x41 && code <= 0x5a) return String.fromCharCode(code - 64) // A-Z → 1-26
    if (code >= 0x61 && code <= 0x7a) return String.fromCharCode(code - 96) // a-z → 1-26
    return sequence
  }
  // Alt: prefix with ESC
  return '\x1b' + sequence
}

export function TerminalVirtualKeys(props: {
  onSendData: (data: string) => void
}) {
  const { onSendData } = props
  const [collapsed, setCollapsed] = useState(false)
  const [ctrlActive, setCtrlActive] = useState(false)
  const [altActive, setAltActive] = useState(false)
  const [position, setPosition] = useState<{ x: number; y: number } | null>(null)
  const panelRef = useRef<HTMLDivElement | null>(null)
  const dragState = useRef<{
    startX: number
    startY: number
    offsetX: number
    offsetY: number
    dragging: boolean
  }>({ startX: 0, startY: 0, offsetX: 0, offsetY: 0, dragging: false })

  // Initialize position on mount: bottom-center, 80px from bottom
  useEffect(() => {
    if (position === null) {
      const x = window.innerWidth / 2 - 130
      const y = window.innerHeight - 200
      setPosition({ x: Math.max(0, x), y: Math.max(0, y) })
    }
  }, [position])

  const handleKeyDown = useCallback(
    (key: VirtualKey) => {
      if (key.isModifier) {
        if (key.label === 'Ctrl') setCtrlActive((v) => !v)
        if (key.label === 'Alt') setAltActive((v) => !v)
        return
      }

      let sequence = key.sequence
      if (ctrlActive) {
        sequence = applyModifier('ctrl', sequence)
        setCtrlActive(false)
      } else if (altActive) {
        sequence = applyModifier('alt', sequence)
        setAltActive(false)
      }
      onSendData(sequence)
    },
    [onSendData, ctrlActive, altActive]
  )

  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    // Only drag from the handle area
    const target = e.target as HTMLElement
    if (!target.closest('[data-drag-handle]')) return

    dragState.current = {
      startX: e.clientX,
      startY: e.clientY,
      offsetX: 0,
      offsetY: 0,
      dragging: false,
    }
    ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
  }, [])

  const handlePointerMove = useCallback(
    (e: React.PointerEvent) => {
      const ds = dragState.current
      if (ds.startX === 0 && ds.startY === 0) return

      const dx = e.clientX - ds.startX
      const dy = e.clientY - ds.startY

      if (!ds.dragging && Math.abs(dx) < DRAG_THRESHOLD && Math.abs(dy) < DRAG_THRESHOLD) {
        return
      }

      ds.dragging = true
      ds.offsetX = dx
      ds.offsetY = dy

      if (position) {
        const newX = Math.max(0, Math.min(window.innerWidth - 260, position.x + dx))
        const newY = Math.max(0, Math.min(window.innerHeight - 60, position.y + dy))
        setPosition({ x: newX, y: newY })
        ds.startX = e.clientX
        ds.startY = e.clientY
        ds.offsetX = 0
        ds.offsetY = 0
      }
    },
    [position]
  )

  const handlePointerUp = useCallback(() => {
    dragState.current.dragging = false
  }, [])

  // Only render on touch-capable devices
  const [isTouchDevice, setIsTouchDevice] = useState(false)
  useEffect(() => {
    setIsTouchDevice('ontouchstart' in window || navigator.maxTouchPoints > 0)
  }, [])

  if (!isTouchDevice) return null

  if (collapsed) {
    return (
      <button
        onClick={() => setCollapsed(false)}
        className="fixed z-50 flex size-11 items-center justify-center rounded-full bg-slate-900/90 text-slate-200 shadow-lg backdrop-blur-sm"
        style={{
          left: position?.x ?? window.innerWidth / 2 - 22,
          top: position?.y ?? window.innerHeight - 200,
        }}
        aria-label="Show virtual keys"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="2" y="4" width="20" height="16" rx="2" />
          <path d="M6 8h.01M10 8h.01M14 8h.01M18 8h.01M8 12h.01M12 12h.01M16 12h.01M7 16h10" />
        </svg>
      </button>
    )
  }

  return (
    <div
      ref={panelRef}
      className="fixed z-50 rounded-xl border border-slate-700/50 bg-slate-900/90 shadow-lg backdrop-blur-sm"
      style={{
        left: position?.x ?? 0,
        top: position?.y ?? 0,
        touchAction: 'none',
      }}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
    >
      {/* Drag handle */}
      <div
        data-drag-handle=""
        className="flex cursor-grab items-center justify-center px-2 pt-1.5 pb-1 active:cursor-grabbing"
      >
        <div className="h-1 w-8 rounded-full bg-slate-600" />
      </div>

      {/* Modifier + control keys row */}
      <div className="flex gap-1 px-2 pb-1.5">
        {VIRTUAL_KEYS.map((key) => (
          <button
            key={key.label}
            className={`flex h-9 min-w-[2.5rem] flex-1 items-center justify-center rounded-lg text-xs font-medium transition-colors ${
              key.label === 'Ctrl' && ctrlActive
                ? 'bg-blue-600/80 text-white'
                : key.label === 'Alt' && altActive
                  ? 'bg-blue-600/80 text-white'
                  : 'bg-slate-700/80 text-slate-200 active:bg-slate-600'
            }`}
            onPointerDown={(e) => {
              e.stopPropagation()
            }}
            onClick={() => handleKeyDown(key)}
          >
            {key.label}
          </button>
        ))}
      </div>

      {/* Arrow keys in cross layout */}
      <div className="flex flex-col items-center gap-1 px-2 pb-2">
        <div className="flex justify-center">
          <button
            className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(ARROW_KEYS[0])}
          >
            ↑
          </button>
        </div>
        <div className="flex gap-1">
          <button
            className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(ARROW_KEYS[1])}
          >
            ←
          </button>
          <button
            className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(ARROW_KEYS[2])}
          >
            ↓
          </button>
          <button
            className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(ARROW_KEYS[3])}
          >
            →
          </button>
        </div>
      </div>

      {/* Collapse button */}
      <button
        className="absolute -right-1.5 -top-1.5 flex size-5 items-center justify-center rounded-full bg-slate-700 text-slate-300 shadow"
        onClick={() => {
          setCollapsed(true)
          setCtrlActive(false)
          setAltActive(false)
        }}
        aria-label="Hide virtual keys"
      >
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>
  )
}
```

- [ ] **Step 2: Commit the new component**

```bash
git add src/Gateway/CortexTerminal.Console/src/terminal/terminal-virtual-keys.tsx
git commit -m "feat(terminal): add floating virtual key panel for mobile devices"
```

---

### Task 2: Integrate into `TerminalView`

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/terminal/terminal-view.tsx`

- [ ] **Step 1: Add import and render `TerminalVirtualKeys`**

In `terminal-view.tsx`:
- Add import: `import { TerminalVirtualKeys } from './terminal-virtual-keys'`
- Add `<TerminalVirtualKeys onSendData={handleTerminalData} />` after `<TerminalViewport>` and before `<TerminalStatusBar>`

The JSX return becomes:
```tsx
return (
    <div className='flex h-full min-h-0 flex-col'>
      <TerminalViewport
        errorMessage={errorMessage}
        onData={handleTerminalData}
        onEvent={handleViewportEvent}
        onReady={handleTerminalReady}
        onResize={handleTerminalResize}
      />
      <TerminalVirtualKeys onSendData={handleTerminalData} />
      <TerminalStatusBar
        status={effectiveStatus}
        sessionId={sessionId}
        workerId={workerId}
        latencyMs={latencyMs}
        cols={terminalSize.columns}
        rows={terminalSize.rows}
        statusMessage={statusMessage}
      />
    </div>
  )
```

- [ ] **Step 2: Verify build compiles**

Run: `cd src/Gateway/CortexTerminal.Console && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit integration**

```bash
git add src/Gateway/CortexTerminal.Console/src/terminal/terminal-view.tsx
git commit -m "feat(terminal): integrate virtual keys into terminal session view"
```
