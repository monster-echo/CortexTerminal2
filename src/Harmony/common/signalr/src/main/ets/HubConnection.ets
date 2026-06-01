import { ILogger, LogLevel } from './ILogger';
import { NullLogger } from './Loggers';
import { HttpConnection, ConnectionState } from './HttpConnection';
import { IHubProtocol, JsonHubProtocol, HubMessageBase, InvocationMessage, StreamItemMessage, CompletionMessage, PingMessage, CloseMessage } from './HubProtocol';
import { StreamManager } from './StreamManager';
import { TimeoutError } from './utils/Errors';
import { isNotEmptyString } from './utils/Arg';

export enum HubConnectionState {
  Disconnected = 'Disconnected',
  Connected = 'Connected',
  Reconnecting = 'Reconnecting',
}

export interface HubConnectionOptions {
  url: string;
  accessTokenFactory?: (() => string | Promise<string>) | null;
  reconnectDelays?: number[] | null;
  logger?: ILogger;
  serverTimeoutInMilliseconds?: number;
  keepAliveIntervalInMilliseconds?: number;
}

class HandshakePromise {
  resolve: () => void = () => {}
  reject: (error: Error) => void = (_e: Error) => {}
}

type Handler = (args: Object[]) => void;

const DEFAULT_SERVER_TIMEOUT = 30000;
const DEFAULT_KEEP_ALIVE_INTERVAL = 15000;
const DEFAULT_RECONNECT_DELAYS = [0, 2000, 5000, 10000, 30000];

export class HubConnection {
  connectionId: string = '';
  state: HubConnectionState = HubConnectionState.Disconnected;

  onreconnecting: ((error: Error | null) => void) | null = null;
  onreconnected: ((connectionId: string | null) => void) | null = null;
  onclose: ((error: Error | null) => void) | null = null;

  private httpConnection: HttpConnection;
  private protocol: IHubProtocol;
  private streamManager: StreamManager;
  private logger: ILogger;
  private handlers: Map<string, Set<Handler>> = new Map();
  private reconnectDelays: number[];
  private serverTimeoutInMilliseconds: number;
  private keepAliveIntervalInMilliseconds: number;

  private pingTimer: number = -1;
  private serverTimeoutTimer: number = -1;
  private reconnectTimer: number = -1;
  private reconnectAttempt: number = 0;
  private stopRequested: boolean = false;
  private handshakePromise: HandshakePromise | null = null;

  constructor(options: HubConnectionOptions) {
    this.logger = options.logger ?? new NullLogger();
    this.reconnectDelays = options.reconnectDelays ?? DEFAULT_RECONNECT_DELAYS;
    this.serverTimeoutInMilliseconds = options.serverTimeoutInMilliseconds ?? DEFAULT_SERVER_TIMEOUT;
    this.keepAliveIntervalInMilliseconds = options.keepAliveIntervalInMilliseconds ?? DEFAULT_KEEP_ALIVE_INTERVAL;
    this.protocol = new JsonHubProtocol();
    this.streamManager = new StreamManager();

    this.httpConnection = new HttpConnection(options.url, {
      accessTokenFactory: options.accessTokenFactory ?? null,
      logger: this.logger,
    });

    this.httpConnection.onreceive = (data: string) => {
      this.processIncomingData(data);
    };

    this.httpConnection.onclose = (error: Error | null) => {
      this.onConnectionClose(error);
    };
  }

  async start(): Promise<void> {
    if (this.state === HubConnectionState.Connected) {
      return;
    }
    this.stopRequested = false;

    this.logger.log(LogLevel.Information, 'Starting HubConnection');

    await this.httpConnection.start();

    // Send handshake and wait for response
    const handshakeRequest = this.protocol.encodeHandshakeRequest();
    await this.httpConnection.send(handshakeRequest);
    await this.waitForHandshake();

    this.connectionId = this.httpConnection.connectionId;
    this.state = HubConnectionState.Connected;
    this.reconnectAttempt = 0;

    this.resetServerTimeout();
    this.resetKeepAlive();

    this.logger.log(LogLevel.Information, `HubConnection connected: ${this.connectionId}`);
  }

  async stop(): Promise<void> {
    this.stopRequested = true;
    this.clearTimers();
    this.reconnectAttempt = 0;
    this.streamManager.rejectAll(new Error('Connection stopped'));

    if (this.state === HubConnectionState.Disconnected) {
      return;
    }

    this.logger.log(LogLevel.Information, 'Stopping HubConnection');

    try {
      const closeMsg = new CloseMessage();
      await this.httpConnection.send(this.protocol.encodeMessage(closeMsg));
    } catch (_e) {
      // Ignore send errors during close
    }

    // httpConnection.stop() triggers onclose -> onConnectionClose
    // which checks stopRequested and fires this.onclose for us
    await this.httpConnection.stop();
    this.state = HubConnectionState.Disconnected;
  }

