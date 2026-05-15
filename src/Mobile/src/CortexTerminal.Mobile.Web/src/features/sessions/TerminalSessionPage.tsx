import {
  IonBadge,
  IonButtons,
  IonContent,
  IonFabButton,
  IonHeader,
  IonIcon,
  IonMenuButton,
  IonPage,
  IonTitle,
  IonToolbar,
  useIonActionSheet,
  useIonToast,
} from "@ionic/react";
import {
  arrowUpOutline,
  arrowDownOutline,
  arrowBackOutline,
  arrowForwardOutline,
  keypadOutline,
} from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import "@xterm/xterm/css/xterm.css";
import { useSessionStore } from "../../store/sessionStore";
import { terminalBridge } from "../../bridge/modules/terminalBridge";
import { transport } from "../../bridge/runtime";

interface RouteParams {
  sessionId: string;
}

function decodeBase64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// Normalize bare \n to \r\n for xterm.js (convertEol: false).
// Linux PTY output may contain bare \n that causes staircase garbling.
function normalizeTerminalOutput(bytes: Uint8Array): Uint8Array {
  const text = new TextDecoder().decode(bytes);
  if (!text.includes('\n')) return bytes;
  const normalized = text.replace(/(?<!\r)\n/g, '\r\n');
  return new TextEncoder().encode(normalized);
}

// ── Custom draggable hook using pointer events, with snap-to-edge ──
function useDraggable(storageKey: string) {
  const loadPos = (): { x: number; y: number } => {
    try {
      const raw = localStorage.getItem(storageKey);
      if (raw) return JSON.parse(raw);
    } catch { /* ignore */ }
    return { x: 0, y: 0 };
  };

  const [pos, setPos] = useState(loadPos);
  const [isDragging, setIsDragging] = useState(false);
  const selfRef = useRef<HTMLDivElement | null>(null);
  const dragState = useRef({
    active: false,
    startX: 0,
    startY: 0,
    origX: 0,
    origY: 0,
    moved: false,
  });

  const onPointerDown = (e: React.PointerEvent) => {
    const ds = dragState.current;
    ds.active = true;
    ds.startX = e.clientX;
    ds.startY = e.clientY;
    ds.origX = pos.x;
    ds.origY = pos.y;
    ds.moved = false;
    setIsDragging(true);
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const ds = dragState.current;
    if (!ds.active) return;
    const dx = e.clientX - ds.startX;
    const dy = e.clientY - ds.startY;
    if (!ds.moved && Math.abs(dx) < 3 && Math.abs(dy) < 3) return;
    ds.moved = true;
    const next = { x: ds.origX + dx, y: ds.origY + dy };
    setPos(next);
  };

  const onPointerUp = () => {
    dragState.current.active = false;
    setIsDragging(false);

    // Snap to nearest horizontal edge, clamp vertical to viewport
    requestAnimationFrame(() => {
      const el = selfRef.current;
      if (!el) return;
      const vpWidth = window.visualViewport?.width ?? window.innerWidth;
      const vpHeight = window.visualViewport?.height ?? window.innerHeight;
      const rect = el.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const margin = 16;

      // Horizontal: snap to nearest edge
      const targetX = centerX < vpWidth / 2
        ? -(rect.left - margin)
        : (vpWidth - rect.right + margin);

      // Vertical: clamp to viewport [margin, vpHeight - height - margin]
      const clampedTop = Math.max(margin, Math.min(rect.top, vpHeight - rect.height - margin));
      const targetY = pos.y + (clampedTop - rect.top);

      const snapped = { x: targetX, y: targetY };
      setPos(snapped);
      try {
        localStorage.setItem(storageKey, JSON.stringify(snapped));
      } catch { /* ignore */ }
    });
  };

  const wasDragged = () => dragState.current.moved;

  const bind = {
    onPointerDown,
    onPointerMove,
    onPointerUp,
    style: {
      transform: `translate(${pos.x}px, ${pos.y}px)`,
      transition: isDragging ? "none" : "transform 0.3s cubic-bezier(0.25, 1, 0.5, 1)",
    } as React.CSSProperties,
    setRef: (el: HTMLDivElement | null) => { selfRef.current = el; },
  };

  return { bind, wasDragged, pos };
}

