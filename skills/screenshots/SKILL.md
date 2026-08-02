---
name: screenshots
description:
  Capture, compose or debug this repo's store screenshots — adding a scene,
  changing a card's layout or caption, chasing a set that will not reproduce, or
  adding a language. Use when working on the screenshot pipeline itself rather
  than shipping a release.
---

# Screenshots

The pipeline has three stages and they fail in different ways. Find the stage first; most of the time spent on a bad set is spent debugging the wrong one.

```
appkit capture   device → .screenshots/<language>/<scene>.png    (gitignored)
appkit render    those  → store/screenshots/<locale>/NN-name.png (tracked)
appkit publish   those  → the store
```

## The four files that decide everything

| File                | Owns                                                      |
| ------------------- | --------------------------------------------------------- |
| `appkit.json`       | the scene list, the locale table, the device, the jobs    |
| `scripts/scenes.sh` | what a scene IS — how it is launched and when it is still |
| `store/cards.json`  | how a card looks and what it says                         |
| `appkit`            | everything else, and it is not yours to edit from here    |

If you are about to write a locale code, a scene name, or a store folder name into a script: stop. All three are rows in `appkit.json`, and every stage reads them from there.

## Adding a scene

1. Add it to the app's own screenshot mode (the debug-only enum that stages it).
2. Add its name to `capture.scenes` in `appkit.json`.
3. Give it a settle floor in `scripts/scenes.sh` if it animates its way in.
4. Add a card for it in `store/cards.json` — the file order is the store order.
5. `appkit capture --scene <name>` then `appkit render`.

A scene that is not in `capture.scenes` is rejected before the first launch. A name that reached the app unchecked would draw the app's default screen and file it under whatever was asked for — a shot that looks fine and is of the wrong thing.

## Adding a language

One row in `appkit.json`'s `locales`, then a caption for it in every card. The capture code drives the app; the store code names the folder. On iOS the run refuses to start if the built bundle has no `.lproj` for a new language — that check exists because capture reuses whatever bundle is there, including one from before the language was added and file a full set of English captures under it.

## A set that will not reproduce

Two captures of one scene must be the same **bytes**. The shutter already waits for two identical frames, so anything that differs is a scene that was still moving when both were taken — usually because the settle floor does not reach past the animation's _start_, and two frames taken before it begins agree just as well as two after it ends.

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
