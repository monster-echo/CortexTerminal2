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

<table>
  <tr>
    <td align="center">
      <a href="https://apps.apple.com/us/app/corterm/id6767838640">
        <img src="docs/corterm_appstore_qr.png" width="120" height="120" alt="App Store 下载" />
      </a>
      <br/>App Store
    </td>
    <td align="center">
      <a href="https://play.google.com/store/apps/details?id=top.rwecho.cortexterminal">
        <img src="docs/corterm_googleplay_qr.png" width="120" height="120" alt="Google Play 获取" />
      </a>
      <br/>Google Play
    </td>
    <td align="center">
      <a href="https://appgallery.huawei.com/app/detail?id=top.rwecho.cortexterminal">
        <img src="docs/corterm_appgallery_qr.png" width="120" height="120" alt="华为应用市场 获取" />
      </a>
      <br/>华为应用市场
    </td>
  </tr>
</table>

## 技术栈

.NET 10 (Gateway / Worker) · React 19 + xterm.js (Console) · .NET MAUI + Ionic (Mobile) · SignalR + MessagePack

## 运行测试

CI 在每次 push 时运行单元测试。本地运行：

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests --configuration Release --filter "Category!=Integration"
dotnet test tests/Worker/CortexTerminal.Worker.Tests --configuration Release --filter "Category!=Integration"
```

S3 兼容存储集成测试为可选（标记为 `Category=Integration`）。本地启动 MinIO 后再运行筛选：

```bash
bash scripts/start-test-minio.sh
dotnet test tests/Gateway --filter "Category=Integration"
```

脚本默认使用 Podman（也支持 Docker），会创建独立于生产环境的 `corterm-artifacts-test` 桶。如需自定义凭据，通过 `CORTERM_TEST_S3_*` 环境变量覆盖。

## Roadmap

- [x] **文件传输** -- Console 与 Worker 之间通过 S3 presigned URL 双向传输（详见下文）
- [ ] **端口转发** -- 通过 Gateway 将本地端口隧道转发到远程机器
- [ ] **结构化输出** -- 将常见命令输出（`top`、`ps`、`docker ps`）渲染为可交互的卡片
- [ ] **多标签终端** -- 在单个浏览器标签页中打开多个会话
- [ ] **命令片段** -- 保存并复用常用命令

## 会话文件（Session Artifacts）

每个终端会话都内置了 WeChat 文件助手风格的文件流。文件在 Console 与 Worker 之间通过 S3 兼容存储（AWS S3、MinIO、Cloudflare R2）流转。Gateway 只签发 presigned URL，从不中转文件字节 —— 托管服务的带宽完全不被文件流量影响。

**非对称自动同步：**

- Console 上传的文件会立即落到 Worker 的 `$CORTERM_ARTIFACTS_DIR` 目录里，shell（包括 Claude Code 之类的 AI agent）可以马上读到。
- Worker 输出（`echo foo > $CORTERM_ARTIFACTS_DIR/log.txt`）通过 SignalR 实时出现在你手机上的"Worker 同步"气泡里。**不会**自动下载到手机 —— 你点击气泡时才按需拉取。

**过期模型：** 每个 artifact 默认有 7 天 TTL。Session terminate 时该 session 的所有 artifact 过期时间会收紧到 24 小时宽限期。后台服务定期清理 S3 + DB。

### 配置

Gateway `appsettings.json`：

```json
"Storage": {
  "Endpoint": "https://s3.amazonaws.com",
  "Bucket": "corterm-artifacts",
  "Region": "us-east-1",
  "AccessKey": "...",
  "SecretKey": "...",
  "ForcePathStyle": false,
  "PresignedUrlTtl": "00:05:00",
  "MaxArtifactSizeBytes": 52428800,
  "MaxArtifactAgeDays": 7,
  "GracePeriodHours": 24
}
```

自托管 MinIO：

```bash
docker compose -f deploy/docker-compose.minio.yml up -d
```

然后把 `Storage:Endpoint` 指向 `http://localhost:9000`，并把 `ForcePathStyle` 设为 `true`。

### Worker 契约

PTY 进程会继承 `CORTERM_ARTIFACTS_DIR=~/.corterm/sessions/{sessionId}/artifacts/` 环境变量。Worker 自动上传写入此目录的文件，并自动下载 Console 上传的文件。**Worker 全程不持有 S3 凭证** —— 它向 Gateway 申请 presigned URL，跟 Console 完全对称。

## 许可证

[MIT](LICENSE)
