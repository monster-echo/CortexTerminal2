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

const ARROW_UP: VirtualKey = { label: '↑', sequence: '\x1b[A' }
const ARROW_LEFT: VirtualKey = { label: '←', sequence: '\x1b[D' }
const ARROW_DOWN: VirtualKey = { label: '↓', sequence: '\x1b[B' }
const ARROW_RIGHT: VirtualKey = { label: '→', sequence: '\x1b[C' }

const DRAG_THRESHOLD = 3

function applyCtrlModifier(sequence: string): string {
  const code = sequence.charCodeAt(0)
  // Ctrl+Esc → Ctrl+C
  if (code === 0x1b) return '\x03'
  // Ctrl+A-Z → 0x01-0x1a
  if (code >= 0x41 && code <= 0x5a) return String.fromCharCode(code - 64)
  // Ctrl+a-z → 0x01-0x1a
  if (code >= 0x61 && code <= 0x7a) return String.fromCharCode(code - 96)
  return sequence
}

function applyAltModifier(sequence: string): string {
  return '\x1b' + sequence
}

export function TerminalVirtualKeys(props: {
  onSendData: (data: string) => void
}) {
  const { onSendData } = props
  const [collapsed, setCollapsed] = useState(false)
  const [ctrlActive, setCtrlActive] = useState(false)
  const [altActive, setAltActive] = useState(false)
  const [position, setPosition] = useState<{ x: number; y: number } | null>(
    null
  )
  const dragState = useRef({
    startX: 0,
    startY: 0,
    dragging: false,
  })

  // Initialize position: bottom-center, 80px from bottom
  useEffect(() => {
    if (position === null) {
      const x = window.innerWidth / 2 - 130
      const y = window.innerHeight - 200
      setPosition({ x: Math.max(8, x), y: Math.max(8, y) })
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
        sequence = applyCtrlModifier(sequence)
        setCtrlActive(false)
      } else if (altActive) {
        sequence = applyAltModifier(sequence)
        setAltActive(false)
      }
      onSendData(sequence)
    },
    [onSendData, ctrlActive, altActive]
  )

  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    const target = e.target as HTMLElement
    if (!target.closest('[data-drag-handle]')) return

    dragState.current = {
      startX: e.clientX,
      startY: e.clientY,
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

      if (
        !ds.dragging &&
        Math.abs(dx) < DRAG_THRESHOLD &&
        Math.abs(dy) < DRAG_THRESHOLD
      ) {
        return
      }

      ds.dragging = true

      if (position) {
        const newX = Math.max(
          0,
          Math.min(window.innerWidth - 260, position.x + dx)
        )
        const newY = Math.max(
          0,
          Math.min(window.innerHeight - 60, position.y + dy)
        )
        setPosition({ x: newX, y: newY })
        ds.startX = e.clientX
        ds.startY = e.clientY
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

  const posX = position?.x ?? 0
  const posY = position?.y ?? 0

  if (collapsed) {
    return (
      <button
        onClick={() => setCollapsed(false)}
        className="fixed z-50 flex size-11 items-center justify-center rounded-full bg-slate-900/90 text-slate-200 shadow-lg backdrop-blur-sm"
        style={{ left: posX, top: posY }}
        aria-label="Show virtual keys"
      >
        <svg
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <rect x="2" y="4" width="20" height="16" rx="2" />
          <path d="M6 8h.01M10 8h.01M14 8h.01M18 8h.01M8 12h.01M12 12h.01M16 12h.01M7 16h10" />
        </svg>
      </button>
    )
  }

  return (
    <div
      className="fixed z-50 rounded-xl border border-slate-700/50 bg-slate-900/90 shadow-lg backdrop-blur-sm"
      style={{ left: posX, top: posY, touchAction: 'none' }}
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
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(key)}
          >
            {key.label}
          </button>
        ))}
      </div>

      {/* Arrow keys in cross layout */}
      <div className="flex flex-col items-center gap-1 px-2 pb-2">
        <button
          className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={() => handleKeyDown(ARROW_UP)}
        >
          ↑
        </button>
        <div className="flex gap-1">
          <button
            className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(ARROW_LEFT)}
          >
            ←
          </button>
          <button
            className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(ARROW_DOWN)}
          >
            ↓
          </button>
          <button
            className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-700/80 text-sm text-slate-200 active:bg-slate-600"
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => handleKeyDown(ARROW_RIGHT)}
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
        <svg
          width="10"
          height="10"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="3"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M18 6L6 18M6 6l12 12" />
        </svg>
      </button>
    </div>
  )
}
