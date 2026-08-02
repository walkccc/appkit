# AGENTS.md

This is `appkit` — the shared half of several app repos, checked out inside each of them as `.kit`. Working here is not like working in an app repo: a change lands in every app that has pulled the submodule forward, so the bar is "is this true of all of them", not "does this help the one in front of me".

`AGENTS.core.md` is the house style that app repos import. **It is not for this repo's own rules** — it is the payload. Read [README.md](README.md) for the layout and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for why it is shaped this way.

## What belongs here

Something belongs in the kit when it is true of every app, or would be if the apps agreed. Everything else stays in the app repo, and the boundary is worth defending:

- **The harness, not the subject.** `commands/capture.sh` resolves devices, makes workers, boots them, shards the languages and draws the progress line. It has no idea what a scene is — the repo's `scripts/scenes.sh` supplies `capture_scene` and `appkit.json` supplies the list. The moment the kit knows an app's scene names, it has stopped being a kit.
- **The composer, not the art.** `render/compose.swift` lays a capture on a background under a caption, from a storyboard the repo owns. An app whose cards are _drawn_ rather than composed keeps its own renderer and says so in `appkit.json`. One app on the kit draws a title card that is a hand of playing cards in CoreGraphics; forcing that through a layout spec would be the same mistake as a shared `Spacing.swift`.
- **The ladder, not the names.** `swift/Scale.swift` is a list of numbers. What a rung is called is the app's `Spacing`/`Radii`. This is not fussiness: three apps had a `Spacing.lg` meaning three different values, so a shared `Spacing.swift` would have silently moved layout in shipped apps.
- **Not the brand.** `Palette`, `Typography`, `Motion`, `Materials` are never shared. One app's `Elevation` is a deliberately no-op flat ladder; sharing it would push "no shadows, ever" onto an app that has them.

## The platform contract

Every capability a command needs from a device is a `platform_*` function, and each of `platform/{ios,android,web}.sh` defines all of them. There is **no `case $PLATFORM`** in any command, and writing one is the signal that a capability is missing from the contract rather than that this platform is special.

The contract is small on purpose: resolve, workers, install, prepare, launch, screenshot, kick, retire, locate_app, verify_languages, build, version, list_devices. A platform that genuinely cannot do one of them defines it as a no-op with a line saying why — `web.sh` has three.

## Two things are copied, not linked

Everything the kit shares is a symlink, so there is nothing to keep in step — except two files that cannot be:

- **`.gitignore`** — git _refuses_ to follow a symlinked one. It fails with `unable to access '.gitignore': Too many levels of symbolic links` and then applies **no rules at all**, silently. Verified, not assumed.
- **`swift/*.swift`** — they have to compile as ordinary sources in the app target.

Both are copied by `appkit sync` and verified by `appkit doctor`, which the pre-commit hook runs. A copy that drifts fails a commit rather than surviving.

When editing either, edit it **here** and re-sync the app. The generated-from header on the Swift files says so; `.gitignore`'s managed block is delimited by markers, and everything below the closing marker is the app's own and is never touched.

## Changing a command

Every script is `bash -n` clean and the libraries are sourced, never executed. There is no test suite; the check is:

```sh
for f in bin/appkit commands/*.sh lib/*.sh platform/*.sh store/*.sh; do
  bash -n "$f" || echo "FAIL $f"
done
sh -n githooks/pre-commit
swiftc -O -o /tmp/compose render/compose.swift
```

Then run `appkit sync && appkit doctor` in a real repo before pushing something several apps will pull.

**Never run `xcodebuild` or `gradlew`** and never launch a simulator to check something — the same rule the app repos carry, for the same reason. `commands/run.sh` and the `platform_build` functions exist for the person at the keyboard.

The renderer is the exception worth naming: it is a macOS command-line program, not an app build, and it is _meant_ to be run and looked at. Render a locale into a scratch directory and open the PNGs.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), and **few**. A subject line, and a body only when it says something the diff cannot. `feat` / `fix` / `refactor` / `docs` / `ci` / `chore`, `!` for a break that makes app repos re-run `appkit sync`.

Group by what changed for the repos on the kit, not by the order the work happened in — a dozen commits narrating one restructure is a worse record of it than four.

## Style

Bash, `set -euo pipefail`, functions in `lib/` and `platform/`, flow in `commands/`. Swift 6 under strict concurrency in `render/` and `swift/`.

Comments earn their place by saying what the code cannot — why `position` and not `.offset`, why serial and not parallel. Prose wraps at 80 columns; prettier enforces it through the same config the apps use.
