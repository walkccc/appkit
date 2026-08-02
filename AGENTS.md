# AGENTS.md

This is `appkit` — the shared half of several app repos, installed once through Homebrew and read by all of them. Working here is not like working in an app repo: a change lands in every app on the next `brew upgrade appkit && appkit sync`, so the bar is "is this true of all of them", not "does this help the one in front of me".

`AGENTS.core.md` is the house style that app repos import. **It is not for this repo's own rules** — it is the payload. Read [README.md](README.md) for the layout and what it deliberately does not do.

## What belongs here

Something belongs in the kit when it is true of every app, or would be if the apps agreed. Everything else stays in the app repo, and the boundary is worth defending:

- **The harness, not the subject.** `commands/capture.sh` resolves devices, makes workers, boots them, shards the languages and draws the progress line. It has no idea what a scene is — the repo's `scripts/scenes.sh` supplies `capture_scene` and `appkit.json` supplies the list. The moment the kit knows an app's scene names, it has stopped being a kit.
- **The composer, not the art.** `render/compose.swift` lays a capture on a background under a caption, from a storyboard the repo owns. An app whose cards are _drawn_ rather than composed keeps its own renderer and says so in `appkit.json`. One app on the kit draws a title card that is a hand of playing cards in CoreGraphics; forcing that through a layout spec would be the same mistake as a shared `Spacing.swift`.
- **The shape, not the values.** `AGENTS.core.md` says every app splits `DesignSystem/Tokens/` the same way — a `Scale` ladder, then `Spacing`/`Radii` naming rungs on it, then the brand. The numbers themselves are never shipped from here: three apps had a `Spacing.lg` meaning three different values, and one app's `Elevation` is a deliberately no-op flat ladder. A file would have moved layout in shipped apps; a paragraph cannot.

## The platform contract

Every capability a command needs from a device is a `platform_*` function, and both of `platform/{ios,android}.sh` define all of them. There is **no `case $PLATFORM`** in any command, and writing one is the signal that a capability is missing from the contract rather than that this platform is special.

The contract is small on purpose: resolve, workers, install, prepare, launch, screenshot, kick, retire, locate_app, verify_languages, build, version, set_version, list_devices, use_device, shared_files. A platform that genuinely cannot do one of them defines it as a no-op with a line saying why — `platform_shared_files` on Android is empty, because the kit has no opinion about formatting Kotlin.

**Both adapters must define all of them, and that is a check, not a habit.** `platform_use_device` lived in `ios.sh` alone while `commands/run.sh` called it on both, so `appkit run --device` on Android died with "command not found" — invisible until somebody ran the one command that needed the missing half. The `diff` that catches it is in [CONTRIBUTING.md](CONTRIBUTING.md).

**A capability only one platform has is `ios_*`, not `platform_*`** — `ios_project`, `ios_bundle_id`, and the `ios_watch_*` group. The test is whether a kit _command_ calls it: nothing in `commands/` touches a watch, so there is no platform to branch on and android.sh owes no no-op. Wear OS is a different shape and inventing a stub for it would be a worse lie than its absence. The moment a command needs one, it becomes `platform_*` and both adapters define it.

## What is copied, and the one thing that is linked

Everything an app repo gets is **copied** by `appkit sync` and verified by `appkit doctor`, which the pre-commit hook runs — a copy that drifts fails a commit rather than surviving. A link into the brew prefix would survive neither an upgrade nor another machine, and a repo should still read as itself on a laptop where appkit was never installed.

`.gitignore` is the one that could not be a link even if we wanted it: git _refuses_ to follow a symlinked one. It fails with `unable to access '.gitignore': Too many levels of symbolic links` and then applies **no rules at all**, silently. Verified, not assumed. Its managed block is delimited by markers, and everything below the closing marker is the app's own and is never touched.

The skills are the exception in the other direction: `appkit skills` **links** them into `~/.claude/skills`, once per machine, because they are the same instructions in every repo and only an agent on this laptop reads them. The link points at brew's `opt` path, so `brew upgrade appkit` is the whole of an update.

When editing any of it, edit it **here** and re-sync the app.

## Changing a command

Every script is `bash -n` clean and the libraries are sourced, never executed. There is no test suite; the check is:

```sh
for f in bin/appkit commands/*.sh lib/*.sh platform/*.sh store/*.sh; do
  bash -n "$f" || echo "FAIL $f"
done
sh -n githooks/pre-commit
for f in render/*.swift; do swiftc -O -o "/tmp/$(basename "$f" .swift)" "$f" || echo "FAIL $f"; done
appkit help && appkit help upload   # both read outside an app repo
```

Then run `appkit sync && appkit doctor` in a real repo before pushing something several apps will pull.

**Never run `xcodebuild` or `gradlew`** and never launch a simulator to check something — the same rule the app repos carry, for the same reason. `commands/run.sh` and the `platform_build` functions exist for the person at the keyboard.

The renderer is the exception worth naming: it is a macOS command-line program, not an app build, and it is _meant_ to be run and looked at. Render a locale into a scratch directory and open the PNGs.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), and **few**. A subject line, and a body only when it says something the diff cannot. `feat` / `fix` / `refactor` / `docs` / `ci` / `chore`, `!` for a break that makes app repos re-run `appkit sync`.

Group by what changed for the repos on the kit, not by the order the work happened in — a dozen commits narrating one restructure is a worse record of it than four.

## Style

Bash, `set -euo pipefail`, functions in `lib/` and `platform/`, flow in `commands/`. Swift 6 under strict concurrency in `render/`.

Comments earn their place by saying what the code cannot — why `position` and not `.offset`, why serial and not parallel. Prose wraps at 80 columns; prettier enforces it through the same config the apps use.
