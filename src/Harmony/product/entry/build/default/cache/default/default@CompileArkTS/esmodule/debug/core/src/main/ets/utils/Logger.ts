import hilog from "@ohos:hilog";
const DOMAIN: number = 0x0001;
const TAG_PREFIX: string = 'CortexTerminal';
export class Logger {
    private tag: string;
    /**
     * Create a logger for a specific module.
     *
     * @param moduleTag - Short module identifier (e.g. 'Auth', 'Terminal', 'Worker')
     */
    constructor(moduleTag: string) {
        this.tag = `${TAG_PREFIX}.${moduleTag}`;
    }
    /**
     * Log at DEBUG level.
     */
    debug(message: string, ...args: Object[]): void {
        hilog.debug(DOMAIN, this.tag, message, args);
    }
    /**
     * Log at INFO level.
     */
    info(message: string, ...args: Object[]): void {
        hilog.info(DOMAIN, this.tag, message, args);
    }
    /**
     * Log at WARN level.
     */
    warn(message: string, ...args: Object[]): void {
        hilog.warn(DOMAIN, this.tag, message, args);
    }
    /**
     * Log at ERROR level.
     */
    error(message: string, ...args: Object[]): void {
        hilog.error(DOMAIN, this.tag, message, args);
    }
    /**
     * Log at FATAL level.
     */
    fatal(message: string, ...args: Object[]): void {
        hilog.fatal(DOMAIN, this.tag, message, args);
    }
}
