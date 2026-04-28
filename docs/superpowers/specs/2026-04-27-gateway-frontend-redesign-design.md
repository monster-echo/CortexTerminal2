# Gateway Frontend Redesign - Design Spec

## Overview

Replace the current Shadcn Admin template in `src/Gateway/CortexTerminal.Gateway/wwwroot/` with a purpose-built CortexTerminal management platform. The new UI preserves the existing Shadcn Admin design system (oklch colors, Inter/Manrope fonts, shadcn/ui components, sidebar layout) and adds CortexTerminal-specific brand customization and functional pages.

## Requirements

- **Scope**: Full management platform (terminal sessions + worker management + user management + system settings + audit log)
- **Visual style**: Modern SaaS Dark (Vercel/Railway feel), built on existing Shadcn Admin design system
- **Tech stack**: React + shadcn/ui + Tailwind CSS (Vite build)
- **Auth**: OAuth/SSO primary, Dev Login secondary (dev-only)
- **Layout**: Sidebar navigation + top bar
- **i18n**: Multi-language support, default English
- **Generation tool**: Stitch (sp_flow for multi-page generation)

## Design System

### Preserved from Shadcn Admin

- oklch color space with `.dark` class theme switching
- Light + Dark dual theme
- Inter (body) + Manrope (headings) fonts
- shadcn/ui component library (Radix-based)
- Collapsible sidebar (full 240px / icon-only 64px)
- Border radius: 0.625rem
- Tailwind CSS v4 utility classes

### Brand Customization

| Token | Value | Purpose |
|-------|-------|---------|
| `--primary` (dark) | `oklch(62% .24 265)` (indigo) | Brand accent replacing default zinc |
| `--primary` (light) | `oklch(55% .24 265)` (indigo) | Brand accent in light mode |
| Terminal BG | `#0a0a0a` | Deeper black for terminal viewport |
| Terminal font | JetBrains Mono, 14px | xterm.js monospace font |
| Status: live | emerald-500 | Active session indicator |
| Status: detached | amber-500 | Grace-period session indicator |
| Status: exited | red-500 | Terminated session indicator |
| Status: online | emerald-500 | Worker online indicator |
| Status: offline | zinc-400 | Worker offline indicator |

### Layout Constants

| Element | Value |
|---------|-------|
| Sidebar width | 240px (expanded), 64px (collapsed) |
| Top bar height | 56px |
| Content max-width | none (fluid) |
| Terminal bottom bar height | 36px |
| Card padding | 24px |
| Page padding | 24px |

## Page Map & Routes

```
/                          -> redirect to /dashboard
/login                     -> OAuth/SSO login page

--- Authenticated layout (sidebar + topbar) ---

/dashboard                 -> Dashboard overview
/sessions                  -> Session list
/sessions/:id              -> Session detail (xterm.js live terminal)
/workers                   -> Worker list
/workers/:id               -> Worker detail
/users                     -> User management list
/users/:id                 -> User detail/edit
/settings                  -> Settings (redirect to /settings/profile)
/settings/profile          -> Profile settings
/settings/general          -> General settings (language, theme)
/audit-log                 -> Audit log

--- Error pages ---

/401, /403, /404, /500     -> Error pages
```

### Sidebar Navigation

| Group | Item | Icon | Route |
|-------|------|------|-------|
| Overview | Dashboard | LayoutDashboard | `/dashboard` |
| Terminal | Sessions | Terminal | `/sessions` |
| Infrastructure | Workers | Server | `/workers` |
| Admin | Users | Users | `/users` |
| System | Settings | Settings | `/settings` |
| System | Audit Log | FileText | `/audit-log` |

### Top Bar

- Left: Breadcrumb navigation
- Right: Language switcher (EN/中文), notification bell, user avatar dropdown (Profile / Sign Out)

## Page Designs

### 1. Login (`/login`)

Centered card layout on branded background. Two auth methods:

1. **OAuth buttons** (primary): GitHub, Google sign-in buttons
2. **Dev Login** (secondary, dev env only): username input + sign-in button, separated by "or" divider

- Supports `?redirect=` query param for post-login redirect
- Shows CortexTerminal logo and tagline "Sign in to continue"
- Footer links: Terms of Service, Privacy Policy

### 2. Dashboard (`/dashboard`)

Four stat cards in a grid:
- Active Sessions (count, emerald accent)
- Detached Sessions (count, amber accent)
- Online Workers (count, emerald accent)
- System Uptime (percentage, blue accent)

Below stats:
- **Recent Sessions** table (last 5 sessions): ID, Worker, Status badge, Created time, click to navigate
- **Worker Status** cards: 2-column grid showing worker ID, online status, session count

