# The card storyboard

`store/cards.json` is what a store card looks like and what it says, in one file, read by `render/compose.swift`. JSON rather than code so it is data: a second renderer, a preview, or another platform's app reads the same file.

## The shape

**The card size is not a choice.** Every iOS card is 1242×2688 and CI fails one that is not — one display size means one set to review. Captures come off an iPhone 17 Pro (1206×2622) and are composed onto it.

```jsonc
{
  "card": { "width": 1242, "height": 2688 },

  "locales": [
    { "capture": "en", "out": "en-US" },
    { "capture": "es", "out": "es-ES" },
    { "capture": "es", "out": "es-MX" }, // one capture, two listings
  ],

  "fonts": {
    "display": {
      "family": "Poppins",
      "files": { "700": "Poppins-Bold.ttf" },
      "cjk": { "ja": "HiraginoSans-W6", "ko": "AppleSDGothicNeo-Bold" },
    },
  },

  "defaultDevice": "iphone",
  "devices": {
    "iphone": {
      "aspect": 0.4891,
      "radius": 0.113,
      "bezel": 0.0533,
      "color": "#1B1B20",
      "rim": "#4A4A52",
      "shadow": 0.05,
    },
  },

  "cards": [/* … */],
}
```

## A card

| Key            | What                                                       |
| -------------- | ---------------------------------------------------------- |
| `name`         | the filename after its number: `03-trending.png`           |
| `background`   | `{"color"}`, or `{"type":"gradient","colors":[…],"angle"}` |
| `device`       | the phone, and which capture is on it                      |
| `extraDevices` | more of them, ordered by `layer`                           |
| `elements`     | art laid on top: a glyph, a widget render, a photo block   |
| `caption`      | the words                                                  |
| `span`         | two cards carrying one device across both                  |
| `size`         | a different canvas — Play's feature graphic, a store icon  |
| `dir`          | a subfolder and its own numbering                          |
| `skip`         | locales this card is not in                                |

### Placement

`at` (vertical) and `x` (horizontal) place a device's **centre** as a percentage of the travel:

- `0` — the device's far edge meets the travel's near edge (almost entirely off)
- `50` — centred
- `100` — the other way round

A device is _meant_ to overflow the card. `zoom` is its width as a percentage of the card's, so `{"at": 40, "zoom": 82}` is the familiar "phone from the top, caption below".

Elements are placed by their top-left corner instead — `x`, `y`, `width`, `height`, all percentages — because they are art, not devices, and art is positioned by its box.

### Spans

Two cards with the same `span` name carry one device across both:

```jsonc
{ "name": "hero-a", "span": "hero", "device": { "…": "…", "x": 35 } },
{ "name": "hero-b", "span": "hero" }
```

The first is the lead and holds the layout; the second shows the continuation. The pair is rendered **once**, on a canvas two cards wide, and each card takes its half — which is what makes the halves line up exactly across a store carousel rather than to within a rounding of a rotation.

### Captions

```jsonc
"caption": {
  "at": 16,
  "lines": [
    { "text": { "en": "Every lyric,", "ja": "どんな歌詞も" },
      "size": 104, "color": "#FFFFFF", "lineHeight": 1.05 }
  ]
}
```

`at` is where the block's centre sits, as a percentage of card height. A `text` that is a plain string is used for every language; an object is keyed by capture language, and a locale with no entry falls back to `default`, then to `en` — never to nothing, because a card silently missing its headline still renders and still uploads.

Sizes are **card pixels**, so they are only comparable within one card size. Everything else is a percentage and moves with the canvas on its own.

### Captures and art

A device or an element names either:

- **`scene`** — a capture, resolved to `.screenshots/<language>/<scene>.png`
- **`image`** — a path in the repo, the same for every language
- **`localized`** — a path per language, for art that carries text

Prefer `scene`. A widget render and a phone capture are both things the app was photographed doing, so both come out of the same per-language folder and neither needs a path per locale written down anywhere.

### Devices are drawn, not photographed

A device model is four numbers and two colours: `aspect` (screen width ÷ height), `radius` and `bezel` (fractions of the device's own width), `color`, and `rim` — a hairline just inside the body, which is the one thing a photographed bezel gives away for free and the difference between reading as a device and reading as a black rectangle.

Drawn rather than photographed because a bezel PNG is another binary asset to keep in step, and one more thing that resamples differently at every card size. This one is exact at any.

The Apple Watch model leaves the band off deliberately: a band is a second material, a second colour choice and a second asset, and the card is about what is on the screen.

### Fonts

A face is a `family` (resolved against installed fonts), or `files` keyed by weight (resolved against the kit's `render/fonts` and then the repo), plus a `cjk` map from capture language to a face appended as a **cascade**.

The cascade is explicit on purpose. CoreText's implicit fallback for Han characters depends on the system's language order, so the same card rendered on two machines came out in two typefaces. With a cascade, a line that mixes Latin and Japanese is shaped once, in the two faces you named.

A face that resolves to neither a file nor an installed family falls back to the system font and says so on stderr. The card renders — but not quietly in the wrong typeface.

## Determinism

Same storyboard, same captures, same bytes. Check it any time:

```sh
appkit render --locale en
shasum -a 256 store/screenshots/en-US/*.png > /tmp/a
appkit render --locale en
shasum -a 256 store/screenshots/en-US/*.png | diff /tmp/a -
```

If that ever differs, the bug is in the composer, not in the tolerance.
