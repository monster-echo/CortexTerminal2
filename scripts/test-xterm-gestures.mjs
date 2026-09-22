#!/usr/bin/env node
/**
 * Regression test for the gesture layer inside
 * src/Harmony/feature/terminal/src/main/resources/rawfile/xterm/index.html
 *
 * The page's inline script is loaded into a vm context with a stub DOM and a stub
 * xterm Terminal, then driven with synthetic touch events. That is the only way to
 * pin the on-device behaviour (SGR mouse reports, wheel notches, exact selection
 * ranges) without a device in the loop.
 *
 * Run: node scripts/test-xterm-gestures.mjs
 */
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import vm from 'node:vm'

const here = dirname(fileURLToPath(import.meta.url))
const pagePath = join(
  here, '..', 'src', 'Harmony', 'feature', 'terminal',
  'src', 'main', 'resources', 'rawfile', 'xterm', 'index.html'
)

const html = readFileSync(pagePath, 'utf8')
const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)]
if (blocks.length !== 1) {
  throw new Error(`expected exactly one inline script in index.html, found ${blocks.length}`)
}
const pageSource = blocks[0][1]

const COLS = 80
const ROWS = 24
const CELL_W = 10
const CELL_H = 20

/** Boot the page against stubs and return a driver for its touch listeners. */
function createHarness() {
  const state = {
    inputs: [],          // data handed to term.input() → onData → PTY
    selections: [],      // term.select(col, row, length)
    scrolls: [],         // term.scrollLines(n)
    onDataRegistrations: 0,
    prevents: 0,
    mouseTrackingMode: 'none',
    viewportY: 0,
    bufferLength: 1000,
    bufferType: 'normal',
    cursorX: 0,
    cursorY: 0,
    lines: new Map(),    // absolute buffer row → text
    timers: new Map(),
    listeners: {},
    term: null,
  }

  class FakeTerminal {
    constructor(options) {
      this.cols = options.cols
      this.rows = options.rows
      state.term = this
    }
    get modes() {
      return { mouseTrackingMode: state.mouseTrackingMode }
    }
    get buffer() {
      return {
        active: {
          viewportY: state.viewportY,
          length: state.bufferLength,
          type: state.bufferType,
          cursorX: state.cursorX,
          cursorY: state.cursorY,
          getLine: (y) => {
            const text = state.lines.get(y)
            return text === undefined ? null : { translateToString: () => text }
          },
        },
      }
    }
    open() {}
    loadAddon() {}
    dispose() {}
    write() {}
    paste() {}
    clearSelection() {}
    onResize() { return { dispose() {} } }
    onData() { state.onDataRegistrations += 1; return { dispose() {} } }
    input(data) { state.inputs.push(data) }
    select(col, row, length) { state.selections.push({ col, row, length }) }
    scrollLines(n) { state.scrolls.push(n) }
  }

  const rowsEl = {
    getBoundingClientRect: () => ({
      left: 0, top: 0, width: COLS * CELL_W, height: ROWS * CELL_H,
    }),
  }
  const textareaEl = { focus() {} }
  const container = {
    addEventListener(type, fn) { (state.listeners[type] ||= []).push(fn) },
    querySelector(sel) {
      if (sel === '.xterm-rows') return rowsEl
      if (sel === '.xterm-helper-textarea') return textareaEl
      return null
    },
  }

  const sandbox = {
    console: { log() {}, info() {}, warn() {}, error() {} },
    document: {
      getElementById: (id) => (id === 'terminal-container' ? container : null),
      querySelector: (sel) => (sel === '.xterm-helper-textarea' ? textareaEl : null),
    },
    window: { addEventListener() {} },
    setTimeout: (fn) => { const id = Symbol('timer'); state.timers.set(id, fn); return id },
    clearTimeout: (id) => { state.timers.delete(id) },
    requestAnimationFrame: () => 0,
    cancelAnimationFrame: () => {},
    atob: (s) => Buffer.from(s, 'base64').toString('binary'),
    TextDecoder,
    TextEncoder,
    Terminal: FakeTerminal,
    FitAddon: { FitAddon: class { fit() {} } },
    SerializeAddon: { SerializeAddon: class { serialize() { return '' } } },
    WebglAddon: { WebglAddon: class {} },
  }

  const context = vm.createContext(sandbox)
  vm.runInContext(pageSource, context, { filename: 'xterm/index.html' })
  context.initTerminal(COLS, ROWS, false)

  const point = (x, y) => ({ clientX: x, clientY: y })
  const emit = (type, points) => {
    const event = {
      touches: points,
      changedTouches: points,
      preventDefault() { state.prevents += 1 },
    }
    for (const fn of state.listeners[type] || []) fn(event)
  }

  return {
    state,
    start: (x, y) => emit('touchstart', [point(x, y)]),
    move: (x, y) => emit('touchmove', [point(x, y)]),
    end: (x, y) => emit('touchend', [point(x, y)]),
    fireLongPress() {
      const pending = [...state.timers.values()]
      state.timers.clear()
      for (const fn of pending) fn()
    },
  }
}

let failures = 0
function check(name, condition, detail) {
  if (condition) {
    console.log(`  ok   ${name}`)
  } else {
    failures += 1
    console.log(`  FAIL ${name}${detail === undefined ? '' : ` — ${detail}`}`)
  }
}
const show = (value) => JSON.stringify(value)

