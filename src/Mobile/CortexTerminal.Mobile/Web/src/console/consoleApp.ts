export type ConsoleRoute =
  | { kind: "login"; path: "/login" }
  | { kind: "register"; path: "/register" }
  | { kind: "dashboard"; path: "/" }
  | { kind: "session-list"; path: "/sessions" }
  | { kind: "session-detail"; path: `/sessions/${string}`; sessionId: string }
  | { kind: "worker-list"; path: "/workers" }
  | { kind: "worker-detail"; path: `/workers/${string}`; workerId: string }
  | { kind: "settings"; path: "/settings" }

export function resolveConsoleRoute(hash: string, isAuthenticated: boolean): ConsoleRoute {
  if (!isAuthenticated) {
    const path = normalizePath(hash)
    if (path === "/register") {
      return { kind: "register", path: "/register" }
    }
    return { kind: "login", path: "/login" }
  }

  const path = normalizePath(hash)
  const sessionMatch = matchDetailRoute(path, "/sessions/")
  if (sessionMatch) {
    return {
      kind: "session-detail",
      path: `/sessions/${sessionMatch}`,
      sessionId: sessionMatch,
    }
  }

  const workerMatch = matchDetailRoute(path, "/workers/")
  if (workerMatch) {
    return {
      kind: "worker-detail",
      path: `/workers/${workerMatch}`,
      workerId: workerMatch,
    }
  }

  if (path === "/sessions") {
    return { kind: "session-list", path: "/sessions" }
  }

  if (path === "/workers") {
    return { kind: "worker-list", path: "/workers" }
  }

  if (path === "/settings") {
    return { kind: "settings", path: "/settings" }
  }

  return { kind: "dashboard", path: "/" }
}

export function toConsoleHash(path: string) {
  return `#${path.startsWith("/") ? path : `/${path}`}`
}

function normalizePath(hash: string) {
  const value = hash.startsWith("#") ? hash.slice(1) : hash
  if (!value || value === "/" || value === "/login") {
    return "/"
  }

  return value.startsWith("/") ? value : `/${value}`
}

function matchDetailRoute(path: string, prefix: "/sessions/" | "/workers/") {
  if (!path.startsWith(prefix)) {
    return null
  }

  const value = path.slice(prefix.length)
  return value.length > 0 ? value : null
}
