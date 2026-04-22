# Gateway wwwroot console design

## Problem

The Gateway console frontend exists, but the running Gateway only returns JSON at `/` and does not serve the Web app. This blocks browser-based end-to-end testing against the local Gateway and Worker processes.

## Goal

Make `http://localhost:5045` open the console directly from the Gateway process, with the existing `/api/*` and `/hubs/*` endpoints unchanged.

## Recommended approach

Use the Gateway as the single host for the console in local testing and basic deployment:

1. Build the Vite app into the Gateway's `wwwroot` directory.
2. Configure the Gateway to serve default/static files.
3. Keep API and SignalR routes mapped explicitly.
4. Add SPA fallback routing so non-API, non-hub browser navigation returns `index.html`.

## Scope

In scope:

- Vite output path targeting Gateway `wwwroot`
- Gateway static file hosting
- Root path serving the console instead of the JSON health payload
- Fallback routing for hash-route-friendly browser loading
- Validation that the browser can load the console from the Gateway origin

Out of scope:

- A separate Vite dev-server workflow
- Authentication model changes
- API contract changes
- SignalR protocol changes

## Design details

### Frontend build output

The Web app will emit production assets directly into `src/Gateway/CortexTerminal.Gateway/wwwroot`. Build artifacts remain generated files; the source of truth stays in the Web project.

### Gateway hosting

The Gateway will:

- enable default file serving
- enable static file serving
- keep `/api/*`, `/hubs/terminal`, and `/hubs/worker` routes mapped as they are today
- return `index.html` for non-file requests that are not API or hub paths

This makes the console available at `/`, while preserving existing backend behavior.

### Testing

Verification will cover:

- Gateway tests still passing
- Worker and Mobile tests still passing
- Web tests still passing
- Web build producing assets into `wwwroot`
- Local Gateway startup serving the console shell at `/`

## Risks and mitigations

- Generated files can drift from Web source. Mitigation: always rebuild the Web app before final verification.
- Fallback routing could shadow backend endpoints. Mitigation: map API and hub endpoints explicitly before fallback and only fall back for non-file routes.
