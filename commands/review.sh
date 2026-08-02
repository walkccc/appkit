#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit review screenshots — every store card in one picture.
#
#   appkit review screenshots            # draw the sheet, and open it
#   appkit review screenshots --no-open  # just draw it
#   appkit review screenshots --width 320
#   appkit review screenshots --scale 1  # half the pixels, for a quick look
#
# One row per locale, one column per card, and a frame around the ones git calls
# new or changed. `git status -- store/screenshots` already answers WHETHER a
# card changed; a PNG diff in a terminal cannot answer WHICH, or show you the
# nine other languages that changed with it.
#
# Reads the composed cards, not the raw captures — this reviews what would go up
# if the next command were `appkit upload screenshots`.
#
# The sheet lands in .build/, which is ignored: it is a view of the tracked
# cards, not another artefact to keep in step with them.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$APPKIT_DIR/lib/manifest.sh"
# shellcheck source=../lib/pictures.sh
. "$APPKIT_DIR/lib/pictures.sh"

what="${1:-screenshots}"
case "$what" in
  screenshots) shift || true ;;
  help | -h | --help) appkit_usage "$0"; exit 0 ;;
  --*) ;;
  *) die "appkit review takes: screenshots" ;;
esac

open_it=true
width=200
# Drawn at 2× and read at 1×, because the thing being reviewed is a caption on a
# card shrunk six-fold: at 1× the sheet answers "which card moved" but not "into
# what", and the second question is the one that sends you back to the app.
scale=2
while (($#)); do
  case "$1" in
    --no-open) open_it=false; shift ;;
    --width) [[ $# -ge 2 ]] || die "--width needs a number"; width="$2"; shift 2 ;;
    --scale) [[ $# -ge 2 ]] || die "--scale needs a number"; scale="$2"; shift 2 ;;
    help | -h | --help) appkit_usage "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see: appkit help review)" ;;
  esac
done

[[ -d "$SHOTS_DIR" ]] ||
  die "no cards at $SHOTS_DIR_REL — run: appkit make screenshots"

# What git already knows, asked once. Tracked-but-modified and never-committed
# are different findings — a card that changed is a screen that moved, and a
# card that is new is a scene or a language that arrived — so they are collected
# apart and framed in different colours.
changed_list="$(mktemp)"
new_list="$(mktemp)"
trap 'rm -f "$changed_list" "$new_list"' EXIT
git -C "$ROOT_DIR" diff --name-only HEAD -- "$SHOTS_DIR_REL" >"$changed_list" 2>/dev/null || true
git -C "$ROOT_DIR" ls-files --others --exclude-standard -- "$SHOTS_DIR_REL" >"$new_list" 2>/dev/null || true

# The order the store shows them in, when the storyboard says: cards.json is the
# same file the composer fanned out over, so the sheet reads down the locales in
# listing order rather than in whatever order the filesystem hands back. A repo
# rendering its own cards has no storyboard, and sorted is the honest fallback.
locales=()
if [[ -n "${CARDS_FILE:-}" && -f "$ROOT_DIR/$CARDS_FILE" ]]; then
  while IFS= read -r locale; do
    [[ -d "$SHOTS_DIR/$locale" ]] && locales+=("$locale")
  done < <(python3 -c '
import json, sys
seen = set()
for row in json.load(open(sys.argv[1]))["locales"]:
    if row["out"] not in seen:
        seen.add(row["out"])
        print(row["out"])
' "$ROOT_DIR/$CARDS_FILE")
fi
# Anything on disk the storyboard did not name — a locale just dropped from it
# still has a folder, and a sheet that hid it would hide the thing to fix.
while IFS= read -r dir; do
  locale="$(basename "$dir")"
  for known in ${locales[@]+"${locales[@]}"}; do
    [[ "$known" == "$locale" ]] && continue 2
  done
  locales+=("$locale")
done < <(find "$SHOTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

((${#locales[@]})) || die "no locale folders under $SHOTS_DIR_REL"

sheet="$ROOT_DIR/.build/review/screenshots.png"

size="$(
  for locale in "${locales[@]}"; do
    while IFS= read -r card; do
      [[ -n "$card" ]] || continue
      relative="$SHOTS_DIR_REL/$locale/$(basename "$card")"
      label="$(basename "$card" .png)"
      if grep -qxF "$relative" "$new_list"; then
        status=new
      elif grep -qxF "$relative" "$changed_list"; then
        status=changed
      else
        status=same
      fi
      printf '%s\t%s\t%s\t%s\n' "$locale" "$label" "$ROOT_DIR/$relative" "$status"
    done < <(find "$SHOTS_DIR/$locale" -maxdepth 1 -name '*.png' | sort)
  done | "$(appkit_tool contact-sheet)" --out "$sheet" --title "$APP_NAME" \
    --width "$width" --scale "$scale"
)"

marked=$(($(grep -c . "$changed_list" || true) + $(grep -c . "$new_list" || true)))
log "Sheet at ${sheet#"$ROOT_DIR"/} ($size)"
if ((marked == 0)); then
  log "  no card differs from HEAD — nothing framed"
else
  log "  $marked card(s) framed: red changed, green new"
fi

[[ "$open_it" == true ]] && open "$sheet"
exit 0
