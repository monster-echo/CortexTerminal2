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

@Observed
export class GatewayInfo {
  version: string = ''
  latestWorkerVersion: string = ''
  latestGatewayVersion: string = ''
}

/**
 * Support / contact info for a group or channel (QQ group / Telegram group).
 */
@Observed
export class SupportGroupInfo {
  name: string = ''
  number: string = ''
  url: string = ''
  qrCodeUrl: string = ''
}

/**
 * Support contact info served by gateway /api/support/info.
 * qqGroup / telegramGroup are null when the gateway disables them
 * (国内 gateway 只返 qqGroup，国外 gateway 只返 telegramGroup).
 */
@Observed
export class SupportInfo {
  qqGroup: SupportGroupInfo | null = null
  telegramGroup: SupportGroupInfo | null = null
  email: string = ''
}
