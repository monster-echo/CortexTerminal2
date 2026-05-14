import { useCallback, useEffect, useRef } from 'react'
import { TriangleAlert } from 'lucide-react'
import { createBrowserTerminal } from './createBrowserTerminal'

export type BrowserTerminal = ReturnType<typeof createBrowserTerminal>

export interface TerminalSize {
  columns: number
  rows: number
}

export function TerminalViewport(props: {
  errorMessage?: string | null
  onData: (data: string) => void
  onEvent?: (message: string) => void
  onReady?: (terminal: BrowserTerminal | null) => void
  onResize?: (size: TerminalSize) => void
}) {
  const { errorMessage, onData, onEvent, onReady, onResize } = props
  const terminalContainerRef = useRef<HTMLDivElement | null>(null)
  const onDataRef = useRef(onData)
  const onEventRef = useRef(onEvent)
  const onReadyRef = useRef(onReady)
  const onResizeRef = useRef(onResize)

  useEffect(() => {
    onDataRef.current = onData
  }, [onData])

  useEffect(() => {
    onEventRef.current = onEvent
  }, [onEvent])

  useEffect(() => {
    onReadyRef.current = onReady
  }, [onReady])

  useEffect(() => {
    onResizeRef.current = onResize
  }, [onResize])

  const pushViewportEvent = useCallback((message: string) => {
    onEventRef.current?.(message)
  }, [])

  useEffect(() => {
    const element = terminalContainerRef.current
    if (!element) {
      return
    }

    pushViewportEvent('Initializing browser terminal.')
    const browserTerminal = createBrowserTerminal(element, (data) => {
      onDataRef.current(data)
    })
    pushViewportEvent('Browser terminal ready.')
    onReadyRef.current?.(browserTerminal)
    const initialSize = browserTerminal.fit()
    pushViewportEvent(
      `Measured terminal at ${initialSize.columns}x${initialSize.rows}.`
    )
    onResizeRef.current?.(initialSize)

    const observer = new ResizeObserver(() => {
      const size = browserTerminal.fit()
      pushViewportEvent(`Viewport resized to ${size.columns}x${size.rows}.`)
      onResizeRef.current?.(size)
    })
    observer.observe(element)

    return () => {
      pushViewportEvent('Disposing browser terminal.')
      observer.disconnect()
      onReadyRef.current?.(null)
      browserTerminal.dispose()
    }
  }, [pushViewportEvent])

  return (
    <div className='flex h-full min-h-0 flex-col gap-2'>
      {errorMessage && (
        <div className='flex items-start gap-2 rounded-none bg-destructive/90 px-4 py-2 text-sm text-white md:rounded-lg'>
          <TriangleAlert className='mt-0.5 size-4 shrink-0' />
          {errorMessage}
        </div>
      )}
      <div
        ref={terminalContainerRef}
        className='min-h-0 flex-1 overflow-hidden rounded-none border bg-slate-950 md:rounded-lg'
      />
    </div>
  )
}
