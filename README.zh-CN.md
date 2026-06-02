# Corterm

**远程终端，触手可及。**

[English](README.md)

[![CI](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml)
[![Gateway Package](https://img.shields.io/badge/ghcr.io-corterm--gateway-blue?logo=docker)](https://github.com/monster-echo/CortexTerminal2/pkgs/container/corterm-gateway)
[![Worker Release](https://img.shields.io/github/v/release/monster-echo/CortexTerminal2?label=worker&logo=github)](https://github.com/monster-echo/CortexTerminal2/releases)

Corterm 是一个自托管的远程终端平台。在任意机器上安装轻量级 Worker，部署 Gateway，即可通过浏览器或手机访问终端——关掉页面，Shell 依然在后台运行。

## 架构

```
浏览器  ──►  Gateway  ──►  Worker
 (UI)         (认证,         (伪终端,
               路由,          Shell
               会话)          执行)
```

- **Gateway** -- 中心服务器，负责认证、会话路由和实时通信。
- **Worker** -- 轻量级代理，运行在被管理机器上，负责 PTY 会话管理和 I/O 流转发。
- **Console** -- 浏览器终端界面，同时提供 iOS 和 Android 原生客户端。

## 功能

- **浏览器原生终端** -- 基于 xterm.js + WebGL 渲染的完整终端，桌面、平板、手机通用。
- **会话持久化** -- 随时断开和重连，Shell 持续运行，重连时自动回放历史输出。
- **多机管理** -- 单个 Gateway 连接和管理任意数量的远程机器。
- **移动端支持** -- iOS / Android 原生应用，内置终端虚拟键盘、触觉反馈和自适应布局。
- **多种登录方式** -- 密码、手机短信、GitHub OAuth、Google OAuth、Apple Sign-In。
- **Worker 管理** -- 监控状态、远程升级、诊断检查（`corterm doctor`）。
- **管理后台** -- 用户管理、邀请、角色权限、审计日志。
- **自托管 & Docker 一键部署** -- 无云依赖，数据完全在你的基础设施上。

## 快速开始

### 1. 部署 Gateway

```bash
docker run -p 5045:5045 ghcr.io/monster-echo/corterm-gateway:latest
```

### 2. 安装 Worker

**Linux / macOS：**

```bash
curl -fsSL https://corterm.rwecho.top/install.sh | sh
```

**Windows (PowerShell)：**

```powershell
powershell -Command "irm https://corterm.rwecho.top/install.ps1 | iex"
```

### 3. 打开浏览器

访问 `http://localhost:5045`，登录后即可开启终端会话。

## 平台支持

**Worker：** Linux (amd64 / arm64) · macOS (Apple Silicon) · Windows x64 · Docker

**客户端：** 任意现代浏览器 · iOS · Android

### 移动端下载

<a href="https://play.google.com/store/apps/details?id=top.rwecho.cortexterminal">
  <img src="https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=https://play.google.com/store/apps/details?id=top.rwecho.cortexterminal" width="120" height="120" alt="Get it on Google Play" /><br/>
  Google Play 获取
</a>

## 技术栈

.NET 10 (Gateway / Worker) · React 19 + xterm.js (Console) · .NET MAUI + Ionic (Mobile) · SignalR + MessagePack

## Roadmap

- [ ] **文件传输** -- 在终端会话中直接上传和下载文件
- [ ] **端口转发** -- 通过 Gateway 将本地端口隧道转发到远程机器
- [ ] **结构化输出** -- 将常见命令输出（`top`、`ps`、`docker ps`）渲染为可交互的卡片
- [ ] **多标签终端** -- 在单个浏览器标签页中打开多个会话
- [ ] **命令片段** -- 保存并复用常用命令

## 许可证

[MIT](LICENSE)
