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
}

const PIXELS_PER_LINE = 17;
const FRICTION = 0.95;
const MIN_VELOCITY = 0.5;

export function useTouchScroll({ terminalRef, xtermRef, enabled }: Options) {
  const stateRef = useRef<TouchScrollState | null>(null);

  useEffect(() => {
    if (!enabled) return;
    const el = terminalRef.current;
    if (!el) return;

    const onTouchStart = (e: TouchEvent) => {
      if (e.touches.length !== 1) return;
      if (stateRef.current?.rafId) {
        cancelAnimationFrame(stateRef.current.rafId);
      }
      stateRef.current = {
        accumulated: 0,
        lastY: e.touches[0].clientY,
        lastTime: Date.now(),
        rafId: 0,
        velocity: 0,
      };
    };

    const onTouchMove = (e: TouchEvent) => {
      if (!stateRef.current || e.touches.length !== 1) return;
      e.preventDefault();

      const s = stateRef.current;
      const currentY = e.touches[0].clientY;
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
