import { useEffect, useRef } from "react";
import type { Terminal } from "@xterm/xterm";

interface Options {
  terminalRef: React.RefObject<HTMLDivElement | null>;
  xtermRef: React.MutableRefObject<Terminal | null>;
  enabled: boolean;
}

interface TouchScrollState {
  accumulated: number;
  lastY: number;
  lastTime: number;
  rafId: number;
  velocity: number;
  startY: number;
  longPressTimer: ReturnType<typeof setTimeout> | null;
  selecting: boolean;
}

const PIXELS_PER_LINE = 17;
const FRICTION = 0.95;
const MIN_VELOCITY = 0.5;
const LONG_PRESS_MS = 500;
const MOVE_THRESHOLD = 10;

export function useTouchScroll({ terminalRef, xtermRef, enabled }: Options) {
  const stateRef = useRef<TouchScrollState | null>(null);

  useEffect(() => {
    if (!enabled) return;
    const el = terminalRef.current;
    if (!el) return;

    const clearLongPress = (s: TouchScrollState) => {
      if (s.longPressTimer) {
        clearTimeout(s.longPressTimer);
        s.longPressTimer = null;
      }
    };

    const onTouchStart = (e: TouchEvent) => {
      if (e.touches.length !== 1) return;
      if (stateRef.current?.rafId) {
        cancelAnimationFrame(stateRef.current.rafId);
      }

      const s: TouchScrollState = {
        accumulated: 0,
        lastY: e.touches[0].clientY,
        lastTime: Date.now(),
        rafId: 0,
        velocity: 0,
        startY: e.touches[0].clientY,
        longPressTimer: null,
        selecting: false,
      };

      s.longPressTimer = setTimeout(() => {
        s.selecting = true;
        // Trigger haptic via the xterm helper textarea click
        const textarea = el.querySelector(".xterm-helper-textarea") as HTMLElement | null;
        textarea?.focus();
        // Dispatch a synthetic touch event pair to let xterm start selection
        // We simulate a touchstart at the current position for xterm to pick up
        const touch = e.touches[0];
        const target = document.elementFromPoint(touch.clientX, touch.clientY);
        if (target) {
          const syntheticTouch = new Touch({
            identifier: touch.identifier,
            target: target,
            clientX: touch.clientX,
            clientY: touch.clientY,
            pageX: touch.pageX,
            pageY: touch.pageY,
            screenX: touch.screenX,
            screenY: touch.screenY,
          });
          const startEvent = new TouchEvent("touchstart", {
            touches: [syntheticTouch],
            targetTouches: [syntheticTouch],
            bubbles: true,
            cancelable: true,
          });
          target.dispatchEvent(startEvent);
        }
      }, LONG_PRESS_MS);

      stateRef.current = s;
    };

    const onTouchMove = (e: TouchEvent) => {
      if (!stateRef.current || e.touches.length !== 1) return;
      const s = stateRef.current;

      const currentY = e.touches[0].clientY;
      const dx = Math.abs(currentY - s.startY);

      // If moved beyond threshold, cancel long press and enter scroll mode
      if (!s.selecting && dx > MOVE_THRESHOLD) {
        clearLongPress(s);
      }

      // In selection mode, let xterm handle the touch event
      if (s.selecting) {
        return;
      }

      e.preventDefault();

      const deltaY = s.lastY - currentY;
      const now = Date.now();
      const dt = now - s.lastTime;

      if (dt > 0) {
        s.velocity = deltaY / dt;
      }

      s.lastY = currentY;
      s.lastTime = now;
      s.accumulated += deltaY;

      const lines = Math.trunc(s.accumulated / PIXELS_PER_LINE);
      if (lines !== 0 && xtermRef.current) {
        xtermRef.current.scrollLines(lines);
        s.accumulated -= lines * PIXELS_PER_LINE;
      }
    };

    const onTouchEnd = () => {
      if (!stateRef.current) return;
      const s = stateRef.current;
      clearLongPress(s);

      // If in selection mode, just reset — xterm handles the rest
      if (s.selecting) {
        stateRef.current = null;
        return;
      }

      if (Math.abs(s.velocity) > MIN_VELOCITY) {
        const inertiaScroll = () => {
          if (!xtermRef.current || !stateRef.current) return;
          const st = stateRef.current;

          st.velocity *= FRICTION;
          if (Math.abs(st.velocity) < MIN_VELOCITY * 0.1) {
            stateRef.current = null;
            return;
          }

          const delta = st.velocity * 16;
          st.accumulated += delta;

          const lines = Math.trunc(st.accumulated / PIXELS_PER_LINE);
          if (lines !== 0) {
            xtermRef.current.scrollLines(lines);
            st.accumulated -= lines * PIXELS_PER_LINE;
          }

          st.rafId = requestAnimationFrame(inertiaScroll);
        };
        s.rafId = requestAnimationFrame(inertiaScroll);
      } else {
        stateRef.current = null;
      }
    };

    el.addEventListener("touchstart", onTouchStart, { passive: true });
    el.addEventListener("touchmove", onTouchMove, { passive: false });
    el.addEventListener("touchend", onTouchEnd, { passive: true });

    return () => {
      el.removeEventListener("touchstart", onTouchStart);
      el.removeEventListener("touchmove", onTouchMove);
      el.removeEventListener("touchend", onTouchEnd);
      if (stateRef.current?.rafId) {
        cancelAnimationFrame(stateRef.current.rafId);
      }
    };
  }, [enabled, terminalRef, xtermRef]);
}
