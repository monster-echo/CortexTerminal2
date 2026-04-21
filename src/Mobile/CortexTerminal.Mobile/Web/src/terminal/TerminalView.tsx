import { useMemo, useState } from "react"
import { createTerminalSessionModel, type TerminalSessionState } from "./useTerminalSession"

export function TerminalView({ writeInput }: { writeInput: (payload: Uint8Array) => void }) {
  const [status, setStatus] = useState<TerminalSessionState>("live")
  const session = useMemo(
    () =>
      createTerminalSessionModel({
        writeInput,
        onStateChange: setStatus,
      }),
    [writeInput]
  )

  return (
    <div id="terminal-container">
      <div data-testid="terminal-status">{status}</div>
      <button onClick={() => session.onTerminalData("\t")}>send-tab</button>
    </div>
  )
}
