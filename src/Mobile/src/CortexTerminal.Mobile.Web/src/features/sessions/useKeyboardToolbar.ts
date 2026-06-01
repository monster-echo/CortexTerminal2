import { useCallback, useEffect, useRef, useState } from "react";

interface KeyboardToolbarState {
  /** Whether the soft keyboard is currently visible */
  keyboardVisible: boolean;
  /** Height of the occluded area (keyboard) in pixels */
  keyboardHeight: number;
  /** Fixed toolbar height in pixels */
  toolbarHeight: number;
}

/**
 * Detects soft keyboard visibility via two methods:
 *
 * 1. Visual Viewport API (iOS WKWebView): window.innerHeight stays fixed,
 *    visualViewport.height shrinks when the keyboard appears.
 *
 * 2. window.innerHeight diff (Android AdjustResize): The system resizes the
 *    WebView content area, so innerHeight shrinks. We compare against a
 *    stored baseline to detect the change.
 */
export function useKeyboardToolbar(): KeyboardToolbarState {
  const [keyboardVisible, setKeyboardVisible] = useState(false);
  const [keyboardHeight, setKeyboardHeight] = useState(0);
  const toolbarHeight = 44;

  const rafRef = useRef<number>(0);
  const initialHeightRef = useRef<number>(0);

  const update = useCallback(() => {
    cancelAnimationFrame(rafRef.current);
    rafRef.current = requestAnimationFrame(() => {
      const currentHeight = window.innerHeight;

      // Keep baseline at the largest observed height
      if (initialHeightRef.current === 0 || currentHeight > initialHeightRef.current) {
        initialHeightRef.current = currentHeight;
      }

      let isKeyboard = false;
      let height = 0;

      // Method 1: Visual Viewport API (iOS)
      const vv = window.visualViewport;
      if (vv) {
        const fullHeight = window.innerHeight;
        const visibleHeight = vv.height + vv.offsetTop;
        const occludedHeight = fullHeight - visibleHeight;
        if (occludedHeight > 100) {
          isKeyboard = true;
          height = occludedHeight;
        }
      }

      // Method 2: innerHeight diff detection (Android AdjustResize)
      if (!isKeyboard && initialHeightRef.current > 0) {
        const diff = initialHeightRef.current - currentHeight;
        if (diff > 100) {
          isKeyboard = true;
          height = diff;
        }
      }

      // Update baseline when keyboard dismisses and height grows
      if (!isKeyboard && currentHeight >= initialHeightRef.current) {
        initialHeightRef.current = currentHeight;
      }

      setKeyboardVisible(isKeyboard);
      setKeyboardHeight(isKeyboard ? height : 0);
    });
  }, []);

  useEffect(() => {
    initialHeightRef.current = window.innerHeight;

    update();

    const vv = window.visualViewport;
    if (vv) {
      vv.addEventListener("resize", update);
      vv.addEventListener("scroll", update);
    }

    // Window resize fires on Android when AdjustResize kicks in
    window.addEventListener("resize", update);

    return () => {
      if (vv) {
        vv.removeEventListener("resize", update);
        vv.removeEventListener("scroll", update);
      }
      window.removeEventListener("resize", update);
      cancelAnimationFrame(rafRef.current);
    };
  }, [update]);

  return { keyboardVisible, keyboardHeight, toolbarHeight };
}
