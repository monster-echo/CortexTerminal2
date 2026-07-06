import { describe, expect, it } from 'vitest'
import { parseAgentActivityFrame } from './agent-activity'

describe('parseAgentActivityFrame', () => {
  describe('AgentTitleUpdated', () => {
    it('parses sessionId and title', () => {
      const frame = parseAgentActivityFrame(
        'AgentTitleUpdated',
        JSON.stringify({ sessionId: 'sess-1', title: 'Live Title From Agent' }),
      )

      expect(frame).toEqual({ sessionId: 'sess-1', title: 'Live Title From Agent' })
    })

    it('falls back to empty string when title field is missing', () => {
      // AgentTitleUpdatedFrame.Title is non-nullable on the backend, but a malformed/garbled
      // payload must never crash the Console — the parser coerces a missing title to ''.
      const frame = parseAgentActivityFrame(
        'AgentTitleUpdated',
        JSON.stringify({ sessionId: 'sess-1' }),
      )

      expect(frame).toEqual({ sessionId: 'sess-1', title: '' })
    })

    it('preserves unicode and emoji end-to-end', () => {
      const frame = parseAgentActivityFrame(
        'AgentTitleUpdated',
        JSON.stringify({ sessionId: 'sess-1', title: '保存 Bilibili cookies 📺' }),
      )

      expect(frame).toEqual({ sessionId: 'sess-1', title: '保存 Bilibili cookies 📺' })
    })
  })
})
