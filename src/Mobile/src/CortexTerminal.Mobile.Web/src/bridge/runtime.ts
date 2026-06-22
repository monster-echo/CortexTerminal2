/* eslint-disable @typescript-eslint/no-explicit-any */

import type { ZodType } from "zod";
import { transport } from "./transport";

const ANALYTICS_METHODS = new Set([
  "TrackAnalyticsEventAsync",
  "SetAnalyticsUserIdAsync",
  "SetAnalyticsUserPropertyAsync",
]);

let onSessionInvalidated: (() => void) | null = null;

export function registerSessionInvalidatedHandler(handler: () => void) {
  onSessionInvalidated = handler;
}

export class BridgeUnavailableError extends Error {}
export class BridgeTimeoutError extends Error {}
export class BridgeSchemaValidationError extends Error {}

interface InvokeOptions {
  timeoutMs?: number;
  retries?: number;
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  methodName: string,
): Promise<T> {
  let timeoutHandle: ReturnType<typeof setTimeout> | undefined;

  const timeoutPromise = new Promise<never>((_, reject) => {
    timeoutHandle = setTimeout(() => {
      reject(new BridgeTimeoutError(`Bridge call timed out: ${methodName}`));
    }, timeoutMs);
  });

  try {
    return await Promise.race([promise, timeoutPromise]);
  } finally {
    if (timeoutHandle) {
      clearTimeout(timeoutHandle);
    }
  }
}

export async function invoke<T>(
  methodName: string,
  schema: ZodType<T>,
  args: unknown[] = [],
  options: InvokeOptions = {},
): Promise<T> {
  const timeoutMs = options.timeoutMs ?? 7000;
  const maxRetries = options.retries ?? 0;
  const t0 = performance.now();

  let lastError: Error | undefined;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      if (attempt > 0) console.log(`⏱ [bridge] retry #${attempt} ${methodName}`);
      const t1 = performance.now();
      const result = await withTimeout(
        transport.invoke(methodName, args),
        timeoutMs,
        methodName,
      );
      const t2 = performance.now();
      const data = typeof result === "string" ? JSON.parse(result) : result;

      if (data && typeof data === "object" && "error" in data) {
        const errorMsg = (data as { error: string }).error;
        console.log(`⏱ [bridge] ${methodName} IPC=${(t2 - t1).toFixed(0)}ms ERROR: ${errorMsg}`);
        reportBridgeCall(methodName, t2 - t1);
        reportBridgeError(methodName, "remote", errorMsg);
        if (errorMsg.includes("401") || errorMsg.toLowerCase().includes("unauthorized")) {
          onSessionInvalidated?.();
        }
        throw new Error(errorMsg);
      }

      const parsed = schema.safeParse(data);
      if (!parsed.success) {
        console.log(`⏱ [bridge] ${methodName} IPC=${(t2 - t1).toFixed(0)}ms SCHEMA_FAIL`);
        reportBridgeCall(methodName, t2 - t1);
        reportBridgeError(methodName, "schema", parsed.error.message);
        throw new BridgeSchemaValidationError(
          `Schema validation failed for ${methodName}: ${parsed.error.message}`,
        );
      }

      console.log(`⏱ [bridge] ${methodName} total=${(performance.now() - t0).toFixed(0)}ms IPC=${(t2 - t1).toFixed(0)}ms ok`);
      reportBridgeCall(methodName, t2 - t1);
      return parsed.data;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      console.log(`⏱ [bridge] ${methodName} FAIL after ${(performance.now() - t0).toFixed(0)}ms: ${lastError.message}`);
      if (error instanceof BridgeTimeoutError) {
        reportBridgeError(methodName, "timeout", lastError.message);
      } else if (!ANALYTICS_METHODS.has(methodName)) {
        reportBridgeError(methodName, "exception", lastError.message);
      }
      // Only retry on timeout errors (JS timeout or C# HttpClient timeout)
      const isRetryable =
        error instanceof BridgeTimeoutError ||
        lastError.message.includes("timedout") ||
        lastError.message.includes("timeout");
      if (!isRetryable || attempt >= maxRetries) {
        throw lastError;
      }
    }
  }

  throw lastError;
}

function reportBridgeCall(methodName: string, durationMs: number): void {
  if (ANALYTICS_METHODS.has(methodName)) return;
  import("./modules/analyticsBridge")
    .then(({ analyticsBridge }) => {
      analyticsBridge.trackTiming("bridge_call", durationMs, { call_name: methodName });
    })
    .catch(() => {});
}

function reportBridgeError(methodName: string, errorType: string, message: string): void {
  if (ANALYTICS_METHODS.has(methodName)) return;
  import("./modules/analyticsBridge")
    .then(({ analyticsBridge }) => {
      analyticsBridge.trackBridgeError(methodName, errorType, message);
    })
    .catch(() => {});
}

export function sendRaw(message: unknown) {
  transport.sendRaw(message);
}

export { transport };
