# CortexTerminal

**远程终端，触手可及。**

[English](README.md)

[![CI](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml)
[![Gateway Docker](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gateway-docker.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gateway-docker.yml)
[![Worker Release](https://github.com/monster-echo/CortexTerminal2/actions/workflows/worker-release.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/worker-release.yml)
[![GitHub Pages](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gh-pages.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/gh-pages.yml)
[![Gateway Package](https://img.shields.io/badge/ghcr.io-cortexterminal--gateway-blue?logo=docker)](https://github.com/monster-echo/CortexTerminal2/pkgs/container/cortexterminal-gateway)
[![Worker Release](https://img.shields.io/github/v/release/monster-echo/CortexTerminal2?label=worker&logo=github)](https://github.com/monster-echo/CortexTerminal2/releases)

CortexTerminal 将你的机器连接到浏览器终端。在任何机器上运行 Worker，通过 Gateway 访问——随时随地，任意设备。

## 架构

```
浏览器  -->  Gateway  -->  Worker
 (UI)       (认证 ·        (伪终端 ·
             路由 ·         Shell
             会话)          执行)
```

- **Gateway** -- ASP.NET Core 后端，负责 JWT 认证、会话路由，以及基于 SignalR + MessagePack 的实时通信。
- **Worker** -- .NET CLI 代理，运行在你的机器上，管理 PTY 会话，通过 SignalR 连接到 Gateway。
- **Console** -- React SPA（Vite + TanStack Router + xterm.js），由 Gateway 提供服务，提供浏览器终端界面。

## 功能

- **浏览器原生终端** -- 基于 xterm.js 的完整终端。支持桌面、平板和手机。
- **JWT 认证** -- 内置令牌认证。支持 Device Flow 安全的机器对机器访问。
- **SignalR 实时通信** -- 基于 WebSocket 的双向流，使用 MessagePack 压缩实现极低延迟。
- **自托管部署** -- 运行你自己的 Gateway 和 Worker。无云依赖，数据完全由你掌控。
- **会话持久化** -- 支持分离和重连会话。关闭浏览器后 Shell 仍然在运行。
- **Docker 就绪** -- Gateway 以容器镜像发布在 GHCR。几秒内部署到任意 Docker 主机。

## 快速开始

### 1. 安装 Worker

**Linux / macOS：**

```bash
curl -fsSL https://gateway.ct.rwecho.top/install.sh | sh
```

**Windows (PowerShell)：**

```powershell
powershell -Command "irm https://gateway.ct.rwecho.top/install.ps1 | iex"
```

支持平台：`linux/amd64`、`linux/arm64`、`macOS (Apple Silicon)`、`Windows x64`、`Docker`

### 2. 部署 Gateway

```bash
docker run -p 5045:5045 ghcr.io/monster-echo/cortexterminal-gateway:latest
```

### 3. 打开浏览器

访问 `http://localhost:5045`，登录后即可使用终端。

## 项目结构

```
src/
  Gateway/
    CortexTerminal.Gateway/    # ASP.NET Core 后端
    CortexTerminal.Console/    # React SPA（Vite + TanStack Router）
  Worker/
    CortexTerminal.Worker/     # .NET CLI 代理
  Shared/
    CortexTerminal.Contracts/  # 共享 SignalR 契约
  Mobile/
    CortexTerminal.Mobile/     # 移动端 Web 客户端
landing/
  index.html                   # 产品首页（GitHub Pages）
  install.sh                   # Worker 安装脚本
```

## 技术栈

| 组件 | 技术 |
|------|------|
| Gateway | .NET 10、ASP.NET Core、EF Core + PostgreSQL |
| Worker | .NET 10、SignalR 客户端 |
| Console | React 19、Vite、TanStack Router、xterm.js、i18next |
| 通信 | SignalR + MessagePack over WebSockets |
| 认证 | JWT Bearer + Device Flow |

## 许可证

[MIT](LICENSE)
