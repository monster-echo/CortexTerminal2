/**
 * @file WebSocketFrames.ets
 * @brief WebSocket frame type interfaces for terminal communication
 *
 * Defines the typed interfaces for frames exchanged between the
 * client and server over the terminal WebSocket connection.
 */

/**
 * Base WebSocket frame interface.
 * All frames include a type discriminator.
 */
@Observed
export class WebSocketFrame {
  type: string = ''
}

/**
 * Output frame carrying terminal output data.
 * The payload is base64-encoded terminal output bytes.
 */
@Observed
export class OutputFrame extends WebSocketFrame {
  type: string = 'output'
  payload: string = ''
  sequence: number = 0
}

/**
 * Input acknowledgment frame confirming received input.
 */
@Observed
export class InputAckFrame extends WebSocketFrame {
  type: string = 'input_ack'
  sequence: number = 0
}

/**
 * Status frame carrying session state updates.
 */
@Observed
export class StatusFrame extends WebSocketFrame {
  type: string = 'status'
  status: string = ''
  message: string = ''
}

/**
 * Error frame indicating a server-side error.
 */
@Observed
export class ErrorFrame extends WebSocketFrame {
  type: string = 'error'
  code: string = ''
  message: string = ''
}

/**
 * Resize frame for terminal dimension changes.
 */
@Observed
export class ResizeFrame extends WebSocketFrame {
  type: string = 'resize'
  columns: number = 80
  rows: number = 24
}

/**
 * Input frame for sending user input to the terminal.
 */
@Observed
export class InputFrame extends WebSocketFrame {
  type: string = 'input'
  payload: string = ''
}

/**
 * Ping/Pong frames for keep-alive.
 */
@Observed
export class PingFrame extends WebSocketFrame {
  type: string = 'ping'
}

@Observed
export class PongFrame extends WebSocketFrame {
  type: string = 'pong'
}

/**
 * Detach frame for gracefully detaching from a session.
 */
@Observed
export class DetachFrame extends WebSocketFrame {
  type: string = 'detach'
}

/**
 * Close frame for terminating the session.
 */
@Observed
export class CloseFrame extends WebSocketFrame {
  type: string = 'close'
}
