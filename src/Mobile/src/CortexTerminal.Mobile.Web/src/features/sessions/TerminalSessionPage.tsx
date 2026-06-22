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
  useIonLoading,
  useIonToast,
} from "@ionic/react";
import {
  arrowUpOutline,
  arrowDownOutline,
  arrowBackOutline,
  arrowForwardOutline,
  clipboardOutline,
  copyOutline,
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
const RESIZE_DEBOUNCE_MS = 150;

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
  if (!text.includes("\n")) return bytes;
  const normalized = text.replace(/(?<!\r)\n/g, "\r\n");
  return new TextEncoder().encode(normalized);
}

function fitTerminal(term: Terminal, fitAddon: FitAddon): void {
  fitAddon.fit();
}

// ── Keyboard toolbar button ──
function ToolbarButton({
  label,
  icon,
  active,
  disabled,
  onClick,
}: {
  label?: string;
  icon?: string;
  active?: boolean;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onMouseDown={(e) => e.preventDefault()}
      onClick={() => {
        if (disabled) return;
        onClick();
        void nativeBridge.haptics("click");
      }}
      disabled={disabled}
      style={{
        minWidth: 40,
        height: 34,
        border: "none",
        borderRadius: 6,
        background: active
          ? "#00ff88"
          : disabled
            ? "rgba(215, 255, 229, 0.05)"
            : "rgba(215, 255, 229, 0.12)",
        color: active
          ? "#000"
          : disabled
            ? "rgba(215, 255, 229, 0.25)"
            : "#d7ffe5",
        fontSize: 13,
        fontWeight: 600,
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        padding: "0 8px",
        cursor: disabled ? "not-allowed" : "pointer",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
        touchAction: "manipulation",
        WebkitTapHighlightColor: "transparent",
        opacity: disabled ? 0.4 : 1,
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
  const [presentLoading, dismissLoading] = useIonLoading();
  const loadingRef = useRef(false);

  // ── Platform detection ──
  const platformLabel = useAppStore((s) => s.platformLabel);


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
  const resizeSyncTimeoutRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const connectedRef = useRef(false);
  const containerHeightRef = useRef<number>(0);
  const cellHeightRef = useRef<number>(0);

  const [ctrlActive, setCtrlActive] = useState(false);
  const [altActive, setAltActive] = useState(false);
  const [hasClipboard, setHasClipboard] = useState(false);
  const [hasSelection, setHasSelection] = useState(false);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleKeyRef = useRef<any>(null);
  const recentInputRef = useRef<{ data: string; time: number }>({ data: "", time: 0 });
  // Tracks the last observed value of xterm's helper textarea so we can compute
  // how many chars an iOS dictation deleteContentBackward actually removed.
  const lastTextareaValueRef = useRef<string>("");

  const {
    keyboardVisible: vvKeyboardVisible,
    keyboardHeight: vvKeyboardHeight,
    toolbarHeight,
  } = useKeyboardToolbar();
  const keyboardVisible = vvKeyboardVisible;
  const keyboardHeight = vvKeyboardHeight;

  // ── Touch scroll for iOS (xterm.js doesn't handle touch natively) ──
  useTouchScroll({ terminalRef, xtermRef, enabled: true });

  // Reset modifiers when keyboard dismisses
  useEffect(() => {
    if (!keyboardVisible) {
      setCtrlActive(false);
      setAltActive(false);
    }
  }, [keyboardVisible]);

  // Check clipboard content when keyboard becomes visible (via native bridge)
  useEffect(() => {
    if (!keyboardVisible) return;
    terminalBridge
      .hasClipboardText()
      .then((result) => setHasClipboard(result.hasText))
      .catch(() => setHasClipboard(false));
  }, [keyboardVisible]);

  // Clean up legacy FAB position from localStorage
  useEffect(() => {
    try {
      localStorage.removeItem("fab-pos");
    } catch {
      /* ignore */
    }
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

  const handlePaste = useCallback(() => {
    terminalBridge
      .readClipboardText()
      .then((result) => {
        const text = result.text;
        if (text) {
          sendInput(text);
        }
        setHasClipboard(!!text);
      })
      .catch(() => setHasClipboard(false));
  }, [sendInput]);

  const handleCopy = useCallback(() => {
    const term = xtermRef.current;
    if (!term?.hasSelection()) return;
    const text = term.getSelection();
    terminalBridge
      .writeClipboardText(text)
      .then(() => {
        term.clearSelection();
        setHasSelection(false);
        void nativeBridge.haptics("click");
        void presentToast({
          message: t("terminal.copied"),
          duration: 1500,
          position: "bottom",
          color: "success",
        });
      })
      .catch(() => {});
  }, [presentToast, t]);

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
      scrollback: 64000,
      convertEol: false,
    });

    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    xtermRef.current = term;
    fitAddonRef.current = fitAddon;

    // iOS dictation & 9-grid pinyin numeric candidates both send input(insertText, composed=true)
    // which xterm's _inputEvent gate (composed && _keyDownSeen) refuses. Capture them here and
    // forward. Dictation's per-char insertText / deleteContentBackward / final whole-string is
    // streamed as-is — the PTY line editor (readline) handles backspace undo itself. No JS-side
    // buffering, no latency. deleteContentBackward doesn't say how many chars it removed, so we
    // compute it from the textarea value delta in a separate input listener below.
    // See xterm.js issues #5835 / #5887 (still open in 6.x).
    const onBeforeInput = (ev: Event) => {
      const ie = ev as InputEvent;
      if (ie.inputType !== "insertText") return;
      if (!ie.composed) return;
      if (typeof ie.data !== "string" || ie.data.length === 0) return;
      const now = Date.now();
      const recent = recentInputRef.current;
      if (now - recent.time < 50 && recent.data === ie.data) return;
      recentInputRef.current = { data: ie.data, time: now };
      handleKeyRef.current?.(ie.data);
    };
    terminalRef.current.addEventListener("beforeinput", onBeforeInput, true);

    term.open(terminalRef.current);

    // deleteContentBackward-as-backspace forwarding is iOS-only: Android's physical keyboard
    // emits \x7f via xterm's keydown path, so listening to `input` here would double-send.
    const imeTextarea =
      platformLabel === "ios"
        ? terminalRef.current?.querySelector<HTMLTextAreaElement>(".xterm-helper-textarea")
        : null;
    if (imeTextarea) lastTextareaValueRef.current = imeTextarea.value;
    const onTextareaInput = (ev: Event) => {
      const ie = ev as InputEvent;
      const textarea = ev.target as HTMLTextAreaElement;
      const currentValue = textarea.value;
      if (ie.inputType === "deleteContentBackward") {
        const deleted = lastTextareaValueRef.current.length - currentValue.length;
        if (deleted > 0) {
          handleKeyRef.current?.("\x7f".repeat(deleted));
        }
      }
      lastTextareaValueRef.current = currentValue;
    };
    imeTextarea?.addEventListener("input", onTextareaInput, true);

    // xterm.js creates a hidden textarea (.xterm-helper-textarea) for keyboard input.
    // Set autocomplete="off" to suppress iOS keyboard autocomplete suggestions.
    const textareaObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (
            node instanceof HTMLElement &&
            node.classList.contains("xterm-helper-textarea")
          ) {
            node.setAttribute("autocomplete", "off");
            node.setAttribute("autocorrect", "off");
            node.setAttribute("autocapitalize", "off");
            node.setAttribute("spellcheck", "false");
          }
        }
      }
    });
    textareaObserver.observe(terminalRef.current, {
      childList: true,
      subtree: true,
    });

    try {
      term.loadAddon(new WebglAddon());
    } catch {
      // Falls back to canvas renderer
    }

    // Double RAF: let CSS height:100% layout settle before first fit
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        fitAddon.fit();
        if (terminalRef.current) {
          containerHeightRef.current = terminalRef.current.clientHeight;
          cellHeightRef.current = terminalRef.current.clientHeight / term.rows;
        }
      });
    });

    const inputDataDisposable = term.onData((data) => {
      const now = Date.now();
      const recent = recentInputRef.current;
      if (now - recent.time < 50 && recent.data === data) return;
      recentInputRef.current = { data, time: now };
      handleKeyRef.current?.(data);
    });

    const selectionDisposable = term.onSelectionChange(() => {
      setHasSelection(term.hasSelection());
    });

    let lastCols = term.cols;
    let lastRows = term.rows;
    const resizeDisposable = term.onResize(({ cols, rows }) => {
      if (cols !== lastCols || rows !== lastRows) {
        lastCols = cols;
        lastRows = rows;
        if (connectedRef.current) {
          if (resizeSyncTimeoutRef.current) {
            clearTimeout(resizeSyncTimeoutRef.current);
          }
          resizeSyncTimeoutRef.current = setTimeout(() => {
            resizeSyncTimeoutRef.current = undefined;
            void terminalBridge.resizeSession(sessionId, cols, rows);
          }, RESIZE_DEBOUNCE_MS);
        }
      }
    });

    const observer = new ResizeObserver(() => {
      if (resizeTimeoutRef.current) clearTimeout(resizeTimeoutRef.current);
      resizeTimeoutRef.current = setTimeout(() => {
        try {
          const el = terminalRef.current;
          if (el) {
            containerHeightRef.current = el.clientHeight;
            if (term.rows > 0) {
              cellHeightRef.current = el.clientHeight / term.rows;
            }
          }
          fitTerminal(term, fitAddon);
        } catch {
          /* component may be unmounted */
        }
      }, RESIZE_DEBOUNCE_MS);
    });
    observer.observe(terminalRef.current);

    return () => {
      observer.disconnect();
      textareaObserver.disconnect();
      terminalRef.current?.removeEventListener("beforeinput", onBeforeInput, true);
      imeTextarea?.removeEventListener("input", onTextareaInput, true);
      inputDataDisposable.dispose();
      selectionDisposable.dispose();
      resizeDisposable.dispose();
      if (resizeTimeoutRef.current) clearTimeout(resizeTimeoutRef.current);
      if (resizeSyncTimeoutRef.current)
        clearTimeout(resizeSyncTimeoutRef.current);
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
        (event.type === "terminal.replay" ||
          event.type === "terminal.output") &&
        event.base64 &&
        term
      ) {
        try {
          term.write(
            normalizeTerminalOutput(decodeBase64ToBytes(event.base64)),
            () => {},
          );
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
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }
        fitAddonRef.current?.fit();
        if (term)
          void terminalBridge.resizeSession(sessionId, term.cols, term.rows);
      }
      if (event.type === "terminal.reattached") {
        term?.reset();
        setStatusMessage(t("terminal.reattached"));
      }
      if (event.type === "terminal.replayCompleted") {
        term?.reset();
        setStatusMessage(t("terminal.live"));
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }
        fitAddonRef.current?.fit();
        if (term)
          void terminalBridge.resizeSession(sessionId, term.cols, term.rows);
      }
      if (event.type === "terminal.reconnecting") {
        connectedRef.current = false;
        setStatusMessage(t("terminal.reconnecting"));
        if (!loadingRef.current) {
          loadingRef.current = true;
          presentLoading({ message: t("terminal.reconnecting"), duration: 0 });
        }
      }
      if (event.type === "terminal.reconnected") {
        connectedRef.current = true;
        setStatusMessage(t("terminal.reconnected"));
        fitAddonRef.current?.fit();
        if (term)
          void terminalBridge.resizeSession(sessionId, term.cols, term.rows);
      }
      if (event.type === "terminal.closed") {
        connectedRef.current = false;
        const reason = event.reason ?? t("terminal.closed");
        setStatusMessage(reason);
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }
        removeSession(sessionId);
        presentToast({
          message: t("terminal.sessionClosedToast", { reason }),
          duration: 3000,
          position: "bottom",
          color: "warning",
        });
        history.replace("/sessions");
      }
      if (event.type === "terminal.expired") {
        connectedRef.current = false;
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }
        const reason = event.reason ?? t("terminal.expired");
        setStatusMessage(reason);
        removeSession(sessionId);
        presentToast({
          message: t("terminal.sessionExpiredToast", { reason }),
          duration: 3000,
          position: "bottom",
          color: "warning",
        });
        history.replace("/sessions");
      }
      if (event.type === "terminal.exited") {
        connectedRef.current = false;
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }
        const code = event.exitCode;
        const reason = event.reason;
        const statusMsg = reason
          ? t("terminal.exitedWithCodeAndReason", { code: code ?? 0, reason })
          : t("terminal.exitedWithCode", { code: code ?? 0 });
        setStatusMessage(statusMsg);
        presentToast({
          message: t("terminal.sessionExitedToast", { code: code ?? 0 }),
          duration: 3000,
          position: "bottom",
          color: "medium",
        });
        setTimeout(() => {
          if (!cancelled) history.replace("/sessions");
        }, 2000);
      }
      if (event.type === "terminal.startFailed") {
        connectedRef.current = false;
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }
        setStatusMessage(
          t("terminal.startFailedReason", {
            reason: event.reason ?? t("common.unknown"),
          }),
        );
        presentToast({
          message: t("terminal.sessionStartFailedToast"),
          duration: 3000,
          position: "bottom",
          color: "danger",
        });
        history.replace("/sessions");
      }
      if (event.type === "terminal.displaced") {
        connectedRef.current = false;
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }
        setStatusMessage(t("terminal.displaced"));
        presentToast({
          message: t("terminal.sessionDisplacedToast"),
          duration: 3000,
          position: "bottom",
          color: "warning",
        });
        setTimeout(() => {
          if (!cancelled) history.replace("/sessions");
        }, 1500);
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
        if (loadingRef.current) {
          loadingRef.current = false;
          dismissLoading();
        }

        const lowerMsg = msg.toLowerCase();
        if (lowerMsg.includes("session-expired")) {
          presentToast({
            message: t("terminal.sessionExpiredToast", { reason: msg }),
            duration: 3000,
            position: "bottom",
            color: "warning",
          });
          history.replace("/sessions");
        } else if (
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
        } else {
          removeSession(sessionId);
          presentToast({
            message: t("terminal.sessionClosedToast", { reason: msg }),
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
      if (loadingRef.current) {
        loadingRef.current = false;
        dismissLoading();
      }
      unsubscribe();
      void terminalBridge.disconnectSession();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionId]);

  return (
    <IonPage
      style={
        {
          "--ion-safe-area-top": "0px",
          "--ion-safe-area-bottom": "0px",
        } as React.CSSProperties
      }
    >
      <IonHeader>
        <IonToolbar
          style={
            {
              "--min-height": "44px",
              "--padding-top": "0px",
              "--padding-bottom": "0px",
            } as React.CSSProperties
          }
        >
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
                  {
                    text: `${t("terminal.cols")}: ${cols}`,
                    role: "destructive" as any,
                  },
                  {
                    text: `${t("terminal.rows")}: ${rows}`,
                    role: "destructive" as any,
                  },
                  {
                    text: `${t("terminal.latency")}: ${lat}`,
                    role: "destructive" as any,
                  },
                  { text: t("common.ok"), role: "cancel" },
                ],
              });
            }}
          >
            {latency !== null ? `${Math.round(latency)}ms` : statusMessage}
          </IonBadge>
        </IonToolbar>
      </IonHeader>
      <IonContent
        scrollY={false}
        style={{ "--background": "#0b0f0e" } as React.CSSProperties}
      >
        <div
          style={{ position: "relative", height: "100%", overflow: "hidden" }}
        >
          <div
            ref={terminalRef}
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              right: 0,
              height: keyboardVisible
                ? `calc(100% - ${toolbarHeight}px)`
                : "100%",
              background: "#0b0f0e",
              touchAction: "none",
            }}
          />

          {/* Keyboard toolbar: positioned inside the relative container */}
          {keyboardVisible && (
          <div
            className="terminal-toolbar"
            style={{
              position: "absolute",
              bottom: 0,
              left: 0,
              right: 0,
              height: toolbarHeight,
              zIndex: 100,
              display: "flex",
              alignItems: "center",
              background: "rgba(11, 15, 14, 0.95)",
              borderTop: "1px solid rgba(215, 255, 229, 0.15)",
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
              <ToolbarButton
                label="S-Tab"
                onClick={() => handleKey("\x1b[Z")}
              />
              <ToolbarButton
                label="Ctrl"
                active={ctrlActive}
                onClick={() => setCtrlActive((v) => !v)}
              />
              <ToolbarButton
                label="Alt"
                active={altActive}
                onClick={() => setAltActive((v) => !v)}
              />
              <ToolbarButton
                icon={arrowBackOutline}
                onClick={() => handleKey("\x1b[D")}
              />
              <ToolbarButton
                icon={arrowUpOutline}
                onClick={() => handleKey("\x1b[A")}
              />
              <ToolbarButton
                icon={arrowDownOutline}
                onClick={() => handleKey("\x1b[B")}
              />
              <ToolbarButton
                icon={arrowForwardOutline}
                onClick={() => handleKey("\x1b[C")}
              />
              <ToolbarButton
                icon={clipboardOutline}
                label={t("terminal.paste")}
                disabled={!hasClipboard}
                onClick={handlePaste}
              />
              {/* <ToolbarButton icon={copyOutline} label={t("terminal.copy")} disabled={!hasSelection} onClick={handleCopy} /> */}
            </div>
            <ToolbarButton
              label={t("terminal.done")}
              onClick={() => {
                const textarea = terminalRef.current?.querySelector(
                  ".xterm-helper-textarea",
                ) as HTMLElement | null;
                textarea?.blur();
              }}
            />
          </div>
          )}
        </div>
      </IonContent>
    </IonPage>
  );
}
