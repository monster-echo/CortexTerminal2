/**
 * Logger - Simple console-based logging utility.
 *
 * Provides leveled logging with a consistent tag prefix
 * 'CortexTerminal' so that all log lines from the app
 * can be easily filtered in DevEco Studio / hdc.
 *
 * Uses ArkTS console.* which routes to hilog under tag A03d00/JSAPP.
 * (Previous hilog.info call with DOMAIN=0x0001 was filtered out by the system.)
 */

const TAG_PREFIX: string = 'CortexTerminal'

export class Logger {
  private tag: string

  /**
   * Create a logger for a specific module.
   *
   * @param moduleTag - Short module identifier (e.g. 'Auth', 'Terminal', 'Worker')
   */
  constructor(moduleTag: string) {
    this.tag = `${TAG_PREFIX}.${moduleTag}`
  }

  /**
   * Log at DEBUG level.
   */
  debug(message: string, ...args: Object[]): void {
    console.info(`[${this.tag}] ${message}`)
  }

  /**
   * Log at INFO level.
   */
  info(message: string, ...args: Object[]): void {
    console.info(`[${this.tag}] ${message}`)
  }

  /**
   * Log at WARN level.
   */
  warn(message: string, ...args: Object[]): void {
    console.warn(`[${this.tag}] ${message}`)
  }

  /**
   * Log at ERROR level.
   */
  error(message: string, ...args: Object[]): void {
    console.error(`[${this.tag}] ${message}`)
  }

  /**
   * Log at FATAL level.
   */
  fatal(message: string, ...args: Object[]): void {
    console.error(`[${this.tag}] ${message}`)
  }
}
