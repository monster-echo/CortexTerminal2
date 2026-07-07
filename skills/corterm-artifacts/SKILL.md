---
name: corterm-artifacts
description: "CortexTerminal session file bridge. $CORTERM_ARTIFACTS_DIR is live-synced with the user's phone: phone uploads appear here, and any file written here is pushed back to the phone. Trigger when $CORTERM_ARTIFACTS_DIR is set and non-empty — enumerate the directory, apply the per-category rules below, and write products back into the same directory so they sync to the phone."
---

# Corterm session artifacts

`$CORTERM_ARTIFACTS_DIR` is a two-way bridge between this terminal session and the user's phone
(the CortexTerminal Console):

- Files the user drops on their phone are downloaded into this directory automatically.
- Any file you write into this directory is uploaded and appears on the phone within seconds
  (origin = worker).

## At the start of every turn

If `$CORTERM_ARTIFACTS_DIR` is set, enumerate it (e.g. `ls -la "$CORTERM_ARTIFACTS_DIR"`).
For each file, apply the matching rule below. Skip files whose product is already present
(idempotent — a second run must be a no-op). Never destroy or overwrite the original.

## Rules

### Images — `.jpg .jpeg .png .webp .gif .bmp .tiff .tif .heic`

For every image that does **not** already have a `<name>-512x512.<ext>` sibling, produce a
512×512 copy that fits within the box while preserving aspect ratio:

- Output path: `$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>`
- Pick whichever tool is on PATH:
  - macOS: `sips -Z 512 "$CORTERM_ARTIFACTS_DIR/<in>" --out "$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>"`
  - ImageMagick: `magick "$CORTERM_ARTIFACTS_DIR/<in>" -resize '512x512>' "$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>"`
  - ffmpeg: `ffmpeg -y -i "$CORTERM_ARTIFACTS_DIR/<in>" -vf 'scale=512:512:force_original_aspect_ratio=decrease' "$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>"`
- The product lands back in the artifacts dir → auto-syncs to the phone. The user does not need
  to @-reference anything; "the photo" means the image(s) in `$CORTERM_ARTIFACTS_DIR` lacking a
  `-512x512` sibling.

Example: `photo.jpg` arrives from the phone (no `photo-512x512.jpg`) → resize →
`$CORTERM_ARTIFACTS_DIR/photo-512x512.jpg` → phone receives the thumbnail.

### Other categories

`pdf`, `video`, `audio`, `archive`, `code`, `text`, `unknown` — no automatic transformation yet.
Leave as-is unless the user explicitly asks.

## Conventions

- Products **always** go back into `$CORTERM_ARTIFACTS_DIR/` — never to `/tmp`, the CWD, or
  elsewhere. A product written outside this directory will not reach the phone.
- Never delete or overwrite the original uploaded file.
- If `$CORTERM_ARTIFACTS_DIR` is unset or the directory is empty, do nothing.
- Escape hatch: if `CORTERM_AGENT=0` is set, Corterm is disabled and these rules do not apply.
