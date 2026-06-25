# Corterm

**Remote Terminals, Everywhere.**

[简体中文](README.zh-CN.md)

[![CI](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml/badge.svg)](https://github.com/monster-echo/CortexTerminal2/actions/workflows/ci.yml)
[![Gateway Package](https://img.shields.io/badge/ghcr.io-corterm--gateway-blue?logo=docker)](https://github.com/monster-echo/CortexTerminal2/pkgs/container/corterm-gateway)
[![Worker Release](https://img.shields.io/github/v/release/monster-echo/CortexTerminal2?label=worker&logo=github)](https://github.com/monster-echo/CortexTerminal2/releases)

Corterm is a self-hosted remote terminal platform. Install a lightweight Worker on any machine, deploy the Gateway, and access your terminals from any browser or mobile device -- your shell keeps running even after you close the tab.

## Architecture

```
Browser  ──►  Gateway  ──►  Worker
 (UI)          (Auth,         (PTY,
                Routing,       Shell
                Sessions)      Execution)
```

- **Gateway** -- Central server handling authentication, session routing, and real-time communication.
- **Worker** -- Lightweight agent that runs on your machines, manages PTY sessions, and streams I/O back to the Gateway.
- **Console** -- Browser-based terminal UI served by the Gateway. Also available as native iOS and Android apps.

## Features

- **Browser-Native Terminal** -- Full xterm.js terminal with WebGL rendering. Works on desktop, tablet, and mobile.
- **Session Persistence** -- Detach and reattach at any time. Your shell keeps running. Previous output is replayed on reattach.
- **Multi-Worker** -- Connect and manage any number of remote machines from a single Gateway.
- **Mobile Access** -- Native iOS and Android apps with custom terminal keyboard, haptic feedback, and responsive layout.
- **Multiple Auth Methods** -- Password, phone SMS, GitHub OAuth, Google OAuth, and Apple Sign-In.
- **Worker Management** -- Monitor worker status, trigger remote upgrades, and run diagnostics (`corterm doctor`).
- **Admin Dashboard** -- User management, invitations, role-based access, and audit logging.
- **Self-Hosted & Docker Ready** -- One command to deploy. No cloud dependency. Your data stays on your infrastructure.

## Quick Start

### 1. Deploy the Gateway

```bash
docker run -p 5045:5045 ghcr.io/monster-echo/corterm-gateway:latest
```

### 2. Install the Worker

**Linux / macOS:**

```bash
curl -fsSL https://corterm.rwecho.top/install.sh | sh
```

**Windows (PowerShell):**

```powershell
powershell -Command "irm https://corterm.rwecho.top/install.ps1 | iex"
```

### 3. Open Your Browser

Navigate to `http://localhost:5045`, log in, and start a terminal session.

## Platform Support

**Worker:** Linux (amd64 / arm64) · macOS (Apple Silicon) · Windows x64 · Docker

**Client:** Any modern browser · iOS · Android

### Mobile App Download

<table>
  <tr>
    <td align="center">
      <a href="https://apps.apple.com/us/app/corterm/id6767838640">
        <img src="docs/corterm_appstore_qr.png" width="120" height="120" alt="Download on the App Store" />
      </a>
      <br/>App Store
    </td>
    <td align="center">
      <a href="https://play.google.com/store/apps/details?id=top.rwecho.cortexterminal">
        <img src="docs/corterm_googleplay_qr.png" width="120" height="120" alt="Get it on Google Play" />
      </a>
      <br/>Google Play
    </td>
    <td align="center">
      <a href="https://appgallery.huawei.com/app/detail?id=top.rwecho.cortexterminal">
        <img src="docs/corterm_appgallery_qr.png" width="120" height="120" alt="Get it on Huawei AppGallery" />
      </a>
      <br/>AppGallery
    </td>
  </tr>
</table>

## Tech Stack

.NET 10 (Gateway / Worker) · React 19 + xterm.js (Console) · .NET MAUI + Ionic (Mobile) · SignalR + MessagePack

## Running Tests

Unit tests run on every push via CI. Run them locally:

```bash
dotnet test tests/Gateway/CortexTerminal.Gateway.Tests --configuration Release --filter "Category!=Integration"
dotnet test tests/Worker/CortexTerminal.Worker.Tests --configuration Release --filter "Category!=Integration"
```

S3-compatible storage integration tests are opt-in (tagged `Category=Integration`). Boot MinIO locally and then run the filter:

```bash
bash scripts/start-test-minio.sh
dotnet test tests/Gateway --filter "Category=Integration"
```

The script uses Podman by default (Docker works too) and provisions a `corterm-artifacts-test` bucket separate from production. Override credentials via `CORTERM_TEST_S3_*` environment variables if needed.

## Roadmap

- [x] **File Transfer** -- Bidirectional file exchange between Console and Worker via S3 presigned URLs (see below)
- [ ] **Port Forwarding** -- Tunnel local ports to remote machines via the Gateway
- [ ] **Structured Output** -- Render common command outputs (`top`, `ps`, `docker ps`) as interactive cards instead of raw text
- [ ] **Multi-tab Terminal** -- Open multiple sessions in a single browser tab
- [ ] **Command Snippets** -- Save and reuse frequently used commands across sessions

## Session Artifacts (File Transfer)

Corterm ships with a WeChat-File-Helper-style file feed for every terminal session. Files flow Console ↔ Worker through S3-compatible storage (AWS S3, MinIO, Cloudflare R2). The Gateway brokers presigned URLs and never relays file bytes -- bandwidth stays cheap on the hosted plan.

**Asymmetric sync:**

- Console uploads land in `$CORTERM_ARTIFACTS_DIR` on the Worker instantly so the shell (and AI agents like Claude Code) can read them.
- Worker outputs (`echo foo > $CORTERM_ARTIFACTS_DIR/log.txt`) appear as Worker-side bubbles in real time via SignalR. Nothing auto-downloads to your phone -- tap a bubble to fetch on demand.

**Expiration:** every artifact has a 7-day TTL. Terminating a session tightens its artifacts to a 24h grace window. A background sweep cleans S3 + DB.

### Configuration

Gateway `appsettings.json`:

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

For self-hosted MinIO:

```bash
docker compose -f deploy/docker-compose.minio.yml up -d
```

Then point `Storage:Endpoint` at `http://localhost:9000` and set `ForcePathStyle: true`.

### Worker contract

PTY processes inherit `CORTERM_ARTIFACTS_DIR=~/.corterm/sessions/{sessionId}/artifacts/`. The Worker auto-uploads files written there and auto-downloads files uploaded from the Console. **The Worker never holds S3 credentials** -- it asks the Gateway for presigned URLs, same as the Console.

## License

[MIT](LICENSE)
