import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
  const [cols, setCols] = useState<number | null>(null);
  const [rows, setRows] = useState<number | null>(null);
  const [latencyMs, setLatencyMs] = useState<number | null>(null);
  const [latencyState, setLatencyState] = useState<"measuring" | "live" | "offline">("measuring");
  const connectionRef = useRef<TerminalGatewayConnection | null>(null);
  const terminalContainerRef = useRef<HTMLDivElement | null>(null);
  const browserTerminalRef = useRef<ReturnType<
    typeof createBrowserTerminal
  > | null>(null);
  const latencySeqRef = useRef(0);
  const pendingProbes = useRef(new Map<string, number>()).current;

  const handleLatencyProbeAck = useCallback((probeId: string) => {
    const startedAt = pendingProbes.get(probeId);
    if (startedAt === undefined) return;
    pendingProbes.delete(probeId);
    setLatencyMs(performance.now() - startedAt);
    setLatencyState("live");
  }, [pendingProbes]);

  const measureLatency = useCallback(() => {
    const conn = connectionRef.current;
    if (!conn || status !== "live") return;
    const probeId = `p-${++latencySeqRef.current}`;
    pendingProbes.set(probeId, performance.now());
    setLatencyState("measuring");
    void conn.probeLatency(probeId);
    setTimeout(() => {
      if (pendingProbes.has(probeId)) {
        pendingProbes.delete(probeId);
        setLatencyState("offline");
      }
    }, 5000);
  }, [status]);

  const session = useMemo(
    () =>
      createTerminalSessionModel({
        writeInput: (payload) => {
          void connectionRef.current?.writeInput(payload);
        },
        onStateChange: (nextStatus) => {
          setStatus(nextStatus);
          if (nextStatus !== "live") {
            pendingProbes.clear();
            setLatencyState("offline");
          }
        },
        onStream: ({ text }) => {
          browserTerminalRef.current?.write(text);
        },
      }),
    [sessionId, pendingProbes],
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

    browserTerminal.fit();

    const observer = new ResizeObserver(() => {
      const next = browserTerminal.fit();
      setCols(next.columns);
      setRows(next.rows);
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
    setLatencyMs(null);
    setLatencyState("measuring");

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
        onLatencyProbeAck: handleLatencyProbeAck,
      })
      .then((connection) => {
        if (!isActive) {
          void connection.dispose();
          return;
        }

        connectionRef.current = connection;

        const browserTerminal = browserTerminalRef.current;
        if (browserTerminal) {
          const size = browserTerminal.fit();
          setCols(size.columns);
          setRows(size.rows);
          void connection.resize(size.columns, size.rows);
        }

        measureLatency();
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
  }, [gateway, session, sessionId, measureLatency]);

  // Periodic latency probes
  useEffect(() => {
    const interval = setInterval(() => {
      measureLatency();
    }, 5000);
    return () => clearInterval(interval);
  }, [measureLatency]);

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
      <div className="flex items-center justify-between px-3 h-8 shrink-0 text-xs text-muted-foreground bg-card/50 border-t border-border mt-1 rounded-b-lg">
        <div className="flex items-center gap-2">
          <span
            className={`h-2 w-2 rounded-full shrink-0 ${status === "live" ? "bg-emerald-500" : "bg-amber-500"}`}
          />
          <span className="font-medium">{status}</span>
        </div>
        <span>
          {latencyState === "measuring" ? "E2E —" : latencyMs !== null ? `E2E ${Math.round(latencyMs)}ms` : "E2E —"}
        </span>
        <span>{cols !== null && rows !== null ? `${cols}\u00d7${rows}` : ""}</span>
      </div>
    </div>
  );
}