### 3. Session List (`/sessions`)

Header: "Sessions" title + `[+ New Session]` button (opens modal to select worker + dimensions).

Filter bar: status dropdown (All/Live/Detached/Exited) + search input.

Table columns:
- Status indicator (dot: emerald/amber/red)
- Session ID (truncated)
- Worker ID
- Status badge (Live/Detached/Exited)
- Dimensions (cols x rows)
- Created time (relative)
- **Delete button** (trash icon): only enabled for Detached/Exited sessions. Click shows confirmation Dialog.

Pagination at bottom.

### 4. Session Detail / Terminal (`/sessions/:id`)

**No top info bar.** The page is maximized for terminal content.

Layout:
- xterm.js terminal fills all available vertical space between top bar and bottom bar
- Terminal uses deeper black background (#0a0a0a) vs page background
- JetBrains Mono 14px, xterm-256color

**Bottom bar** (36px, compact):
- Left: status dot + status text + session ID (short) + Worker ID
- Center: Latency probe value (e.g., "12ms") + PTY dimensions (e.g., "120x40")
- Right: **Fullscreen button** (expand icon)

**Fullscreen mode**:
- Hides sidebar + bottom bar
- Terminal fills entire browser viewport
- Press `Esc` to exit fullscreen
- Floating minimal status indicator in corner (status dot only)

### 5. Worker List (`/workers`)

Table/list of registered workers:
- Status indicator (emerald dot = online, zinc dot = offline)
- Worker ID
- Address (IP/hostname)
- Active session count
- Uptime (relative)

Rows are clickable, navigate to `/workers/:id`.

### 6. Worker Detail (`/workers/:id`)

Top: Worker info card showing ID, status badge, address, uptime.

Below: "Sessions on this Worker" section reusing the session list row component. Shows all sessions (active and historical) for this worker.

### 7. User Management (`/users`)

Header: "User Management" + `[+ Invite]` button (opens invite dialog).

Filter bar: search input + Role dropdown (All/Admin/User) + Status dropdown (All/Active/Disabled).

Table columns:
- Avatar (initials or image)
- Name
- Email
- Role badge (Admin/User)
- Actions menu (kebab `⋮`): Edit role, Disable/Enable, Delete

### 8. Settings (`/settings`)

Split layout: left sub-nav + right content panel.

Sub-nav items:
- **Profile** (default): Avatar upload, display name, email (read-only from OAuth), Security section (change password, active sessions list), Danger zone (delete account)
- **General**: Language selector (English/中文), Theme toggle (Light/Dark/System)

### 9. Audit Log (`/audit-log`)

Filter bar: date range picker + action type dropdown + user dropdown.

Table (chronological, newest first):
- Timestamp
- User
- Action type
- Target entity (session ID, worker ID, etc.)

Action types: `session.create`, `session.close`, `session.detach`, `session.reattach`, `session.expire`, `session.delete`, `worker.register`, `worker.unregister`, `user.login`, `user.invite`, `user.update`, `user.disable`

Pagination at bottom.

### 10. Error Pages

Unified error page component with:
- Error code (401/403/404/500) as large text
- Description message
- "Go to Dashboard" button
- Illustration or icon

## Component Inventory

### Shared Components

| Component | Used By |
|-----------|---------|
| `AppLayout` | All authenticated pages |
| `Sidebar` | AppLayout |
| `TopBar` | AppLayout |
| `Breadcrumb` | TopBar |
| `UserMenu` | TopBar |
| `LanguageSwitcher` | TopBar |
| `StatusBadge` | Sessions, Workers |
| `StatusDot` | Sessions, Workers, Audit Log |
| `SessionRow` | Session List, Worker Detail, Dashboard |
| `WorkerCard` | Worker List, Dashboard |
| `DataTable` | Sessions, Users, Audit Log |
| `ConfirmDialog` | Session delete, User actions |
| `CreateSessionModal` | Session List, Dashboard |
| `TerminalViewport` | Session Detail |
| `TerminalStatusBar` | Session Detail |

### Page Components

| Page | Component |
|------|-----------|
| Login | `LoginPage` |
| Dashboard | `DashboardPage`, `StatCard`, `RecentSessionsTable`, `WorkerStatusGrid` |
| Sessions | `SessionListPage`, `SessionTable`, `SessionFilters`, `CreateSessionModal` |
| Session Detail | `SessionDetailPage`, `TerminalViewport`, `TerminalStatusBar` |
| Workers | `WorkerListPage`, `WorkerTable` |
| Worker Detail | `WorkerDetailPage`, `WorkerInfoCard`, `WorkerSessionsTable` |
| Users | `UserManagementPage`, `UserTable`, `InviteUserDialog` |
| User Detail | `UserDetailPage`, `UserForm` |
| Settings | `SettingsPage`, `ProfilePanel`, `GeneralPanel` |
| Audit Log | `AuditLogPage`, `AuditLogTable`, `AuditFilters` |
| Errors | `ErrorPage` |

## API Integration

### REST Endpoints (existing)

| Method | Endpoint | Used By |
|--------|----------|---------|
| POST | `/api/dev/login` | Login |
| POST | `/api/auth/device-flow` | Auth (future) |
| POST | `/api/sessions` | CreateSessionModal |
| GET | `/api/me/sessions` | Session List, Dashboard |
| GET | `/api/me/sessions/:id` | Session Detail |
| GET | `/api/me/workers` | Worker List, Dashboard |
| GET | `/api/me/workers/:id` | Worker Detail |

### REST Endpoints (new, needed)

| Method | Endpoint | Purpose |
|--------|----------|---------|
| DELETE | `/api/me/sessions/:id` | Delete session (detached/exited only) |
| GET | `/api/me` | Current user profile |
| PATCH | `/api/me` | Update profile |
| GET | `/api/users` | User list (admin) |
| POST | `/api/users/invite` | Invite user |
| PATCH | `/api/users/:id` | Update user role/status |
| DELETE | `/api/users/:id` | Delete user |
| GET | `/api/audit-log` | Audit log entries |
| GET | `/api/stats/dashboard` | Dashboard aggregated stats |

### SignalR Hub (existing, `/hubs/terminal`)

| Method | Used By |
|--------|---------|
| `CreateSession` | CreateSessionModal |
| `WriteInput` | TerminalViewport |
| `ResizeSession` | TerminalViewport (auto-resize) |
| `ReattachSession` | TerminalViewport (reconnect) |
| `DetachSession` | TerminalStatusBar |
| `CloseSession` | TerminalStatusBar |
| `ProbeLatency` | TerminalStatusBar |

## i18n Strategy

- Library: `react-i18next`
- Default locale: `en`
- Supported locales: `en`, `zh`
- Translation files: `src/locales/en.json`, `src/locales/zh.json`
- Language detection: stored preference > browser language > default
- All user-facing strings externalized; component names, route paths, API keys remain in English

## Stitch Generation Plan

Batch pages into 3 Stitch flows:

**Batch 1 - Auth + Core Terminal** (5 screens):
1. Login page
2. Dashboard
3. Session list
4. Session detail (terminal viewport placeholder)
5. Error page

**Batch 2 - Infrastructure + Admin** (5 screens):
6. Worker list
7. Worker detail
8. User management
9. User detail
10. Settings

**Batch 3 - System** (2 screens):
11. Audit log
12. Settings general panel

Each batch uses `sp_flow` with `framework: react`, `componentLibrary: shadcn`, `deviceType: DESKTOP`, and the CortexTerminal design system.

## File Structure

```
src/Gateway/CortexTerminal.Gateway/wwwroot/
  index.html
  assets/                          <- Vite build output
  images/                          <- Static images (favicon, logo)

src/Gateway/CortexTerminal.Console/
  src/
    main.tsx
    App.tsx
    routes.tsx
    locales/
      en.json
      zh.json
    components/
      layout/
        AppLayout.tsx
        Sidebar.tsx
        TopBar.tsx
        Breadcrumb.tsx
        UserMenu.tsx
        LanguageSwitcher.tsx
      shared/
        StatusBadge.tsx
        StatusDot.tsx
        SessionRow.tsx
        WorkerCard.tsx
        DataTable.tsx
        ConfirmDialog.tsx
        CreateSessionModal.tsx
      terminal/
        TerminalViewport.tsx
        TerminalStatusBar.tsx
        createBrowserTerminal.ts
        useTerminalSession.ts
    pages/
      LoginPage.tsx
      DashboardPage.tsx
      SessionListPage.tsx
      SessionDetailPage.tsx
      WorkerListPage.tsx
      WorkerDetailPage.tsx
      UserManagementPage.tsx
      UserDetailPage.tsx
      SettingsPage.tsx
      AuditLogPage.tsx
      ErrorPage.tsx
    services/
      consoleApi.ts
      terminalGateway.ts
      authStore.ts
    hooks/
      useAuth.ts
      useSessions.ts
      useWorkers.ts
      useUsers.ts
      useAuditLog.ts
    lib/
      utils.ts
      i18n.ts
  index.html
  vite.config.ts
  tailwind.config.ts
  tsconfig.json
  package.json
```

Note: The Console project directory (`src/Gateway/CortexTerminal.Console/`) already exists in the repo as an untracked directory. Source code lives there; Vite builds to `wwwroot/`.
