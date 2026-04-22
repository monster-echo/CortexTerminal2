# Gateway Console Real Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the hosted Gateway console to use `shadcn/ui + Tailwind` across all pages and replace the placeholder terminal with a real `xterm.js` PTY console that shows current Worker information in Session detail.

**Architecture:** Keep the current HTTP and SignalR contracts intact, and limit the change to the Web console presentation layer. Add a UI foundation (`Tailwind`, `shadcn/ui`, shared console components), then replace `TerminalView` with an `xterm.js` adapter while keeping `terminalGateway.ts` and the session lifecycle model as the protocol boundary.

**Tech Stack:** React 19, TypeScript, Vite, Tailwind CSS, shadcn/ui patterns, xterm.js, SignalR, Vitest, xUnit

---

## File Structure

### UI foundation

- Create: `src/Mobile/CortexTerminal.Mobile/Web/components.json` — shadcn/ui component registry config
- Create: `src/Mobile/CortexTerminal.Mobile/Web/postcss.config.js` — Tailwind/PostCSS wiring
- Create: `src/Mobile/CortexTerminal.Mobile/Web/tailwind.config.ts` — Tailwind content/theme config
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/package.json` — add Tailwind/shadcn/xterm addon dependencies
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/vite.config.ts` — preserve Gateway `wwwroot` build output and add `@` alias
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/tsconfig.json` — add `@/*` path alias
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/index.css` — Tailwind layers, theme variables, xterm styles
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/main.tsx` — import global styles
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/lib/utils.ts` — `cn()` helper
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/*.tsx` — shadcn-style primitives used by console pages

### Console shell

- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/components/AppLayout.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/components/SessionList.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerList.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerInfoCard.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionListPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerListPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerDetailPage.tsx`

### Real terminal

- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/createBrowserTerminal.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionDetailPage.tsx`

### Tests / verification

- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionPages.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerPages.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/App.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts`
- Refresh: `src/Gateway/CortexTerminal.Gateway/wwwroot/index.html`
- Refresh: `src/Gateway/CortexTerminal.Gateway/wwwroot/assets/*`

### Task 1: Add Tailwind + shadcn/ui foundation

**Files:**
- Create: `src/Mobile/CortexTerminal.Mobile/Web/components.json`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/postcss.config.js`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/tailwind.config.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/index.css`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/lib/utils.ts`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/button.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/card.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/input.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/badge.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/table.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/alert.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/separator.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/ui/skeleton.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/package.json`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/vite.config.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/tsconfig.json`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/main.tsx`
- Test: `src/Mobile/CortexTerminal.Mobile/Web/src/App.spec.tsx`

- [ ] **Step 1: Write the failing test**

Add a shell smoke test that depends on the new class-based layout so the UI foundation has a red test:

```tsx
it("renders the console shell classes", () => {
  render(<App />)

  expect(document.querySelector(".min-h-screen")).not.toBeNull()
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run src/App.spec.tsx`
Expected: FAIL because the current shell does not render Tailwind-backed layout classes.

- [ ] **Step 3: Write minimal implementation**

Update `package.json` dependencies:

```json
{
  "dependencies": {
    "@microsoft/signalr": "^8.0.7",
    "@radix-ui/react-alert-dialog": "^1.1.2",
    "@radix-ui/react-label": "^2.1.0",
    "@radix-ui/react-separator": "^1.1.0",
    "@radix-ui/react-slot": "^1.1.0",
    "@xterm/addon-fit": "^0.10.0",
    "@xterm/xterm": "^5.5.0",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.1.1",
    "lucide-react": "^0.511.0",
    "react": "^19.1.0",
    "react-dom": "^19.1.0",
    "tailwind-merge": "^2.5.2"
  },
  "devDependencies": {
    "@testing-library/react": "^16.3.0",
    "@types/react": "^19.1.2",
    "@types/react-dom": "^19.1.2",
    "autoprefixer": "^10.4.20",
    "jsdom": "^26.1.0",
    "postcss": "^8.4.49",
    "tailwindcss": "^3.4.17",
    "typescript": "^5.8.3",
    "vite": "^6.3.2",
    "vitest": "^3.1.2"
  }
}
```

Add `tsconfig.json` alias:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  }
}
```

Update `vite.config.ts`:

```ts
import { resolve } from "node:path"
import { fileURLToPath, URL } from "node:url"
import { defineConfig } from "vite"

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  build: {
    emptyOutDir: true,
    outDir: resolve(__dirname, "../../../Gateway/CortexTerminal.Gateway/wwwroot"),
  },
  test: {
    environment: "jsdom",
    globals: true,
  },
})
```

Create `src/lib/utils.ts`:

```ts
import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

Create `src/index.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@import "@xterm/xterm/css/xterm.css";

@layer base {
  :root {
    --background: 222 47% 11%;
    --foreground: 210 40% 98%;
    --card: 224 36% 15%;
    --card-foreground: 210 40% 98%;
    --border: 217 33% 24%;
    --primary: 213 94% 68%;
    --primary-foreground: 222 47% 11%;
    --muted: 217 33% 24%;
    --muted-foreground: 215 20% 65%;
    --destructive: 0 72% 51%;
    --destructive-foreground: 210 40% 98%;
    --input: 217 33% 24%;
    --ring: 213 94% 68%;
    color-scheme: dark;
  }

  body {
    @apply min-h-screen bg-[hsl(var(--background))] text-[hsl(var(--foreground))] antialiased;
  }

  #root {
    @apply min-h-screen;
  }
}
```

Update `src/main.tsx`:

```tsx
import "./index.css"
import { createRoot } from "react-dom/client"
import { App } from "./App"
```

Create minimal shadcn-style primitives (`button.tsx`, `card.tsx`, `input.tsx`, `badge.tsx`, `table.tsx`, `alert.tsx`, `separator.tsx`, `skeleton.tsx`) using `cn()` and the usual `cva` patterns.

Add `components.json`:

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "default",
  "rsc": false,
  "tsx": true,
  "tailwind": {
    "config": "tailwind.config.ts",
    "css": "src/index.css",
    "baseColor": "slate",
    "cssVariables": true
  },
  "aliases": {
    "components": "@/components",
    "utils": "@/lib/utils",
    "ui": "@/components/ui"
  }
}
```

- [ ] **Step 4: Run tests and install dependencies**

Run:

```bash
cd src/Mobile/CortexTerminal.Mobile/Web
npm install
npm test -- --run src/App.spec.tsx
```

Expected: PASS; the shell can import the new UI foundation and global styles.

- [ ] **Step 5: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/package.json \
        src/Mobile/CortexTerminal.Mobile/Web/package-lock.json \
        src/Mobile/CortexTerminal.Mobile/Web/tsconfig.json \
        src/Mobile/CortexTerminal.Mobile/Web/vite.config.ts \
        src/Mobile/CortexTerminal.Mobile/Web/postcss.config.js \
        src/Mobile/CortexTerminal.Mobile/Web/tailwind.config.ts \
        src/Mobile/CortexTerminal.Mobile/Web/components.json \
        src/Mobile/CortexTerminal.Mobile/Web/src/main.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/index.css \
        src/Mobile/CortexTerminal.Mobile/Web/src/lib/utils.ts \
        src/Mobile/CortexTerminal.Mobile/Web/src/components/ui \
        src/Mobile/CortexTerminal.Mobile/Web/src/App.spec.tsx
git commit -m "feat: add gateway console ui foundation"
```

### Task 2: Restyle the hosted console pages with shadcn/ui

**Files:**
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/components/AppLayout.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/components/SessionList.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerList.tsx`
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerInfoCard.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionListPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerListPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerDetailPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionPages.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerPages.spec.tsx`

- [ ] **Step 1: Write the failing tests**

Add page-level expectations for the new shell:

```tsx
it("renders worker summaries as cards with status badges", async () => {
  render(<WorkerListPage api={api} navigate={vi.fn()} />)

  expect(await screen.findByText("Open worker")).toBeInTheDocument()
  expect(screen.getByText("Online")).toHaveClass("inline-flex")
})
```

```tsx
it("renders the login screen with a card header and primary action", () => {
  render(<LoginPage login={vi.fn()} navigate={vi.fn()} />)

  expect(screen.getByRole("button", { name: "Sign in" })).toHaveClass("inline-flex")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd src/Mobile/CortexTerminal.Mobile/Web
npm test -- --run src/pages/LoginPage.spec.tsx src/pages/SessionPages.spec.tsx src/pages/WorkerPages.spec.tsx
```

Expected: FAIL because the current pages are plain semantic HTML without the new component structure/classes.

- [ ] **Step 3: Write minimal implementation**

Replace `AppLayout.tsx` with a dashboard shell using shadcn primitives:

```tsx
import type { ReactNode } from "react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"

export function AppLayout(/* existing props */) {
  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,hsl(var(--primary)/0.15),transparent_45%),hsl(var(--background))]">
      <header className="border-b border-border/60">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
          <div>
            <h1 className="text-xl font-semibold">Gateway Console</h1>
            {username ? <Badge variant="secondary">Signed in as {username}</Badge> : null}
          </div>
          {isAuthenticated ? <Button onClick={onLogout} variant="outline">Sign out</Button> : null}
        </div>
      </header>
      <main className="mx-auto grid max-w-7xl gap-6 px-6 py-6 md:grid-cols-[220px_1fr]">
        {isAuthenticated ? (
          <Card className="p-3">
            <nav className="flex flex-col gap-2" aria-label="Primary">
              {navItems.map((item) => (
                <Button
                  key={item.path}
                  variant={currentPath === item.path ? "default" : "ghost"}
                  className="justify-start"
                  onClick={() => onNavigate(item.path)}
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
```

Replace `LoginPage.tsx` with a card/form layout using `Card`, `Input`, `Button`, and `Alert`.

Replace `SessionList.tsx` and `WorkerList.tsx` with `Table`-based renderers that show status badges and open actions.

Create `WorkerInfoCard.tsx`:

```tsx
import type { WorkerDetail, WorkerSummary } from "@/services/consoleApi"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

export function WorkerInfoCard({ worker }: { worker: WorkerSummary | WorkerDetail }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{worker.displayName}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2 text-sm">
        <div className="flex items-center justify-between">
          <span>Worker ID</span>
          <code>{worker.workerId}</code>
        </div>
        <div className="flex items-center justify-between">
          <span>Status</span>
          <Badge variant={worker.isOnline ? "default" : "secondary"}>
            {worker.isOnline ? "Online" : "Offline"}
          </Badge>
        </div>
        <div className="flex items-center justify-between">
          <span>Sessions</span>
          <span>{worker.sessionCount}</span>
        </div>
        <div className="flex items-center justify-between">
          <span>Last seen</span>
          <span>{new Date(worker.lastSeenAt).toLocaleString()}</span>
        </div>
      </CardContent>
    </Card>
  )
}
```

Update the list/detail pages to use `Card`, `Alert`, `Skeleton`, `Badge`, and the new shared list/card components rather than raw `<section>`, `<dl>`, and `<ul>`.

- [ ] **Step 4: Run page tests**

Run:

```bash
cd src/Mobile/CortexTerminal.Mobile/Web
npm test -- --run src/pages/LoginPage.spec.tsx src/pages/SessionPages.spec.tsx src/pages/WorkerPages.spec.tsx
```

Expected: PASS; login, sessions, and workers pages now render through the shared shadcn-style shell.

- [ ] **Step 5: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/components/AppLayout.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/components/SessionList.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerList.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/components/WorkerInfoCard.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/LoginPage.spec.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionListPage.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerListPage.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerDetailPage.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionPages.spec.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/WorkerPages.spec.tsx
git commit -m "feat: restyle gateway console pages"
```

### Task 3: Replace the placeholder terminal with real xterm.js and show worker info in Session detail

**Files:**
- Create: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/createBrowserTerminal.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.spec.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionDetailPage.tsx`
- Modify: `src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionPages.spec.tsx`

- [ ] **Step 1: Write the failing tests**

Add a terminal host test:

```tsx
it("mounts an xterm instance and forwards streamed output", async () => {
  const write = vi.fn()
  mockTerminal(write)

  render(<TerminalView gateway={gateway} sessionId="session-123" />)

  await waitFor(() => expect(write).toHaveBeenCalledWith("hello"))
})
```

Add a session detail test:

```tsx
it("loads worker info beside the terminal", async () => {
  render(
    <SessionDetailPage
      api={api}
      navigate={vi.fn()}
      sessionId="session-123"
      terminalGateway={gateway}
    />
  )

  expect(await screen.findByText("Worker ID")).toBeInTheDocument()
  expect(screen.getByText("worker-1")).toBeInTheDocument()
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd src/Mobile/CortexTerminal.Mobile/Web
npm test -- --run src/terminal/TerminalView.spec.tsx src/terminal/useTerminalSession.spec.ts src/pages/SessionPages.spec.tsx
```

Expected: FAIL because `TerminalView` still renders `<pre>` output and `SessionDetailPage` does not load/display Worker detail.

- [ ] **Step 3: Write minimal implementation**

Create `createBrowserTerminal.ts`:

```ts
import { FitAddon } from "@xterm/addon-fit"
import { Terminal } from "@xterm/xterm"

export function createBrowserTerminal(container: HTMLElement, onData: (data: string) => void) {
  const terminal = new Terminal({
    cursorBlink: true,
    fontFamily: "ui-monospace, SFMono-Regular, monospace",
    fontSize: 13,
    scrollback: 5000,
    theme: {
      background: "#0f172a",
      foreground: "#e2e8f0",
    },
  })

  const fitAddon = new FitAddon()
  terminal.loadAddon(fitAddon)
  terminal.open(container)
  fitAddon.fit()

  const disposable = terminal.onData(onData)

  return {
    write(data: string) {
      terminal.write(data)
    },
    fit() {
      fitAddon.fit()
      return {
        columns: terminal.cols,
        rows: terminal.rows,
      }
    },
    dispose() {
      disposable.dispose()
      terminal.dispose()
    },
  }
}
```

Update `useTerminalSession.ts` so `onStream` still emits decoded text, but the state model stays protocol-focused:

```ts
onStdout(payload: Uint8Array) {
  const text = emitStream("stdout", payload)
  return text
}
```

Replace `TerminalView.tsx` with an xterm-backed view:

```tsx
const terminalContainerRef = useRef<HTMLDivElement | null>(null)
const browserTerminalRef = useRef<ReturnType<typeof createBrowserTerminal> | null>(null)

useEffect(() => {
  const element = terminalContainerRef.current
  if (!element) {
    return
  }

  const browserTerminal = createBrowserTerminal(element, (data) => {
    session.onTerminalData(data)
  })
  browserTerminalRef.current = browserTerminal

  const size = browserTerminal.fit()
  void connectionRef.current?.resize(size.columns, size.rows)

  const observer = new ResizeObserver(() => {
    const next = browserTerminal.fit()
    void connectionRef.current?.resize(next.columns, next.rows)
  })
  observer.observe(element)

  return () => {
    observer.disconnect()
    browserTerminal.dispose()
    browserTerminalRef.current = null
  }
}, [session])
```

Inside stream handlers:

```tsx
onStream: ({ text }) => {
  browserTerminalRef.current?.write(text)
}
```

Update `SessionDetailPage.tsx` to load worker detail after session detail resolves:

```tsx
const [worker, setWorker] = useState<WorkerDetail | null>(null)

useEffect(() => {
  if (!session) {
    setWorker(null)
    return
  }

  let isActive = true
  api.getWorker(session.workerId)
    .then((value) => {
      if (isActive) {
        setWorker(value)
      }
    })
    .catch((error: unknown) => {
      if (isActive) {
        setErrorMessage(error instanceof Error ? error.message : "Could not load worker.")
      }
    })

  return () => {
    isActive = false
  }
}, [api, session])
```

Render a split layout:

```tsx
<div className="grid gap-6 xl:grid-cols-[1fr_320px]">
  <Card className="overflow-hidden">
    <CardHeader>
      <CardTitle>Session {session.sessionId}</CardTitle>
      <Badge>{statusLabel}</Badge>
    </CardHeader>
    <CardContent>
      <TerminalView gateway={terminalGateway} sessionId={session.sessionId} />
    </CardContent>
  </Card>
  {worker ? <WorkerInfoCard worker={worker} /> : <Skeleton className="h-[220px]" />}
</div>
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd src/Mobile/CortexTerminal.Mobile/Web
npm test -- --run src/terminal/TerminalView.spec.tsx src/terminal/useTerminalSession.spec.ts src/pages/SessionPages.spec.tsx
```

Expected: PASS; the terminal mounts xterm, session streams are forwarded, and worker info is visible in session detail.

- [ ] **Step 5: Commit**

```bash
git add src/Mobile/CortexTerminal.Mobile/Web/src/terminal/createBrowserTerminal.ts \
        src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.ts \
        src/Mobile/CortexTerminal.Mobile/Web/src/terminal/TerminalView.spec.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/terminal/useTerminalSession.spec.ts \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionDetailPage.tsx \
        src/Mobile/CortexTerminal.Mobile/Web/src/pages/SessionPages.spec.tsx
git commit -m "feat: add real terminal session console"
```

### Task 4: Rebuild hosted assets and verify the full console flow

**Files:**
- Modify: `src/Gateway/CortexTerminal.Gateway/wwwroot/index.html`
- Modify: `src/Gateway/CortexTerminal.Gateway/wwwroot/assets/*`
- Test: `tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj`
- Test: `tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj`
- Test: `tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj`
- Test: `src/Mobile/CortexTerminal.Mobile/Web/package.json`

- [ ] **Step 1: Run the full verification matrix**

Run:

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests/CortexTerminal.Gateway.Tests.csproj --nologo --verbosity minimal
dotnet test tests/Worker/CortexTerminal.Worker.Tests/CortexTerminal.Worker.Tests.csproj --nologo --verbosity minimal
dotnet test tests/Mobile/CortexTerminal.Mobile.Tests/CortexTerminal.Mobile.Tests.csproj --nologo --verbosity minimal
cd src/Mobile/CortexTerminal.Mobile/Web && npm test -- --run && npm run build
```

Expected: PASS across all suites, and the Vite build refreshes Gateway `wwwroot`.

- [ ] **Step 2: Verify hosted console output**

Run:

```bash
curl -I http://localhost:5045/
curl -s http://localhost:5045/ | grep "<title>Gateway Console</title>"
```

Expected: root responds with `200 OK`, `text/html`, and the console title.

- [ ] **Step 3: Verify manual terminal target**

Run:

```bash
curl -s -X POST http://localhost:5045/api/dev/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"echo"}'
```

Expected: access token payload is returned, proving the browser login flow still has a working backend target.

- [ ] **Step 4: Commit refreshed hosted assets**

```bash
git add src/Gateway/CortexTerminal.Gateway/wwwroot
git commit -m "chore: refresh real terminal console assets"
```
