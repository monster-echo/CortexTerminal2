# Gateway Frontend Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the existing CortexTerminal.Console Shadcn Admin template into a branded CortexTerminal management platform with full terminal, worker, user, settings, and audit log pages.

**Architecture:** The Console project (`src/Gateway/CortexTerminal.Console/`) already has a working Shadcn Admin foundation with TanStack Router, shadcn/ui, xterm.js, SignalR, and Zustand. We rebrand, restructure navigation, add new feature pages, and modify existing terminal pages per spec. Vite builds output to `../CortexTerminal.Gateway/wwwroot`.

**Tech Stack:** React 19, TanStack Router + Query, shadcn/ui (Radix), Tailwind CSS v4, Zustand, @xterm/xterm, @microsoft/signalr, react-i18next, Vite 8

**Existing key files:**
- `src/components/layout/data/sidebar-data.ts` — sidebar navigation config
- `src/components/layout/authenticated-layout.tsx` — app shell
- `src/features/sessions/` — session list + detail + new session
- `src/terminal/` — xterm.js terminal, SignalR gateway, session state machine
- `src/services/console-api.ts` — REST client
- `src/services/terminal-gateway.ts` — SignalR client
- `src/stores/auth-store.ts` — auth state
- `src/styles/theme.css` — CSS variables (light/dark)
- `src/routes/` — TanStack Router file-based routes

---

## Phase 1: Brand & Theme Foundation

### Task 1: Rebrand app title and meta tags

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/index.html`

- [ ] **Step 1: Update index.html**

Replace all "Shadcn Admin" references with "CortexTerminal". Update OG/Twitter meta tags. Keep existing favicon references and Google Fonts import.

```html
<title>CortexTerminal</title>
<meta name="title" content="CortexTerminal" />
<meta name="description" content="Cloud-hosted terminal gateway management platform." />
<meta property="og:title" content="CortexTerminal" />
<meta property="og:description" content="Cloud-hosted terminal gateway management platform." />
<meta property="twitter:title" content="CortexTerminal" />
<meta property="twitter:description" content="Cloud-hosted terminal gateway management platform." />
```

Remove the `og:image`, `twitter:image`, `og:url`, `twitter:url` that reference `shadcn-admin.netlify.app`.

- [ ] **Step 2: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/index.html
git commit -m "chore: rebrand index.html from Shadcn Admin to CortexTerminal"
```

### Task 2: Customize theme with indigo brand color

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/styles/theme.css`

- [ ] **Step 1: Update CSS custom properties**

In `theme.css`, change `--primary` in both `:root` (light) and `.dark` blocks to indigo:

```css
:root {
  /* Change from default zinc to indigo */
  --primary: oklch(55% .24 265);
  --primary-foreground: oklch(100% 0 0);
}

.dark {
  --primary: oklch(62% .24 265);
  --primary-foreground: oklch(100% 0 0);
}
```

Keep all other tokens unchanged. The `--radius: 0.625rem`, sidebar tokens, chart colors, etc. remain as-is.

- [ ] **Step 2: Verify visually**

Run: `cd src/Gateway/CortexTerminal.Console && pnpm dev`
Expected: Sidebar active items, buttons, links now use indigo accent instead of default zinc.

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/styles/theme.css
git commit -m "style: apply indigo brand color to primary tokens"
```

### Task 3: Update sidebar navigation and team switcher

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/components/layout/data/sidebar-data.ts`
- Modify: `src/Gateway/CortexTerminal.Console/src/components/layout/team-switcher.tsx`

- [ ] **Step 1: Replace sidebar-data.ts with CortexTerminal navigation**

Replace `sidebar-data.ts` content to match spec navigation:

```typescript
import {
  LayoutDashboard,
  Terminal,
  Server,
  Users,
  Settings,
  FileText,
} from 'lucide-react'
import { type SidebarData } from '../types'

