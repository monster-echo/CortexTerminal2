# CortexTerminal

**Remote Terminals, Everywhere.**

[简体中文](README.zh-CN.md)

[![CI](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml)
[![Gateway Docker](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gateway-docker.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gateway-docker.yml)
[![Worker Release](https://github.com/monster-echo/CortexTerminal2/actions/workflows/worker-release.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/worker-release.yml)
[![GitHub Pages](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gh-pages.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gh-pages.yml)
[![Gateway Package](https://img.shields.io/badge/ghcr.io-cortexterminal--gateway-blue?logo=docker)](https://github.com/monster-echo/CortexTerminal2/pkgs/container/cortexterminal-gateway)
[![Worker Release](https://img.shields.io/github/v/release/monster-echo/CortexTerminal2?label=worker&logo=github)](https://github.com/monster-echo/CortexTerminal2/releases)

CortexTerminal connects your machines to a browser-based terminal. Run a Worker on any machine, access it through the Gateway -- from anywhere, on any device.

## Architecture

```
Browser  -->  Gateway  -->  Worker
 (UI)        (Auth ·        (PTY ·
              Routing ·      Shell
              Sessions)      Execution)
```

- **Gateway** -- ASP.NET Core backend that handles JWT authentication, session routing, and SignalR real-time communication with MessagePack.
- **Worker** -- .NET CLI agent that runs on your machines, manages PTY sessions, and connects to the Gateway via SignalR.
- **Console** -- React SPA (Vite + TanStack Router + xterm.js) served by the Gateway, providing the browser-based terminal UI.

## Features

- **Browser-Native Terminal** -- Full xterm.js terminal in your browser. Works on desktop, tablet, and mobile.
- **JWT Authentication** -- Built-in token-based auth with device flow support for secure machine-to-machine access.
- **SignalR Real-Time** -- Bidirectional streaming over WebSockets with MessagePack for minimal latency.
- **Self-Hosted** -- Run your own Gateway and Workers. No cloud dependency. Your data stays yours.
- **Session Persistence** -- Detach and reattach to sessions. Your shell keeps running even if you close the browser.
- **Docker Ready** -- Gateway ships as a container image on GHCR. Deploy to any Docker host in seconds.

## Quick Start

### 1. Install the Worker

**Linux / macOS:**

```bash
curl -fsSL https://gateway.ct.rwecho.top/install.sh | sh
```

**Windows (PowerShell):**

```powershell
powershell -Command "irm https://gateway.ct.rwecho.top/install.ps1 | iex"
```

Supported platforms: `linux/amd64`, `linux/arm64`, `macOS (Apple Silicon)`, `Windows x64`, `Docker`

### 2. Deploy the Gateway

```bash
docker run -p 5045:5045 ghcr.io/monster-echo/cortexterminal-gateway:latest
```

### 3. Open Your Browser

Navigate to `http://localhost:5045`, log in, and your terminal is ready.

## Project Structure

```
src/
  Gateway/
    CortexTerminal.Gateway/    # ASP.NET Core backend
    CortexTerminal.Console/    # React SPA (Vite + TanStack Router)
  Worker/
    CortexTerminal.Worker/     # .NET CLI agent
  Shared/
    CortexTerminal.Contracts/  # Shared SignalR contracts
  Mobile/
    CortexTerminal.Mobile/     # Mobile web client
landing/
  index.html                   # Landing page (GitHub Pages)
  install.sh                   # Worker install script
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Gateway | .NET 10, ASP.NET Core, EF Core + PostgreSQL |
| Worker | .NET 10, SignalR client |
| Console | React 19, Vite, TanStack Router, xterm.js, i18next |
| Communication | SignalR + MessagePack over WebSockets |
| Auth | JWT Bearer + Device Flow |

## License

[MIT](LICENSE)
