# AGENTS.core

Shared app conventions, copied by `appkit sync`. Personal rules live in `~/.codex/AGENTS.md`; project-specific rules belong in each repository's `AGENTS.md`.

## Development

- Build and device verification follow personal and project rules. Use the project's conventional build when no personal command applies.
- Use Swift 6 and strict concurrency. Avoid `@unchecked Sendable`, `nonisolated(unsafe)`, force unwraps, unowned tasks, type erasure for convenience, and hidden state synchronization.
- Prefer value types, small views, clear names, async/await, and `@MainActor` only where needed. Keep changes minimal and follow the surrounding architecture.
- Read only what the task needs. Do not add speculative layers or duplicate state.
- Commit to `main` unless the project says otherwise. Follow its beta deployment and public release workflows; a push is not automatically a public release.
- Preserve behavior, persistence, and navigation unless the task changes them. Data-shape changes include initializers, previews, fixtures, and migration.
- User-facing text must remain localizable. Follow personal comment and communication rules rather than duplicating them here.

## Shared files

`appkit.json` declares platform, locales, scenes, and store IDs. `scripts/scenes.sh` defines capture scenes; `store/` holds store metadata and assets.

`AGENTS.core.md`, `.prettierrc`, `.swiftformat`, and `.githooks/` come from AppKit. Edit their sources in the AppKit repository, then sync and run `appkit doctor`. Never overwrite unrelated local changes. Claude repository files import `@AGENTS.md`.

The pre-commit hook formats staged files with SwiftFormat and Prettier. AppKit skills are linked once per machine, not copied into app repositories. Keep generated caches, captures, and temporary reports out of tracked source.

## Design tokens

Every app uses a `Scale` ladder, then `Spacing` and `Radii` naming its rungs, followed by `Palette`, `Typography`, `Motion`, and `Materials`. The structure is shared; values and brand-specific tokens belong to each app. Use an existing token whenever it covers the value.
