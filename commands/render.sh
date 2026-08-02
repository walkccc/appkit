#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit render — compose the raw captures into store cards.
#
#   appkit render                 # every card, every locale
#   appkit render --locale ja     # one locale
#   appkit render --card widgets  # one card, by name
#   appkit render --card 6..8     # or by the number in its filename
#
# `--card` is the loop for working on a layout: composing is CoreGraphics, not a
# simulator, so redrawing one card in one locale is a second and needs nothing
# photographed. Both narrowings compose: `--locale en-US --card 8`.
#
# Two renderers, and a repo declares which in appkit.json:
#
#   "render": { "cards": "store/cards.json" }      appkit's composer
#   "render": { "command": "scripts/draw.sh" }     the repo's own
#
# The composer is the usual answer: a card is a capture on a background under a
# caption, which is a layout, not a drawing. A repo owns its renderer when its
# cards are ILLUSTRATED rather than composed — a title card drawn with
# CoreGraphics is a program, not a layout, and forcing it through a layout spec
# would be the same mistake as a shared Spacing.swift.
#
# Either way this command owns the two ends: it clears the output first (a scene
# dropped from the storyboard must leave with it, rather than shipping on under
# a number nothing claims) and settles the unchanged cards back to the bytes git
# already has afterwards.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$APPKIT_DIR/lib/manifest.sh"
# shellcheck source=../lib/pictures.sh
. "$APPKIT_DIR/lib/pictures.sh"

want_locales=()
want_cards=()
while (($#)); do
  case "$1" in
    --locale) [[ $# -ge 2 ]] || die "--locale needs a code"; want_locales+=("$2"); shift 2 ;;
    --card) [[ $# -ge 2 ]] || die "--card needs a name, number or range"; want_cards+=("$2"); shift 2 ;;
    help | -h | --help) appkit_usage "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see: appkit help render)" ;;
  esac
done

[[ -d "$OUT_DIR" ]] || die "no captures at $OUT_DIR — run: appkit capture"

if [[ -n "${CARDS_FILE:-}" ]]; then
  [[ -f "$ROOT_DIR/$CARDS_FILE" ]] || die "no storyboard at $CARDS_FILE"
  log "Composing $CARDS_FILE"
  mkdir -p "$SHOTS_DIR"
  compose="$(appkit_tool compose)"
  args=(--cards "$ROOT_DIR/$CARDS_FILE" --captures "$OUT_DIR" --out "$SHOTS_DIR"
    --fonts "$APPKIT_DIR/render/fonts" --appkit "$APPKIT_DIR")
  if ((${#want_cards[@]})); then
    for card in "${want_cards[@]}"; do args+=(--card "$card"); done
  fi
  if ((${#want_locales[@]} == 0)); then
    # Fanned out over the OUT folders, not the capture codes: two rows may
    # share one capture (es-ES and es-MX are photographed once), and a process
    # per capture would then render both rows twice.
    while IFS= read -r locale; do want_locales+=("$locale"); done < <(
      python3 -c '
import json, sys
for row in json.load(open(sys.argv[1]))["locales"]:
    print(row["out"])
' "$ROOT_DIR/$CARDS_FILE"
    )
    # A locale dropped from the storyboard should leave with its folder — but
    # only a whole-set pass may say so. A narrowed one is topping a set up, and
    # clearing first would delete every card it was not asked to draw.
    if ((${#want_cards[@]} == 0)); then
      rm -rf "${SHOTS_DIR:?}"
      mkdir -p "$SHOTS_DIR"
    fi
  fi
  # One process per locale: ten locales of three-megapixel cards is the one
  # place this pipeline is worth parallelising, and a process each keeps the
  # renderer itself single-threaded.
  render_pids=()
  for locale in "${want_locales[@]}"; do
    "$compose" "${args[@]}" --locale "$locale" &
    render_pids+=($!)
  done
  for pid in "${render_pids[@]}"; do
    wait "$pid" || die "rendering failed"
  done
elif [[ -n "${RENDER_CMD:-}" ]]; then
  log "Rendering with $RENDER_CMD"
  (cd "$ROOT_DIR" && eval "$RENDER_CMD")
else
  die "appkit.json declares neither render.cards nor render.command"
fi

settle_unchanged "$SHOTS_DIR"

log "Cards in $SHOTS_DIR"
