import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogLevel, ILogger } from './ILogger';

const DOMAIN = 0x0001;
const TAG = 'SignalR';

export class NullLogger implements ILogger {
  log(_logLevel: LogLevel, _message: string): void {
    // no-op
  }
}

export class DefaultLogger implements ILogger {
  private minLevel: LogLevel;

  constructor(minLevel: LogLevel = LogLevel.Information) {
    this.minLevel = minLevel;
  }

  log(logLevel: LogLevel, message: string): void {
    if (logLevel < this.minLevel) {
      return;
    }
    switch (logLevel) {
      case LogLevel.Trace:
      case LogLevel.Debug:
        hilog.debug(DOMAIN, TAG, message);
        break;
      case LogLevel.Information:
        hilog.info(DOMAIN, TAG, message);
        break;
      case LogLevel.Warning:
        hilog.warn(DOMAIN, TAG, message);
        break;
      case LogLevel.Error:
        hilog.error(DOMAIN, TAG, message);
        break;
      case LogLevel.Critical:
        hilog.fatal(DOMAIN, TAG, message);
        break;
      default:
        break;
    }
  }
}
