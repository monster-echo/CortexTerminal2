import type { ReactNode } from "react"
import { LayoutDashboard, MonitorPlay, Server, Settings } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"

const tabs = [
  { id: "dashboard", label: "Home", path: "/", icon: LayoutDashboard },
  { id: "sessions", label: "Sessions", path: "/sessions", icon: MonitorPlay },
  { id: "workers", label: "Workers", path: "/workers", icon: Server },
  { id: "settings", label: "Settings", path: "/settings", icon: Settings },
] as const

function activeTabFromPath(currentPath: string): string {
  if (currentPath === "/" || currentPath === "") return "dashboard"
  if (currentPath.startsWith("/sessions")) return "sessions"
  if (currentPath.startsWith("/workers")) return "workers"
  if (currentPath === "/settings") return "settings"
  return "dashboard"
}

export function AppLayout(props: {
  children: ReactNode
  currentPath: string
  isAuthenticated: boolean
  username: string | null
  onNavigate: (path: string) => void
  onLogout: () => void
}) {
  const { children, currentPath, isAuthenticated, username, onNavigate } = props
  const activeTab = activeTabFromPath(currentPath)
  const isFullScreen = currentPath.startsWith("/sessions/") && isAuthenticated

  if (!isAuthenticated) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background p-4">
        <div className="w-full max-w-sm">{children}</div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <header className="sticky top-0 z-50 border-b border-border bg-card">
        <div className="flex h-14 items-center justify-between px-4">
          <div>
            <h1 className="text-lg font-semibold tracking-tight text-foreground">
              {currentPath === "/" || currentPath === "" ? "Dashboard" : ""}
              {currentPath.startsWith("/sessions/") ? "Terminal" : ""}
              {currentPath === "/sessions" ? "Sessions" : ""}
              {currentPath === "/workers" ? "Workers" : ""}
              {currentPath.startsWith("/workers/") ? "Worker" : ""}
              {currentPath === "/settings" ? "Settings" : ""}
            </h1>
            {username ? (
              <p className="text-xs text-muted-foreground">Hello, {username}</p>
            ) : null}
          </div>
          <Badge variant="secondary" className="text-[10px]">
            Gateway
          </Badge>
        </div>
      </header>

      <main className={`flex-1 overflow-auto ${isFullScreen ? "pb-0" : "pb-20"}`}>
        <div className={isFullScreen ? "" : "p-4"}>{children}</div>
      </main>

      {!isFullScreen ? (
        <nav
          className="fixed bottom-0 left-0 right-0 z-50 border-t border-border bg-card"
          role="navigation"
          aria-label="Main navigation"
        >
          <div className="mx-auto flex max-w-lg items-center justify-around h-16">
            {tabs.map((tab) => {
              const Icon = tab.icon
              const isActive = activeTab === tab.id
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => onNavigate(tab.path)}
                  className={`flex flex-col items-center justify-center gap-0.5 px-3 py-1.5 rounded-lg min-w-[56px] min-h-[44px] transition-colors ${
                    isActive
                      ? "text-primary"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                  aria-label={tab.label}
                  aria-current={isActive ? "page" : undefined}
                >
                  <Icon className="h-5 w-5" />
                  <span className={`text-[10px] font-medium ${isActive ? "" : ""}`}>
                    {tab.label}
                  </span>
                </button>
              )
            })}
          </div>
        </nav>
      ) : null}
    </div>
  )
}