export const sidebarData: SidebarData = {
  user: {
    name: '',
    email: '',
    avatar: '',
  },
  teams: [
    {
      name: 'CortexTerminal',
      logo: Terminal,
      plan: 'Gateway',
    },
  ],
  navGroups: [
    {
      title: 'Overview',
      items: [
        { title: 'Dashboard', icon: LayoutDashboard, href: '/dashboard' },
      ],
    },
    {
      title: 'Terminal',
      items: [
        { title: 'Sessions', icon: Terminal, href: '/sessions' },
      ],
    },
    {
      title: 'Infrastructure',
      items: [
        { title: 'Workers', icon: Server, href: '/workers' },
      ],
    },
    {
      title: 'Admin',
      items: [
        { title: 'Users', icon: Users, href: '/users' },
      ],
    },
    {
      title: 'System',
      items: [
        { title: 'Settings', icon: Settings, href: '/settings' },
        { title: 'Audit Log', icon: FileText, href: '/audit-log' },
      ],
    },
  ],
}
```

- [ ] **Step 2: Simplify team-switcher.tsx to show CortexTerminal brand**

In `team-switcher.tsx`, replace the team data to show only the CortexTerminal brand name. The dropdown for switching teams can be simplified or removed since we only have one "team".

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/components/layout/
git commit -m "feat: update sidebar navigation to CortexTerminal structure"
```

### Task 4: Add i18n infrastructure

**Files:**
- Create: `src/Gateway/CortexTerminal.Console/src/lib/i18n.ts`
- Create: `src/Gateway/CortexTerminal.Console/src/locales/en.json`
- Create: `src/Gateway/CortexTerminal.Console/src/locales/zh.json`
- Modify: `src/Gateway/CortexTerminal.Console/src/main.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/package.json`

- [ ] **Step 1: Install react-i18next**

```bash
cd src/Gateway/CortexTerminal.Console && pnpm add react-i18next i18next i18next-browser-languagedetector i18next-http-backend
```

- [ ] **Step 2: Create i18n config `src/lib/i18n.ts`**

```typescript
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'
import en from '@/locales/en.json'
import zh from '@/locales/zh.json'

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: { en: { translation: en }, zh: { translation: zh } },
    fallbackLng: 'en',
    supportedLngs: ['en', 'zh'],
    interpolation: { escapeValue: false },
    detection: {
      order: ['localStorage', 'navigator'],
      lookupLocalStorage: 'cortex_terminal_lang',
      caches: ['localStorage'],
    },
  })

export default i18n
```

- [ ] **Step 3: Create `src/locales/en.json`**

```json
{
  "brand": {
    "name": "CortexTerminal"
  },
  "nav": {
    "dashboard": "Dashboard",
    "sessions": "Sessions",
    "workers": "Workers",
    "users": "Users",
    "settings": "Settings",
    "auditLog": "Audit Log"
  },
  "auth": {
    "signIn": "Sign In",
    "signInWith": "Sign in with {{provider}}",
    "signInToContinue": "Sign in to continue",
    "or": "or",
    "username": "Username",
    "signOut": "Sign Out",
    "signOutConfirm": "Are you sure you want to sign out?"
  },
  "dashboard": {
    "title": "Dashboard",
    "welcomeBack": "Welcome back, {{name}}",
    "activeSessions": "Active Sessions",
    "detachedSessions": "Detached Sessions",
    "onlineWorkers": "Online Workers",
    "systemUptime": "System Uptime",
    "recentSessions": "Recent Sessions",
    "workerStatus": "Worker Status"
  },
  "sessions": {
    "title": "Sessions",
    "newSession": "New Session",
    "filter": {
      "all": "All",
      "live": "Live",
      "detached": "Detached",
      "exited": "Exited"
    },
    "status": {
      "live": "Live",
      "detached": "Detached",
      "exited": "Exited",
      "expired": "Expired"
    },
    "delete": {
      "button": "Delete",
      "confirm": "Delete Session",
      "message": "Are you sure you want to delete this session? This action cannot be undone."
    },
    "created": "Created {{time}}",
    "dimensions": "{{cols}}x{{rows}}"
  },
  "terminal": {
    "latency": "{{ms}}ms",
    "fullscreen": "Fullscreen",
    "exitFullscreen": "Exit Fullscreen"
  },
  "workers": {
    "title": "Workers",
    "status": {
      "online": "Online",
      "offline": "Offline"
    },
    "sessions": "{{count}} sessions",
    "uptime": "Uptime",
    "address": "Address"
  },
  "users": {
    "title": "User Management",
    "invite": "Invite",
    "role": {
      "admin": "Admin",
      "user": "User"
    },
    "actions": {
      "editRole": "Edit Role",
      "disable": "Disable",
      "enable": "Enable",
      "delete": "Delete"
    }
  },
  "settings": {
    "title": "Settings",
    "profile": "Profile",
    "general": "General",
    "language": "Language",
    "theme": "Theme",
    "displayName": "Display Name",
    "security": "Security",
    "dangerZone": "Danger Zone"
  },
  "auditLog": {
    "title": "Audit Log",
    "timestamp": "Timestamp",
    "user": "User",
    "action": "Action",
    "target": "Target"
  },
  "common": {
    "search": "Search...",
    "loading": "Loading...",
    "error": "Error",
    "cancel": "Cancel",
    "confirm": "Confirm",
    "save": "Save",
    "delete": "Delete",
    "edit": "Edit",
    "close": "Close",
    "goToDashboard": "Go to Dashboard"
  }
}
```

