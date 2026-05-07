/**
 * AppTheme - Reusable @Builder components for common UI patterns.
 *
 * Provides a consistent visual language across all CortexTerminal
 * feature modules. Every builder follows the dark-theme tokens
 * defined in DesignTokens.
 */

import { DesignTokens } from '../constants/DesignTokens'

// ── Terminal session state enum ────────────────────────────────────

export enum TerminalState {
  Live,
  Connecting,
  Reconnecting,
  Replaying,
  Detached,
  Expired,
  Exited
}

// ── Button type ────────────────────────────────────────────────────

export type ButtonType = 'primary' | 'secondary'

// ── Builders ───────────────────────────────────────────────────────

export { DesignTokens as Colors }
export { DesignTokens as Spacing }
