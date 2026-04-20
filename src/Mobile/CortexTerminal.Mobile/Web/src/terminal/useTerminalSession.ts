export function useTerminalSession(writeInput: (payload: Uint8Array) => void) {
  return {
    onTerminalData(data: string) {
      writeInput(new TextEncoder().encode(data))
    },
    onStdout(payload: Uint8Array) {
      return new TextDecoder().decode(payload)
    },
    onStderr(payload: Uint8Array) {
      return new TextDecoder().decode(payload)
    },
  }
}
