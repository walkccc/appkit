---
name: copy
description: Write or change the product's words — the store listing, the release notes, the privacy and support pages — in every language. Use when drafting what's new for a release, editing a description or keywords, adding a language, or reviewing listing text before it goes up.
---

# Copy

Every word a store shows lives in one tracked directory, `store/metadata/`. Nothing is typed into App Store Connect or the Play Console by hand: appkit reads this tree and uploads it.

## The tree

```
store/metadata/
  app/<language>.json                  name, subtitle, privacy URL
  version/<language>.json              description, keywords, promo text, support URL
  changelog/<version>/<language>.md    what changed in one release
  pages/<page>/<language>.md           privacy, support, terms — full documents
```

`app/` and `version/` split the way Apple splits them: **`app/` fields survive a release, `version/` fields belong to the one being submitted.** That matters because a change to `app/` affects the listing immediately and a change to `version/` waits for review.

Which keys go where:

| File        | Keys                                                                                   |
| ----------- | -------------------------------------------------------------------------------------- |
| `app/…`     | `name`, `subtitle`, `privacyPolicyUrl`, `privacyChoicesUrl`                            |
| `version/…` | `description`, `keywords`, `promotionalText`, `marketingUrl`, `supportUrl`, `whatsNew` |

A key in the wrong file is ignored silently, so check this table when a field you edited does not appear on the store.

## Filenames are capture languages, not store locales

`<language>` is the `capture` value from a row of `appkit.json`'s `locales` — the same code the screenshots are shot in. It is **not** what either store calls that language.

```json
{ "capture": "ja", "appStore": "ja", "play": "ja-JP" }
```

So the file is `app/ja.json`, and appkit renames it to `ja` for Apple and `ja-JP` for Google on the way out. Naming the file `ja-JP.json` would serve Google and leave Apple with nothing.

**One exception, and it is the reason the rule exists:** a file named for a _store_ locale wins over the capture language for that row. `es-ES.json` beside `es.json` means Spain gets the first and every other Spanish row gets the second — which is how one screenshot set serves two listings that say different things.

## The commands

```sh
appkit publish copy --pull    # download what the store shows RIGHT NOW
appkit copy check             # lengths and per-language coverage, no network
appkit copy note 1.3.0        # create an empty release-note file per language
appkit publish copy 1.3.0     # upload
```

`appkit copy check` touches no network and is the one to run while writing: it checks the lengths **and** that every language has every file. `appkit publish copy --check` checks the lengths only, then stops before uploading.

## Always pull before editing

```sh
appkit publish copy --pull
```

It writes the live listing to `.asc/metadata-live/`, untracked. Compare it against `store/metadata/` before changing a word.

The reason is specific: someone tightens a subtitle in App Store Connect during a review, it never comes back to the repo, and the next `publish copy` overwrites it with the older tracked version. The tree is the source of truth only if it is kept current, and pulling is how you keep it current.

## Limits

`check` counts **characters, not bytes** — every CJK locale fails a byte count that `en-US` passes. An app on both stores is checked against the tighter of the two, because copy that fits one store and not the other fails a push after it has already changed some locales.

| Field              | App Store | Play                    |
| ------------------ | --------- | ----------------------- |
| `name`             | 30        | 30 (title)              |
| `subtitle`         | 30        | —                       |
| `shortDescription` | —         | 80                      |
| `keywords`         | 100       | — (no such field)       |
| `promotionalText`  | 170       | —                       |
| `description`      | 4000      | 4000 (full description) |
| release note       | 4000      | 500                     |

Write release notes to Play's 500 and the App Store is free.

Keywords are comma-separated with **no space after the comma** — a space is an indexed character, so `puzzle, cards` wastes one of the hundred on nothing.

## Writing rules

- **Borrow the app's own words.** Every term should be one the app already ships in its dictionary. A listing that names a mechanic differently teaches the wrong word before the user has opened anything.
- **Keywords repeat nothing from the name or subtitle.** Those are already indexed; a repeat spends characters twice.
- **N languages means N keyword sets, not one translated N times.** What a Japanese user types into search is not the translation of what an English one types.
- **Promotional text is the only field that changes without a review.** Anything time-bound — a sale, an event, a season — goes there and nowhere else.

## Release notes

```sh
appkit copy note 1.3.0
```

Creates `changelog/1.3.0/<language>.md`, empty, one per language. Empty on purpose: a stub reading "TODO" looks like finished text to a translator. Write English first, then translate.

`appkit copy check` names any that stayed empty. This is the failure worth catching — a language with no note for this version ships the previous version's note, and no one notices because the listing looks complete.

Old versions stay in the tree. The stores take the version being shipped; the changelog is the history.

## Pages

`pages/privacy`, `pages/support`, `pages/terms` are full Markdown documents, one per language. The stores **link** to them rather than hosting them, so the product's own site serves them and this tree is where they are written.

Both stores refuse to publish without a privacy URL. It goes in `app/<language>.json` as `privacyPolicyUrl`.