- [ ] **Step 4: Create `src/locales/zh.json`**

```json
{
  "brand": {
    "name": "CortexTerminal"
  },
  "nav": {
    "dashboard": "仪表盘",
    "sessions": "会话",
    "workers": "工作节点",
    "users": "用户",
    "settings": "设置",
    "auditLog": "审计日志"
  },
  "auth": {
    "signIn": "登录",
    "signInWith": "使用 {{provider}} 登录",
    "signInToContinue": "登录以继续",
    "or": "或",
    "username": "用户名",
    "signOut": "退出登录",
    "signOutConfirm": "确定要退出登录吗？"
  },
  "dashboard": {
    "title": "仪表盘",
    "welcomeBack": "欢迎回来, {{name}}",
    "activeSessions": "活跃会话",
    "detachedSessions": "断开会话",
    "onlineWorkers": "在线节点",
    "systemUptime": "系统运行时间",
    "recentSessions": "最近会话",
    "workerStatus": "节点状态"
  },
  "sessions": {
    "title": "会话",
    "newSession": "新建会话",
    "filter": {
      "all": "全部",
      "live": "活跃",
      "detached": "断开",
      "exited": "已退出"
    },
    "status": {
      "live": "活跃",
      "detached": "断开",
      "exited": "已退出",
      "expired": "已过期"
    },
    "delete": {
      "button": "删除",
      "confirm": "删除会话",
      "message": "确定要删除此会话吗？此操作无法撤销。"
    },
    "created": "{{time}}创建",
    "dimensions": "{{cols}}x{{rows}}"
  },
  "terminal": {
    "latency": "{{ms}}ms",
    "fullscreen": "全屏",
    "exitFullscreen": "退出全屏"
  },
  "workers": {
    "title": "工作节点",
    "status": {
      "online": "在线",
      "offline": "离线"
    },
    "sessions": "{{count}} 个会话",
    "uptime": "运行时间",
    "address": "地址"
  },
  "users": {
    "title": "用户管理",
    "invite": "邀请",
    "role": {
      "admin": "管理员",
      "user": "用户"
    },
    "actions": {
      "editRole": "编辑角色",
      "disable": "禁用",
      "enable": "启用",
      "delete": "删除"
    }
  },
  "settings": {
    "title": "设置",
    "profile": "个人资料",
    "general": "通用",
    "language": "语言",
    "theme": "主题",
    "displayName": "显示名称",
    "security": "安全",
    "dangerZone": "危险区域"
  },
  "auditLog": {
    "title": "审计日志",
    "timestamp": "时间",
    "user": "用户",
    "action": "操作",
    "target": "目标"
  },
  "common": {
    "search": "搜索...",
    "loading": "加载中...",
    "error": "错误",
    "cancel": "取消",
    "confirm": "确认",
    "save": "保存",
    "delete": "删除",
    "edit": "编辑",
    "close": "关闭",
    "goToDashboard": "前往仪表盘"
  }
}
```

- [ ] **Step 5: Import i18n in main.tsx**

Add `import '@/lib/i18n'` at the top of `main.tsx`, before the router import.

- [ ] **Step 6: Add language switcher component**