export default function TerminalSessionPage({
  match,
  history,
}: RouteComponentProps<RouteParams>) {
  const sessionId = match.params.sessionId;
  const { t } = useTranslation();
  const [statusMessage, setStatusMessage] = useState(t("terminal.connecting"));
  const [latency, setLatency] = useState<number | null>(null);
  const [presentActionSheet] = useIonActionSheet();

  const session = useSessionStore((state) =>
    state.recentSessions.find((item) => item.id === sessionId),
  );
  const removeSession = useSessionStore((state) => state.removeSession);
  const [presentToast] = useIonToast();

  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const resizeTimeoutRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const connectedRef = useRef(false);

  const [ctrlActive, setCtrlActive] = useState(false);
  const [altActive, setAltActive] = useState(false);
  const [keysExpanded, setKeysExpanded] = useState(false);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleKeyRef = useRef<any>(null);

  const keysDrag = useDraggable("fab-pos");

  // Track FAB quadrant for dynamic expansion direction
  const fabRef = useRef<HTMLDivElement | null>(null);
  const [fabQuadrant, setFabQuadrant] = useState({ isRight: true, isBottom: true });

  useEffect(() => {
    requestAnimationFrame(() => {
      const el = fabRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vpWidth = window.visualViewport?.width ?? window.innerWidth;
      const vpHeight = window.visualViewport?.height ?? window.innerHeight;
      setFabQuadrant({
        isRight: rect.left + rect.width / 2 > vpWidth / 2,
        isBottom: rect.top + rect.height / 2 > vpHeight / 2,
      });
    });
  }, [keysDrag.pos]);

  const sendInput = (text: string) => {
    if (!connectedRef.current) return;
    void terminalBridge.writeInput(sessionId, text);
  };

  const applyCtrl = (sequence: string): string => {
    const code = sequence.charCodeAt(0);
    if (code === 0x1b) return "\x03";
    if (code >= 0x41 && code <= 0x5a) return String.fromCharCode(code - 64);
    if (code >= 0x61 && code <= 0x7a) return String.fromCharCode(code - 96);
    return sequence;
  };

  const handleKey = useCallback(
    (sequence: string) => {
      if (ctrlActive) {
        sequence = applyCtrl(sequence);
      } else if (altActive) {
        sequence = "\x1b" + sequence;
      }
      sendInput(sequence);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [ctrlActive, altActive, connectedRef.current],
  );
  handleKeyRef.current = handleKey;

  // ── Initialize xterm ──
  useEffect(() => {
    if (!terminalRef.current) return;

    const term = new Terminal({
      fontSize: 14,
      fontFamily:
        "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      theme: {
        background: "#0b0f0e",
        foreground: "#d7ffe5",
        cursor: "#d7ffe5",
        selectionBackground: "rgba(215,255,229,0.25)",
      },
      cursorBlink: true,
      scrollback: 5000,
      convertEol: false,
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    xtermRef.current = term;
    fitAddonRef.current = fitAddon;

    term.open(terminalRef.current);

    try {
      term.loadAddon(new WebglAddon());
    } catch {
      // Falls back to canvas renderer
    }

    // Double RAF: let CSS height:100% layout settle before first fit
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        fitAddon.fit();
      });
    });

    const inputDataDisposable = term.onData((data) => {
      handleKeyRef.current?.(data);
    });

    let lastCols = term.cols;
    let lastRows = term.rows;
    const resizeDisposable = term.onResize(({ cols, rows }) => {
      if (cols !== lastCols || rows !== lastRows) {
        lastCols = cols;
        lastRows = rows;
        if (connectedRef.current) {
          void terminalBridge.resizeSession(sessionId, cols, rows);
        }
      }
    });

    const observer = new ResizeObserver(() => {
      if (resizeTimeoutRef.current) clearTimeout(resizeTimeoutRef.current);
      resizeTimeoutRef.current = setTimeout(() => {
        try {
          fitAddon.fit();
        } catch {
          /* component may be unmounted */
        }
      }, 100);
    });
    observer.observe(terminalRef.current);

    return () => {
      observer.disconnect();
      inputDataDisposable.dispose();
      resizeDisposable.dispose();
      term.dispose();
      xtermRef.current = null;
      fitAddonRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Connect session & handle events ──
  useEffect(() => {
    let cancelled = false;
    const term = xtermRef.current;

    const unsubscribe = transport.onMessage((data) => {
      if (!data || typeof data !== "object") return;
      const event = data as {
        type?: string;
        sessionId?: string;
        stream?: string;
        base64?: string;
        reason?: string;
        exitCode?: number;
        timestamp?: string;
      };
      if (event.sessionId && event.sessionId !== sessionId) return;

      if (
        (event.type === "terminal.replay" || event.type === "terminal.output") &&
        event.base64 &&
        term
      ) {
        try {
          term.write(normalizeTerminalOutput(decodeBase64ToBytes(event.base64)));
        } catch {
          /* ignore decode errors */
        }
        if (event.type === "terminal.replay") {
          setStatusMessage(t("terminal.replaying"));
        } else {
          setStatusMessage(t("terminal.live"));
        }
        return;
      }

      if (event.type === "terminal.connected") {
        connectedRef.current = true;
        setStatusMessage(t("terminal.connected"));
        setLatency(null);
        fitAddonRef.current?.fit();
        if (term) void terminalBridge.resizeSession(sessionId, term.cols, term.rows);
      }
      if (event.type === "terminal.reattached") {
        term?.reset();
        setStatusMessage(t("terminal.reattached"));
      }
      if (event.type === "terminal.replayCompleted") {
        term?.reset();
        setStatusMessage(t("terminal.live"));
        fitAddonRef.current?.fit();
        if (term) void terminalBridge.resizeSession(sessionId, term.cols, term.rows);
      }
      if (event.type === "terminal.reconnecting") {
        connectedRef.current = false;
        setStatusMessage(t("terminal.reconnecting"));
      }
      if (event.type === "terminal.reconnected") {
        connectedRef.current = true;
        setStatusMessage(t("terminal.reconnected"));
        fitAddonRef.current?.fit();
        if (term) void terminalBridge.resizeSession(sessionId, term.cols, term.rows);
      }
      if (event.type === "terminal.closed") {
        setStatusMessage(event.reason ?? t("terminal.closed"));
        removeSession(sessionId);
      }
      if (event.type === "terminal.expired") {
        setStatusMessage(event.reason ?? t("terminal.expired"));
        removeSession(sessionId);
      }
      if (event.type === "terminal.exited") {
        const code = event.exitCode;
        const reason = event.reason;
        setStatusMessage(
          reason
            ? t("terminal.exitedWithCodeAndReason", { code: code ?? 0, reason })
            : t("terminal.exitedWithCode", { code: code ?? 0 }),
        );
      }
      if (event.type === "terminal.startFailed") {
        setStatusMessage(t("terminal.startFailedReason", { reason: event.reason ?? t("common.unknown") }));
      }
      if (event.type === "terminal.latency") {
        const rtt = (event as any).rtt;
        if (typeof rtt === "number" && rtt >= 0) {
          setLatency(rtt);
          setStatusMessage(t("terminal.live"));
        }
      }
    });

    const connect = async () => {
      try {
        await terminalBridge.connectSession(sessionId);
        if (!cancelled) {
          setStatusMessage(t("terminal.connected"));
        }
      } catch (error) {
        if (cancelled) return;
        const msg = error instanceof Error ? error.message : String(error);
        setStatusMessage(msg);

        const lowerMsg = msg.toLowerCase();
        if (
          lowerMsg.includes("not found") ||
          lowerMsg.includes("404") ||
          lowerMsg.includes("does not exist") ||
          lowerMsg.includes("no longer")
        ) {
          removeSession(sessionId);
          presentToast({
            message: t("sessions.sessionNotExist"),
            duration: 3000,
            position: "bottom",
            color: "warning",
          });
          history.replace("/sessions");
        }
      }
    };

    setStatusMessage(t("terminal.connecting"));
    void connect();

    return () => {
      cancelled = true;
      connectedRef.current = false;
      unsubscribe();
      void terminalBridge.disconnectSession();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionId]);

  return (
    <IonPage style={{ "--ion-safe-area-top": "0px", "--ion-safe-area-bottom": "0px" } as React.CSSProperties}>
      <IonHeader>
        <IonToolbar style={{ "--min-height": "44px", "--padding-top": "0px", "--padding-bottom": "0px" } as React.CSSProperties}>
          <IonButtons slot="start">
            <IonMenuButton />
          </IonButtons>
          <IonTitle>{session?.title ?? "Session"}</IonTitle>
          <IonBadge
            slot="end"
            color={session?.status === "running" ? "success" : "medium"}
            style={{ marginRight: 8, cursor: "pointer" }}
            onClick={() => {
              const term = xtermRef.current;
              const cols = term?.cols ?? "?";
              const rows = term?.rows ?? "?";
              const lat = latency !== null ? `${Math.round(latency)}ms` : "—";
              void presentActionSheet({
                header: t("terminal.sessionDetails"),
                subHeader: `${t("terminal.status")}: ${statusMessage}`,
                buttons: [
                  { text: `${t("terminal.cols")}: ${cols}`, role: "destructive" as any },
                  { text: `${t("terminal.rows")}: ${rows}`, role: "destructive" as any },
                  { text: `${t("terminal.latency")}: ${lat}`, role: "destructive" as any },
                  { text: "OK", role: "cancel" },
                ],
              });
            }}
          >
            {latency !== null ? `${Math.round(latency)}ms` : statusMessage}
          </IonBadge>
        </IonToolbar>
      </IonHeader>
      <IonContent scrollY={false} style={{ '--background': '#0b0f0e' } as React.CSSProperties}>
          <div
            ref={terminalRef}
            style={{
              height: "100%",
              background: "#0b0f0e",
            }}
          />

          {/* FAB overlay: zero-height container, FAB uses fixed positioning */}
          <div style={{ position: "relative", height: 0 }}>
            <div
              ref={(el) => { fabRef.current = el; keysDrag.bind.setRef(el); }}
              onPointerDown={keysDrag.bind.onPointerDown}
              onPointerMove={keysDrag.bind.onPointerMove}
              onPointerUp={keysDrag.bind.onPointerUp}
              style={{
                ...keysDrag.bind.style,
                position: "fixed",
                bottom: 16,
                right: 16,
                zIndex: 100,
                touchAction: "none",
                pointerEvents: "auto",
              }}
            >
          <div style={{ position: "relative" }}>
            <IonFabButton onMouseDown={(e) => e.preventDefault()} onClick={() => {
              if (keysDrag.wasDragged()) return;
              setKeysExpanded((e) => !e);
            }}>
              <IonIcon icon={keypadOutline} />
            </IonFabButton>
            {(ctrlActive || altActive) && (
              <div style={{
                position: "absolute", top: 2, right: 2,
                width: 12, height: 12, borderRadius: "50%",
                background: ctrlActive && altActive ? "#ffaa00" : "#00ff88",
                border: "2px solid #0b0f0e",
                zIndex: 1,
                pointerEvents: "none",
              }} />
            )}
          </div>
          {keysExpanded && (
            <>
              <div style={{
                position: "absolute",
                ...(fabQuadrant.isRight
                  ? { right: 56, top: 0 }
                  : { left: 56, top: 0 }),
                display: "flex",
                flexDirection: fabQuadrant.isRight ? "row-reverse" : "row",
                gap: 8,
              }}>
                <IonFabButton onMouseDown={(e) => e.preventDefault()} onPointerDown={(e) => e.stopPropagation()} onClick={() => handleKey("\x1b")}>
                  <span style={{ fontSize: 11, fontWeight: 600 }}>Esc</span>
                </IonFabButton>
                <IonFabButton onMouseDown={(e) => e.preventDefault()} onPointerDown={(e) => e.stopPropagation()} onClick={() => handleKey("\t")}>
                  <span style={{ fontSize: 11, fontWeight: 600 }}>Tab</span>
                </IonFabButton>
                <IonFabButton
                  style={ctrlActive ? { "--background": "#00ff88", "--color": "#000" } as React.CSSProperties : undefined}
                  onMouseDown={(e) => e.preventDefault()}
                  onPointerDown={(e) => e.stopPropagation()}
                  onClick={() => setCtrlActive((v) => !v)}
                >
                  <span style={{ fontSize: 11, fontWeight: 600 }}>Ctrl</span>
                </IonFabButton>
                <IonFabButton
                  style={altActive ? { "--background": "#00ff88", "--color": "#000" } as React.CSSProperties : undefined}
                  onMouseDown={(e) => e.preventDefault()}
                  onPointerDown={(e) => e.stopPropagation()}
                  onClick={() => setAltActive((v) => !v)}
                >
                  <span style={{ fontSize: 11, fontWeight: 600 }}>Alt</span>
                </IonFabButton>
              </div>
              <div style={{
                position: "absolute",
                left: 0,
                ...(fabQuadrant.isBottom
                  ? { bottom: 56 }
                  : { top: 56 }),
                display: "flex",
                flexDirection: fabQuadrant.isBottom ? "column-reverse" : "column",
                gap: 8,
              }}>
                <IonFabButton onMouseDown={(e) => e.preventDefault()} onPointerDown={(e) => e.stopPropagation()} onClick={() => handleKey("\x1b[D")}>
                  <IonIcon icon={arrowBackOutline} />
                </IonFabButton>
                <IonFabButton onMouseDown={(e) => e.preventDefault()} onPointerDown={(e) => e.stopPropagation()} onClick={() => handleKey("\x1b[A")}>
                  <IonIcon icon={arrowUpOutline} />
                </IonFabButton>
                <IonFabButton onMouseDown={(e) => e.preventDefault()} onPointerDown={(e) => e.stopPropagation()} onClick={() => handleKey("\x1b[B")}>
                  <IonIcon icon={arrowDownOutline} />
                </IonFabButton>
                <IonFabButton onMouseDown={(e) => e.preventDefault()} onPointerDown={(e) => e.stopPropagation()} onClick={() => handleKey("\x1b[C")}>
                  <IonIcon icon={arrowForwardOutline} />
                </IonFabButton>
              </div>
            </>
          )}
            </div>
            </div>
      </IonContent>
    </IonPage>
  );
}
