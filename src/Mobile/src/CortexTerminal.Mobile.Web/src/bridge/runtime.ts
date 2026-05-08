/* eslint-disable @typescript-eslint/no-explicit-any */

import type { ZodType } from "zod";
import { transport } from "./transport";

export class BridgeUnavailableError extends Error {}
export class BridgeTimeoutError extends Error {}
export class BridgeSchemaValidationError extends Error {}

interface InvokeOptions {
  timeoutMs?: number;
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
  const result = await withTimeout(
    transport.invoke(methodName, args),
    options.timeoutMs ?? 7000,
    methodName,
  );
  const data = typeof result === "string" ? JSON.parse(result) : result;

  if (data && typeof data === "object" && "error" in data) {
    throw new Error((data as { error: string }).error);
  }

  const parsed = schema.safeParse(data);
  if (!parsed.success) {
    throw new BridgeSchemaValidationError(
      `Schema validation failed for ${methodName}: ${parsed.error.message}`,
    );
  }

  return parsed.data;
}

export function sendRaw(message: unknown) {
  transport.sendRaw(message);
}

export { transport };
