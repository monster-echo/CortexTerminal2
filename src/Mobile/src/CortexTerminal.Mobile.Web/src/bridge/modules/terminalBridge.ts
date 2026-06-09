import { HasClipboardTextSchema, ReadClipboardTextSchema, SuccessResponseSchema } from "../../schemas/bridgeSchema";
import {
  TerminalSessionSchema,
  TerminalSessionsSchema,
  WorkerSummariesSchema,
} from "../../schemas/sessionSchema";
import { invoke } from "../runtime";

export const terminalBridge = {
  listSessions: () => invoke("ListTerminalSessionsAsync", TerminalSessionsSchema, [], { timeoutMs: 45000, retries: 1 }),
  listWorkers: () => invoke("ListTerminalWorkersAsync", WorkerSummariesSchema, [], { timeoutMs: 45000, retries: 1 }),
  createSession: (columns = 120, rows = 40, workerId?: string) =>
    invoke("CreateTerminalSessionAsync", TerminalSessionSchema, [
      columns,
      rows,
      workerId ?? null,
    ], { timeoutMs: 45000, retries: 1 }),
  connectSession: (sessionId: string) =>
    invoke("ConnectTerminalSessionAsync", SuccessResponseSchema, [sessionId], {
      timeoutMs: 45000,
      retries: 1,
    }),
  writeInput: (sessionId: string, text: string) =>
    invoke("WriteTerminalInputAsync", SuccessResponseSchema, [sessionId, text], { timeoutMs: 15000 }),
  resizeSession: (sessionId: string, columns: number, rows: number) =>
    invoke("ResizeTerminalSessionAsync", SuccessResponseSchema, [
      sessionId,
      columns,
      rows,
    ], { timeoutMs: 15000 }),
  closeSession: (sessionId: string) =>
    invoke("CloseTerminalSessionAsync", SuccessResponseSchema, [sessionId], { timeoutMs: 15000 }),
  disconnectSession: () =>
    invoke("DisconnectTerminalSessionAsync", SuccessResponseSchema, [], { timeoutMs: 15000 }),
  deleteSession: (sessionId: string) =>
    invoke("DeleteTerminalSessionAsync", SuccessResponseSchema, [sessionId], { timeoutMs: 15000 }),
  renameSession: (sessionId: string, name: string) =>
    invoke("RenameTerminalSessionAsync", SuccessResponseSchema, [sessionId, name], { timeoutMs: 15000 }),
  hasClipboardText: () =>
    invoke("HasClipboardTextAsync", HasClipboardTextSchema, [], { timeoutMs: 3000 }),
  readClipboardText: () =>
    invoke("ReadClipboardTextAsync", ReadClipboardTextSchema, [], { timeoutMs: 3000 }),
  writeClipboardText: (text: string) =>
    invoke("WriteClipboardTextAsync", SuccessResponseSchema, [text], { timeoutMs: 3000 }),
};
