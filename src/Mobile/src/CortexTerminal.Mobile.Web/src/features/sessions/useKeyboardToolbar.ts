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
 * Detects soft keyboard visibility via the Visual Viewport API.
 *
 * On iOS WKWebView: window.innerHeight stays fixed, visualViewport.height
 * shrinks when the keyboard appears. The resize event on visualViewport fires.
 *
 * On Android (AdjustResize): The WebView content area is resized by the system.
 * visualViewport.height reflects the available space above the keyboard.
 */
export function useKeyboardToolbar(): KeyboardToolbarState {
  const [keyboardVisible, setKeyboardVisible] = useState(false);
  const [keyboardHeight, setKeyboardHeight] = useState(0);
  const toolbarHeight = 44;

  // Use refs for the latest state in the resize callback to avoid
  // re-registering the listener on every state change.
  const rafRef = useRef<number>(0);

  const update = useCallback(() => {
    cancelAnimationFrame(rafRef.current);
    rafRef.current = requestAnimationFrame(() => {
      const vv = window.visualViewport;
      if (!vv) return;

      const fullHeight = window.innerHeight;
      const visibleHeight = vv.height + vv.offsetTop;
      const occludedHeight = fullHeight - visibleHeight;

      // Threshold: treat as keyboard-visible if more than 100px is occluded.
      // Avoids false positives from minor viewport adjustments (address bar, etc.)
      const isKeyboard = occludedHeight > 100;

      setKeyboardVisible(isKeyboard);
      setKeyboardHeight(isKeyboard ? occludedHeight : 0);
    });
  }, []);

  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;

    update();

    // visualViewport.resize fires on keyboard show/hide
    vv.addEventListener("resize", update);
    // iOS sometimes fires scroll alongside keyboard changes
    vv.addEventListener("scroll", update);

    return () => {
      vv.removeEventListener("resize", update);
      vv.removeEventListener("scroll", update);
      cancelAnimationFrame(rafRef.current);
    };
  }, [update]);

  return { keyboardVisible, keyboardHeight, toolbarHeight };
}
