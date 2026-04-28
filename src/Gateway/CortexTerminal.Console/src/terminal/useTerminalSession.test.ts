import { describe, expect, it, vi } from 'vitest'
import {
  createTerminalOutputNormalizer,
  createTerminalSessionModel,
} from './useTerminalSession'

describe('createTerminalOutputNormalizer', () => {
  it('converts lone line feeds into CRLF for xterm rendering', () => {
    const normalizer = createTerminalOutputNormalizer()

    expect(normalizer.push('a\nb\n')).toBe('a\r\nb\r\n')
  })

  it('preserves existing CRLF sequences', () => {
    const normalizer = createTerminalOutputNormalizer()

    expect(normalizer.push('a\r\nb\r\n')).toBe('a\r\nb\r\n')
  })

  it('handles CRLF pairs that are split across chunks', () => {
    const normalizer = createTerminalOutputNormalizer()

    expect(normalizer.push('hello\r')).toBe('hello')
    expect(normalizer.push('\nworld\n')).toBe('\r\nworld\r\n')
  })
})

describe('createTerminalSessionModel', () => {
  it('normalizes stdout before forwarding it to the terminal view', () => {
    const onStream = vi.fn()
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStream,
    })

    const payload = new TextEncoder().encode('alpha\nbeta\n')

    expect(session.onStdout(payload)).toBe('alpha\r\nbeta\r\n')
    expect(onStream).toHaveBeenCalledWith({
      stream: 'stdout',
      text: 'alpha\r\nbeta\r\n',
    })
  })

  it('keeps replay output ordered when CRLF spans multiple chunks', () => {
    const chunks: Array<{ stream: 'stdout' | 'stderr'; text: string }> = []
    const session = createTerminalSessionModel({
      writeInput: vi.fn(),
      onStream: (chunk) => {
        chunks.push(chunk)
      },
    })

    session.onSessionReattached('sess-1')
    session.onReplayChunk(new TextEncoder().encode('one\r'), 'stdout')
    session.onReplayChunk(new TextEncoder().encode('\ntwo\n'), 'stdout')

    expect(chunks).toEqual([
      { stream: 'stdout', text: 'one' },
      { stream: 'stdout', text: '\r\ntwo\r\n' },
    ])
  })

  it('preserves carriage return for enter-driven TUI commands', () => {
    const writeInput = vi.fn()
    const session = createTerminalSessionModel({
      writeInput,
    })

    session.onTerminalData('/model\r')

    expect(writeInput).toHaveBeenCalledOnce()
    expect(Array.from(writeInput.mock.calls[0]![0] as Uint8Array)).toEqual(
      Array.from(new TextEncoder().encode('/model\r'))
    )
  })
})