const SGR_LEFT_PRESS = (col, row) => `\x1b[<0;${col + 1};${row + 1}M`
const SGR_LEFT_RELEASE = (col, row) => `\x1b[<0;${col + 1};${row + 1}m`
const SGR_WHEEL = (button, col, row) => `\x1b[<${button};${col + 1};${row + 1}M`

// ── 1. Mouse mode: a tap is a left click (click-to-expand) ───────────────────
{
  const h = createHarness()
  h.state.mouseTrackingMode = 'vt200'
  h.start(105, 45) // col 10, row 2
  h.end(105, 45)
  check(
    'mouse mode tap reports press + release at the tapped cell',
    show(h.state.inputs) === show([SGR_LEFT_PRESS(10, 2), SGR_LEFT_RELEASE(10, 2)]),
    show(h.state.inputs)
  )
  check('mouse mode tap does not nudge the shell cursor', !h.state.inputs.some((d) => d.includes('\x1b[C')))
  check('mouse mode tap does not scroll the local buffer', h.state.scrolls.length === 0)
}

// ── 2. Mouse mode: a drag becomes wheel reports ──────────────────────────────
{
  const h = createHarness()
  h.state.mouseTrackingMode = 'vt200'
  h.start(100, 300)
  h.move(100, 204) // 96px up → 2 notches at 48px
  check(
    'mouse mode drag up sends two wheel-down reports',
    show(h.state.inputs) === show([SGR_WHEEL(65, 10, 10), SGR_WHEEL(65, 10, 10)]),
    show(h.state.inputs)
  )
  h.move(100, 108) // another 96px up
  check('wheel reports keep coming while the drag continues', h.state.inputs.length === 4)
  check('mouse mode never touches the local scrollback', h.state.scrolls.length === 0)

  h.state.inputs.length = 0
  h.start(100, 204)
  h.move(100, 300) // 96px down → wheel up
  check(
    'mouse mode drag down sends wheel-up reports',
    show(h.state.inputs) === show([SGR_WHEEL(64, 10, 15), SGR_WHEEL(64, 10, 15)]),
    show(h.state.inputs)
  )
}

// ── 3. Local mode: the same drag scrolls our own scrollback ──────────────────
{
  const h = createHarness()
  h.start(100, 300)
  h.move(100, 266) // 34px up → 2 lines
  check('local mode drag scrolls the buffer by whole lines', show(h.state.scrolls) === show([2]), show(h.state.scrolls))
  check('local mode sends no mouse reports', h.state.inputs.length === 0)
}

// ── 4. Long press: exact multi-row selection, buffer coordinates ─────────────
{
  const h = createHarness()
  h.state.mouseTrackingMode = 'vt200'
  h.state.viewportY = 100
  h.state.lines.set(102, 'hello world foo') // viewport row 2
  h.start(65, 45) // col 6 → inside "world"
  h.fireLongPress()
  check(
    'long press selects the word under the finger in buffer coordinates',
    show(h.state.selections[0]) === show({ col: 6, row: 102, length: 5 }),
    show(h.state.selections[0])
  )

  h.move(35, 90) // col 3, viewport row 4
  const last = h.state.selections[h.state.selections.length - 1]
  check(
    'dragging selects the exact cell range across rows',
    show(last) === show({ col: 6, row: 102, length: 158 }),
    show(last)
  )
  check('a selection drag sends no mouse reports to the app', h.state.inputs.length === 0)
}

// ── 5. Selection stops at the screen edge instead of running past it ─────────
{
  const h = createHarness()
  h.state.viewportY = 100
  h.state.lines.set(102, 'hello world foo')
  h.start(65, 45)
  h.fireLongPress()
  h.move(65, 100000) // far below the terminal, same column
  const below = h.state.selections[h.state.selections.length - 1]
  const belowEnd = below.row * COLS + below.col + below.length - 1
  check(
    'a drag past the bottom edge clamps to the last visible row',
    belowEnd === (100 + ROWS - 1) * COLS + 6,
    `end=${belowEnd} expected=${(100 + ROWS - 1) * COLS + 6}`
  )

  h.move(100000, 100000) // past the bottom-right corner
  const corner = h.state.selections[h.state.selections.length - 1]
  const cornerEnd = corner.row * COLS + corner.col + corner.length - 1
  const lastVisibleIndex = (100 + ROWS - 1) * COLS + COLS - 1
  check(
    'a drag past the corner clamps to the last visible cell',
    cornerEnd === lastVisibleIndex,
    `end=${cornerEnd} expected=${lastVisibleIndex}`
  )
}

// ── 6. Local mode tap-to-move goes through term.input(), not onData ──────────
{
  const h = createHarness()
  h.state.bufferLength = ROWS // viewport sits at the bottom
  h.start(55, 5) // col 5, row 0; cursor at col 0
  h.end(55, 5)
  check(
    'local mode tap nudges the cursor with arrow keys via term.input()',
    show(h.state.inputs) === show(['\x1b[C\x1b[C\x1b[C\x1b[C\x1b[C']),
    show(h.state.inputs)
  )
  check(
    'the page registers exactly one onData listener (no bogus registration)',
    h.state.onDataRegistrations === 1,
    String(h.state.onDataRegistrations)
  )
}

// ── 7. Every gesture is claimed from the browser ─────────────────────────────
{
  const h = createHarness()
  h.state.mouseTrackingMode = 'vt200'
  h.start(100, 100)
  check('touchstart is cancelled so no synthetic mouse events reach xterm', h.state.prevents >= 1)
}

console.log(failures === 0 ? '\nAll gesture checks passed.' : `\n${failures} gesture check(s) failed.`)
process.exit(failures === 0 ? 0 : 1)