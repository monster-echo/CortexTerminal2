import { DesignTokens } from "@bundle:top.rwecho.cortexterminal/entry@core/ets/constants/DesignTokens";
// ── Terminal session state enum ────────────────────────────────────
export enum TerminalState {
    Live = 0,
    Connecting = 1,
    Reconnecting = 2,
    Replaying = 3,
    Detached = 4,
    Expired = 5,
    Exited = 6
}
// ── Button type ────────────────────────────────────────────────────
export type ButtonType = 'primary' | 'secondary';
// ── Builders ───────────────────────────────────────────────────────
export { DesignTokens as Colors };
export { DesignTokens as Spacing };