Create `src/Gateway/CortexTerminal.Console/src/components/layout/language-switcher.tsx`:

```tsx
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { Languages } from 'lucide-react'

export function LanguageSwitcher() {
  const { i18n } = useTranslation()

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon">
          <Languages className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => i18n.changeLanguage('en')}>
          English
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => i18n.changeLanguage('zh')}>
          中文
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
```

- [ ] **Step 7: Add LanguageSwitcher to header.tsx**

Import and add `<LanguageSwitcher />` next to the existing `<ThemeSwitch />` in the header component.

- [ ] **Step 8: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/lib/i18n.ts \
  src/Gateway/CortexTerminal.Console/src/locales/ \
  src/Gateway/CortexTerminal.Console/src/main.tsx \
  src/Gateway/CortexTerminal.Console/src/components/layout/language-switcher.tsx \
  src/Gateway/CortexTerminal.Console/src/components/layout/header.tsx \
  src/Gateway/CortexTerminal.Console/package.json \
  src/Gateway/CortexTerminal.Console/pnpm-lock.yaml
git commit -m "feat: add i18n infrastructure with en/zh locales and language switcher"
```

---

## Phase 2: Route Structure Cleanup

### Task 5: Add new routes and remove unused routes

**Files:**
- Create: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/dashboard.tsx`
- Create: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/workers/route.tsx`
- Create: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/workers/index.tsx`
- Create: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/workers/$workerId.tsx`
- Create: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/audit-log.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/index.tsx` — redirect to `/dashboard` instead of `/sessions`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/apps/`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/chats/`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/tasks/`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/help-center/`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/(auth)/sign-up.tsx`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/(auth)/sign-in-2.tsx`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/(auth)/forgot-password.tsx`
- Delete: `src/Gateway/CortexTerminal.Console/src/routes/(auth)/otp.tsx`
- Delete: `src/Gateway/CortexTerminal.Console/src/features/apps/`
- Delete: `src/Gateway/CortexTerminal.Console/src/features/chats/`
- Delete: `src/Gateway/CortexTerminal.Console/src/features/tasks/`

- [ ] **Step 1: Update _authenticated/index.tsx redirect**

Change redirect from `/sessions` to `/dashboard`:

```typescript
import { createFileRoute, redirect } from '@tanstack/react-router'

export const Route = createFileRoute('/_authenticated/')({
  beforeLoad: () => {
    throw redirect({ to: '/dashboard' })
  },
})
```

- [ ] **Step 2: Create dashboard route file**

`src/routes/_authenticated/dashboard.tsx`:

```typescript
import { createFileRoute } from '@tanstack/react-router'
import { DashboardPage } from '@/features/dashboard'

export const Route = createFileRoute('/_authenticated/dashboard')({
  component: DashboardPage,
})
```

- [ ] **Step 3: Create workers route files**

`src/routes/_authenticated/workers/route.tsx`:

```typescript
import { createFileRoute, Outlet } from '@tanstack/react-router'

export const Route = createFileRoute('/_authenticated/workers')({
  component: () => <Outlet />,
})
```

`src/routes/_authenticated/workers/index.tsx`:

```typescript
import { createFileRoute } from '@tanstack/react-router'
import { WorkerListPage } from '@/features/workers'

export const Route = createFileRoute('/_authenticated/workers/')({
  component: WorkerListPage,
})
```

`src/routes/_authenticated/workers/$workerId.tsx`:

```typescript
import { createFileRoute } from '@tanstack/react-router'
import { WorkerDetailPage } from '@/features/workers/worker-detail-page'

export const Route = createFileRoute('/_authenticated/workers/$workerId')({
  component: WorkerDetailPage,
})
```

- [ ] **Step 4: Create audit-log route file**

`src/routes/_authenticated/audit-log.tsx`:

```typescript
import { createFileRoute } from '@tanstack/react-router'
import { AuditLogPage } from '@/features/audit-log'