  async invoke(methodName: string, ...args: Object[]): Promise<Object | null> {
    isNotEmptyString(methodName, 'methodName');
    this.ensureConnected();

    const invocationId = this.streamManager.generateInvocationId();
    const message = new InvocationMessage();
    message.invocationId = invocationId;
    message.target = methodName;
    message.arguments = args;

    this.logger.log(LogLevel.Debug, `Invoking '${methodName}' with id ${invocationId}`);

    const encoded = this.protocol.encodeMessage(message);

    return new Promise<Object | null>((resolve, reject) => {
      this.streamManager.addInvocation(invocationId,
        (value: Object | null) => {
          this.logger.log(LogLevel.Debug, `Invocation '${methodName}' completed`);
          resolve(value);
        },
        (error: Error) => {
          this.logger.log(LogLevel.Error, `Invocation '${methodName}' failed: ${error.message}`);
          reject(error);
        }
      );
      this.httpConnection.send(encoded).catch((e: Error) => {
        this.streamManager.removeInvocation(invocationId);
        reject(e);
      });
    });
  }

  async send(methodName: string, ...args: Object[]): Promise<void> {
    isNotEmptyString(methodName, 'methodName');
    this.ensureConnected();

    const message = new InvocationMessage();
    message.invocationId = '';
    message.target = methodName;
    message.arguments = args;

    this.logger.log(LogLevel.Debug, `Sending '${methodName}' (fire-and-forget)`);

    const encoded = this.protocol.encodeMessage(message);
    await this.httpConnection.send(encoded);
  }

  on(methodName: string, handler: Handler): void {
    isNotEmptyString(methodName, 'methodName');
    if (!this.handlers.has(methodName)) {
      this.handlers.set(methodName, new Set());
    }
    this.handlers.get(methodName)!.add(handler);
  }

  off(methodName: string, handler?: Handler): void {
    isNotEmptyString(methodName, 'methodName');
    const handlerSet = this.handlers.get(methodName);
    if (handlerSet === undefined) {
      return;
    }
    if (handler !== undefined) {
      handlerSet.delete(handler);
      if (handlerSet.size === 0) {
        this.handlers.delete(methodName);
      }
    } else {
      this.handlers.delete(methodName);
    }
  }

  private ensureConnected(): void {
    if (this.state !== HubConnectionState.Connected) {
      throw new Error('HubConnection is not connected');
    }
  }

