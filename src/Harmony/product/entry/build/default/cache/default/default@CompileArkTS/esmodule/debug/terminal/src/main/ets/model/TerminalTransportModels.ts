/**
 * @file TerminalTransportModels.ets
 * @brief Data transfer objects for terminal WebSocket frames
 *
 * Defines the frame types used for WebSocket communication
 * with the terminal gateway.
 */
/**
 * WebSocket frame for terminal communication.
 */
@Observed
export class WsFrame {
    type: string = '';
    sessionId: string = '';
    payload: string = '';
    columns: number = 0;
    rows: number = 0;
}
