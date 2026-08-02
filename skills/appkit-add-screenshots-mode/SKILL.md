---
name: appkit-add-screenshots-mode
description: Wire a debug-only screenshot mode into an app so appkit can drive it — read the scene off the launch, stage deterministic data, hold still for the shutter. Use once the app exists and before the first `appkit capture`, or when a second platform's app needs the same wiring a sibling already has.
---

# Add screenshots mode

`appkit new` writes the half of the contract that CAPTURES a scene — `scripts/scenes.sh` already launches the app with `-ScreenshotScene <name>` (iOS) or `-e screenshotScene <name>` (Android). No appkit command can write the other half: the app has to listen for that argument and stage the scene, and that is real code in the app's own source, shaped by its own screens and its own state. Nothing in this skill runs as a command — appkit owns the harness, not the app's UI.

Do this once, after the app exists and before the first `appkit capture`. A second platform for a product that already has one needs it too — the launch argument is the same idea, but the code is a second app's.

## What it looks like, iOS

- Read `-ScreenshotMode` and `-ScreenshotScene` off `ProcessInfo.processInfo.arguments` at launch, before the app's real state loads.
- Route to a seeded state for that scene — fixture data, not whatever is already in the simulator. Real data is not deterministic and the captures will not reproduce.
- Compile it out of release: an `#if DEBUG` guard, or a separate build configuration if the app already has one for other debug-only surfaces. It must not be reachable from a shipped binary.
- `-AppleLanguages` on the same launch drives which locale's captures come out — nothing extra to wire for that.

## What it looks like, Android

- Read the `screenshotScene` and `screenshotLanguage` extras off the launching `Intent`.
- Route to the same kind of seeded state as above.
- Log a line once the scene has actually rendered — `scripts/scenes.sh` blocks on it rather than guessing when a cold start has finished painting: `Log.d(TAG, "screenshot: staged $scene")`.
- Gate it behind a debug build type, the same as iOS.

## Make every scene deterministic

The shutter waits for two byte-identical frames, so anything still moving when it fires is the failure this step exists to prevent:

- Seed each scene's data by hand — no live network call, no random ordering.
- Freeze anything with `repeatForever` in it (a shimmer, a pulsing badge, a looping animation) for the duration of screenshot mode.
- Give the scene a settle floor in `scripts/scenes.sh`'s `settle_for` — the floor has to reach past the animation's _start_, because two frames taken before it begins agree just as well as two taken after it ends.

## Prove it

```sh
appkit capture --language en --scene <one>
appkit render
```

Look at what came out before wiring the rest of the scenes. A scene not yet staged draws the app's default screen and files it under whatever name was asked for — a shot that looks fine and is of the wrong thing.

## Related

`/appkit-screenshots` is for the pipeline once this half exists — adding a new scene later, debugging a set that will not reproduce, laying out the storyboard. This skill is only the one-time wiring a screen needs before appkit can drive it at all.
