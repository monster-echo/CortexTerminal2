import type { ReactNode } from "react"

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
    <div className="min-h-screen flex flex-col bg-[hsl(var(--background))] text-[hsl(var(--foreground))]">
      <header>
        <h1>Gateway Console</h1>
        {username ? <p>Signed in as {username}</p> : null}
        {isAuthenticated ? (
          <>
            <nav aria-label="Primary">
              {navItems.map((item) => (
                <button
                  key={item.path}
                  aria-current={currentPath === item.path ? "page" : undefined}
                  onClick={() => onNavigate(item.path)}
                  type="button"
                >
                  {item.label}
                </button>
              ))}
            </nav>
            <button onClick={onLogout} type="button">
              Sign out
            </button>
          </>
        ) : null}
      </header>
      <main>{children}</main>
    </div>
  )
}
