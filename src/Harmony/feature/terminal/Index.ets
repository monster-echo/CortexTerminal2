/**
 * @file Index.ets
 * @brief Terminal feature HAR export barrel
 *
 * Exports the main TerminalComponent and all public types
 * from the terminal feature module.
 */
export { TerminalComponent } from './src/main/ets/TerminalComponent'
export { TerminalPage } from './src/main/ets/view/TerminalPage'
export { TerminalTransport } from './src/main/ets/service/TerminalTransport'
export { TerminalStateManager } from './src/main/ets/service/TerminalStateManager'
export { RestApiClient } from './src/main/ets/service/RestApiClient'
export { NetworkMonitor } from './src/main/ets/service/NetworkMonitor'
export type { TerminalStateEnum } from './src/main/ets/model/TerminalState'
export type {
  SessionInfo,
  SessionListResponse,
  SessionCreateRequest,
  SessionCreateResponse
} from './src/main/ets/model/SessionModels'
export type {
  WebSocketFrame,
  OutputFrame,
  InputAckFrame,
  StatusFrame,
  ErrorFrame,
  ResizeFrame
} from './src/main/ets/model/WebSocketFrames'
