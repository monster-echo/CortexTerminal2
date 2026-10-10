/**
 * @file SessionModels.ets
 * @brief Data transfer objects for terminal sessions.
 *
 * Shared across session, terminal, worker, and settings modules.
 */

/**
 * A workspace (project directory on a worker). Sessions may be bound to one;
 * 会话的 workspaceId 为空串表示未分组。
 */
@Observed
export class WorkspaceInfo {
  id: string = ''
  name: string = ''
  workerId: string = ''
  rootPath: string = ''
  isDefault: boolean = false
}

@Observed
export class SessionInfo {
  id: string = ''
  sessionId: string = ''
  name: string = ''
  status: string = ''
  workerId: string = ''
  workerName: string = ''
  createdAt: string = ''
  updatedAt: string = ''
  lastActivityAt: string = ''
  lastActiveAt: string = ''
  columns: number = 80
  rows: number = 24
  ttl: number = 0
  workspaceId: string = ''
}

@Observed
export class SessionListResponse {
  sessions: SessionInfo[] = []
}

@Observed
export class SessionCreateRequest {
  runtime: string = 'shell'
  name: string = ''
  workerId: string = ''
  columns: number = 80
  rows: number = 24
  clientRequestId: string = ''
  workspaceId: string = ''
}

@Observed
export class SessionCreateResponse {
  id: string = ''
  sessionId: string = ''
  workerId: string = ''
  name: string = ''
  status: string = ''
  wsUrl: string = ''
  createdAt: string = ''
}
