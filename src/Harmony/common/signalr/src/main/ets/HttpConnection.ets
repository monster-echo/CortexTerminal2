import { http, webSocket } from '@kit.NetworkKit';
import { buffer } from '@kit.ArkTS';
import { ILogger, LogLevel } from './ILogger';
import { NullLogger } from './Loggers';
import { HttpError } from './utils/Errors';

export enum ConnectionState {
  Disconnected = 0,
  Connecting = 1,
  Connected = 2,
  Disconnecting = 3,
}

export interface HttpConnectionOptions {
  accessTokenFactory?: (() => string | Promise<string>) | null;
  logger?: ILogger;
}

interface NegotiateResponse {
  connectionToken: string;
  connectionId: string;
  negotiateVersion: number;
  availableTransports: Array<TransportDescription>;
  error?: string;
  url?: string;
  accessToken?: string;
}

interface TransportDescription {
  transport: string;
  transferFormats: string[];
}

export class HttpConnection {
  connectionId: string = '';
  state: ConnectionState = ConnectionState.Disconnected;

  onreceive: ((data: string) => void) | null = null;
  onclose: ((error: Error | null) => void) | null = null;

  private url: string;
  private accessTokenFactory: (() => string | Promise<string>) | null;
  private logger: ILogger;
  private ws: webSocket.WebSocket | null = null;
  private connectionToken: string = '';
  private stopRequested: boolean = false;

  constructor(url: string, options?: HttpConnectionOptions) {
    this.url = url;
    this.accessTokenFactory = options?.accessTokenFactory ?? null;
    this.logger = options?.logger ?? new NullLogger();
  }

  async start(): Promise<void> {
    if (this.state !== ConnectionState.Disconnected) {
      throw new Error('Cannot start when not disconnected');
    }
    this.stopRequested = false;
    this.state = ConnectionState.Connecting;

    try {
      const accessToken = await this.getAccessToken();

      // Negotiate
      this.connectionToken = await this.negotiate(accessToken);

      // Connect WebSocket
      await this.connectWebSocket(accessToken);

      this.state = ConnectionState.Connected;
    } catch (e) {
      this.state = ConnectionState.Disconnected;
      throw new Error(`Connection failed: ${(e as Error).message}`);
    }
  }

  async send(data: string): Promise<void> {
    if (this.state !== ConnectionState.Connected || this.ws === null) {
      throw new Error('Cannot send when not connected');
    }
    try {
      await this.ws.send(data);
    } catch (e) {
      throw new Error((e as Error).message);
    }
  }

  async stop(error?: Error): Promise<void> {
    this.stopRequested = true;
    this.state = ConnectionState.Disconnecting;

    if (this.ws !== null) {
      try {
        this.ws.close();
      } catch (_e) {
        // Ignore close errors
      }
      this.ws = null;
    }

    this.state = ConnectionState.Disconnected;
    if (this.onclose !== null) {
      this.onclose(error ?? null);
    }
  }

  private async getAccessToken(): Promise<string> {
    if (this.accessTokenFactory === null) {
      return '';
    }
    const token = this.accessTokenFactory();
    if (token instanceof Promise) {
      return await token;
    }
    return token;
  }

  private async negotiate(accessToken: string): Promise<string> {
    const negotiateUrl = `${this.url}/negotiate?negotiateVersion=1`;
    this.logger.log(LogLevel.Information, `Negotiating at ${this.url}/negotiate`);

    const httpClient = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (accessToken.length > 0) {
        headers['Authorization'] = `Bearer ${accessToken}`;
      }

      const response = await httpClient.request(negotiateUrl, {
        method: http.RequestMethod.POST,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 15000,
      });

      if (response.responseCode === 200 || response.responseCode === 204) {
        const body = response.result as string;
        if (!body || body.length === 0) {
          throw new Error('Empty negotiate response');
        }
        const negotiateResponse = JSON.parse(body) as NegotiateResponse;

        if (negotiateResponse.error) {
          throw new Error(`Negotiate error: ${negotiateResponse.error}`);
        }

        this.connectionId = negotiateResponse.connectionId ?? '';
        this.logger.log(LogLevel.Information,
          `Negotiated: connectionId=${this.connectionId}`);

        return negotiateResponse.connectionToken ?? '';
      } else {
        throw new HttpError(
          `Negotiate failed with status ${response.responseCode}`,
          response.responseCode
        );
      }
    } finally {
      httpClient.destroy();
    }
  }

  private async connectWebSocket(accessToken: string): Promise<void> {
    const wsUrl = this.url
      .replace('https://', 'wss://')
      .replace('http://', 'ws://');

    let fullUrl = wsUrl;
    const params: string[] = [];
    if (this.connectionToken.length > 0) {
      params.push(`id=${encodeURIComponent(this.connectionToken)}`);
    }
    if (accessToken.length > 0) {
      params.push(`access_token=${encodeURIComponent(accessToken)}`);
    }
    if (params.length > 0) {
      fullUrl += '?' + params.join('&');
    }

    this.logger.log(LogLevel.Information, `Connecting WebSocket to ${this.redactUrl(fullUrl)}`);

    this.ws = webSocket.createWebSocket();
    const ws = this.ws;

    const openPromise = new Promise<void>((resolve, reject) => {
      ws.on('open', () => {
        this.logger.log(LogLevel.Information, 'WebSocket connected');
        resolve();
      });
      ws.on('error', (err: Error) => {
        this.logger.log(LogLevel.Error, `WebSocket error: ${err.message}`);
        if (this.stopRequested) {
          return;
        }
        reject(new Error(`WebSocket error: ${err.message}`));
      });
    });

    ws.on('message', (_err: Error, data: string | ArrayBuffer) => {
      if (this.stopRequested) {
        return;
      }
      let text: string;
      if (typeof data === 'string') {
        text = data;
      } else {
        text = buffer.from(data).toString('utf-8');
      }
      if (this.onreceive !== null) {
        this.onreceive(text);
      }
    });

    ws.on('close', (_err: Error, data: webSocket.CloseResult) => {
      this.logger.log(LogLevel.Information,
        `WebSocket closed: code=${data?.code}, reason=${data?.reason ?? ''}`);
      if (this.stopRequested) {
        return;
      }
      this.state = ConnectionState.Disconnected;
      this.ws = null;
      if (this.onclose !== null) {
        this.onclose(null);
      }
    });

    const connectHeaders: Record<string, string> = {};
    if (accessToken.length > 0) {
      connectHeaders['Authorization'] = `Bearer ${accessToken}`;
    }

    try {
      await ws.connect(fullUrl, {
        header: connectHeaders,
      });
    } catch (e) {
      throw new Error((e as Error).message);
    }

    await openPromise;
  }

  private redactUrl(url: string): string {
    const tokenIndex = url.indexOf('access_token=');
    if (tokenIndex < 0) {
      return url;
    }
    return url.substring(0, tokenIndex) + 'access_token=<redacted>';
  }
}
