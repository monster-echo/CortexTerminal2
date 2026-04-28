export type TerminalSessionState =
  | 'live'
  | 'reattached'
  | 'replaying'
  | 'expired'

export function createTerminalOutputNormalizer() {
  let pendingCarriageReturn = false

  return {
    push(text: string) {
      if (!text) {
        return ''
      }

      let normalized = ''
      let index = 0

      if (pendingCarriageReturn) {
        if (text.startsWith('\n')) {
          normalized += '\r\n'
          index = 1
        } else {
          normalized += '\r'
        }

        pendingCarriageReturn = false
      }

      for (; index < text.length; index += 1) {
        const char = text[index]

        if (char === '\r') {
          const next = text[index + 1]

          if (next === '\n') {
            normalized += '\r\n'
            index += 1
            continue
          }

          if (index === text.length - 1) {
            pendingCarriageReturn = true
            continue
          }

          normalized += '\r'
          continue
        }

        if (char === '\n') {
          normalized += '\r\n'
          continue
        }

        normalized += char
      }

      return normalized
    },
  }
}

export function createTerminalSessionModel(deps: {
  writeInput: (payload: Uint8Array) => void
  onStateChange?: (state: TerminalSessionState) => void
  onStream?: (chunk: { stream: 'stdout' | 'stderr'; text: string }) => void
}) {
  let state: TerminalSessionState = 'live'
  const decoders = {
    stdout: new TextDecoder(),
    stderr: new TextDecoder(),
  }
  const outputNormalizers = {
    stdout: createTerminalOutputNormalizer(),
    stderr: createTerminalOutputNormalizer(),
  }

  const transitionTo = (
    next: TerminalSessionState,
    allowedFrom: TerminalSessionState[]
  ) => {
    if (state === next || !allowedFrom.includes(state)) {
      return
    }

    state = next
    deps.onStateChange?.(state)
  }

  const emitStream = (stream: 'stdout' | 'stderr', payload: Uint8Array) => {
    const text = decoders[stream].decode(payload, { stream: true })
    const normalizedText = outputNormalizers[stream].push(text)

    if (normalizedText) {
      deps.onStream?.({ stream, text: normalizedText })
    }

    return normalizedText
  }

  return {
    getState() {
      return state
    },
    onTerminalData(data: string) {
      deps.writeInput(new TextEncoder().encode(data))
    },
    onStdout(payload: Uint8Array) {
      return emitStream('stdout', payload)
    },
    onStderr(payload: Uint8Array) {
      return emitStream('stderr', payload)
    },
    onSessionReattached(sessionId: string) {
      transitionTo('reattached', ['live'])
      return sessionId
    },
    onReplayChunk(payload: Uint8Array, stream: 'stdout' | 'stderr') {
      transitionTo('replaying', ['reattached'])
      emitStream(stream, payload)
      return { payload, stream }
    },
    onReplayCompleted() {
      transitionTo('live', ['reattached', 'replaying'])
    },
    onSessionExpired() {
      transitionTo('expired', ['live', 'reattached', 'replaying'])
    },
  }
}
