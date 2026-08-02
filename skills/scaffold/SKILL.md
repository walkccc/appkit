---
name: scaffold
description:
  Stand up a new platform for a product — a new iOS or Android repo wired to
  appkit, or a second platform for a product that already has one. Use when
  starting a repo, adding a platform, or asked to "set up the pipeline" for an
  app that has none.
---

# Scaffold

```sh
appkit new ios     --name Tefuda --bundle com.example.Tefuda \
  --locales "en ja zh-Hant zh-Hans ko" --scenes "board cash perk"
appkit new android --name Tefuda --package com.example.tefuda --locales "…"
```

Writes the manifest, the scenes file, a storyboard, a metadata skeleton and CI, then runs `appkit sync`. It never overwrites an existing file without `--force`, so running it a second time to add a platform is safe.

**It does not make the app.** Xcode, Android Studio and your framework still create the project. What this creates is the pipeline around it — the part that is the same every time.

## Adding a platform to an existing product

This is the common case, and the answer is **a repo per product-platform**, not an umbrella repo:

```
tefuda-ios/      appkit.json  platform: ios
tefuda-android/  appkit.json  platform: android
```

Each is an ordinary repo that declares a `appkit.json` and nothing else about the pipeline. An umbrella holding all three gives nothing back — the platforms build with different toolchains and CI never wants them together.

**What the platforms of one product genuinely share is words, not directories.** Keep them in step deliberately:

- The **scene vocabulary** should match where the screens match, so the two storyboards can carry the same caption. Name them the same thing in both `appkit.json`s.
- The **captions** should be copied verbatim where the screen is the same screen. They were written and translated once; a second wording is just a second wording.
- The **locale table** should list the same languages, with each store's own spelling — that is what the `appStore` and `play` columns are for.
- What must **not** match is anything the platforms genuinely differ on: the card size (iOS is always 1242x2688; Play refuses anything taller than 9:16, so its card is 1242x2208), the device model, and any claim about a feature one binary does not have.

If a caption ever needs to be identical and enforced, put it in a small data file both repos read — not a shared checkout.

## After scaffolding

1. **A debug-only screenshot mode in the app.** The scene comes in on the launch: `-ScreenshotScene` on iOS, `-e screenshotScene` on Android, a path on web. It has to be compiled out of release builds.
2. **Make each scene deterministic.** Seed its data; freeze anything with `repeatForever` in it. The shutter waits for two byte-identical frames, so anything still moving will be named at the end of the run.
3. **Give the scenes settle floors** in `scripts/scenes.sh` — the floor has to reach past every animation's _start_, because two frames taken before one begins agree just as well as two taken after it ends.
4. **Fill in `store/metadata`.** If the app is already on a store, **pull the live listing first** (`appkit publish copy --pull`) — what is live is not what is tracked, and authoring from scratch is how good copy gets painted over.
5. **Then**: `appkit capture --language en && appkit render`, and look at what came out.

## What to check before saying it is done

```sh
appkit doctor                # wiring
appkit publish copy --check  # every field within its store's limit
appkit render                # the cards
git status -- store/screenshots   # what actually changed
```

None of those touch a store, and none of them build the app.
