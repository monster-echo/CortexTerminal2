/**
 * @file TerminalCache.ets
 * @brief Per-session local cache of the terminal output stream.
 *
 * WebView-terminal parity of the Flutter build's TerminalRegistry: a session's
 * last-known screen is painted the moment its page opens, and the cached byte
 * stream doubles as the cursor for incremental replay (hub method
 * ReattachSessionIncremental) — the server sends only the chunks after the
 * cached sequence and the screen continues without a reset.
 *
 * Two files per session under filesDir/terminal_cache/:
 *   <id>.bin   the base64 frames exactly as the gateway delivered them, joined
 *              with '|' — byte-for-byte the packing writeBatchedOutput()
 *              consumes, so restoring is a single bridge call
 *   <id>.meta  "<cursorSeq> <countedBytes>" — bin[0..countedBytes) is exactly
 *              the authoritative server stream through cursorSeq; bytes beyond
 *              that are an unpaintable tail the server will resend
 *
 * The server replay is the source of truth: every completed full replay
 * replaces the bin, and every incremental delta is appended and counted. The
 * cache is a paint optimization, never a source of truth.
 */
import { fileIo as fs } from '@kit.CoreFileKit'

const CACHE_SUBDIR = 'terminal_cache'
/** Rewrite the file keeping only the newest tail once it grows past this. */
const CACHE_MAX_BYTES = 2 * 1024 * 1024
/** Tail size kept after a trim. */
const CACHE_KEEP_BYTES = 1024 * 1024

/** What load() hands back: the paintable prefix and its replay cursor. */
export class TerminalCacheEntry {
  packed: string = ''
  sinceSeq: number = 0
}

/** Stored cursor: bin[0..bytes) is the authoritative stream through seq. */
export class TerminalCacheCursor {
  seq: number = 0
  bytes: number = 0
}

export class TerminalCache {
  private static instance: TerminalCache | null = null
  private filesDir: string = ''

  static getInstance(): TerminalCache {
    if (TerminalCache.instance === null) {
      TerminalCache.instance = new TerminalCache()
    }
    return TerminalCache.instance
  }

  /** One-time sandbox root; later calls are no-ops so any page can seed it. */
  init(filesDir: string): void {
    if (this.filesDir === '') {
      this.filesDir = filesDir
    }
  }

  private binPath(sessionId: string): string {
    return `${this.filesDir}/${CACHE_SUBDIR}/${sessionId}.bin`
  }

  private metaPath(sessionId: string): string {
    return `${this.filesDir}/${CACHE_SUBDIR}/${sessionId}.meta`
  }

  /**
   * The paintable cached prefix ('|'-packed base64 frames) and the replay
   * cursor it reaches. Empty packed + cursor 0 when nothing is cached.
   * @throws on real I/O failures — callers decide how to degrade.
   */
  load(sessionId: string): TerminalCacheEntry {
    const entry = new TerminalCacheEntry()
    const bin = this.binPath(sessionId)
    if (!fs.accessSync(bin)) {
      return entry
    }
    const content = fs.readTextSync(bin)
    const cursor = this.readCursor(sessionId)
    if (cursor.bytes > 0 && cursor.bytes < content.length) {
      entry.packed = content.substring(0, cursor.bytes)
    } else {
      entry.packed = content
    }
    entry.sinceSeq = cursor.seq
    return entry
  }

  /** The stored replay cursor (0 = none — the next reattach is a full replay). */
  loadLastSeq(sessionId: string): number {
    return this.readCursor(sessionId).seq
  }

  /**
   * Replace the whole bin with the stream that was just painted (an
   * authoritative full replay). The cursor is dropped — the caller re-arms it
   * via setCursor only when the server announced a sequence for this stream.
   */
  replaceAll(sessionId: string, packed: string): void {
    const file = this.binPath(sessionId)
    const handle = fs.openSync(file, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE)
    try {
      fs.writeSync(handle.fd, packed)
    } finally {
      fs.closeSync(handle)
    }
    this.clearCursor(sessionId)
  }

  /**
   * Fold an applied incremental delta into the cache: bin += delta, and the
   * cursor advances to the sequence the server confirmed — bin and cursor
   * stay exactly in step with what is on screen.
   */
  commitDelta(sessionId: string, deltaPacked: string, lastSeq: number): void {
    const file = this.binPath(sessionId)
    let content = ''
    if (fs.accessSync(file)) {
      content = fs.readTextSync(file)
    }
    const merged = content + deltaPacked
    const handle = fs.openSync(file, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE)
    try {
      fs.writeSync(handle.fd, merged)
    } finally {
      fs.closeSync(handle)
    }
    this.setCursor(sessionId, lastSeq, merged.length)
    this.trimIfNeeded(sessionId, file)
  }

  /** Store the cursor: bin[0..bytes) is the authoritative stream through seq. */
  setCursor(sessionId: string, seq: number, bytes: number): void {
    const handle = fs.openSync(this.metaPath(sessionId),
      fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.CREATE)
    try {
      fs.writeSync(handle.fd, `${seq} ${bytes}`)
    } finally {
      fs.closeSync(handle)
    }
  }

  /** Drop the cursor only (bin content is unchanged). */
  clearCursor(sessionId: string): void {
    const meta = this.metaPath(sessionId)
    if (fs.accessSync(meta)) {
      fs.unlinkSync(meta)
    }
  }

  /** Drop a session's cache entirely (session exited / expired / empty replay). */
  clear(sessionId: string): void {
    const bin = this.binPath(sessionId)
    if (fs.accessSync(bin)) {
      fs.unlinkSync(bin)
    }
    this.clearCursor(sessionId)
  }

  private readCursor(sessionId: string): TerminalCacheCursor {
    const meta = this.metaPath(sessionId)
    if (!fs.accessSync(meta)) {
      return new TerminalCacheCursor()
    }
    const raw = fs.readTextSync(meta).trim()
    const parts = raw.split(' ')
    const seq = Number(parts[0])
    const bytes = parts.length > 1 ? Number(parts[1]) : 0
    if (Number.isNaN(seq) || Number.isNaN(bytes) || seq < 0 || bytes < 0) {
      throw new Error('Corrupt terminal cache cursor: ' + raw)
    }
    const cursor = new TerminalCacheCursor()
    cursor.seq = seq
    cursor.bytes = bytes
    return cursor
  }

  /**
   * The file holds one ASCII byte per character (base64 + '|'), so trimming
   * keeps the newest frames by cutting at the first frame boundary past the
   * keep line. If the cut eats into the counted prefix the cursor is
   * invalidated — the next reattach falls back to a full replay, which is the
   * only safe answer once bytes are gone.
   */
  private trimIfNeeded(sessionId: string, file: string): void {
    const size = fs.statSync(file).size
    if (size <= CACHE_MAX_BYTES) {
      return
    }
    const content = fs.readTextSync(file)
    const cut = content.indexOf('|', size - CACHE_KEEP_BYTES)
    if (cut < 0) {
      return
    }
    const handle = fs.openSync(file, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(handle.fd, content.substring(cut + 1))
    } finally {
      fs.closeSync(handle)
    }
    const cursor = this.readCursor(sessionId)
    const newBytes = cursor.bytes - (cut + 1)
    if (newBytes <= 0) {
      this.clearCursor(sessionId)
    } else {
      this.setCursor(sessionId, cursor.seq, newBytes)
    }
  }
}
