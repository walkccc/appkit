# AppKit

AppKit is the installed shared tooling for several app repositories. Read `README.md` for its layout and `CONTRIBUTING.md` for checks and rollout. `AGENTS.core.md` is the payload copied into app repos, not this repository's own rules.

## Boundaries

- Shared harnesses, rendering machinery, token structure, and store adapters belong here. App scenes, artwork, storyboard choices, brand values, and product behavior stay in app repositories.
- Commands call `platform_*` capabilities. Every adapter in `platform/{ios,macos,android}.sh` implements the complete contract; a genuine no-op explains why. Do not branch on `$PLATFORM` in commands or shared libraries. Platform-only helpers use their platform prefix.
- Managed files are copied by `appkit sync` and checked by `appkit doctor`. Preserve app-specific content outside managed blocks, especially `.gitignore`. Skills are linked through Homebrew's stable `opt` path.
- Personal rules remain in `~/.codex/AGENTS.md`; app-specific commands and exceptions remain in each app's `AGENTS.md`. Keep these instruction files concise and move explanatory background into existing documentation.

## Changes and checks

Use Bash with `set -euo pipefail`, libraries for capabilities, and commands for flow. Renderers use Swift 6 with strict concurrency. Comments explain constraints, not the line above them.

Run the relevant checks from `CONTRIBUTING.md`: shell syntax, the complete platform contract, and no platform branching. Compile and visually inspect a renderer only when changing it; check determinism for composer changes. App build/device verification rules apply when changing app source, not these tools' documentation.

After changing managed files, update their source, upgrade the installed AppKit, and propagate identical copies to consumers without overwriting unrelated changes. Run `appkit sync && appkit doctor` in a real app repository.

Use a few Conventional Commits grouped by the resulting change. Do not turn intermediate corrections into a commit log or add CI hosting and app-specific deployment services to AppKit.
