import type { ReactNode } from "react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"

const navItems = [
  {
    label: "Sessions",
    path: "/sessions",
  },
  {
    label: "Workers",
    path: "/workers",
  },
]

export function AppLayout(props: {
  children: ReactNode
  currentPath: string
  isAuthenticated: boolean
  username: string | null
  onNavigate: (path: string) => void
  onLogout: () => void
}) {
  const { children, currentPath, isAuthenticated, username, onNavigate, onLogout } = props

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,hsl(var(--primary)/0.15),transparent_45%),hsl(var(--background))]">
      <header className="border-b border-border/60">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-3">
            <h1 className="text-xl font-semibold">Gateway Console</h1>
            {username ? (
              <Badge variant="secondary" className="text-xs">
                {username}
              </Badge>
            ) : null}
          </div>
          {isAuthenticated ? (
            <Button onClick={onLogout} variant="outline" size="sm">
              Sign out
            </Button>
          ) : null}
        </div>
      </header>
      <main className="mx-auto grid max-w-7xl gap-6 px-6 py-6 md:grid-cols-[220px_1fr]">
        {isAuthenticated ? (
          <Card className="h-fit p-3">
            <nav className="flex flex-col gap-2" aria-label="Primary">
              {navItems.map((item) => (
                <Button
                  key={item.path}
                  variant={currentPath === item.path ? "default" : "ghost"}
                  className="justify-start"
                  onClick={() => onNavigate(item.path)}
                  type="button"
                  aria-current={currentPath === item.path ? "page" : undefined}
                >
                  {item.label}
                </Button>
              ))}
            </nav>
          </Card>
        ) : null}
        <div className="space-y-6">{children}</div>
      </main>
    </div>
  )
}
