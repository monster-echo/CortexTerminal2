/**
 * @file ReplayBuffer.ets
 * @brief Pure state machine for the terminal output pipeline: live output
 *        batching, authoritative full replay, and incremental delta replay.
 *
 * Extracted from TerminalPage so the replay/swap decisions — the source of
 * the scrollback duplication regression — are unit-testable without a
 * webview or a filesystem. The page wires the callbacks; this class owns
 * ONLY the decision logic. No @kit imports by design.
 *
 * Invariants the tests pin down:
 *   - An authoritative full replay REPLACES whatever is on screen (reset +
 *     single write) — appending it below a restored snapshot would duplicate
 *     the history, and the duplicated buffer would be re-saved into the
 *     scrollback snapshot, compounding on every reopen.
 *   - An EMPTY authoritative replay never destroys local content: a restored
 *     snapshot (restart-shell reattach) stays painted, live output continues
 *     below the divider; a cache-painted screen is reset and the cache
 *     cleared (nothing authoritative backs it anymore).
 *   - Delta chunks paint as they arrive and commit to the cache only when
 *     the server confirms the sequence.
 *   - Live and replay output keep arrival order, batched with '|' per frame.
 */

type ReadyCheck = () => boolean
type VoidFn = () => void
type PackedFn = (packed: string) => void
type CommitFn = (packed: string, lastSeq: number) => void
type ScheduleFn = (fn: VoidFn) => void

export class ReplayBuffer {
  /** Webview finished init (and initial fit) — writes are safe. */
  isReady: ReadyCheck = (): boolean => false
  /** xterm resetTerminal() — wipes buffer AND scrollback. */
  resetScreen: VoidFn = (): void => {}
  /** One '|' packed batch of base64 frames into the webview. */
  writePacked: PackedFn = (_packed: string): void => {}
  /** A flush reached the screen — host schedules a scrollback snapshot save. */
  onPainted: VoidFn = (): void => {}
  /** Cache: fold an applied incremental delta and advance the cursor. */
  commitDelta: CommitFn = (_packed: string, _lastSeq: number): void => {}
  /** Cache: rewrite the bin from an authoritative full replay. */
  replaceCache: PackedFn = (_packed: string): void => {}
  /** Cache: drop the session entirely (empty authoritative replay). */
  clearCache: VoidFn = (): void => {}
  /** Run `fn` on the next batching tick (16ms in the page; sync in tests). */
  scheduleFlush: ScheduleFn = (_fn: VoidFn): void => {}

  private batches: string[] = []
  private flushScheduled: boolean = false
  private replaying: boolean = false
  private swapPending: boolean = false
  private deltaActive: boolean = false
  private deltaParts: string[] = []
  private deltaBase: number = 0
  /** The page painted a scrollback snapshot before this reattach landed. */
  private snapshotRestored: boolean = false

  setSnapshotRestored(restored: boolean): void {
    this.snapshotRestored = restored
  }

  isReplaying(): boolean {
    return this.replaying
  }

  /** Server announced an authoritative full replay: buffer, don't paint yet. */
  onReplaying(): void {
    this.replaying = true
    this.batches = []
    this.flushScheduled = false
    this.swapPending = true
  }

  /**
   * The sequence base the NEXT delta replay will start from — the page sets
   * it to the cache cursor it painted from (0 when nothing seq-aligned is on
   * screen). A delta starting at 0 re-delivers the WHOLE authoritative stream:
   * reset the screen first or the delta appends below the local paint and
   * duplicates the history.
   */
  setDeltaBase(seq: number): void {
    this.deltaBase = seq
  }

  onReplayChunk(payload: string): void {
    this.batches.push(payload)
  }

  onReplayCompleted(): void {
    this.replaying = false
    this.swapPending = true
    this.settle()
  }

  /** Incremental reattach: the cached screen continues seamlessly. */
  onDeltaStart(): void {
    this.replaying = true
    this.deltaActive = true
    this.deltaParts = []
    if (this.deltaBase <= 0) {
      // Delta-from-0 IS the full authoritative stream: any local paint (a
      // restored snapshot, a cursor-less cache) predates it — wipe the screen
      // so the delta fills a clean buffer instead of stacking below it.
      this.resetScreen()
      this.snapshotRestored = false
    }
  }

  onDeltaChunk(payload: string): void {
    this.deltaParts.push(payload)
    this.pushPaint(payload)
  }

  onDeltaCompleted(lastSeq: number): void {
    this.replaying = false
    this.deltaActive = false
    this.commitDelta(this.deltaParts.join('|'), lastSeq)
    this.deltaParts = []
    this.settle()
  }

  isDeltaActive(): boolean {
    return this.deltaActive
  }

  /** Live (non-replay) output; batched and painted on the next tick. */
  onOutput(payload: string): void {
    this.pushPaint(payload)
  }

  /** Webview just became ready / finished its initial fit — paint queued work. */
  flushWhenReady(): void {
    this.settle()
  }

  private pushPaint(payload: string): void {
    this.batches.push(payload)
    if (this.isReady() && !this.flushScheduled) {
      this.flushScheduled = true
      this.scheduleFlush((): void => {
        this.flushBatch()
      })
    }
  }

  private flushBatch(): void {
    this.flushScheduled = false
    if (this.batches.length === 0) {
      return
    }
    const packed = this.batches.join('|')
    this.batches = []
    this.writePacked(packed)
    this.onPainted()
  }

  /** Swap or flush once nothing is replaying and the screen can take writes. */
  private settle(): void {
    if (this.replaying) {
      return
    }
    if (!this.isReady()) {
      return
    }
    if (this.swapPending) {
      this.swapReplayedScreen()
      return
    }
    this.flushBatch()
  }

  private swapReplayedScreen(): void {
    this.swapPending = false
    if (this.batches.length === 0) {
      if (this.snapshotRestored) {
        // Restart-shell reattach: nothing authoritative to replay — the
        // restored history plus its divider stays; live output continues
        // below it.
        return
      }
      // Empty authoritative replay over a cache-painted screen: the cache
      // must not outlive it.
      this.resetScreen()
      this.clearCache()
      return
    }
    // The replay is the source of truth: replace whatever is on screen.
    // Appending below a restored snapshot duplicates the whole history —
    // and the duplicated buffer would be re-serialized into the snapshot,
    // compounding on every reopen.
    this.resetScreen()
    const packed = this.batches.join('|')
    this.batches = []
    this.flushScheduled = false
    this.writePacked(packed)
    this.replaceCache(packed)
    this.snapshotRestored = false
  }
}
