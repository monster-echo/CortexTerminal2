import { useTerminalSession } from "./useTerminalSession"

export function TerminalView({ writeInput }: { writeInput: (payload: Uint8Array) => void }) {
  const session = useTerminalSession(writeInput)

  return (
    <div id="terminal-container">
      <button onClick={() => session.onTerminalData("\t")}>send-tab</button>
    </div>
  )
}
