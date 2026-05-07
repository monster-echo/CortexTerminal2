/**
 * @file TerminalState.ets
 * @brief Terminal connection state enum
 *
 * Defines all possible states for a terminal session connection.
 * The state machine transitions through these states during the
 * session lifecycle.
 */

/**
 * Terminal session connection states.
 */
export enum TerminalState {
  /**
   * No active connection. Initial state.
   */
  Disconnected = 0,

  /**
   * WebSocket connection in progress.
   */
  Connecting = 1,

  /**
   * Replaying historical session data before going live.
   */
  Replaying = 2,

  /**
   * Active live connection. Terminal is fully interactive.
   */
  Live = 3,

  /**
   * Connection lost, attempting to reconnect with backoff.
   */
  Reconnecting = 4,

  /**
   * Session was deliberately detached. Can be resumed.
   */
  Detached = 5,

  /**
   * Session TTL expired. Cannot be resumed.
   */
  Expired = 6,

  /**
   * The remote process has exited.
   */
  Exited = 7,

  /**
   * An error occurred. May be recoverable.
   */
  Error = 8
}

/**
 * Type alias for use in import/export.
 */
export type TerminalStateEnum = TerminalState
