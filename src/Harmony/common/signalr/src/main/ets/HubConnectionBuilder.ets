import { HubConnection, HubConnectionOptions } from './HubConnection';
import { ILogger } from './ILogger';
import { LogLevel } from './ILogger';
import { DefaultLogger } from './Loggers';

export class HubConnectionBuilder {
  private url: string | null = null;
  private accessTokenFactory: (() => string | Promise<string>) | null = null;
  private reconnectDelays: number[] | null = null;
  private logger: ILogger | null = null;
  private logLevel: LogLevel = LogLevel.Information;
  private serverTimeoutInMilliseconds: number = 30000;
  private keepAliveIntervalInMilliseconds: number = 15000;

  withUrl(url: string): HubConnectionBuilder {
    this.url = url;
    return this;
  }

  withAccessToken(factory: (() => string) | (() => Promise<string>)): HubConnectionBuilder {
    this.accessTokenFactory = factory;
    return this;
  }

  withAutomaticReconnect(retryDelays?: number[]): HubConnectionBuilder {
    if (retryDelays !== undefined) {
      this.reconnectDelays = retryDelays;
    } else {
      this.reconnectDelays = [0, 2000, 5000, 10000, 30000];
    }
    return this;
  }

  withServerTimeout(timeoutMs: number): HubConnectionBuilder {
    this.serverTimeoutInMilliseconds = timeoutMs;
    return this;
  }

  withKeepAliveInterval(intervalMs: number): HubConnectionBuilder {
    this.keepAliveIntervalInMilliseconds = intervalMs;
    return this;
  }

  configureLogging(level: LogLevel): HubConnectionBuilder {
    this.logLevel = level;
    return this;
  }

  build(): HubConnection {
    if (this.url === null || this.url.length === 0) {
      throw new Error('URL is required. Call withUrl() before build().');
    }

    const resolvedLogger = this.logger ?? new DefaultLogger(this.logLevel);

    const options: HubConnectionOptions = {
      url: this.url!,
      accessTokenFactory: this.accessTokenFactory,
      reconnectDelays: this.reconnectDelays,
      logger: resolvedLogger,
      serverTimeoutInMilliseconds: this.serverTimeoutInMilliseconds,
      keepAliveIntervalInMilliseconds: this.keepAliveIntervalInMilliseconds,
    };

    return new HubConnection(options);
  }
}
