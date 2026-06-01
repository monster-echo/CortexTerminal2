/**
 * @file SharedModels.ets
 * @brief Shared data transfer objects used across feature modules
 *
 * Contains models that are needed by multiple feature modules
 * to avoid cross-module imports between HAR modules.
 */

/**
 * Navigation parameter for terminal session screen.
 */
@Observed
export class TerminalNavParam {
  sessionId: string = ''
  sessionName: string = ''
}

/**
 * Navigation parameter for worker detail screen.
 */
@Observed
export class WorkerNavParam {
  workerId: string = ''
  workerName: string = ''
}

/**
 * Information about a worker machine.
 */
@Observed
export class WorkerInfo {
  id: string = ''
  workerId: string = ''
  name: string = ''
  hostname: string = ''
  status: string = 'offline'
  os: string = ''
  operatingSystem: string = ''
  arch: string = ''
  architecture: string = ''
  version: string = ''
  ip: string = ''
  address: string = ''
  isOnline: boolean = false
  activeSessions: number = 0
  sessionCount: number = 0
  maxSessions: number = 1
  cpuUsage: number = 0
  memoryUsage: number = 0
  diskUsage: number = 0
  lastSeenAt: string = ''
  createdAt: string = ''
  activatedAt: string = ''
}

/**
 * Response from listing workers.
 */
@Observed
export class WorkerListResponse {
  workers: WorkerInfo[] = []
}

/**
 * Session information within a worker context.
 */
@Observed
export class WorkerSessionInfo {
  id: string = ''
  sessionId: string = ''
  workerId: string = ''
  name: string = ''
  status: string = ''
  createdAt: string = ''
  updatedAt: string = ''
  lastActivityAt: string = ''
  lastActiveAt: string = ''
}
