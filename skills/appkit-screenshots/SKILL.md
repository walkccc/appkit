---
name: appkit-screenshots
description: Capture, compose or debug this repo's store screenshots — adding a scene, changing a card's layout or caption, chasing a set that will not reproduce, or adding a language. Use when working on the screenshot pipeline itself rather than shipping a release.
---

# Screenshots

The pipeline has three stages and they fail in different ways. Find the stage first; most of the time spent on a bad set is spent debugging the wrong one.

```
appkit capture             device → .screenshots/<language>/<scene>.png    (gitignored)
appkit render              those  → store/screenshots/<locale>/NN-name.png (tracked)
appkit make screenshots    both of the above, and stop
appkit review screenshots  those  → one sheet, every locale, changes framed
appkit upload screenshots  those  → the store
```

`review` is how a set is read: every card at once, a red frame where git says one
changed and a green one where it is new. A hole in the grid is a locale short of
a scene, which is the finding a per-file diff is worst at showing.

## The four files that decide everything

| File                | Owns                                                      |
| ------------------- | --------------------------------------------------------- |
| `appkit.json`       | the scene list, the locale table, the jobs                |
| `scripts/scenes.sh` | what a scene IS — how it is launched and when it is still |
| `store/cards.json`  | how a card looks and what it says                         |
| `appkit`            | everything else, and it is not yours to edit from here    |

If you are about to write a locale code, a scene name, or a store folder name into a script: stop. All three are rows in `appkit.json`, and every stage reads them from there.

**The device is not one of them.** Every iOS capture is taken on an iPhone 17 Pro, which appkit finds or creates; a parallel worker of any other model is deleted and remade. There is nothing to configure and nothing to keep in step — and a run that ends with captures of two different sizes says so, loudly, because that is the failure that otherwise arrives disguised as an animation.

`appkit doctor` prints the model, so "which phone do these come off" is answerable here rather than by reading appkit. It is pinned there and not in `appkit.json` on purpose: one place to move means every repo moves at once, and a per-repo model is a per-repo way to drift silently.

**`ios.deviceTypes` is the display size the cards are FILED under**, which follows `store/cards.json`'s own dimensions and not the phone. 1242x2688 is `IPHONE_65`. Get it wrong and nothing errors: `--device-type` is a filter, so an upload with no matching pixels sends zero files and reports success. Doctor checks the two against each other.

## Adding a scene

No screenshot mode in the app yet? That's `/appkit-add-screenshots-mode`, not this — this skill assumes the wiring already exists and is about the scenes running through it.

1. Add it to the app's own screenshot mode (the debug-only enum that stages it).
2. Add its name to `capture.scenes` in `appkit.json`.
3. Give it a settle floor in `scripts/scenes.sh` if it animates its way in.
4. Add a card for it in `store/cards.json` — the file order is the store order.
5. `appkit capture --scene <name>` then `appkit render`.
6. `appkit review screenshots` — the new column should be green in every locale. One that is missing is a caption the storyboard never got.

A scene that is not in `capture.scenes` is rejected before the first launch. A name that reached the app unchecked would draw the app's default screen and file it under whatever was asked for — a shot that looks fine and is of the wrong thing.

## Adding a language

One row in `appkit.json`'s `locales`, then a caption for it in every card. The capture code drives the app; the store code names the folder. On iOS the run refuses to start if the built bundle has no `.lproj` for a new language — that check exists because capture reuses whatever bundle is there, including one from before the language was added and file a full set of English captures under it.

## A set that will not reproduce

Two captures of one scene must be the same **bytes**. The shutter already waits for two identical frames, so anything that differs is a scene that was still moving when both were taken — usually because the settle floor does not reach past the animation's _start_, and two frames taken before it begins agree just as well as two after it ends.

- **First check the sizes.** A capture off another model composes into a card that looks plausible and will not reproduce — the run now says "Captures are NOT all one size" when that happens, and that is the real cause, not an animation.
- The run names every scene that never held still, at the end and again in the warning. Believe it.
- `appkit render` says how many cards it put back at the old bytes. Any at all means the same thing.
- Anything with `repeatForever` in it has to be stilled under screenshot mode, not waited out.
- The composer itself is deterministic: same storyboard, same captures, same bytes. If the cards differ and the captures did not, the storyboard changed.

## Layout, in the storyboard

- `at` and `x` place a device's **centre** as a percentage of the travel: 0 puts its far edge against the near edge, 100 the other way, 50 centres it. A device is meant to overflow the card — that is what makes a card look like a phone rather than a picture of one.
- `zoom` is the device's width as a percentage of the card's.
- Two cards sharing a `span` carry one device across both. The pair is rendered once, on a canvas two cards wide, and each card takes its half — so the halves line up exactly rather than to within a rounding.
- Captions are laid out by CoreText with an explicit CJK cascade per language. Do not add a second font "for Japanese"; add a `cjk` entry to the face.

## What not to do

- Do not build to take a screenshot. Ask for a build; capture reuses it.
- Do not run two capture runs at once — they interleave silently.
- Do not widen the same-picture tolerance to make a diff go away.
- Do not hand-edit anything under `store/screenshots`. It is output.
