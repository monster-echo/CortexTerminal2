import { TextMessageFormat } from './utils/TextMessageFormat';
import { ILogger, LogLevel } from './ILogger';

// --- Message types ---

export class HubMessageBase {
  type: number = 0;
}

export class InvocationMessage extends HubMessageBase {
  type: number = 1;
  invocationId: string = '';
  target: string = '';
  arguments: Object[] = [];
}

export class StreamItemMessage extends HubMessageBase {
  type: number = 2;
  invocationId: string = '';
  item: Object | null = null;
}

export class CompletionMessage extends HubMessageBase {
  type: number = 3;
  invocationId: string = '';
  result: Object | null = null;
  error: string = '';
}

export class PingMessage extends HubMessageBase {
  type: number = 6;
}

export class CloseMessage extends HubMessageBase {
  type: number = 7;
  error: string = '';
  allowReconnect: boolean = false;
}

// --- Protocol interface ---

export interface IHubProtocol {
  readonly name: string;
  readonly version: number;
  encodeHandshakeRequest(): string;
  decodeHandshakeResponse(input: string): Record<string, Object>;
  encodeMessage(message: HubMessageBase): string;
  decodeMessages(input: string, logger: ILogger): HubMessageBase[];
}

// --- JSON implementation ---

export class JsonHubProtocol implements IHubProtocol {
  readonly name: string = 'json';
  readonly version: number = 1;

  encodeHandshakeRequest(): string {
    return TextMessageFormat.write(JSON.stringify({ protocol: 'json', version: 1 }));
  }

  decodeHandshakeResponse(input: string): Record<string, Object> {
    const messages = TextMessageFormat.parse(input);
    if (messages.length === 0) {
      throw new Error('Empty handshake response');
    }
    const response = JSON.parse(messages[0]) as Record<string, Object>;
    if (response['error'] !== undefined && response['error'] !== null) {
      throw new Error(`Handshake error: ${response['error']}`);
    }
    return response;
  }

  encodeMessage(message: HubMessageBase): string {
    return TextMessageFormat.write(JSON.stringify(message));
  }

  decodeMessages(input: string, logger: ILogger): HubMessageBase[] {
    const rawMessages = TextMessageFormat.parse(input);
    const messages: HubMessageBase[] = [];

    for (const raw of rawMessages) {
      try {
        const obj = JSON.parse(raw) as Record<string, Object>;
        const type = obj['type'] as number;
        const msg = this.parseMessage(type, obj);
        if (msg !== null) {
          messages.push(msg);
        }
      } catch (e) {
        logger.log(LogLevel.Warning, `Failed to parse message: ${e}`);
      }
    }

    return messages;
  }

  private parseMessage(type: number, obj: Record<string, Object>): HubMessageBase | null {
    switch (type) {
      case 1: {
        const msg = new InvocationMessage();
        msg.invocationId = (obj['invocationId'] as string) ?? '';
        msg.target = obj['target'] as string;
        msg.arguments = (obj['arguments'] as Object[]) ?? [];
        return msg;
      }
      case 2: {
        const msg = new StreamItemMessage();
        msg.invocationId = obj['invocationId'] as string;
        msg.item = obj['item'] ?? null;
        return msg;
      }
      case 3: {
        const msg = new CompletionMessage();
        msg.invocationId = obj['invocationId'] as string;
        msg.result = obj['result'] ?? null;
        msg.error = (obj['error'] as string) ?? '';
        return msg;
      }
      case 6:
        return new PingMessage();
      case 7: {
        const msg = new CloseMessage();
        msg.error = (obj['error'] as string) ?? '';
        msg.allowReconnect = (obj['allowReconnect'] as boolean) ?? false;
        return msg;
      }
      default:
        return null;
    }
  }
}
