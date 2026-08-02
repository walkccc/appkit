# appkit

<p align="center">

![](https://img.shields.io/badge/macOS-000000.svg?style=flat-square&logo=apple&logoColor=white)
![](https://img.shields.io/badge/brew-walkccc%2Fappkit-E6B422?style=flat-square&logo=homebrew&logoColor=white)
![](https://img.shields.io/badge/Bash%20%2B%20Swift-F8674F?style=flat-square&logo=swift&logoColor=white)
![](https://img.shields.io/badge/licence-MIT-1E50A2?style=flat-square)

</p>

**One installed program that ships one product on iOS and Android.** Store
screenshots in every language, the listing text, the version bump and the
binary — from the command line, with the same words on every app.

A release is this, and nothing else:

```sh
appkit make screenshots         # capture every scene, in every language
appkit review screenshots       # look at all of them at once
appkit upload metadata 1.3.0    # the listing text
appkit upload screenshots 1.3.0 # the cards
appkit ship --submit            # archive, upload, attach, send for review
```

No more Organizer, no more Distribute App wizard, no more dragging thirty
screenshots into App Store Connect one locale at a time, no more refreshing
TestFlight in a browser tab, no more Play Console upload form. You create the
store record once, by hand, and never open either web console again.

Xcode and Android Studio are the SDK, not the workflow. Write the app in
whatever you write code in — `appkit run` builds it, installs it and launches
it, and nothing above this line needs an IDE window open.

## What comes out

`appkit make screenshots` launches the app once per scene per language, waits
for each screen to hold still, and composes the captures into store cards.
`appkit review screenshots` then draws you the whole set at once — one row per
locale, one column per card, a red frame where git says a card changed and a
green one where it is new:

![A contact sheet of 55 store cards across 5 locales, one row per language](docs/contact-sheet.png)

That picture is the review step. `git status` can tell you _whether_ a card
changed; it cannot tell you **which**, because a PNG diff in a terminal is one
line about bytes. A hole in the grid is a locale missing a scene — the most
common way a set goes wrong, and the hardest to catch one file at a time.

The cards are **deterministic**: same captures and same storyboard in, same
bytes out, on every machine. That is what makes them reviewable at all — a
pipeline whose pixels drift every run produces noise you learn to ignore, and
the day you ignore a real change is the day a stale screen ships.

## Install

```sh
brew tap walkccc/appkit
brew trust walkccc/appkit   # Homebrew 6 loads no third-party formula untrusted
brew install --HEAD appkit
appkit skills   # once per machine — links the /appkit-… skills into ~/.claude/skills
```

The formula sits in [walkccc/homebrew-appkit][tap] rather than beside the code,
because that repo is the only thing the tap name `walkccc/appkit` resolves to.
Held here it still worked, but every install line had to carry the clone URL.

[tap]: https://github.com/walkccc/homebrew-appkit

Needs macOS and Homebrew, plus Xcode for iOS or the Android SDK for Android.
Everything else (`bash`, `python3`, `swiftc`, `curl`, `openssl`) already ships
with the Xcode command line tools. Publishing to the App Store also needs
[`asc`](https://github.com/rork-labs/asc) (`brew install asc`); appkit says so
when it needs it.

macOS is not optional: the composer is CoreText, which is the only thing on the
machine that lays out Japanese and Korean beside Latin from an explicit font
cascade instead of a guess.

## Getting started

appkit does not create the app — Xcode and Android Studio do. It creates the
pipeline around it.

1. **Create the project.** Xcode ▸ File ▸ New ▸ Project (name `MyApp`, bundle
   `com.example.MyApp`), or Android Studio ▸ New Project. This makes the repo
   folder; naming it `myapp-ios` / `myapp-android` keeps it apart from a web
   repo for the same product.
2. **Scaffold the pipeline**, from inside it:
   ```sh
   appkit new ios     --name MyApp --bundle com.example.MyApp --locales "en zh-Hant ja"
   appkit new macos   --name MyApp --bundle com.example.MyApp --locales "en"
   appkit new android --name MyApp --package com.example.myapp --locales "en ja"
   ```
   Or run `/appkit-scaffold`, which is the same call with the judgement attached.
   Nothing here touches screenshots yet — there is no app to photograph.
3. **Build the app.** This is the product; appkit has nothing to do here.
4. **Wire the screenshot mode** with `/appkit-add-screenshots-mode`:
   `-ScreenshotScene` on iOS, `-e screenshotScene` on Android, read off the
   launch, seeding each scene's data and freezing anything that animates
   forever. Then `appkit make screenshots` and look at what came out.
5. **Create the store record** in App Store Connect or the Play Console (appkit
   cannot — Play has no API for it), then `appkit pull metadata` and fill in
   `store/metadata` with `/appkit-metadata`, through to `appkit check metadata`.
6. **Release** with `/appkit-release`: the version bump, the real screenshot
   set, the listing upload, and `appkit ship`.

A second platform for a product already on appkit is the same `appkit new` call
in its own sibling repo — it never overwrites without `--force`.

## Commands

Every command is `verb noun`, spelled out. There are no short forms and no flags
to memorise; `appkit help VERB` prints any one command's own page.

```sh
appkit help                # what any of these do (appkit help VERB for one)

appkit new ios             # scaffold a repo, from nothing (ios | macos | android)
appkit sync                # write this repo's shared files
appkit doctor              # check they stayed put (the pre-commit hook does)
appkit skills              # link the skills into ~/.claude/skills, once
appkit setup signing       # the one-time machine setup a platform needs
appkit path                # where appkit is installed, for a repo's scripts

appkit run                 # build, install, launch
appkit capture             # photograph the store scenes, one launch each
appkit render              # compose them into store cards
appkit make screenshots    # capture + render, and stop
appkit review screenshots  # every card in one picture, changes framed

appkit check metadata      # every store's limits, every language's coverage
appkit pull metadata       # what the listing says right now, to compare

appkit upload metadata     # the listing text, onto the store
appkit upload screenshots  # the store cards, onto the store
appkit ship                # the binary, onto the store
appkit distribute          # the binary, onto the internet — Mac, notarized
appkit version 1.3.0       # move the version everywhere it is written
appkit version build       # the build number only, +1
```

**The device.** On iOS appkit resolves and boots the simulators itself, one per
language, and runs them in parallel — you never open Simulator.app, and the
model is pinned in appkit so every repo moves off it at once. On Android an
emulator or a phone on a cable is something the machine already has, so appkit
uses whatever `adb` gives it and boots nothing. On macOS the device is the Mac
appkit is running on: nothing to boot, nothing to create, one pass, and a
capture photographs the app's front **window** rather than the screen — a screen
carries your desktop into the shot and comes out at whatever size this
particular Mac's panel is.

**Building is yours — except on macOS.** appkit only runs `xcodebuild` or
`gradlew` inside `appkit run`, `appkit ship` and `appkit capture --build`;
everything else reuses what the IDE already built, which is why capture takes a
flag to compile rather than doing it by default.

macOS is the exception, because SwiftPM emits a bare executable and there is no
IDE build to reuse: the `.app` around it — `Info.plist`, the icon, the SwiftPM
resource bundles, the signature — is assembled by appkit. That assembly is what
replaced a hand-written `build.sh` in each Mac repo, and the reason it is worth
sharing is the signature. macOS pins a TCC permission grant (Accessibility,
Screen Recording, the microphone) to the app's **designated requirement**;
ad-hoc signed, that requirement contains the binary's hash, so every rebuild is
a new app to TCC and the grant is silently dropped while System Settings still
shows the toggle on. Signed with a real certificate it survives. A Mac with no
Apple certificate gets one from `appkit setup signing`, once.

**A Mac app can also skip the store entirely.** `appkit distribute` is the other
end of the same signature: Developer ID, hardened runtime, secure timestamp,
notarized by Apple and the ticket stapled into the bundle, which together are
what let somebody who has never heard of you open the download. It builds
universal — `appkit run` compiles for this Mac, a download cannot, because
macOS 14 still runs on Intel — and hands back two files: a **`.dmg`** with an
`/Applications` alias in it, which is what a person downloads, and a **`.zip`**,
which is what an in-app updater unpacks. Both are notarized and stapled; the zip
is not the thing to put behind a download button, because a `.app` unzipped in
`~/Downloads` and opened there is [translocated][t] — run from a randomised
read-only path, with every permission it is granted filed under that path and
gone by the next launch. It verifies its own output against Gatekeeper before
printing each file with its sha256, which is what an appcast and a download page
need. The entitlements that go with the hardened runtime are the repo's,
declared as `macos.entitlements`, and declaring them hardens **every** build so
a capability the runtime withholds fails here rather than after notarization has
already said yes.

A dependency that ships as a binary `.xcframework` — Sparkle, most likely — is
named in `macos.frameworks`. SwiftPM links against one but will not embed it,
because embedding is Xcode's half of the job and a package has no Xcode project;
appkit copies the macOS slice into `Contents/Frameworks`, adds the rpath that
finds it, and signs what is inside it before the app around it. Miss any of
those three and the app builds, signs, verifies, and dies at launch on
`Library not loaded`.

[t]: https://developer.apple.com/library/archive/technotes/tn2206/_index.html

Two of those entitlements are not the app's to declare alone. A restricted one —
any `com.apple.developer.*` key, so Sign in with Apple, iCloud, push — is
checked against a profile Apple signed for that bundle id, and an app that
claims one without it is killed at `exec` with `Launchd job spawn failed`: built,
signed, installed, and never runs a line of its own code. Name the downloaded
profile as `macos.provisioningProfile` and it is copied to
`Contents/embedded.provisionprofile` before signing. Leave it out while the
entitlements file names such a key and the build says so.

## What's yours, what's appkit's

| A repo owns                                     | appkit syncs in, and `doctor` checks         |
| ----------------------------------------------- | -------------------------------------------- |
| `appkit.json` — platform, locales, scenes, ids  | `AGENTS.core.md` — the house style           |
| `scripts/scenes.sh` — what a screenshot IS      | `.prettierrc`, `.swiftformat` (iOS + macOS)  |
| `store/` — the storyboard, the words, the cards | `.githooks/pre-commit`, `.gitignore`'s block |

Everything appkit hands a repo is a **copy**, never a symlink — a link survives
neither an upgrade nor another machine, and a repo should still read as itself on
a laptop where appkit was never installed. `appkit sync` writes it, `appkit
doctor` fails on any difference, so an upgrade reaches a repo as a reviewable
diff rather than silently. A repo that genuinely extends a shared file declines
it instead of drifting: `"sync": { "skip": [".prettierrc"] }`.

A locale, a scene name or a store folder written into a script is drift — all
three are rows in `appkit.json`, and every command reads them from there.

## Skills

`appkit skills` links these into `~/.claude/skills`, once per machine — the
**command is the mechanism, the skill is the judgement** a script can't make:

| Skill                          | For                                                                                         |
| ------------------------------ | ------------------------------------------------------------------------------------------- |
| `/appkit-scaffold`             | standing up a new repo, or a second platform for one                                        |
| `/appkit-add-screenshots-mode` | wiring the debug-only screenshot mode into an app that doesn't have it yet                  |
| `/appkit-screenshots`          | adding a scene, mixing in a widget or the watch, or debugging a set that will not reproduce |
| `/appkit-metadata`             | writing the listing text — every field, every language                                      |
| `/appkit-release`              | shipping end to end, in order, knowing what's reversible                                    |

## What it does not share

- **Design tokens.** The _shape_ is shared, in a paragraph of `AGENTS.core.md`;
  the values never are — the same token name has meant three different values
  across the repos this came from, so shipping the file would have moved layout
  in shipped apps.
- **`.editorconfig`.** Ships in `config/` to copy by hand, not to sync: it
  carries a language's indent and lint rules, which are the repo's own.
- **An illustrated card set**, or a site's own OG pipeline. A repo whose cards
  are drawn rather than composed keeps its own renderer, declared as
  `render.command` in `appkit.json`.

## Layout

```
appkit/
├── AGENTS.core.md    the house style, copied into every app
├── bin/appkit        the entry point: one verb per command, and appkit help
├── commands/         one file per subject — capture, render, review, upload, …
├── lib/              manifest, log + shutter, sharding, the picture gate
├── platform/         ios.sh, macos.sh, android.sh — the device contract
├── render/           compose.swift, same-picture.swift, contact-sheet.swift, fonts/
├── store/            asc.sh, play.sh, metadata.sh — the store adapters
├── skills/           agent instructions, linked into ~/.claude/skills
├── config/           .swiftformat, .prettierrc, .editorconfig, gitignore.base
├── githooks/         pre-commit
├── templates/        cards.json
├── docs/CARDS.md     the card storyboard schema
└── VERSION           what doctor checks a repo's floor against
```

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md). The bar is "is this true of every app on
appkit" — if it's true of one platform it belongs in `platform/`, and if it's
true of one app it belongs in that app.

## Licence

MIT — [LICENSE](LICENSE). The vendored Poppins is under the SIL Open Font Licence
(`render/fonts/OFL.txt`).
