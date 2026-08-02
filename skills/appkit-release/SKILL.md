---
name: appkit-release
description: Run a whole release in one pass — the version, the store screenshots, the preview videos recorded, framed and uploaded, the listing text, and the binary, on the App Store or Google Play. Use when cutting a release, or when regenerating or uploading any one of those pieces for a version.
---

# Release

The shared release flow. What is specific to one app — its scenes, its preview reel, the traps it has already fallen into — is in that repo's own `AGENTS.md`, which wins where the two disagree. Read both before starting.

Every command is `appkit …`, one installed program rather than one per repo, plus the three preview scripts where a repo makes previews. The platform is read from `appkit.json`.

Takes one argument, the version: `/appkit-release 1.5.5`. Without one, ask; every upload is keyed by it.

Run the phases in order, in one sitting, stopping only where a phase says to. Each is skippable only if you can say why. A phase that fails is fixed and resumed **from that phase**, never from the top — phase 2 alone is an hour of simulator time.

## What invoking this authorises

- **Every upload in it** — the cards, the preview videos, the release notes, and `appkit ship` attaching a build. Asking for a release is asking for these; do not stop to confirm each one.
- **The Screeny credits** framing costs, 3 per capture language. Say the number when that phase starts.
- **Not the send for review.** It is the one step with no undo. Only when the user has said so in this conversation; otherwise stop with the build attached and say it is ready to send.
- **Builds follow the repo.** The default is never to build — no `xcodebuild`, no `gradlew`, and not through `appkit run`, `appkit ship` or `capture --build` either — and to ask for a DEBUG build in the IDE at phase 2. Where the repo's `AGENTS.md` authorises release builds, pass `--build` and run `appkit ship` yourself.

## 0. Preflight

```
ps -Ao pid,lstart,command | grep -E 'appkit (capture|make)|record-preview|frame-preview' | grep -v grep
appkit doctor
git status
asc versions list --app <ascAppId> --platform IOS --output table
appkit check metadata
```

- The `ps` must print nothing. **Exactly one run drives the simulators at a time**: two interleave, one launching a scene while the other photographs, and the PNG lands under another scene's name in another language's folder. Nothing fails and nothing warns.
- `git status` must be clean of anything generated. Anything regenerated ships with the release, not after it.
- **The version must exist on App Store Connect before anything uploads to it.** Nothing in appkit creates it except `appkit ship`, which runs last — so when it is missing, `asc versions create --app <ascAppId> --version <v> --platform IOS`.
- `check` must pass. A locale with no release note ships the previous release's words; writing them is `/appkit-metadata`, not this.
- If the repo frames its previews, open Screeny with its MCP server on **now**. The framing phase checks for it, but an hour in.

## 1. Version

```
appkit version <v>
```

iOS: `MARKETING_VERSION` moves alone — the build number is resolved by `asc publish appstore` against what Connect already holds, at ship time. Android: `versionName` and `versionCode` move together, and Play refuses a code it has seen, so run `appkit version build` before any ship that would reuse one.

## 2. Screenshots

```
appkit make screenshots --build     # --build only where the repo allows it
appkit review screenshots
```

**Without `--build`, check the installed build is newer than the sources first.** appkit only warns, and every scene comes back looking exactly right while none of them is the change being shipped.

Read the sheet, `.build/review/screenshots.png`, before going on. It frames in red every card git says changed and in green every new one. A red card nobody can name a reason for stops the run: say which, and why it is suspect. A sheet with nothing framed is a set that did not change, which is an answer, not a failure.

- A suspect set is suspect entirely: kill every run, `rm -rf` each language folder under `.screenshots/`, and capture again from scratch.
- `--scene` / `--language` narrow a run and top a set up; a whole-set run wipes each language folder first.
- A card whose picture did not change is put back at the bytes git already has. A run that puts _any_ back had a scene that would not hold still — chase what is moving rather than widening the tolerance.
- The simulator does not render Liquid Glass the way hardware does. A set is worth one look on a device.

## 3. Preview videos

