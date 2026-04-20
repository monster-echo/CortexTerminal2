import { TerminalView } from "./terminal/TerminalView"

export function App() {
  const handleWriteInput = (payload: Uint8Array) => {
    // In production, this bridges to MAUI native via window.chrome.webview
    console.log("terminal input:", payload)
  }

  return <TerminalView writeInput={handleWriteInput} />
}
