/**
 * Transport frame for terminal communication.
 * Used by TerminalTransport to pass events to TerminalPage.
 */
export class TransportFrame {
  type: string = ''
  sessionId: string = ''
  stream: string = ''
  payload: string = ''
  exitCode: number = 0
  reason: string = ''
  code: string = ''
  message: string = ''
  probeId: string = ''
  clientTime: number = 0
  serverTime: number = 0
  // ReplayDeltaChunk: worker-assigned sequence of this chunk.
  seq: number = 0
  hasSeq: boolean = false
  // ReplayDeltaCompleted: newest sequence in the session stream.
  lastSeq: number = 0
  hasLastSeq: boolean = false
}

/**
 * Hub method parameter: ReattachSessionIncremental
 */
export class ReattachSessionSinceParams {
  sessionId: string = ''
  sinceSeq: number = 0
}

/**
 * Hub method parameter: ReattachSession
 */
export class ReattachSessionParams {
  sessionId: string = ''
}

/**
 * Hub method parameter: WriteInput
 */
export class WriteInputParams {
  sessionId: string = ''
  payload: string = ''
}

/**
 * Hub method parameter: ResizeSession
 */
export class ResizeSessionParams {
  sessionId: string = ''
  columns: number = 0
  rows: number = 0
}

/**
 * Hub method parameter: CloseSession
 */
export class CloseSessionParams {
  sessionId: string = ''
}

/**
 * Hub method parameter: ProbeLatency
 */
export class ProbeLatencyParams {
  sessionId: string = ''
  probeId: string = ''
}
