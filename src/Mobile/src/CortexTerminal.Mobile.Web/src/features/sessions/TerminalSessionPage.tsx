import {
  IonBadge,
  IonButtons,
  IonContent,
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
} from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import "@xterm/xterm/css/xterm.css";
import { useSessionStore, type SessionState } from "../../store/sessionStore";
import { useAppStore } from "../../store/appStore";
import { terminalBridge } from "../../bridge/modules/terminalBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import { transport } from "../../bridge/runtime";
import { useKeyboardToolbar } from "./useKeyboardToolbar";
import { useTouchScroll } from "./useTouchScroll";

const selectRemoveSession = (s: SessionState) => s.removeSession;
const selectRecentSessions = (s: SessionState) => s.recentSessions;

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

/**
 * Smooth resize: skip _renderService.clear(), call terminal.resize() directly.
 * When only rows/cols change (keyboard show/hide), the render buffer doesn't need
 * clearing — xterm reflows in-place instead of redrawing top-to-bottom.
 */
function smoothFit(term: Terminal, fitAddon: FitAddon): void {
  const dims = fitAddon.proposeDimensions();
  if (!dims) return;
  if (term.cols === dims.cols && term.rows === dims.rows) return;
  term.resize(dims.cols, dims.rows);
}

// ── Keyboard toolbar button ──
function ToolbarButton({ label, icon, active, onClick }: {
  label?: string;
  icon?: string;
  active?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onMouseDown={(e) => e.preventDefault()}
      onClick={() => {
        onClick();
        void nativeBridge.haptics("click");
      }}
      style={{
        minWidth: 40,
        height: 34,
        border: "none",
        borderRadius: 6,
        background: active ? "#00ff88" : "rgba(215, 255, 229, 0.12)",
        color: active ? "#000" : "#d7ffe5",
        fontSize: 13,
        fontWeight: 600,
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        padding: "0 8px",
        cursor: "pointer",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
        touchAction: "manipulation",
        WebkitTapHighlightColor: "transparent",
      }}
    >
      {label ?? <IonIcon icon={icon!} style={{ fontSize: 18 }} />}
    </button>
  );
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

  // ── Platform detection ──
  const platformLabel = useAppStore((s) => s.platformLabel);
  const isIOS = platformLabel === "ios" || platformLabel === "maccatalyst";

  // ── Native keyboard state (iOS: from native layer, others: from visualViewport) ──
  const [nativeKeyboardVisible, setNativeKeyboardVisible] = useState(false);
  const [nativeKeyboardHeight, setNativeKeyboardHeight] = useState(0);

  const recentSessions = useSessionStore(selectRecentSessions);
  const session = useMemo(
    () => recentSessions.find((item) => item.id === sessionId),
    [recentSessions, sessionId],
  );
  const removeSession = useSessionStore(selectRemoveSession);
  const [presentToast] = useIonToast();

  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const resizeTimeoutRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const connectedRef = useRef(false);
  const keyboardTransitionRef = useRef(false);
  const keyboardTransitionTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  const [ctrlActive, setCtrlActive] = useState(false);
  const [altActive, setAltActive] = useState(false);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleKeyRef = useRef<any>(null);

  const { keyboardVisible: vvKeyboardVisible, keyboardHeight: vvKeyboardHeight, toolbarHeight } = useKeyboardToolbar();
  const keyboardVisible = isIOS ? nativeKeyboardVisible : vvKeyboardVisible;
  const keyboardHeight = isIOS ? nativeKeyboardHeight : vvKeyboardHeight;

  // ── Touch scroll for iOS (xterm.js doesn't handle touch natively) ──
  useTouchScroll({ terminalRef, xtermRef, enabled: isIOS });

  // Reset modifiers when keyboard dismisses
  useEffect(() => {
    if (!keyboardVisible) {
      setCtrlActive(false);
      setAltActive(false);
    }
  }, [keyboardVisible]);

  // Clean up legacy FAB position from localStorage
  useEffect(() => {
    try { localStorage.removeItem("fab-pos"); } catch { /* ignore */ }
  }, []);

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

    // xterm.js creates a hidden textarea (.xterm-helper-textarea) for keyboard input.
    // Set autocomplete="off" to suppress iOS keyboard autocomplete suggestions.
    const textareaObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node instanceof HTMLElement && node.classList.contains("xterm-helper-textarea")) {
            node.setAttribute("autocomplete", "off");
          }
        }
      }
    });
    textareaObserver.observe(terminalRef.current, { childList: true, subtree: true });

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
      if (keyboardTransitionRef.current) return;
      resizeTimeoutRef.current = setTimeout(() => {
        try {
          smoothFit(term, fitAddon);
        } catch {
          /* component may be unmounted */
        }
      }, 100);
    });
    observer.observe(terminalRef.current);

    return () => {
      observer.disconnect();
      textareaObserver.disconnect();
      inputDataDisposable.dispose();
      resizeDisposable.dispose();
      if (resizeTimeoutRef.current) clearTimeout(resizeTimeoutRef.current);
      if (keyboardTransitionTimerRef.current) clearTimeout(keyboardTransitionTimerRef.current);
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

      // ── Native keyboard state (iOS) ──
      if (event.type === "nativeKeyboard") {
        const knEvent = event as any;
        setNativeKeyboardVisible(knEvent.visible === true);
        setNativeKeyboardHeight(typeof knEvent.height === "number" ? knEvent.height : 0);

        // iOS keyboard transition: suppress ResizeObserver-triggered fit() and
        // perform a single smoothFit after the native animation + React re-render settle.
        keyboardTransitionRef.current = true;
        if (keyboardTransitionTimerRef.current) clearTimeout(keyboardTransitionTimerRef.current);
        keyboardTransitionTimerRef.current = setTimeout(() => {
          keyboardTransitionRef.current = false;
          const t = xtermRef.current;
          const fa = fitAddonRef.current;
          if (t && fa) {
            try { smoothFit(t, fa); } catch {}
          }
        }, 400);
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
          <IonTitle>{session?.title ?? t("terminal.session")}</IonTitle>
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
                  { text: t("common.ok"), role: "cancel" },
                ],
              });
            }}
          >
            {latency !== null ? `${Math.round(latency)}ms` : statusMessage}
          </IonBadge>
        </IonToolbar>
      </IonHeader>
      <IonContent scrollY={false} style={{ '--background': '#0b0f0e' } as React.CSSProperties}>
          <div style={{ position: "relative", height: "100%" }}>
            <div
              ref={terminalRef}
              style={{
                height: "100%",
                background: "#0b0f0e",
                paddingBottom: keyboardVisible ? toolbarHeight : 0,
                boxSizing: "border-box",
                touchAction: "none",
              }}
            />
          </div>

          {/* Keyboard toolbar: appears above the soft keyboard */}
          {keyboardVisible && (
            <div
              className="terminal-toolbar"
              style={{
                position: "fixed",
                bottom: 0,
                left: 0,
                right: 0,
                height: toolbarHeight,
                zIndex: 100,
                display: "flex",
                alignItems: "center",
                background: "rgba(11, 15, 14, 0.95)",
                borderTop: "1px solid rgba(215, 255, 229, 0.15)",
                transform: `translateY(-${isIOS ? 0 : keyboardHeight}px)`,
                willChange: "transform",
                transition: "transform 0.25s cubic-bezier(0.25, 1, 0.5, 1)",
                touchAction: "manipulation",
                userSelect: "none",
                WebkitUserSelect: "none",
              }}
            >
              <div
                style={{
                  flex: 1,
                  display: "flex",
                  alignItems: "center",
                  padding: "0 6px",
                  gap: 4,
                  overflowX: "auto",
                  overflowY: "hidden",
                  WebkitOverflowScrolling: "touch",
                  scrollbarWidth: "none",
                }}
              >
                <ToolbarButton label="Esc" onClick={() => handleKey("\x1b")} />
                <ToolbarButton label="Tab" onClick={() => handleKey("\t")} />
                <ToolbarButton label="S-Tab" onClick={() => handleKey("\x1b[Z")} />
                <ToolbarButton label="Ctrl" active={ctrlActive} onClick={() => setCtrlActive((v) => !v)} />
                <ToolbarButton label="Alt" active={altActive} onClick={() => setAltActive((v) => !v)} />
                <ToolbarButton icon={arrowBackOutline} onClick={() => handleKey("\x1b[D")} />
                <ToolbarButton icon={arrowUpOutline} onClick={() => handleKey("\x1b[A")} />
                <ToolbarButton icon={arrowDownOutline} onClick={() => handleKey("\x1b[B")} />
                <ToolbarButton icon={arrowForwardOutline} onClick={() => handleKey("\x1b[C")} />
              </div>
              <ToolbarButton
                label={t("terminal.done")}
                onClick={() => {
                  const textarea = terminalRef.current?.querySelector(".xterm-helper-textarea") as HTMLElement | null;
                  textarea?.blur();
                }}
              />
            </div>
          )}
      </IonContent>
    </IonPage>
  );
}
