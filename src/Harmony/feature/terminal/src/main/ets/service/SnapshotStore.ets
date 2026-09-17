/**
 * @file SnapshotStore.ets
 * @brief Device-side persistence for serialized xterm scrollback snapshots
 *
 * Snapshots are keyed by WORKER id (not session id): when a session exits and
 * the user creates a new session on the same machine, the new terminal
 * restores this snapshot and appends live output below it — Windows-Terminal
 * style concat, where restarting the shell never clears the visible history.
 * Callers pass `workerId || sessionId` as the key so worker-less sessions
 * degrade to per-session behavior.
 *
 * Serialized content can reach several MB (64k scrollback lines), so it is
 * streamed in chunks by the caller and written atomically here (tmp file +
 * rename) — a killed process can never leave a half-written snapshot.
 */
import { fileIo as fs } from '@kit.CoreFileKit'
import { buffer } from '@kit.ArkTS'

const SNAPSHOT_DIR_NAME = 'xterm_snapshots'
const SNAPSHOT_EXT = '.b64'
const MAX_SNAPSHOTS = 10

/** One snapshot file with its mtime, for LRU pruning. */
class SnapshotFile {
  name: string = ''
  mtime: number = 0
}

export class SnapshotStore {
  private static snapshotDir(): string {
    const filesDir = AppStorage.get<string>('filesDir') ?? ''
    if (filesDir.length === 0) {
      throw new Error('filesDir is not initialized')
    }
    return `${filesDir}/${SNAPSHOT_DIR_NAME}`
  }

  private static ensureDir(dir: string): void {
    // fs.accessSync RETURNS a boolean on HarmonyOS — it does not throw for
    // missing paths (same idiom as TerminalCache).
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true)
    }
  }

  private static pathFor(key: string): string {
    return `${SnapshotStore.snapshotDir()}/${key}${SNAPSHOT_EXT}`
  }

  /** Atomic write: content lands at `<key>.b64` only after the full tmp write + rename. */
  static save(key: string, content: string): void {
    const dir = SnapshotStore.snapshotDir()
    SnapshotStore.ensureDir(dir)
    const tmpPath = `${dir}/${key}${SNAPSHOT_EXT}.tmp`
    const dstPath = SnapshotStore.pathFor(key)
    let file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, content)
    } finally {
      fs.closeSync(file)
    }
    fs.renameSync(tmpPath, dstPath)
    SnapshotStore.prune(MAX_SNAPSHOTS)
  }

  /** Serialized content, or '' when no snapshot exists yet (first ever session). */
  static load(key: string): string {
    const path = SnapshotStore.pathFor(key)
    let stat = fs.statSync(path)
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY)
    try {
      const sizeBytes = stat.size
      const buf = new ArrayBuffer(sizeBytes)
      fs.readSync(file.fd, buf)
      return buffer.from(buf).toString('utf-8')
    } finally {
      fs.closeSync(file)
    }
  }

  static exists(key: string): boolean {
    // accessSync returns a boolean (no throw on missing) — mirror TerminalCache.
    return fs.accessSync(SnapshotStore.pathFor(key))
  }

  static remove(key: string): void {
    fs.unlinkSync(SnapshotStore.pathFor(key))
  }

  /** Keep only the `keep` most recently modified snapshots (by mtime). */
  static prune(keep: number): void {
    const dir = SnapshotStore.snapshotDir()
    const names = fs.listFileSync(dir).filter((n: string) => n.endsWith(SNAPSHOT_EXT))
    if (names.length <= keep) {
      return
    }
    const byMtime: SnapshotFile[] = names.map((n: string) => {
      const stat = fs.statSync(`${dir}/${n}`)
      const item = new SnapshotFile()
      item.name = n
      item.mtime = stat.mtime
      return item
    })
    byMtime.sort((a, b) => b.mtime - a.mtime)
    for (let i = keep; i < byMtime.length; i++) {
      fs.unlinkSync(`${dir}/${byMtime[i].name}`)
    }
  }
}
