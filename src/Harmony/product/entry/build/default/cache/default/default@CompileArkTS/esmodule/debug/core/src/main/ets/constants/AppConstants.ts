/**
 * AppConstants - Application-wide default configuration values.
 *
 * Centralises gateway URLs, WebSocket timing, session
 * parameters, and network timeouts so that every module
 * references the same constants.
 */
export class AppConstants {
    // ── Gateway ──────────────────────────────────────────────────────
    /** Default API gateway base URL */
    static readonly DEFAULT_GATEWAY_URL: string = 'https://gateway.ct.rwecho.top';
    // ── WebSocket ────────────────────────────────────────────────────
    /** Interval between WebSocket ping frames (ms) */
    static readonly WS_PING_INTERVAL_MS: number = 30000;
    /** Base delay before the first reconnect attempt (ms) */
    static readonly WS_RECONNECT_BASE_MS: number = 1000;
    /** Maximum delay for exponential back-off reconnect (ms) */
    static readonly WS_RECONNECT_MAX_MS: number = 30000;
    // ── Session ──────────────────────────────────────────────────────
    /** Default session lease duration (minutes) */
    static readonly SESSION_LEASE_MINUTES: number = 5;
    // ── Network ──────────────────────────────────────────────────────
    /** Default REST request timeout (ms) */
    static readonly REST_TIMEOUT_MS: number = 15000;
}
