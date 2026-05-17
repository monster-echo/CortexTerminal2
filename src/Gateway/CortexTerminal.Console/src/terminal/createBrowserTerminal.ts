import { FitAddon } from '@xterm/addon-fit'
import { Terminal } from '@xterm/xterm'

export function createBrowserTerminal(
  container: HTMLElement,
  onData: (data: string) => void
) {
  const terminal = new Terminal({
    cursorBlink: true,
    fontFamily:
      "ui-monospace, SFMono-Regular, Menlo, Monaco, 'Courier New', monospace",
    fontSize: 13,
    scrollback: 5000,
    theme: {
      background: '#0f172a',
      foreground: '#e2e8f0',
      cursor: '#e2e8f0',
      cursorAccent: '#0f172a',
      selectionBackground: 'rgba(148, 163, 184, 0.3)',
    },
  })

  const fitAddon = new FitAddon()
  let scrollToBottomFrameId: number | null = null
  terminal.loadAddon(fitAddon)
  terminal.open(container)
  fitAddon.fit()

  const disposable = terminal.onData(onData)

  return {
    write(data: string) {
      terminal.write(data)
    },
    clear() {
      terminal.clear()
    },
    fit() {
      const dimensions = fitAddon.proposeDimensions()
      if (
        dimensions &&
        (terminal.cols !== dimensions.cols || terminal.rows !== dimensions.rows)
      ) {
        const wasAtBottom =
          terminal.buffer.active.viewportY + terminal.rows >=
          terminal.buffer.active.baseY - 1
        terminal.resize(dimensions.cols, dimensions.rows)

        if (wasAtBottom) {
          terminal.scrollToBottom()
          if (scrollToBottomFrameId !== null) {
            window.cancelAnimationFrame(scrollToBottomFrameId)
          }
          scrollToBottomFrameId = window.requestAnimationFrame(() => {
            terminal.scrollToBottom()
            scrollToBottomFrameId = null
          })
        }
      }

      return {
        columns: terminal.cols,
        rows: terminal.rows,
      }
    },
    dispose() {
      if (scrollToBottomFrameId !== null) {
        window.cancelAnimationFrame(scrollToBottomFrameId)
        scrollToBottomFrameId = null
      }
      disposable.dispose()
      terminal.dispose()
    },
  }
}
