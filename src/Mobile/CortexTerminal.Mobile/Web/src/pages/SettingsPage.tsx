import { useState, useEffect } from "react"
import { Moon, Sun, Monitor, Globe, LogOut, User } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"

type Theme = "light" | "dark" | "system"

function getStoredTheme(): Theme {
  return (localStorage.getItem("theme") as Theme) ?? "system"
}

function setStoredTheme(theme: Theme) {
  localStorage.setItem("theme", theme)
  applyTheme(theme)
}

function applyTheme(theme: Theme) {
  const root = document.documentElement
  if (theme === "system") {
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    root.classList.toggle("dark", prefersDark)
  } else {
    root.classList.toggle("dark", theme === "dark")
  }
}

export function SettingsPage(props: {
  username: string | null
  onLogout: () => void
}) {
  const { username, onLogout } = props
  const [theme, setTheme] = useState<Theme>(getStoredTheme)

  useEffect(() => {
    applyTheme(theme)
  }, [theme])

  const themes: { value: Theme; label: string; icon: typeof Sun }[] = [
    { value: "light", label: "Light", icon: Sun },
    { value: "dark", label: "Dark", icon: Moon },
    { value: "system", label: "System", icon: Monitor },
  ]

  return (
    <div className="space-y-5">
      <Card>
        <CardContent className="flex items-center gap-3 p-4">
          <div className="flex h-11 w-11 items-center justify-center rounded-full bg-primary/10">
            <User className="h-5 w-5 text-primary" />
          </div>
          <div>
            <p className="font-semibold">{username ?? "User"}</p>
            <p className="text-xs text-muted-foreground">Gateway Console</p>
          </div>
        </CardContent>
      </Card>

      <div className="space-y-1">
        <h2 className="px-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Appearance
        </h2>
        <div className="flex gap-2">
          {themes.map(({ value, label, icon: Icon }) => (
            <Button
              key={value}
              variant={theme === value ? "default" : "outline"}
              size="sm"
              onClick={() => setStoredTheme(value)}
              className="flex-1 flex-col gap-1 h-auto py-3"
            >
              <Icon className="h-4 w-4" />
              <span className="text-xs">{label}</span>
            </Button>
          ))}
        </div>
      </div>

      <div className="space-y-1">
        <h2 className="px-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Language
        </h2>
        <div className="flex gap-2">
          <Button variant="default" size="sm" className="flex-1">
            <Globe className="mr-1.5 h-4 w-4" /> English
          </Button>
          <Button variant="outline" size="sm" className="flex-1">
            <Globe className="mr-1.5 h-4 w-4" /> 中文
          </Button>
        </div>
      </div>

      <div className="space-y-1">
        <h2 className="px-1 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Account
        </h2>
        <Button
          variant="outline"
          className="w-full justify-start text-destructive hover:text-destructive"
          onClick={onLogout}
        >
          <LogOut className="mr-3 h-4 w-4" />
          Sign out
        </Button>
      </div>

      <p className="text-center text-xs text-muted-foreground">
        CortexTerminal Gateway v2.2.1
      </p>
    </div>
  )
}
