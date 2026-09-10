/**
 * @file SnapshotStore.ets
 * @brief Device-side persistence of xterm scrollback snapshots
 *
 * The web layer serializes the terminal (screen + scrollback) with
 * xterm-addon-serialize and streams base64 chunks through the message port;
 * XtermWebview/TerminalPage reassemble them and hand the joined base64 to
 * SnapshotStore.save(). Saves write a temp file and rename it into place, so
 * an interrupted save never leaves a corrupt snapshot.
 */
import { buffer } from '@kit.ArkTS'
import { fileIo as fs } from '@kit.CoreFileKit'

const SNAPSHOT_DIR_NAME = 'xterm_snapshots'
const SNAPSHOT_KEEP_COUNT = 10

export class SnapshotStore {
  private dir: string

  constructor() {
    const filesDir = AppStorage.get<string>('filesDir')
    if (!filesDir) {
      throw new Error('filesDir is not initialized in AppStorage')
    }
    this.dir = `${filesDir}/${SNAPSHOT_DIR_NAME}`
    fs.mkdirSync(this.dir, true)
  }

  private validateSessionId(sessionId: string): void {
    if (!sessionId) {
      throw new Error('Snapshot session id must not be empty')
    }
    for (let i = 0; i < sessionId.length; i++) {
      const c = sessionId.charAt(i)
      const isSafe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c === '-' || c === '_'
      if (!isSafe) {
        throw new Error(`Snapshot session id contains invalid character '${c}'`)
      }
    }
  }

  private pathFor(sessionId: string): string {
    this.validateSessionId(sessionId)
    return `${this.dir}/${sessionId}.b64`
  }

  /**
   * Persist a snapshot atomically (temp file + rename).
   * @param sessionId owning session
   * @param base64 joined base64 payload from the web layer
   */
  save(sessionId: string, base64: string): void {
    const finalPath = this.pathFor(sessionId)
    const tempPath = `${finalPath}.tmp`
    const bytes = buffer.from(base64, 'base64')
    const file = fs.openSync(tempPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, bytes.buffer)
    } finally {
      fs.closeSync(file)
    }
    if (fs.accessSync(finalPath)) {
      fs.unlinkSync(finalPath)
    }
    fs.renameSync(tempPath, finalPath)
    this.prune()
  }

  /**
   * Load a snapshot as base64, or empty string when none exists (first run /
   * cleared data — a normal state, the caller falls back to server replay).
   */
  loadBase64(sessionId: string): string {
    const path = this.pathFor(sessionId)
    if (!fs.accessSync(path)) {
      return ''
    }
    const stat = fs.statSync(path)
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
    try {
      const content = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, content)
      return buffer.from(content).toString('base64')
    } finally {
      fs.closeSync(file)
    }
  }

  remove(sessionId: string): void {
    const path = this.pathFor(sessionId)
    if (fs.accessSync(path)) {
      fs.unlinkSync(path)
    }
  }

  /** Keep only the newest snapshots — a full 64k-line one is ~3.4MB. */
  private prune(): void {
    const names = fs.listFileSync(this.dir)
    const entries: SnapshotEntry[] = []
    for (let i = 0; i < names.length; i++) {
      if (!names[i].endsWith('.b64')) {
        continue
      }
      const path = `${this.dir}/${names[i]}`
      const stat = fs.statSync(path)
      entries.push(new SnapshotEntry(path, stat.mtime))
    }
    entries.sort((a, b) => b.modifiedTime - a.modifiedTime)
    for (let i = SNAPSHOT_KEEP_COUNT; i < entries.length; i++) {
      fs.unlinkSync(entries[i].path)
    }
  }
}

class SnapshotEntry {
  path: string
  modifiedTime: number

  constructor(path: string, modifiedTime: number) {
    this.path = path
    this.modifiedTime = modifiedTime
  }
}
