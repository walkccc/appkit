# AGENTS.core

The house style for every app here — iOS and Android. Copied into each repo by `appkit sync` and imported from its `AGENTS.md`.

Only what is true of **every** app belongs here. One app → that repo's own `AGENTS.md`.

## Rules

- **Never build.** No `xcodebuild`, `./gradlew` or `next build`, directly or through a wrapper, and never launch a simulator to check something. Ask for a build and a screenshot. To see the app without one, install the last build — check its mtime against the sources first.
  - Exception: a release capture the user asked for. `appkit capture` reuses what the IDE built; `--build` is the flag that would compile, and is theirs to pass.
  - `appkit render` is not a build. Run it and look at what it drew.
- **Swift 6, strict concurrency.** No `@unchecked Sendable` or `nonisolated(unsafe)` unless nothing safer fits — then say why in a line.
- **Read only what the task needs.** Don't scan directories.
- **Simplicity first.** Shortest path to the requirement, root causes not symptoms, no speculative abstractions.
- **Commit to `main`.** No side branches, no pull requests. Pushing `main` ships nothing; releases go out through the release flow. If a change shouldn't land, leave it uncommitted and say so.

## Where things are

| Path                | What                                          |
| ------------------- | --------------------------------------------- |
| `appkit.json`       | platform, locales, scenes, store ids, version |
| `scripts/scenes.sh` | what a store screenshot IS for this app       |
| `store/`            | the storyboard, the words, the cards          |
| `appkit`            | shared, installed; never edited from the app  |

`AGENTS.core.md`, `.prettierrc`, `.swiftformat`, `.githooks/` and `.claude/skills/` are appkit's, copied in by `appkit sync` and checked by `appkit doctor`. Edit them in appkit and sync, never here.

A locale, scene name or store folder written into a script is drift — all three are rows in `appkit.json`.

## Design tokens

`DesignSystem/Tokens/`. `Scale` and `Opacity` are the kit's and generated — edit them in `../appkit/swift/` and re-sync. `Spacing`, `Radii`, `Palette`, `Typography`, `Motion`, `Materials` are the app's, because they are the brand.

`Spacing` and `Radii` **name** rungs on `Scale` rather than restating numbers (`static let giant = Scale.s8`): the ladder is shared, which rung a name points at is not.

A number a token covers, written into a view, is drift.

## Swift style

Value types, small views, clear names, async/await, `@MainActor` only where needed. Avoid force unwraps, unowned tasks, type erasure for its own sake, massive view bodies, hidden state synchronisation.

## Changes

Match the surrounding style, keep diffs minimal, prefer local fixes. Never silently change behaviour, persistence or navigation. Changing a data shape means its initializers, previews and sample data too — and migration for data already on devices.

Formatting is the pre-commit hook's job: `swiftformat` then `prettier`, over **staged** files only. `kit sync` points git at it.

## Comments

Say what the code cannot — why this constant, why this ordering — in a line or two. No file headers, no essays, nothing restating the code. A trap someone would fall back into is worth a sentence; history is not.

## Copy

Concise, warm, product-like. Never a raw `String` for a label a person reads — `LocalizedStringKey` or `LocalizedStringResource`.

## Answers

Say what changed, why, and what to verify. **Never claim a build ran unless you ran it** — and you almost certainly did not.
