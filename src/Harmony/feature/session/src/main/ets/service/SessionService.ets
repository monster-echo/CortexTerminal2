import { ApiService, SessionInfo, SessionCreateRequest, SessionCreateResponse, WorkerInfo } from '@rwecho/core'

interface TerminalSize { cols: number; rows: number }

interface HomeData {
  activeSessions: SessionInfo[]
  historySessions: SessionInfo[]
  workers: WorkerInfo[]
}

export class SessionService {
  static isSessionActive(session: SessionInfo): boolean {
    const status = session.status.toLowerCase()
    return status === 'running' || status === 'idle' || status === 'live' || status === 'connected'
  }

  static async loadHomeData(): Promise<HomeData> {
    const sessions = await ApiService.listSessions()
    const workers = await ApiService.listWorkers()
    const activeSessions = sessions.filter(s => SessionService.isSessionActive(s))
    const historySessions = sessions.filter(s => !SessionService.isSessionActive(s))
    const result: HomeData = {
      activeSessions: activeSessions,
      historySessions: historySessions,
      workers: workers
    }
    return result
  }

  static async createSessionOnWorker(workerId: string): Promise<SessionCreateResponse> {
    const size = SessionService.calculateTerminalSize()
    const request = new SessionCreateRequest()
    request.columns = size.cols
    request.rows = size.rows
    request.workerId = workerId
    return await ApiService.createSession(request)
  }

  static async deleteSession(sessionId: string): Promise<void> {
    await ApiService.deleteSession(sessionId)
  }

  static async renameSession(sessionId: string, name: string): Promise<void> {
    await ApiService.renameSession(sessionId, name)
  }

  private static calculateTerminalSize(): TerminalSize {
    const vpWidth = AppStorage.get<number>('windowWidth') || 360
    const vpHeight = AppStorage.get<number>('windowHeight') || 640
    const fontSize = 14
    const charWidth = fontSize * 0.602
    const charHeight = fontSize * 1.2
    const topBarHeight = 52 + 28
    const keyBarHeight = 52
    const cols = Math.floor(vpWidth / charWidth)
    const rows = Math.floor((vpHeight - topBarHeight - keyBarHeight) / charHeight)
    const result: TerminalSize = { cols: Math.max(cols, 20), rows: Math.max(rows, 6) }
    return result
  }
}