export const Route = createFileRoute('/_authenticated/audit-log')({
  component: AuditLogPage,
})
```

- [ ] **Step 5: Delete unused route files and feature directories**

```bash
cd src/Gateway/CortexTerminal.Console
rm -rf src/routes/_authenticated/apps/
rm -rf src/routes/_authenticated/chats/
rm -rf src/routes/_authenticated/tasks/
rm -rf src/routes/_authenticated/help-center/
rm -rf src/routes/(auth)/sign-up.tsx
rm -rf src/routes/(auth)/sign-in-2.tsx
rm -rf src/routes/(auth)/forgot-password.tsx
rm -rf src/routes/(auth)/otp.tsx
rm -rf src/features/apps/
rm -rf src/features/chats/
rm -rf src/features/tasks/
rm -rf src/features/auth/sign-up/
rm -rf src/features/auth/forgot-password/
rm -rf src/features/auth/otp/
```

- [ ] **Step 6: Regenerate route tree and verify build**

```bash
cd src/Gateway/CortexTerminal.Console && pnpm tsc -b && pnpm vite build
```

Expected: Build succeeds with new route tree. Fix any import errors from deleted features.

- [ ] **Step 7: Commit**

```bash
git add -A src/Gateway/CortexTerminal.Console/src/routes/ \
  src/Gateway/CortexTerminal.Console/src/features/
git commit -m "feat: add dashboard/workers/audit-log routes, remove unused features"
```

---

## Phase 3: Shared Components

### Task 6: Create StatusBadge and StatusDot shared components

**Files:**
- Create: `src/Gateway/CortexTerminal.Console/src/components/shared/status-dot.tsx`
- Create: `src/Gateway/CortexTerminal.Console/src/components/shared/status-badge.tsx`

- [ ] **Step 1: Create status-dot.tsx**

```tsx
import { cn } from '@/lib/utils'

type Status = 'live' | 'detached' | 'exited' | 'expired' | 'online' | 'offline'

const colorMap: Record<Status, string> = {
  live: 'bg-emerald-500',
  detached: 'bg-amber-500',
  exited: 'bg-red-500',
  expired: 'bg-zinc-400',
  online: 'bg-emerald-500',
  offline: 'bg-zinc-400',
}

interface StatusDotProps {
  status: Status
  className?: string
}

export function StatusDot({ status, className }: StatusDotProps) {
  return (
    <span
      className={cn('inline-block h-2 w-2 rounded-full shrink-0', colorMap[status], className)}
      aria-label={status}
    />
  )
}
```

- [ ] **Step 2: Create status-badge.tsx**

```tsx
import { cn } from '@/lib/utils'

type BadgeStatus = 'live' | 'detached' | 'exited' | 'expired' | 'online' | 'offline'

const styleMap: Record<BadgeStatus, string> = {
  live: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/30',
  detached: 'bg-amber-500/10 text-amber-500 border-amber-500/30',
  exited: 'bg-red-500/10 text-red-500 border-red-500/30',
  expired: 'bg-zinc-500/10 text-zinc-400 border-zinc-500/30',
  online: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/30',
  offline: 'bg-zinc-500/10 text-zinc-400 border-zinc-500/30',
}

interface StatusBadgeProps {
  status: BadgeStatus
  label: string
  className?: string
}

export function StatusBadge({ status, label, className }: StatusBadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5 text-xs font-medium',
        styleMap[status],
        className
      )}
    >
      {label}
    </span>
  )
}
```

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/components/shared/
git commit -m "feat: add StatusDot and StatusBadge shared components"
```

---

## Phase 4: Feature Pages

### Task 7: Refactor session list page — add delete action and status filters

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/features/sessions/session-list-page.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/services/console-api.ts`

- [ ] **Step 1: Add deleteSession method to console-api.ts**

Add to the `ConsoleApi` interface and implementation:

```typescript
// In ConsoleApi interface:
deleteSession(sessionId: string): Promise<void>

// In createConsoleApi implementation:
async deleteSession(sessionId: string) {
  const res = await fetchFn(`${baseUrl}/api/me/sessions/${sessionId}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${getToken()}` },
  })
  if (!res.ok) throw await mapError(res)
}
```

- [ ] **Step 2: Update session-list-page.tsx**

Add status filter tabs (All/Live/Detached/Exited), add delete column with trash icon button, add `ConfirmDialog` for delete confirmation. Only enable delete for `detached`, `exited`, `expired` statuses. Use `useTranslation` for i18n strings. Import `StatusDot` and `StatusBadge` from shared components.

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/sessions/session-list-page.tsx \
  src/Gateway/CortexTerminal.Console/src/services/console-api.ts
git commit -m "feat: add session delete action and status filters to session list"
```

