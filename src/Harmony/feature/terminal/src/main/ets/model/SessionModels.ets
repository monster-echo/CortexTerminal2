/**
 * @file SessionModels.ets
 * @brief Data transfer objects for terminal sessions
 *
 * Defines request and response models for the session management API.
 */

/**
 * Information about a terminal session.
 */
@Observed
export class SessionInfo {
  id: string = ''
  name: string = ''
  status: string = ''
  workerId: string = ''
  workerName: string = ''
  createdAt: string = ''
  updatedAt: string = ''
  lastActiveAt: string = ''
  columns: number = 80
  rows: number = 24
  ttl: number = 0
}

/**
 * Response from listing sessions.
 */
@Observed
export class SessionListResponse {
  sessions: SessionInfo[] = []
}

/**
 * Request to create a new session.
 */
@Observed
export class SessionCreateRequest {
  name: string = ''
  workerId: string = ''
  columns: number = 80
  rows: number = 24
}

/**
 * Response from creating a session.
 */
@Observed
export class SessionCreateResponse {
  id: string = ''
  name: string = ''
  status: string = ''
  wsUrl: string = ''
  createdAt: string = ''
}
