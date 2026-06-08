/**
 * @file SessionModels.ets
 * @brief Data transfer objects for terminal sessions.
 *
 * Shared across session, terminal, worker, and settings modules.
 */

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
