// HubConnection - main API
export { HubConnection, HubConnectionState } from './src/main/ets/HubConnection'
export type { HubConnectionOptions } from './src/main/ets/HubConnection'

// Builder
export { HubConnectionBuilder } from './src/main/ets/HubConnectionBuilder'

// Transport
export { HttpConnection, ConnectionState } from './src/main/ets/HttpConnection'
export type { HttpConnectionOptions } from './src/main/ets/HttpConnection'

// Protocol
export { JsonHubProtocol } from './src/main/ets/HubProtocol'
export type { IHubProtocol } from './src/main/ets/HubProtocol'
export { HubMessageBase, InvocationMessage, StreamItemMessage, CompletionMessage, PingMessage, CloseMessage } from './src/main/ets/HubProtocol'

// Invocation tracking
export { StreamManager, InvocationRequest } from './src/main/ets/StreamManager'

// Logging
export { LogLevel } from './src/main/ets/ILogger'
export type { ILogger } from './src/main/ets/ILogger'
export { NullLogger, DefaultLogger } from './src/main/ets/Loggers'

// Utils
export { TextMessageFormat } from './src/main/ets/utils/TextMessageFormat'
export { HttpError, TimeoutError, HubException, InternalServerError } from './src/main/ets/utils/Errors'