  private async waitForHandshake(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const p = new HandshakePromise();
      p.resolve = () => resolve();
      p.reject = (e: Error) => reject(e);
      this.handshakePromise = p;

      // Timeout for handshake
      setTimeout(() => {
        if (this.handshakePromise !== null) {
          this.handshakePromise = null;
          reject(new TimeoutError('Handshake timed out'));
        }
      }, 15000);
    });
  }

  private processIncomingData(data: string): void {
    // First message after connect is the handshake response (not a regular message)
    if (this.handshakePromise !== null) {
      try {
        this.protocol.decodeHandshakeResponse(data);
        const promise = this.handshakePromise;
        this.handshakePromise = null;
        if (promise !== null) {
          promise.resolve();
        }
        return;
      } catch (e) {
        const promise = this.handshakePromise;
        this.handshakePromise = null;
        if (promise !== null) {
          promise.reject(new Error((e as Error).message));
        }
        return;
      }
    }

    // Regular messages
    const messages = this.protocol.decodeMessages(data, this.logger);
    for (const message of messages) {
      this.dispatchMessage(message);
    }
  }

  private dispatchMessage(message: HubMessageBase): void {
    this.resetServerTimeout();

    switch (message.type) {
      case 1: {
        const invocation = message as InvocationMessage;
        this.invokeHandler(invocation.target, invocation.arguments);
        break;
      }
      case 2: {
        const streamItem = message as StreamItemMessage;
        const pending = this.streamManager.getInvocation(streamItem.invocationId);
        if (pending !== undefined) {
          pending.resolve(streamItem.item);
        }
        break;
      }
      case 3: {
        const completion = message as CompletionMessage;
        const pending = this.streamManager.removeInvocation(completion.invocationId);
        if (pending !== undefined) {
          if (completion.error.length > 0) {
            pending.reject(new Error(completion.error))
          } else {
            pending.resolve(completion.result);
          }
        }
        break;
      }
      case 6:
        // Ping - already reset server timeout above
        break;
      case 7: {
        const close = message as CloseMessage;
        this.handleCloseMessage(close);
        break;
      }
      default:
        this.logger.log(LogLevel.Warning, `Unknown message type: ${message.type}`);
        break;
    }
  }

  private invokeHandler(target: string, args: Object[]): void {
    const handlerSet = this.handlers.get(target);
    if (handlerSet === undefined) {
      this.logger.log(LogLevel.Warning, `No handler registered for '${target}'`);
      return;
    }
    handlerSet.forEach((handler: Handler) => {
      try {
        handler(args);
      } catch (e) {
        this.logger.log(LogLevel.Error, `Handler for '${target}' threw: ${(e as Error).message}`);
      }
    });
  }

  private handleCloseMessage(close: CloseMessage): void {
    this.logger.log(LogLevel.Information,
      `Close message received: error='${close.error}', allowReconnect=${close.allowReconnect}`);

    if (close.allowReconnect && this.reconnectDelays.length > 0 && !this.stopRequested) {
      this.triggerReconnect(close.error.length > 0 ? new Error(close.error) : null);
    } else {
      this.clearTimers();
      const error = close.error.length > 0 ? new Error(close.error) : null;
      this.state = HubConnectionState.Disconnected;
      this.streamManager.rejectAll(new Error('Connection closed'));
      if (this.onclose !== null) {
        this.onclose(error);
      }
    }
  }

  private onConnectionClose(error: Error | null): void {
    this.clearTimers();

    if (this.handshakePromise !== null) {
      const promise = this.handshakePromise;
      this.handshakePromise = null;
      promise.reject(error ?? new Error('Connection closed during handshake'));
      return;
    }

    if (this.stopRequested) {
      this.state = HubConnectionState.Disconnected;
      this.streamManager.rejectAll(new Error('Connection stopped'));
      if (this.onclose !== null) {
        this.onclose(error);
      }
      return;
    }

    // Already reconnecting (e.g. httpConnection.stop() called during attemptReconnect)
    if (this.state === HubConnectionState.Reconnecting) {
      return;
    }

    // Auto-reconnect
    if (this.reconnectDelays.length > 0) {
      this.triggerReconnect(error);
    } else {
      this.state = HubConnectionState.Disconnected;
      this.streamManager.rejectAll(new Error('Connection lost'));
      if (this.onclose !== null) {
        this.onclose(error);
      }
    }
  }

  private triggerReconnect(error: Error | null): void {
    if (this.state === HubConnectionState.Reconnecting) {
      return;
    }

    const previousState = this.state;
    this.state = HubConnectionState.Reconnecting;
    this.reconnectAttempt = 0;

    if (this.onreconnecting !== null) {
      this.onreconnecting(error);
    }

    this.scheduleReconnect();
  }

  private scheduleReconnect(): void {
    if (this.stopRequested) {
      return;
    }

    const delayIndex = Math.min(this.reconnectAttempt, this.reconnectDelays.length - 1);
    const delay = this.reconnectDelays[delayIndex];

    this.logger.log(LogLevel.Information,
      `Reconnect attempt ${this.reconnectAttempt + 1}, delay=${delay}ms`);

    this.reconnectTimer = setTimeout(() => {
      this.attemptReconnect();
    }, delay) as number;
  }

  private async attemptReconnect(): Promise<void> {
    if (this.stopRequested) {
      return;
    }

    try {
      this.logger.log(LogLevel.Information, 'Attempting reconnect...');

      if (this.httpConnection.state !== ConnectionState.Disconnected) {
        await this.httpConnection.stop();
      }

      await this.start();

      this.logger.log(LogLevel.Information, `Reconnected: ${this.connectionId}`);

      if (this.onreconnected !== null) {
        this.onreconnected(this.connectionId);
      }
    } catch (e) {
      this.reconnectAttempt++;
      this.logger.log(LogLevel.Warning,
        `Reconnect failed (attempt ${this.reconnectAttempt}): ${(e as Error).message}`);

      const maxAttempts = this.reconnectDelays.length * 3;
      if (this.reconnectAttempt >= maxAttempts) {
        this.logger.log(LogLevel.Error, 'Max reconnect attempts exceeded');
        this.state = HubConnectionState.Disconnected;
        this.streamManager.rejectAll(new Error('Max reconnect attempts exceeded'));
        if (this.onclose !== null) {
          this.onclose(new Error('Max reconnect attempts exceeded'));
        }
        return;
      }

      this.scheduleReconnect();
    }
  }

  private resetKeepAlive(): void {
    if (this.pingTimer !== -1) {
      clearInterval(this.pingTimer);
    }
    this.pingTimer = setInterval(() => {
      if (this.state !== HubConnectionState.Connected) {
        return;
      }
      try {
        const ping = new PingMessage();
        const encoded = this.protocol.encodeMessage(ping);
        this.httpConnection.send(encoded).catch((e: Error) => {
          this.logger.log(LogLevel.Warning, `Ping send failed: ${e.message}`);
        });
      } catch (_e) {
        // Ignore
      }
    }, this.keepAliveIntervalInMilliseconds) as number;
  }

  private resetServerTimeout(): void {
    if (this.serverTimeoutTimer !== -1) {
      clearTimeout(this.serverTimeoutTimer);
    }
    this.serverTimeoutTimer = setTimeout(() => {
      this.logger.log(LogLevel.Warning, 'Server timeout - no message received');
      this.httpConnection.stop(new Error('Server timeout'));
    }, this.serverTimeoutInMilliseconds) as number;
  }

  private clearTimers(): void {
    if (this.pingTimer !== -1) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
    if (this.serverTimeoutTimer !== -1) {
      clearTimeout(this.serverTimeoutTimer);
      this.serverTimeoutTimer = -1;
    }
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }
}
