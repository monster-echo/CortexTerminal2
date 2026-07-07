# Corterm session artifacts

`$CORTERM_ARTIFACTS_DIR` is a two-way bridge between this terminal session and the user's phone
(the CortexTerminal Console):

- Files the user drops on their phone are downloaded into this directory automatically.
- Any file you write into this directory is uploaded and appears on the phone within seconds
  (origin = worker).

## At the start of every turn

If `$CORTERM_ARTIFACTS_DIR` is set, enumerate it (e.g. `ls -la "$CORTERM_ARTIFACTS_DIR"`).
For each file, apply the matching rule below. Skip files whose product is already present
(idempotent). Never destroy or overwrite the original.

## Rules

### Images — `.jpg .jpeg .png .webp .gif .bmp .tiff .tif .heic`

For every image that does **not** already have a `<name>-512x512.<ext>` sibling, produce a
512×512 copy (fit within the box, preserve aspect ratio) at
`$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>`. Pick whichever tool is on PATH:

- macOS: `sips -Z 512 "$CORTERM_ARTIFACTS_DIR/<in>" --out "$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>"`
- ImageMagick: `magick "$CORTERM_ARTIFACTS_DIR/<in>" -resize '512x512>' "$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>"`
- ffmpeg: `ffmpeg -y -i "$CORTERM_ARTIFACTS_DIR/<in>" -vf 'scale=512:512:force_original_aspect_ratio=decrease' "$CORTERM_ARTIFACTS_DIR/<name>-512x512.<ext>"`

The product lands back in the artifacts dir → auto-syncs to the phone. "The photo" means the
image(s) in `$CORTERM_ARTIFACTS_DIR` lacking a `-512x512` sibling.

### Other categories

`pdf`, `video`, `audio`, `archive`, `code`, `text`, `unknown` — no automatic transformation yet.

## Conventions

- Products **always** go back into `$CORTERM_ARTIFACTS_DIR/` — never elsewhere, or the phone
  won't see them.
- Never delete or overwrite the original uploaded file.
- If `$CORTERM_ARTIFACTS_DIR` is unset or empty, do nothing.
- If `CORTERM_AGENT=0` is set, Corterm is disabled and these rules do not apply.
