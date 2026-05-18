export type DebouncedAction = {
  (): void
  cancel(): void
}

export function createDebouncedAction(
  callback: () => void,
  delayMs: number
): DebouncedAction {
  let timer: ReturnType<typeof setTimeout> | undefined

  const action = (() => {
    if (timer) {
      clearTimeout(timer)
    }

    timer = setTimeout(() => {
      timer = undefined
      callback()
    }, delayMs)
  }) as DebouncedAction

  action.cancel = () => {
    if (timer) {
      clearTimeout(timer)
      timer = undefined
    }
  }

  return action
}