### Task 8: Refactor session detail — remove top bar, add bottom bar, add fullscreen

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/terminal/terminal-view.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/terminal/terminal-viewport.tsx`
- Create: `src/Gateway/CortexTerminal.Console/src/terminal/terminal-status-bar.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/sessions/session-detail-page.tsx`

- [ ] **Step 1: Create terminal-status-bar.tsx**

A compact 36px bottom bar with:
- Left: `<StatusDot>` + status text + session ID (short) + Worker ID
- Center: Latency value + PTY dimensions
- Right: Fullscreen toggle button (Maximize2 icon from lucide)

Props: `{ status, sessionId, workerId, latencyMs, cols, rows, isFullscreen, onToggleFullscreen }`

- [ ] **Step 2: Update terminal-view.tsx**

Remove the `TerminalHeaderActions` import/rendering. Add fullscreen state (`useState<boolean>`). Add `onToggleFullscreen` callback. Render `TerminalStatusBar` below `TerminalViewport`. Wrap in a flex column that takes full height. When fullscreen is true, add CSS class to hide the sidebar and top bar (use `document.documentElement.classList.add('terminal-fullscreen')`).

- [ ] **Step 3: Update session-detail-page.tsx**

Simplify to just render the terminal view without any extra info card above it. The page should be a simple flex container that gives the terminal all available space:

```tsx
export function SessionDetailPage() {
  const { sessionId } = Route.useParams()
  return (
    <div className="flex h-full flex-col">
      <TerminalView sessionId={sessionId} />
    </div>
  )
}
```

- [ ] **Step 4: Add fullscreen CSS**

Add to `styles/index.css`:

```css
html.terminal-fullscreen .sidebar-container,
html.terminal-fullscreen header,
html.terminal-fullscreen .terminal-status-bar {
  display: none !important;
}
html.terminal-fullscreen #root > div {
  height: 100vh;
}
```

- [ ] **Step 5: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/terminal/ \
  src/Gateway/CortexTerminal.Console/src/features/sessions/session-detail-page.tsx \
  src/Gateway/CortexTerminal.Console/src/styles/index.css
git commit -m "feat: add terminal bottom status bar and fullscreen mode"
```

### Task 9: Create Dashboard page

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/features/dashboard/index.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/services/console-api.ts`

- [ ] **Step 1: Add dashboard stats endpoint to console-api.ts**

Add to the API client:

```typescript
interface DashboardStats {
  activeSessions: number
  detachedSessions: number
  onlineWorkers: number
  systemUptime: number
}

// In ConsoleApi interface:
getDashboardStats(): Promise<DashboardStats>
```

Implementation calls `GET /api/stats/dashboard`. If the endpoint doesn't exist yet, add a fallback that computes stats from `listSessions()` and `listWorkers()`.

- [ ] **Step 2: Rewrite dashboard/index.tsx**

Replace the existing shadcn-admin dashboard (analytics chart, recent sales) with CortexTerminal dashboard:
- 4 stat cards in a responsive grid (Active Sessions, Detached Sessions, Online Workers, Uptime)
- Recent Sessions table (reuse session row component, last 5)
- Worker Status cards grid

Use `@tanstack/react-query` for data fetching. Use `useTranslation` for i18n.

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/dashboard/ \
  src/Gateway/CortexTerminal.Console/src/services/console-api.ts
git commit -m "feat: create CortexTerminal dashboard with stats and recent sessions"
```

### Task 10: Create Worker feature (list + detail)

**Files:**
- Create: `src/Gateway/CortexTerminal.Console/src/features/workers/index.tsx`
- Create: `src/Gateway/CortexTerminal.Console/src/features/workers/worker-detail-page.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/services/console-api.ts`

- [ ] **Step 1: Add worker types and API methods to console-api.ts**

