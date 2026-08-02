# appkit

<p align="center">
  <a href="#install"><img alt="brew" src="https://img.shields.io/badge/brew-walkccc%2Fappkit-E6B422?style=flat-square&logo=homebrew&logoColor=white"></a>
  <a href="#requirements"><img alt="platform" src="https://img.shields.io/badge/platform-macOS-595857?style=flat-square&logo=apple&logoColor=white"></a>
  <a href="#layout"><img alt="made with" src="https://img.shields.io/badge/bash%20%2B%20swift-F8674F?style=flat-square&logo=swift&logoColor=white"></a>
  <a href="LICENSE"><img alt="licence" src="https://img.shields.io/badge/licence-MIT-1E50A2?style=flat-square"></a>
</p>

A shared harness for shipping one product on iOS and Android.

One installed program, one manifest per repo, one command. It captures store screenshots on a device, composes them into store cards, keeps the listing copy and the changelog in one place, and pushes the words, the imagery and the binary to the App Store and Google Play — deterministically, with no browser and no package manager at render time.

## Install

```sh
brew tap walkccc/appkit https://github.com/walkccc/appkit
brew install --HEAD appkit
```

Then, in any repo that has a `appkit.json`:

```sh
appkit doctor
```

**A repo keeps its own manifest and the handful of files `appkit sync` writes** — see [What lands in your repo](#what-lands-in-your-repo).

## Commands

```sh
appkit new ios       # scaffold a repo, from nothing
appkit sync          # write this repo's shared files
appkit doctor        # check they stayed put
appkit run           # build, install, launch
appkit capture       # the store scenes, one launch each
appkit render        # compose them into store cards
appkit release       # capture + render, and stop
appkit copy          # check the words; export them for a site
appkit publish copy  # the listing text
appkit publish shots # the store cards
appkit ship          # the binary: an archive onto Connect, an AAB onto a track
appkit version 1.3.0 # move the version everywhere it is written
```

Same commands on every platform. What differs is behind `platform/`, and no command contains a `case $PLATFORM`.

The repo is found by walking up for `appkit.json`, the way git looks for `.git`, so every command works from any subdirectory.

**Three of them build**, and every app repo's `AGENTS.md` forbids an agent from running those: `appkit run`, `appkit ship`, and `appkit capture --build`. Capture without that flag reuses whatever the IDE last built, which is the default because it is what nearly every run wants.

**Two of them are outward-facing** and hard to walk back: `appkit publish` and `appkit ship`. `ship` stops once the build is attached; `--submit` is the extra word that sends it for review, and `--dry-run` prints the plan instead.

## The four things a repo owns

Everything else is appkit's.

| Path                | What                                                         |
| ------------------- | ------------------------------------------------------------ |
| `appkit.json`       | the manifest — platform, locales, scenes, store ids, version |
| `scripts/scenes.sh` | what a store screenshot IS for this app                      |
| `store/`            | the storyboard, the words, the finished cards                |
| `.github/`          | the CI caller                                                |

A locale, a scene name or a store folder written into a script is drift: all three are rows in `appkit.json`.

## Starting an app

appkit does not create the app. Xcode and Android Studio do that. appkit creates everything around it — the manifest, the screenshot pipeline, the listing copy, CI, the agent harness — which is the part that is identical for every app and tedious to copy out of a sibling repo.

Two kinds of step below. **`appkit …`** is a command you run. **`/skill`** is a Claude Code skill: the instructions for a job that needs judgement rather than a fixed sequence, installed into the repo by `appkit sync` and invoked by name in a Claude session.

### An iOS app

```sh
mkdir myapp-ios && cd myapp-ios && git init
appkit new ios --name MyApp --bundle com.example.MyApp --locales "en ja"
```

1. **`appkit new ios`** writes `appkit.json`, `scripts/scenes.sh`, a storyboard, a copy skeleton and CI, then runs `appkit sync`.
2. **Make the Xcode project yourself**, with the scheme named the same as `ios.scheme` in `appkit.json`. appkit never touches the project file.
3. **Add a screenshot mode to the app** — a launch argument that puts it on one named screen with one language. `/screenshots` explains what a scene has to guarantee before it can be photographed reproducibly.
4. **Create the app record on App Store Connect**, then put its id in `appkit.json` as `ios.ascAppId` (`asc apps list` prints it).
5. **Write the listing copy** into `store/metadata/`. `/copy` has the tree, the character limits and the rule about pulling the live listing first.
6. **Shoot and compose the cards**: build in Xcode, then `appkit release`. `/screenshots` covers scenes that will not hold still.
7. **Ship**: `appkit publish copy`, `appkit publish shots`, `appkit ship`. `/release` runs the whole thing in order and knows what is reversible.

### An Android app

```sh
mkdir myapp-android && cd myapp-android && git init
appkit new android --name MyApp --package com.example.myapp --locales "en ja"
```

The same seven steps, with four differences:

- The project is an Android Studio one, and `appkit.json` names `android.package` rather than a scheme.
- A scene is staged by **intent extras**, and the app must log a line when the scene is on screen — an emulator's cold start is long enough that "not blank" is the wrong thing to wait for. The scaffolded `scripts/scenes.sh` shows the shape.
- Auth is a service-account JSON at `.secrets/play-key.json`, not a keychain entry.
- `appkit ship` puts the AAB on a track. There is no Organizer to fall back to, and no review to wait for on the first upload.

### Adding the second platform

Run `appkit new` again in a **sibling repo** — `myapp-ios` and `myapp-android`, never one repo holding both. The platforms build with different toolchains and CI never wants them together. What they share is words, and those are shared by copying `store/metadata/` between the repos deliberately. `/scaffold` has that checklist.

## Upgrading

```sh
brew upgrade appkit     # once
appkit sync             # in each repo, when you want it to take the change
```

`appkit sync` rewrites the shared files and `appkit doctor` fails on any difference, so an upgrade reaches a repo as a **reviewable diff** rather than silently. Nothing is picked up just by being installed.

A repo declares the oldest appkit that can run it:

```json
"appkit": "1.0.0"
```

A floor, not a pin — the point of installing once is that every repo moves together. `appkit doctor` fails below it and says nothing above it.

## Screenshots

```
appkit capture   device → .screenshots/<language>/<scene>.png    (gitignored)
appkit render    those  → store/screenshots/<locale>/NN-name.png (tracked)
appkit publish   those  → the store
```

The harness resolves the device, boots one worker per parallel language pass, shards the languages across them, and waits for the screen to stop moving — two byte-identical frames, not a sleep. `scripts/scenes.sh` decides what a scene is and when this app has settled; appkit never decides what a screenshot is _of_.

The composer draws each card with CoreGraphics and CoreText from `store/cards.json`: background, device frame, caption, foreground art, and pairs that span two cards. Same storyboard and captures in, same bytes out — which is what makes `git status -- store/screenshots` the answer to "did any screen change".

- **One size, everywhere.** Captures come off an iPhone 17 Pro (1206x2622) and every iOS card is 1242x2688. CI fails a storyboard that disagrees.
- **A device is a photographed bezel or a drawn one.** `frame` + `screen` puts the capture inside a real bezel PNG; `aspect`/`radius`/`bezel` draws one from four numbers, exact at any size with no asset to keep in step.
- **CJK is an explicit cascade**, per language, per face. CoreText's implicit fallback depends on the machine's language order, so a card without one is not the same card on two Macs.
- **A repo may draw its own cards** with `render.command` in `appkit.json`. Do that when the cards are illustrated rather than composed; a layout and a drawing are different things that share an output format.

Schema: [docs/CARDS.md](docs/CARDS.md).

## Words

One tree, every surface. The stores call it metadata and a website calls it a page; they are the same words.

```
store/metadata/app/<language>.json        name, subtitle, short description
store/metadata/version/<language>.json    description, keywords, promo text
store/metadata/changelog/<version>/<language>.md   what changed, per release
store/metadata/pages/<page>/<language>.md          privacy, support, terms
```

Keyed by the **capture language**, never a store's spelling of it — `ja` is `ja` on the App Store and `ja-JP` on Play, and a tree keyed by either can only serve that one. The emitters rename on the way out, from `appkit.json`'s locale rows. A file named for a store locale wins for that row, which is how two listings can share one set of screenshots and still have different words.

| Surface | Takes                                                        |
| ------- | ------------------------------------------------------------ |
| iOS     | name, subtitle, keywords, description, what's new, page URLs |
| Android | title, short + full description, release notes, page URLs    |
| web     | the description, the changelog, and the pages themselves     |

```sh
appkit copy note 1.3.0   # a release-note file per language, to fill
appkit copy check        # every store's limits, and every language's coverage
appkit copy export       # one JSON bundle for a site to render
```

`appkit copy check` counts **characters, not bytes** — every CJK locale fails a byte check that `en-US` passes — and against the tighter of the two stores when an app is on both. Coverage is the half nobody does by hand: a language missing a release note ships the previous release's words and nobody notices.

**The privacy and support pages a listing links to live in this tree too.** Canonical here, served from wherever the product's site is, one wording.

## Publishing

| Store       | How                                                                    |
| ----------- | ---------------------------------------------------------------------- |
| App Store   | `asc`, one Go binary. Auth is one keychain entry per account.          |
| Google Play | the Developer API directly, signed with `openssl`. Nothing to install. |

Every Play change happens inside one edit — insert, change, commit — so a run that dies halfway leaves the listing untouched. Imagery is counted before anything is deleted, and a type with no local files is left alone rather than emptied.

`appkit ship` puts the binary up on both. On iOS it hands the project to `asc publish appstore`, which archives, exports, uploads, waits for processing and attaches — and resolves the build number against what Connect already holds, because a number picked locally is rejected as a duplicate _after_ the archive, which is the expensive half.

## What lands in your repo

Everything shared is a **copy**, written by `appkit sync` and checked by `appkit doctor`. Nothing is a symlink: a link into the brew prefix survives neither an upgrade nor another machine, and a repo should still read as itself on a laptop where appkit was never installed.

| Path                              | Why it is there                                   |
| --------------------------------- | ------------------------------------------------- |
| `AGENTS.core.md`                  | the house style, imported by your own `AGENTS.md` |
| `.claude/skills/*/SKILL.md`       | the agent instructions for each errand            |
| `.prettierrc`                     | one formatter config for every repo               |
| `.swiftformat` (iOS)              | ditto                                             |
| `.githooks/pre-commit`            | the formatters, then `appkit doctor`              |
| `.gitignore`                      | a managed block; everything below it is yours     |
| `DesignSystem/Tokens/Scale.swift` | has to compile as an ordinary target source       |

A repo that legitimately _extends_ a shared config declines the copy:

```json
"sync": { "skip": [".prettierrc"] }
```

`appkit doctor` then reports it as the repo's own rather than as drift. The pre-commit hook runs `.githooks/local` last, if present, for whatever else a repo wants on a commit.

## What it does not share

- **Brand tokens.** `Palette`, `Typography`, `Motion`, `Materials` stay with the app. `Spacing` and `Radii` name rungs on appkit's `Scale` ladder rather than restating numbers — the same token name meant three different values across the repos this came from.
- **`.editorconfig`.** It ships in `config/` to copy by hand, not to sync: it carries a language's indent and lint rules, which are the repo's.
- **An illustrated card set**, or a site's own OG pipeline. Both above.

## Layout

```
AGENTS.core.md   the house style, copied into every app
bin/appkit       the entry point
commands/        one file per command
lib/             manifest, log + shutter, sharding, the picture gate
platform/        ios.sh, android.sh — the device contract
render/          compose.swift, same-picture.swift, fonts/
store/           asc.sh, play.sh, metadata.sh, copy.sh — the publishers
skills/          agent instructions, copied into every repo
ci/              the caller workflow a repo copies
config/          .swiftformat, .prettierrc, .editorconfig, gitignore.base
githooks/        pre-commit
swift/           Scale.swift, Opacity.swift
templates/       appkit.json, cards.json, og.json, scenes.sh
docs/CARDS.md    the card storyboard schema
Formula/         the brew formula
VERSION          what doctor checks a repo's floor against
```

## Requirements

macOS and Homebrew, plus what your platform needs: Xcode for iOS, the Android SDK for Android. Otherwise `bash`, `python3`, `swiftc`, `curl` and `openssl`, all of which macOS or the Xcode command line tools already carry.

Publishing to the App Store also needs [`asc`](https://github.com/rork-labs/asc) (`brew install asc`); appkit says so when it needs it rather than up front.

The composer is macOS-only: CoreText is why it lays out Japanese and Korean beside Latin without a font per script.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md). The bar is "is this true of every app on appkit" — if it is true of one platform it belongs in `platform/`, and if it is true of one app it belongs in that app.

## Licence

MIT — [LICENSE](LICENSE). The vendored Poppins is under the SIL Open Font Licence (`render/fonts/OFL.txt`).