Only where the repo has `scripts/record-preview.sh`. The apps that make previews share one convention — three scripts, each taking capture languages as arguments and defaulting to all of them:

```
scripts/record-preview.sh     # → .screenshots/preview/<language>.mp4
scripts/frame-preview.sh      # → .screenshots/preview/framed/<language>.mp4
```

- **After phase 2, never alongside it.** The recorder takes whatever was built last, and phase 2 just made it — DEBUG, the only configuration the reel exists in. It drives the same simulators, too.
- Up to three takes a language, the smoothest kept: allow a minute or two each. Run it in the background and wait to be told it finished.
- **Framing takes the screen.** Screeny renders in its on-screen editor and stalls when it is not frontmost, so nothing else comes forward until it is done.
- One language that failed is re-run alone — `scripts/record-preview.sh de` — rather than the set.

Look before uploading. Pull the poster frame (the timecode `scripts/upload-previews.sh` sets) out of two languages and read them:

```
ffmpeg -v error -ss 0.33 -i .screenshots/preview/framed/en.mp4 -frames:v 1 <scratch>/en.png
```

It leads the gallery ahead of every card, so it is the one frame that has to be right on its own.

On Play there is nothing to do here: its video is a YouTube link, set once in the Console.

## 4. Listing text

```
appkit pull metadata          # the live listing → .asc/metadata-live; nothing tracked is touched
git diff -- store/metadata
```

Compare the live listing with the tracked one. A field that differs and that this release did not set out to change was edited in App Store Connect — bring it back into the repo rather than paint over it, and say so. Limits and writing rules are `/appkit-metadata`'s.

## 5. Upload

Cheapest to redo first, the binary last:

```
appkit upload metadata <v>                  # what's new; --all only if another field changed
appkit upload screenshots <v>
scripts/upload-previews.sh --framed <v>     # the set the store takes — see below
appkit ship --dry-run
appkit ship
```

- On the App Store, `upload metadata` sends the release notes and nothing else. `--all` sends the whole listing, and is the run that can paint over words edited in Connect — phase 4 is what makes it safe.
- **Which preview set goes up is the repo's call**, in its `AGENTS.md`. `--framed` is the bezel set; without it, the bare recording. They differ only by the bezel, and the wrong one uploads without complaint.
- Every upload here replaces rather than adds, so each is safe to re-run. A preview upload that died partway is finished with only the languages it had left, `scripts/upload-previews.sh --framed <v> -- de fr`; a poster frame that did not take, with `--poster-only`.
- Imagery persists **per version**, so a new version starts with none: cards and previews go up every release, changed or not. Unchanged ones cost minutes; a version without them costs a review cycle.
- `appkit ship` archives, uploads, waits for processing and attaches — on iOS through `asc publish appstore`, so the build number is resolved against Connect rather than guessed here and rejected as a duplicate _after_ the archive. It is the long one: background it. On Android the same verb puts the AAB on a track, inside one edit, so a run that dies halfway leaves the listing untouched.
- With the user's say-so only: `appkit ship --submit-only` sends the attached build.
- **A prepared submission is not a sent one.** `READY_FOR_REVIEW` is a draft Connect shows with a Submit button nobody pressed; `WAITING_FOR_REVIEW` is the one that means it went. If only the send failed, `appkit ship --submit-only` finishes it.
- **A failed send may still have gone.** asc validates after POSTing and can lose to Connect's lag, naming by id a version the submission holds. Check `asc review status --app <ascAppId>` and **never re-run `appkit ship`** over it — that burns a build number on a version already with review.
- App Store auth is one keychain entry, `asc auth login`. Play's is `.secrets/play-key.json`, gitignored. No private key goes in a tracked file.

## 6. After

Commit the composed cards and anything regenerated as one commit, in the shape the repo's log already uses for a release (`git log --oneline -5`). Stage explicit paths. No video is ever tracked — nothing under `.screenshots/` goes in. Push only when asked.

Then report, a line a phase: what went up and to how many locales, anything skipped and why, and whether the build is attached or sent.