```typescript
interface WorkerSummary {
  workerId: string
  name?: string
  address?: string
  isOnline: boolean
  sessionCount: number
  connectedAt?: string
}

interface WorkerDetail extends WorkerSummary {
  sessions: SessionSummary[]
}

// Add to ConsoleApi:
listWorkers(): Promise<WorkerSummary[]>
getWorker(workerId: string): Promise<WorkerDetail>
```

Implementation: `GET /api/me/workers` and `GET /api/me/workers/:id`.

- [ ] **Step 2: Create worker list page `features/workers/index.tsx`**

Table with columns: Status dot, Worker ID, Address, Session count, Uptime. Rows clickable → navigate to `/workers/$workerId`. Use `StatusDot`, `StatusBadge`, `useTranslation`.

- [ ] **Step 3: Create worker detail page `features/workers/worker-detail-page.tsx`**

Top: Worker info card (ID, status badge, address, connected time). Below: "Sessions on this Worker" table reusing the session row pattern from session list.

- [ ] **Step 4: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/workers/ \
  src/Gateway/CortexTerminal.Console/src/services/console-api.ts
git commit -m "feat: add Worker list and detail pages"
```

### Task 11: Refactor Users feature

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/features/users/index.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/services/console-api.ts`

- [ ] **Step 1: Add user management API methods to console-api.ts**

```typescript
interface UserSummary {
  id: string
  name: string
  email: string
  role: 'admin' | 'user'
  status: 'active' | 'disabled'
  avatarUrl?: string
}

// Add to ConsoleApi:
listUsers(): Promise<UserSummary[]>
inviteUser(email: string, role: string): Promise<UserSummary>
updateUser(userId: string, updates: Partial<Pick<UserSummary, 'role' | 'status'>>): Promise<void>
deleteUser(userId: string): Promise<void>
```

- [ ] **Step 2: Refactor users/index.tsx**

Replace the existing demo data with API-backed user list. Add role/status filter dropdowns. Keep existing table structure but adapt columns to: Avatar, Name, Email, Role badge, Actions (kebab menu with Edit Role, Disable/Enable, Delete). Add `[+ Invite]` button with invite dialog.

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/users/ \
  src/Gateway/CortexTerminal.Console/src/services/console-api.ts
git commit -m "feat: refactor Users page with API integration"
```

### Task 12: Refactor Settings page

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/features/settings/index.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/settings/profile/index.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/settings/appearance/index.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/routes/_authenticated/settings/route.tsx`

- [ ] **Step 1: Update settings sidebar navigation**

In `features/settings/components/sidebar-nav.tsx`, update the nav items to match spec: Profile, General (replacing account/appearance/display/notifications).

- [ ] **Step 2: Update General settings panel**

Update the appearance settings page to become "General" with: Language selector (dropdown with EN/中文) and Theme toggle (Light/Dark/System). Use `useTranslation` for language switching.

- [ ] **Step 3: Simplify Profile settings**

Keep profile form with display name and avatar. Remove form fields not relevant to CortexTerminal.

- [ ] **Step 4: Update settings routes**

Update `settings/route.tsx` to remove old sub-routes and add new ones. Keep `settings/index.tsx` redirecting to profile.

- [ ] **Step 5: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/settings/ \
  src/Gateway/CortexTerminal.Console/src/routes/_authenticated/settings/
git commit -m "feat: refactor Settings with Profile and General panels"
```

### Task 13: Create Audit Log page

**Files:**
- Create: `src/Gateway/CortexTerminal.Console/src/features/audit-log/index.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/services/console-api.ts`

- [ ] **Step 1: Add audit log types and API to console-api.ts**

```typescript
interface AuditLogEntry {
  id: string
  timestamp: string
  userId: string
  userName: string
  action: string
  targetEntity: string
  targetId: string
}

interface AuditLogResponse {
  entries: AuditLogEntry[]
  totalCount: number
}

// Add to ConsoleApi:
getAuditLog(params: { page?: number; pageSize?: number; actionType?: string; userId?: string; fromDate?: string; toDate?: string }): Promise<AuditLogResponse>
```

- [ ] **Step 2: Create audit-log/index.tsx**

Filter bar with date range picker, action type dropdown, user dropdown. Table with columns: Timestamp, User, Action, Target. Pagination at bottom. Use `DataTable` component, `useTranslation`.

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/audit-log/ \
  src/Gateway/CortexTerminal.Console/src/services/console-api.ts
git commit -m "feat: add Audit Log page with filters and pagination"
```

