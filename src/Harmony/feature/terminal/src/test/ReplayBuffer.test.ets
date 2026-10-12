import { describe, it, expect } from '@ohos/hypium';
import { ReplayBuffer } from '../main/ets/model/ReplayBuffer';

/**
 * Records every ReplayBuffer decision so tests assert on effects, not
 * implementation. scheduleFlush enqueues; tick() plays the queued callbacks
 * — a deterministic stand-in for the page's 16ms batching timer.
 */
class RecordingHost {
  resets: number = 0
  writes: string[] = []
  painted: number = 0
  commits: string[] = []
  replaced: string[] = []
  clears: number = 0
  ready: boolean = true
  private scheduled: Array<() => void> = new Array<() => void>()

  bind(target: ReplayBuffer): void {
    target.isReady = (): boolean => this.ready
    target.resetScreen = (): void => {
      this.resets++
    }
    target.writePacked = (packed: string): void => {
      this.writes.push(packed)
    }
    target.onPainted = (): void => {
      this.painted++
    }
    target.commitDelta = (packed: string, _lastSeq: number): void => {
      this.commits.push(packed)
    }
    target.replaceCache = (packed: string): void => {
      this.replaced.push(packed)
    }
    target.clearCache = (): void => {
      this.clears++
    }
    target.scheduleFlush = (fn: () => void): void => {
      this.scheduled.push(fn)
    }
  }

  /** Play one batching tick. */
  tick(): void {
    const pending = this.scheduled
    this.scheduled = new Array<() => void>()
    pending.forEach((fn: () => void): void => {
      fn()
    })
  }

  joinedWrites(): string {
    return this.writes.join(';')
  }
}

function makeBuffer(host: RecordingHost): ReplayBuffer {
  const buffer = new ReplayBuffer()
  host.bind(buffer)
  return buffer
}

export default function replayBufferTest() {
  describe('replayBufferTest', () => {

    /**
     * THE regression: a snapshot-restored screen plus a non-empty
     * authoritative replay used to APPEND the replay below the snapshot —
     * the whole history painted twice, and the duplicated buffer was
     * re-saved into the snapshot, compounding on every reopen.
     */
    it('snapshotRestored_nonEmptyReplay_replacesScreen', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)
      buffer.setSnapshotRestored(true)

      buffer.onReplaying()
      buffer.onReplayChunk('AAA')
      buffer.onReplayChunk('BBB')
      buffer.onReplayCompleted()

      expect(host.resets).assertEqual(1)
      expect(host.joinedWrites()).assertEqual('AAA|BBB')
      expect(host.replaced.length).assertEqual(1)
      expect(host.replaced[0]).assertEqual('AAA|BBB')
      expect(host.clears).assertEqual(0)
    })

    it('snapshotRestored_emptyReplay_keepsRestoredHistory', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)
      buffer.setSnapshotRestored(true)

      buffer.onReplaying()
      buffer.onReplayCompleted()

      // Restart-shell reattach: nothing authoritative to replay — resetting
      // would wipe the only history the device has.
      expect(host.resets).assertEqual(0)
      expect(host.writes.length).assertEqual(0)
      expect(host.clears).assertEqual(0)
    })

    it('cachePainted_emptyReplay_resetsAndClearsCache', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)

      buffer.onReplaying()
      buffer.onReplayCompleted()

      expect(host.resets).assertEqual(1)
      expect(host.writes.length).assertEqual(0)
      expect(host.clears).assertEqual(1)
    })

    it('noSnapshot_fullReplay_swapsOnceAtomically', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)

      buffer.onReplaying()
      buffer.onReplayChunk('R1')
      buffer.onReplayChunk('R2')
      buffer.onReplayCompleted()

      expect(host.resets).assertEqual(1)
      expect(host.joinedWrites()).assertEqual('R1|R2')
      expect(host.replaced[0]).assertEqual('R1|R2')
    })

    it('deltaReplay_paintsIncrementally_commitsOnConfirm', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)
      buffer.setDeltaBase(41)

      buffer.onDeltaStart()
      expect(buffer.isReplaying()).assertTrue()
      buffer.onDeltaChunk('D1')
      buffer.onDeltaChunk('D2')
      buffer.onDeltaCompleted(42)
      host.tick()

      // No reset, no swap — the cached screen continues seamlessly; chunks
      // that landed in the same batching tick go out as one packed write.
      expect(host.resets).assertEqual(0)
      expect(host.joinedWrites()).assertEqual('D1|D2')
      expect(host.commits.length).assertEqual(1)
      expect(host.commits[0]).assertEqual('D1|D2')
      expect(buffer.isReplaying()).assertFalse()
    })

    it('liveOutput_batchedIntoSingleWrite', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)

      buffer.onOutput('L1')
      buffer.onOutput('L2')
      buffer.onOutput('L3')
      expect(host.writes.length).assertEqual(0)

      host.tick()
      expect(host.joinedWrites()).assertEqual('L1|L2|L3')
      expect(host.painted).assertEqual(1)
    })

    it('outputBeforeReady_queuesUntilFlush', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)
      host.ready = false

      buffer.onOutput('early')
      expect(host.writes.length).assertEqual(0)

      host.ready = true
      buffer.flushWhenReady()
      expect(host.joinedWrites()).assertEqual('early')
    })

    it('liveOutputDuringReplay_keepsArrivalOrderAcrossSwap', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)

      buffer.onReplaying()
      buffer.onReplayChunk('R1')
      buffer.onOutput('LIVE')
      buffer.onReplayChunk('R2')
      buffer.onReplayCompleted()

      expect(host.resets).assertEqual(1)
      expect(host.joinedWrites()).assertEqual('R1|LIVE|R2')
    })

    it('snapshotFlag_clearedAfterAuthoritativeReplace', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)
      buffer.setSnapshotRestored(true)

      buffer.onReplaying()
      buffer.onReplayChunk('R1')
      buffer.onReplayCompleted()

      // A second empty replay in the same page session must now behave like
      // the cache path (reset + clear), not keep protecting a snapshot that
      // is no longer on screen.
      buffer.onReplaying()
      buffer.onReplayCompleted()
      expect(host.resets).assertEqual(2)
      expect(host.clears).assertEqual(1)
    })

    /**
     * Gateway works, cursor is 0 (cache painted without a sequence): the
     * delta carries the WHOLE authoritative stream — the local paint must be
     * reset away or the delta stacks below it and duplicates the history.
     */
    it('deltaFromZero_resetsLocalPaintBeforeApplying', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)
      buffer.setSnapshotRestored(true)
      buffer.setDeltaBase(0)

      buffer.onDeltaStart()
      expect(host.resets).assertEqual(1)

      buffer.onDeltaChunk('D1')
      host.tick()
      buffer.onDeltaCompleted(9)
      expect(host.joinedWrites()).assertEqual('D1')
      expect(host.commits.length).assertEqual(1)
    })

    it('deltaFromCursor_continuesSeamlesslyWithoutReset', 0, () => {
      const host = new RecordingHost()
      const buffer = makeBuffer(host)
      buffer.setDeltaBase(41)

      buffer.onDeltaStart()
      buffer.onDeltaChunk('new bytes')
      host.tick()
      buffer.onDeltaCompleted(42)

      // Cursor-aligned continuation: no reset, no swap — the cached screen
      // keeps its paint and only the new bytes arrive.
      expect(host.resets).assertEqual(0)
      expect(host.joinedWrites()).assertEqual('new bytes')
      expect(host.commits[0]).assertEqual('new bytes')
    })
  })
}
