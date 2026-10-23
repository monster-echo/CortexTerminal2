# Terminal startup diagnosis and recovery

## User flow

A live transport and a latency acknowledgement do not prove that the remote shell has produced output. Flutter and HarmonyOS start a 12-second watch when attaching. If first output or replay readiness is still missing, a visible inline warning offers **Diagnose** and **Reconnect**. Once a session has produced output and is live, ordinary idle time does not trigger this warning.

Diagnosis reads the owned remote session's status. It does not type commands into its PTY, restart its shell, terminate its tasks, or alter macOS permissions. The bounded directory probe runs as a separate child under the same app attribution. Paths are data, never interpolated shell code.

| Evidence | User message / next step |
| --- | --- |
| Worker has produced output | Output is available; reconnect the display if still blank |
| Directory access explicitly denied | Show the directory; on Mac, explain permissions on the remote computer |
| Directory probe times out | Explain that disk access or a system prompt may be pending; do not claim denial |
| Directory is unavailable | Ask the user to check its existence and availability |
| Directory is accessible but no shell output | Cause is unconfirmed; check shell startup configuration and system prompts |
| Worker is offline | Restore connection to the computer |
| Session no longer exists | Explain that the terminal has ended; do not silently start a replacement |
| Older Worker or diagnostic request fails | Show unavailable, allow recheck, retain permission guidance |

On macOS, review the required **Files and Folders** permissions first. If access remains blocked, grant the installed Corterm.app Full Disk Access in System Settings on the remote Mac. OS consent is manual. If macOS requests quitting the app, save other tasks before doing so. A timeout alone never confirms the Full Disk Access setting.

Desktop reads a fresh local warning feed (no terminal contents or credentials), offers diagnosis for the affected directory, opens System Settings, and reruns the check on returning to the app. Stale feed records are ignored after 15 seconds. Headless Worker mode does not start the desktop warning feed.

## API and protocol

- `GET /api/me/sessions/{id}/diagnostics`: authentication and ownership checked before contacting the Worker; other users receive 404. Current Worker connection is resolved on every call.
- Worker `DiagnoseSession` SignalR request returns `SessionDiagnosticReport`, including state, output flag, directory access result, platform, and elapsed seconds. At most two directory probes run concurrently. Each probe has a 3-second bound on POSIX and an 8-second bound on Windows (including PowerShell cold start); gateway has a 12-second bound.
- Directory access failures do not claim a specific privacy setting. No TCC database is queried or changed.
- Flutter native WebSocket advertises `resume-only`; HarmonyOS SignalR reattach requests set `ResumeOnly=true`. The coordinator rejects expired/exited shells with `session-not-running` before changing their attachment state. A display reconnect therefore cannot silently replace an ended shell.
- Existing clients retain legacy reattach behavior through the optional flag's default value.

## Rollout order

1. Deploy the Gateway first: diagnostics routing and `ResumeOnly` enforcement.
2. Ship Worker and desktop together: diagnostic handler, directory doctor option, local warning feed.
3. Ship Flutter and HarmonyOS clients.

Older Workers degrade to an explicit unavailable result. Older Gateways ignore newly appended protocol fields, so the no-replacement guarantee requires the new Gateway. Do not describe this feature as available in production before that deployment.

## Verification

Automated coverage includes no initial output despite latency acknowledgements, stalled replay, normal idle sessions, output recovery, same-session reconnect, stale socket-close races, directory path quoting, missing directories, desktop stale/corrupt feed handling, permission/timeout guidance and recheck, diagnostic request round trips, cross-user denial before dispatch, offline/older Workers, and rejected reattach for ended shells.

The Harmony terminal HAR must compile. Full test runs and build results belong in the delivery report. A module build or fixture result does not prove real-device permission behavior. Do not revoke live users' privacy grants or terminate their active sessions for fault injection.
