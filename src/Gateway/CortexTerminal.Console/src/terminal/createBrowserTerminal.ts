import { FitAddon } from '@xterm/addon-fit'
import { Terminal } from '@xterm/xterm'

export interface TerminalSize {
  columns: number
  rows: number
}

export function createBrowserTerminal(
  container: HTMLElement,
  onData: (data: string) => void,
  onResize?: (size: TerminalSize) => void
) {
  const terminal = new Terminal({
    cursorBlink: true,
    fontFamily:
      "ui-monospace, SFMono-Regular, Menlo, Monaco, 'Courier New', monospace",
    fontSize: 13,
    scrollback: 1000,
    theme: {
      background: '#0f172a',
      foreground: '#e2e8f0',
      cursor: '#e2e8f0',
      cursorAccent: '#0f172a',
      selectionBackground: 'rgba(148, 163, 184, 0.3)',
    },
  })

  const fitAddon = new FitAddon()
  terminal.loadAddon(fitAddon)
  terminal.open(container)

  const dataDisposable = terminal.onData(onData)
  const resizeDisposable = terminal.onResize(({ cols, rows }) => {
    onResize?.({ columns: cols, rows })
  })

  fitAddon.fit()

  return {
    write(data: string) {
      terminal.write(data, () => {})
    },
    clear() {
      terminal.clear()
    },
    fit() {
      fitAddon.fit()

      return {
        columns: terminal.cols,
        rows: terminal.rows,
      }
    },
    dispose() {
      dataDisposable.dispose()
      resizeDisposable.dispose()
      terminal.dispose()
    },
  }
}
