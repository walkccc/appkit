---
name: appkit-release
description: Ship a release end to end — version bumps, store screenshot capture and delivery, and the listing text, on the App Store or Google Play. Use when cutting a release, regenerating store screenshots, or writing/editing store metadata (name, subtitle, keywords, description, what's new).
---

# Release

The shared release flow, copied into every app repo by `appkit sync`. What is specific to one app — its engine sync, its scenes, the traps it has already fallen into — is in that repo's own `AGENTS.md`. Read both.

Every command below is `appkit …`, one installed program rather than one per repo. The platform is read from `appkit.json`; nothing here needs to know whether this app is iOS or Android.

Run the phases in order. Each is skippable only if you can say why.

## 0. Preflight

Anything generated must be regenerated and committed with the release, not after it. `git status` following a regenerate is the check; a diff there is real.

```
appkit doctor   # the repo is still wired to appkit
git status      # nothing generated is stale
```

## 1. Versions

```
appkit version 1.3.0     # the app's version, everywhere the platform writes it
```

iOS: `MARKETING_VERSION` moves alone — `CURRENT_PROJECT_VERSION` is a separate motion, `appkit version build`, because `asc publish appstore` resolves the real build number against what Connect already holds at ship time. Android: `versionName` and `versionCode` move together, since Play refuses a code it has already seen and nothing resolves that for you — run `appkit version build` again before any ship that would otherwise reuse one.

## 2. The build

**Never run `xcodebuild` or `gradlew` yourself** — not directly, and not through the commands that wrap them, which are `appkit run`, `appkit ship`, and `appkit capture --build`. Ask for a build in the IDE; capture reuses whatever is already there, which is why it takes no flag to do the safe thing.

**Verify the build is newer than the sources before capturing.** This is the one failure that is silent: appkit only _warns_, and every scene comes back looking exactly right while none of them is the change being shipped.

## 3. Screenshots

```
appkit make screenshots             # capture, compose, stop
appkit review screenshots           # every card in one picture, changes framed
```

- **Exactly one capture run at a time.** Two runs drive the same devices and interleave: one launches a scene while the other photographs, and the PNG lands under another scene's name in another language's folder. Nothing fails and nothing warns. Check before starting, and before trusting a set someone else kicked off:

  ```
  ps -Ao pid,lstart,command | grep -E 'appkit (capture|make)' | grep -v grep
  ```

  If a set is suspect it is suspect entirely: kill both runs, `rm -rf` every language folder under `.screenshots/`, and capture again from scratch.

- Raw captures are gitignored; the composed cards under `store/screenshots` are **tracked**, because a store screenshot is reviewed in a diff. `git status` says _whether_ one changed; the sheet says _which_, and shows the nine other languages that changed with it. **Look at the sheet before uploading** — a card that changed for a reason nobody can name is the one to chase.
- `--scene` / `--language` narrow a run and top a set up rather than replacing it. A whole-set run wipes each language folder first.
- A card whose picture did not change is put back at the bytes git already has. So a run that puts _any_ back had a scene that would not hold still — chase what is moving rather than widening the tolerance.
- The simulator does not render Liquid Glass the way hardware does. A set is worth one look on a device before it goes up.

## 4. The listing text

```
appkit pull metadata         # what the store ACTUALLY shows
appkit check metadata        # lengths + locale coverage, no network
git diff -- store/metadata   # what you are about to change
appkit upload metadata 1.3.0 # what's new only — --all for the whole listing
```

On the App Store that sends the release notes and nothing else, which is all a release usually changes. Reword a description, a subtitle or a keyword set and it needs `--all` to reach the store — pull first, because that is the run that can paint over words edited in App Store Connect.

**Always pull before editing, even for a one-word change.** What comes back is the truth about what the store currently shows, and it is the only thing that tells you whether you are filling a gap or painting over good words. Never author a metadata tree from scratch without pulling first.

`check` counts **characters, not bytes** — every CJK locale fails a `wc -c` check that `en-US` passes. An app on both stores is checked against the tighter of the two limits, because text that fits one and not the other fails an upload halfway through, having already changed the locales before it. `upload metadata` runs the same check itself and refuses rather than half-uploading.

| Field            | Key                | App Store | Play                     |
| ---------------- | ------------------ | --------- | ------------------------ |
| App name         | `name`             | 30        | 30 (`title`)             |
| Subtitle         | `subtitle`         | 30        | —                        |
| Short desc.      | `shortDescription` | —         | 80                       |
| Keywords         | `keywords`         | 100       | — (Play has no field)    |
| Promotional text | `promotionalText`  | 170       | —                        |
| Description      | `description`      | 4000      | 4000 (`fullDescription`) |
| What's New       | `whatsNew`         | 4000      | 500 (release notes)      |

Keywords are comma-separated with **no space after the comma** — a space is an indexed character.

Writing rules:

- **Borrow the words, don't invent them.** The listing is usually the one place an app repo may write a sentence, so it writes as few as it can: every term should come from what the app already ships in its own dictionary. A store page that names a mechanic differently from the app teaches the wrong word before the user arrives.
- **Keywords carry no repeats.** The name and subtitle are already indexed; spending keyword characters on words that appear there wastes the field.
- **N languages means N keyword fields**, not one translated N times. What a Japanese user searches for is not the translation of what an English one does.
- **Promotional text is the only field that changes without a review.** Anything time-bound goes there and nowhere else.

Categories, review information, age rating and export compliance are **not** in the metadata tree — they are set once through `asc categories`, `asc review`, `asc age-rating` and `asc encryption` (or the Play Console's own forms), and then left alone. That is deliberate: under the old Ruby path an empty `review_information/` killed a run _after_ every locale's copy had uploaded.

## 5. Upload

```
appkit upload screenshots 1.3.0  # the cards, every locale in one run
appkit ship --dry-run            # the binary: the plan, and stop
appkit ship                      # …archived, uploaded, attached
appkit ship --submit             # …and sent for review
appkit ship --submit-only        # just the send, for a build already attached
```

- App Store auth is one keychain entry for the whole account (`asc auth login`). Play auth is a service-account JSON at `.secrets/play-key.json`, gitignored. No private key belongs in a tracked file.
- **`appkit ship` archives** — on iOS it hands the project to `asc publish appstore`, which runs the xcodebuild half itself, then uploads, waits for processing and attaches. So it is the one appkit command that builds on purpose, and §2's rule covers it: it is the user's to run.
- **The build number is resolved against Connect**, not guessed here. That is the whole reason the archive goes through asc rather than a chain written in appkit — a number picked locally is rejected as a duplicate _after_ the archive, which is the expensive half.
- **Attaching is reversible in the Connect UI; `--submit` is not.** That is why it is a separate flag and why `--dry-run` prints the plan. Default to running without it and letting the user send the build for review.
- **A prepared submission is not a sent one.** Creating the review submission and POSTing the send are two calls, and a run has ended between them — leaving Connect showing a "Draft Submission" with a **Submit for Review** button nobody pressed. `--submit` now checks the submission's state afterwards and sends a draft it finds, because `READY_FOR_REVIEW` means _draft_; `WAITING_FOR_REVIEW` is the one that means it went. If only the send failed, finish it with `appkit ship --submit-only` — re-running the whole ship burns a build number and attaches nothing, since asc sees the draft and returns early.
- **A failed send is not a send that failed.** asc validates its own submission after POSTing it, and that read can lose to Connect's lag: `submit review: final submission validation: review submission … does not contain target version …` names, by id, a version the submission holds. The send went through. Check with `asc review status --app <ascAppId>` — `WAITING_FOR_REVIEW` on both the version and the submission means shipped — and **do not re-run `appkit ship`**, which burns a build number on a version already with review. `--submit` now ends on that state check rather than on asc's exit code, so the run reports what Connect holds.
- On Android the same verb puts the AAB on a track, because Play has no Organizer. One command, two stores, whichever `appkit.json` declares.
- Imagery persists **per version**, so a new version starts with none: the upload runs every time it is asked for, whether or not the cards changed since the last release. Unchanged cards cost minutes; a version with no cards costs a review cycle.
- Everything on Play happens inside one edit, so a run that dies halfway leaves the listing untouched.
- This is outward-facing and hard to walk back. Confirm before running it unless the user has already authorized the upload in this conversation.

## 6. After

Commit the composed cards and anything regenerated together — they are one change.
