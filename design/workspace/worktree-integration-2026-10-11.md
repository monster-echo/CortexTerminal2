# Worktree integration — 2026-10-11

Integrated into main from preserved worktree snapshots:

- a056: `59c71546bacd0f85671c116cdd077a41db8d063a`
- 559a: `23a19afa04a26ce5205981c1d39050e2d954eb5f`

## Changes

Recovered the workspace creation redesign, picker translations, design references and repository layout guidance. Computer and directory selection now use full-screen content covers with return navigation. Directory requests use the home root, selection changes are kept as drafts until confirmed, and stale directory responses are ignored. Existing sheet entry points share the same content sizing.

Retained main's newer inline activation camera, theme tokens, workspace return navigation, session list refresh and session naming fixes. Older snapshot versions were not applied over these changes. Local signing settings were used temporarily for the build and restored afterwards.

## Validation

- `git diff --check`: passed.
- HarmonyOS signed HAP build: passed (`BUILD SUCCESSFUL in 7 s 796 ms`).
- Initial emulator inspection found an empty computer list and clipped header. The picker layout was corrected and rebuilt successfully.
- The emulator disconnected before the final layout could be installed and rechecked. Visual acceptance of that correction remains pending.
- Unit and integration suites were not run as part of this merge.

The recovered review images are historical worktree evidence, not verification of the final merged build.

## Follow-up: picker state and safe areas

The full-screen builder now has a reactive container and linked loading, error, path and list state. System top inset is read from the window and refreshed on avoid-area changes. Both pickers use the existing theme colors.

Validated on the Mate 60 emulator after reinstalling the signed HAP:

- Computer picker shows four workers, including online/offline states.
- Folder picker on echos-Mac-mini loads the home directory and `.agents` children.
- Confirming `.agents` returns to creation with the folder and suggested name filled.
- Reopening the computer picker shows the correct page; switching computers clears the previous folder/name.
- System Back returns from the folder picker to creation.
- Screenshots confirm the title clears the status bar and the folder action clears the gesture bar.
- The second online worker, tengxun-2, returns HTTP 404 for its home-directory listing. The page shows Retry and disables confirmation; this remote response remains unresolved.
- Signed HAP build and `git diff --check` passed. No unit/integration suites were run.
