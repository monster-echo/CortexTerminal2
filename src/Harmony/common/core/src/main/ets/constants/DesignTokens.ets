/**
 * DesignTokens - Color, spacing, and typography constants
 * derived from the Stitch DESIGN.md dark theme specification.
 *
 * These tokens provide a single source of truth for the visual
 * design language used across all CortexTerminal modules.
 */

export class DesignTokens {
  // ── Colors ──────────────────────────────────────────────────────

  /** Main background surface */
  static readonly surface: string = '#121414'

  /** Elevated surface / card background */
  static readonly surfaceContainer: string = '#1f2020'

  /** Higher-emphasis surface */
  static readonly surfaceContainerHigh: string = '#292a2a'

  /** Highest-emphasis surface (e.g. dialogs) */
  static readonly surfaceContainerHighest: string = '#343535'

  /** Primary text & high-emphasis content */
  static readonly primary: string = '#e3e2e2'

  /** Secondary / blue action color */
  static readonly secondary: string = '#9fcaff'

  /** Active / pressed state for secondary actions */
  static readonly secondaryContainer: string = '#3a95e8'

  /** Tertiary / green success color */
  static readonly tertiary: string = '#a2d489'

  /** Error / red color */
  static readonly error: string = '#ffb4ab'

  /** Text & icons on surface */
  static readonly onSurface: string = '#e3e2e2'

  /** Secondary text on surface (dimmed) */
  static readonly onSurfaceVariant: string = '#8e9192'

  /** Text on secondary container */
  static readonly onSecondaryContainer: string = '#003258'

  /** Subtle borders and dividers */
  static readonly outline: string = '#8e9192'

  /** Very subtle borders and dividers */
  static readonly outlineVariant: string = '#444748'

  /** Inverse surface (light on dark) */
  static readonly inverseSurface: string = '#e3e2e2'

  /** Text on inverse surface */
  static readonly inverseOnSurface: string = '#2f3030'

  // ── Spacing ─────────────────────────────────────────────────────

  /** Base grid unit (dp) */
  static readonly unit: number = 4

  /** Small spacing (dp) */
  static readonly sm: number = 8

  /** Medium spacing (dp) */
  static readonly md: number = 16

  /** Large spacing (dp) */
  static readonly lg: number = 24

  /** Standard edge / content margin (dp) */
  static readonly edgeMargin: number = 16

  /** Minimum touch target size (dp) */
  static readonly touchTarget: number = 44

  /** Standard corner radius (dp) */
  static readonly cornerRadius: number = 4

  // ── Typography ──────────────────────────────────────────────────

  /** Display / hero font size (fp) */
  static readonly fontSizeDisplay: number = 32

  /** Headline font size (fp) */
  static readonly fontSizeHeadline: number = 24

  /** Title font size (fp) */
  static readonly fontSizeTitle: number = 20

  /** Body font size (fp) */
  static readonly fontSizeBody: number = 16

  /** Label / caption font size (fp) */
  static readonly fontSizeLabel: number = 14

  /** Small caption font size (fp) */
  static readonly fontSizeCaption: number = 12

  /** Standard font family */
  static readonly fontFamily: string = 'HarmonyOS Sans'

  /** Monospace font family for terminal output */
  static readonly fontFamilyMono: string = 'HarmonyOS Sans Mono'
}
