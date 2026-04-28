import { useEffect, useMemo, useRef, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import type {
  TerminalGateway,
  TerminalGatewayConnection,
} from "../services/terminalGateway";
import {
  createTerminalSessionModel,
  type TerminalSessionState,
} from "./useTerminalSession";
import { createBrowserTerminal } from "./createBrowserTerminal";

export function TerminalView(props: {
  gateway: TerminalGateway;
  sessionId: string;
}) {
  const { gateway, sessionId } = props;
  const [status, setStatus] = useState<TerminalSessionState>("live");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const connectionRef = useRef<TerminalGatewayConnection | null>(null);
  const terminalContainerRef = useRef<HTMLDivElement | null>(null);
  const browserTerminalRef = useRef<ReturnType<
    typeof createBrowserTerminal
  > | null>(null);

  const session = useMemo(
    () =>
      createTerminalSessionModel({
        writeInput: (payload) => {
          void connectionRef.current?.writeInput(payload);
        },
        onStateChange: setStatus,
        onStream: ({ text }) => {
          browserTerminalRef.current?.write(text);
        },
      }),
    [sessionId],
  );

  // Mount xterm terminal
  useEffect(() => {
    const element = terminalContainerRef.current;
    if (!element) {
      return;
    }

    const browserTerminal = createBrowserTerminal(element, (data) => {
      session.onTerminalData(data);
    });
    browserTerminalRef.current = browserTerminal;

    // Initial fit
    browserTerminal.fit();

    // Handle container resize
    const observer = new ResizeObserver(() => {
      const next = browserTerminal.fit();
      void connectionRef.current?.resize(next.columns, next.rows);
    });
    observer.observe(element);

    return () => {
      observer.disconnect();
      browserTerminal.dispose();
      browserTerminalRef.current = null;
    };
  }, [session]);

  // Connect to terminal gateway
  useEffect(() => {
    let isActive = true;
    setStatus("live");
    setErrorMessage(null);

    void gateway
      .connect(sessionId, {
        onStdout: (payload) => {
          session.onStdout(payload);
        },
        onStderr: (payload) => {
          session.onStderr(payload);
        },
        onSessionReattached: (nextSessionId) => {
          session.onSessionReattached(nextSessionId);
        },
        onReplayChunk: (payload, stream) => {
          session.onReplayChunk(payload, stream);
        },
        onReplayCompleted: () => {
          session.onReplayCompleted();
        },
        onSessionExpired: (reason) => {
          setErrorMessage(reason ?? "Session expired.");
          session.onSessionExpired();
        },
      })
      .then((connection) => {
        if (!isActive) {
          void connection.dispose();
          return;
        }

        connectionRef.current = connection;

        // Resize after connection is established
        const browserTerminal = browserTerminalRef.current;
        if (browserTerminal) {
          const size = browserTerminal.fit();
          void connection.resize(size.columns, size.rows);
        }
      })
      .catch((error: unknown) => {
        if (!isActive) {
          return;
        }

        setErrorMessage(
          error instanceof Error
            ? error.message
            : "Could not connect terminal.",
        );
      });

    return () => {
      isActive = false;
      const connection = connectionRef.current;
      connectionRef.current = null;
      if (connection) {
        void connection.dispose();
      }
    };
  }, [gateway, session, sessionId]);

  return (
    <div className="flex flex-col flex-1 min-h-0">
      {errorMessage ? (
        <Alert variant="destructive" className="mx-1 mb-2">
          <AlertDescription>{errorMessage}</AlertDescription>
        </Alert>
      ) : null}
      <div
        ref={terminalContainerRef}
        className="flex-1 min-h-0 w-full rounded-lg bg-[#0d1117] border border-border"
      />
      <div className="flex items-center justify-between px-2 py-1.5 text-[11px] text-muted-foreground shrink-0">
        <div className="flex items-center gap-2">
          <span
            className={`h-2 w-2 rounded-full ${status === "live" ? "bg-emerald-500" : "bg-amber-500"}`}
          />
          <span className="font-medium">{status}</span>
        </div>
        <span>E2E &mdash;</span>
        <span>&mdash; &times; &mdash;</span>
      </div>
    </div>
  );
}