---

## Phase 5: Auth Refactoring

### Task 14: Update sign-in page for OAuth/SSO + Dev Login

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/features/auth/sign-in/index.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/auth/sign-in/components/user-auth-form.tsx`

- [ ] **Step 1: Update user-auth-form.tsx**

Add OAuth buttons (GitHub, Google) as the primary sign-in method above the divider. Keep the existing username-only dev login form below an "or" divider. Add an environment check: if `import.meta.env.VITE_AUTH_MODE === 'dev'`, show the dev login form; otherwise hide it.

```tsx
{/* OAuth buttons */}
<div className="grid gap-3">
  <Button variant="outline" onClick={() => handleOAuth('github')}>
    <GithubIcon className="mr-2 h-4 w-4" />
    {t('auth.signInWith', { provider: 'GitHub' })}
  </Button>
  <Button variant="outline" onClick={() => handleOAuth('google')}>
    <GoogleIcon className="mr-2 h-4 w-4" />
    {t('auth.signInWith', { provider: 'Google' })}
  </Button>
</div>

<div className="relative my-4">
  <div className="absolute inset-0 flex items-center">
    <span className="w-full border-t" />
  </div>
  <div className="relative flex justify-center text-xs uppercase">
    <span className="bg-background px-2 text-muted-foreground">
      {t('auth.or')}
    </span>
  </div>
</div>

{/* Dev login (only in dev mode) */}
{import.meta.env.VITE_AUTH_MODE === 'dev' && (
  <form onSubmit={handleDevLogin}>
    <Input placeholder={t('auth.username')} ... />
    <Button type="submit">{t('auth.signIn')}</Button>
  </form>
)}
```

- [ ] **Step 2: Add `.env.example` update**

Update `.env.example`:
```
VITE_AUTH_MODE=dev
```

- [ ] **Step 3: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/auth/ \
  src/Gateway/CortexTerminal.Console/.env.example
git commit -m "feat: add OAuth/SSO buttons to sign-in page, keep dev login as fallback"
```

---

## Phase 6: Error Pages

### Task 15: Update error pages with CortexTerminal branding

**Files:**
- Modify: `src/Gateway/CortexTerminal.Console/src/features/errors/general-error.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/errors/not-found-error.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/errors/unauthorized-error.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/errors/forbidden-error.tsx`
- Modify: `src/Gateway/CortexTerminal.Console/src/features/errors/maintenance-error.tsx`

- [ ] **Step 1: Update each error page**

Replace any "Shadcn Admin" references with "CortexTerminal". Update the "Go to Dashboard" link to point to `/dashboard` instead of `/`. Use `useTranslation` for error messages.

- [ ] **Step 2: Commit**

```bash
git add src/Gateway/CortexTerminal.Console/src/features/errors/
git commit -m "chore: update error pages with CortexTerminal branding"
```

---

## Phase 7: Final Integration & Build

### Task 16: Full build and verification

**Files:**
- All modified files

- [ ] **Step 1: Run TypeScript check**

```bash
cd src/Gateway/CortexTerminal.Console && pnpm tsc -b
```

Expected: No type errors. Fix any remaining issues.

- [ ] **Step 2: Run tests**

```bash
cd src/Gateway/CortexTerminal.Console && pnpm test
```

Expected: All existing tests pass. Fix any broken tests from refactoring.

- [ ] **Step 3: Run lint**

```bash
cd src/Gateway/CortexTerminal.Console && pnpm lint
```

Expected: No lint errors. Fix any issues.

- [ ] **Step 4: Production build**

```bash
cd src/Gateway/CortexTerminal.Console && pnpm build
```

Expected: Build succeeds. Output goes to `../CortexTerminal.Gateway/wwwroot/` with new assets.

- [ ] **Step 5: Verify build output**

```bash
ls -la src/Gateway/CortexTerminal.Gateway/wwwroot/assets/ | head -20
```

Expected: New JS/CSS bundles are generated with new hashes. Old shadcn-admin assets are replaced.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete Gateway frontend redesign with CortexTerminal management platform"
```
