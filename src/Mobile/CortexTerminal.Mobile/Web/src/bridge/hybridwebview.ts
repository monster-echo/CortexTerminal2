/* eslint-disable @typescript-eslint/no-explicit-any */

export {};

declare global {
  interface External {
    receiveMessage?: (message: unknown) => void;
  }

  interface Window {
    HybridWebView?: {
      SendRawMessage: (message: string) => void;
      InvokeDotNet: (methodName: string, paramValues?: unknown[]) => Promise<unknown>;
      __InvokeJavaScript: (taskId: string, methodName: (...args: unknown[]) => unknown, args: unknown[]) => Promise<void>;
    };
    checkWebViewHealth?: () => string;
    canGoBack?: () => boolean;
    platform?: string;
    initData?: { platform?: string };
    chrome?: { webview?: { addEventListener?(type: string, handler: (arg: { data: unknown }) => void): void; postMessage?(msg: string): void } };
    webkit?: { messageHandlers?: { webwindowinterop?: { postMessage(msg: string): void } } };
    hybridWebViewHost?: { sendMessage(msg: string): void };
  }
}

(() => {
  let sendMessageFunction: ((message: string) => void) | null = null;

  function stringifyAsciiSafe(value: unknown) {
    return JSON.stringify(value).replace(/[\u007F-\uFFFF]/g, (character) => {
      const codeUnit = character.charCodeAt(0);
      return `\\u${codeUnit.toString(16).padStart(4, "0")}`;
    });
  }

  function dispatchHybridWebViewMessage(message: unknown) {
    window.dispatchEvent(
      new CustomEvent("HybridWebViewMessageReceived", {
        detail: { message },
      }),
    );
  }

  function initHybridWebView() {
    if (window.chrome?.webview?.addEventListener) {
      window.chrome.webview.addEventListener("message", (arg) => {
        dispatchHybridWebViewMessage(arg.data);
      });
      sendMessageFunction = (message: string) =>
        window.chrome!.webview!.postMessage!(message);
      return;
    }

    if (window.webkit?.messageHandlers?.webwindowinterop) {
      window.external = window.external ?? {};
      window.external.receiveMessage = (message: unknown) => {
        dispatchHybridWebViewMessage(message);
      };
      sendMessageFunction = (message: string) =>
        window.webkit?.messageHandlers?.webwindowinterop?.postMessage(message);
      return;
    }

    if (window.hybridWebViewHost) {
      window.addEventListener("message", (arg) => {
        dispatchHybridWebViewMessage((arg as MessageEvent).data);
      });
      sendMessageFunction = (message: string) =>
        window.hybridWebViewHost!.sendMessage(message);
    }
  }

  function sendMessageToDotNet(type: string, message: string) {
    const payload = `${type}|${message}`;
    if (!sendMessageFunction) {
      initHybridWebView();
    }

    if (!sendMessageFunction) {
      console.error("Hybrid host is unavailable.");
      return;
    }

    sendMessageFunction(payload);
  }

  function sendRawMessage(message: string) {
    sendMessageToDotNet("__RawMessage", message);
  }

  function invokeJavaScriptCallbackInDotNet(taskId: string, result: unknown) {
    sendMessageToDotNet(
      "__InvokeJavaScriptCompleted",
      `${taskId}|${JSON.stringify(result)}`,
    );
  }

  function invokeJavaScriptFailedInDotNet(taskId: string, error: unknown) {
    const err =
      error instanceof Error
        ? { Name: error.name, Message: error.message, StackTrace: error.stack }
        : {
            Message: String(error ?? "Unknown error"),
            StackTrace: new Error().stack,
          };

    sendMessageToDotNet(
      "__InvokeJavaScriptFailed",
      `${taskId}|${JSON.stringify(err)}`,
    );
  }

  async function invokeDotNet(methodName: string, paramValues?: unknown[]) {
    const body: { MethodName: string; ParamValues?: string[] } = {
      MethodName: methodName,
    };
    const values = Array.isArray(paramValues)
      ? [...paramValues]
      : paramValues === undefined
        ? []
        : [paramValues];

    if (values.length > 0) {
      body.ParamValues = values.map((value) => stringifyAsciiSafe(value));
    }

    const message = stringifyAsciiSafe(body);
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-Maui-Invoke-Token": "HybridWebView",
    };

    if (window.initData?.platform === "android") {
      headers["X-Maui-Request-Body"] = message;
    }

    const response = await fetch("/__hwvInvokeDotNet", {
      method: "POST",
      referrerPolicy: "origin",
      headers,
      body: message,
    });

    const responseText = await response.text();
    if (!response.ok) {
      throw new Error(
        `HybridWebView bridge request failed for ${methodName}: ${response.status} ${response.statusText}${responseText ? ` - ${responseText}` : ""}`,
      );
    }

    if (!responseText.trim()) {
      throw new Error(
        `HybridWebView bridge returned an empty response for ${methodName}.`,
      );
    }

    let payload: any;
    try {
      payload = JSON.parse(responseText);
    } catch (error) {
      throw new Error(
        `HybridWebView bridge returned invalid JSON for ${methodName}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }

    if (!payload) {
      return null;
    }

    if (payload.IsError) {
      const error = new Error(
        payload.ErrorMessage || "Unknown .NET error",
      ) as Error & {
        dotNetErrorType?: string;
        dotNetStackTrace?: string;
      };
      error.dotNetErrorType = payload.ErrorType;
      error.dotNetStackTrace = payload.ErrorStackTrace;
      throw error;
    }

    return payload.IsJson ? JSON.parse(payload.Result) : payload.Result;
  }

  async function invokeJavaScript(
    taskId: string,
    methodName: (...args: any[]) => any,
    args: any[],
  ) {
    try {
      const result = await methodName(...args);
      invokeJavaScriptCallbackInDotNet(taskId, result);
    } catch (error) {
      invokeJavaScriptFailedInDotNet(taskId, error);
    }
  }

  window.HybridWebView = {
    SendRawMessage: sendRawMessage,
    InvokeDotNet: invokeDotNet,
    __InvokeJavaScript: invokeJavaScript,
  };

  initHybridWebView();
})();
