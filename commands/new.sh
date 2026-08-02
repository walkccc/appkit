#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit new — stand up a repo on the kit, from nothing.
#
#   appkit new ios      --name Tefuda --bundle com.example.Tefuda
#   appkit new android  --name Tefuda --package com.example.tefuda
#
#   --locales "en ja zh-Hant"   the languages this app ships (default: en)
#   --scenes  "home detail"     the store scenes (default: two placeholders)
#   --force                     overwrite files that already exist
#
# Writes the five files a repo on the kit owns, then syncs. It does NOT create
# the app — Xcode, Android Studio and your framework of choice still make the
# project. What this makes is the pipeline around it, which is the part that is
# the same every time and the part nobody enjoys copying out of a sibling repo.
#
# Copying a sibling repo is exactly what this replaces: every time it happened
# here, something app-specific came across with it — a locale table, a settle
# floor measured against another app's animations, a scene name for a screen
# this app does not have.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The one command that scaffolds INTO the current directory rather than into the
# repo above it: there is no appkit.json yet, so there is nothing to walk up to.
# `mkdir tefuda-ios && cd tefuda-ios && appkit new ios --name Tefuda`.
ROOT_DIR="$PWD"
# shellcheck source=../lib/log.sh
. "$KIT_DIR/lib/log.sh"

platform="${1:-}"
shift || true
case "$platform" in
  ios | android) ;;
  -h | --help)
    sed -n '5,25p' "$0"
    exit 0
    ;;
  *) die "usage: appkit new <ios|android> --name <Name> [...]" ;;
esac

name=""
bundle=""
package=""
locales="en"
scenes=""
force=false

while (($#)); do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    --bundle) bundle="$2"; shift 2 ;;
    --package) package="$2"; shift 2 ;;
    --locales) locales="$2"; shift 2 ;;
    --scenes) scenes="$2"; shift 2 ;;
    --force) force=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$name" ]] || die "--name is required"
[[ -n "$scenes" ]] || scenes="home detail"

# Never clobber. A repo being scaffolded twice is usually somebody adding a
# platform to a product, not starting over.
write() {
  local path="$ROOT_DIR/$1"
  if [[ -e "$path" && "$force" == false ]]; then
    warn "  kept existing $1"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  cat >"$path"
  log "  wrote $1"
}

# --- the manifest -----------------------------------------------------------

log "Scaffolding $name ($platform)"

manifest_locales() {
  local first=true language store
  for language in $locales; do
    [[ "$first" == true ]] || printf ',\n'
    first=false
    # `en` is the one code both stores rename; everything else is already what
    # they call it, and a row only carries the stores this app is on.
    store="$language"
    [[ "$language" == "en" ]] && store="en-US"
    case "$platform" in
      android) printf '    { "capture": "%s", "play": "%s" }' "$language" "$store" ;;
      *) printf '    { "capture": "%s", "appStore": "%s" }' "$language" "$store" ;;
    esac
  done
}

manifest_scenes() {
  local first=true scene
  for scene in $scenes; do
    [[ "$first" == true ]] || printf ', '
    first=false
    printf '"%s"' "$scene"
  done
}

manifest_platform() {
  case "$platform" in
    ios) cat <<IOS

  "ios": {
    "scheme": "$name",
    "simulator": "iPhone 17 Pro Max",
    "deviceTypes": ["IPHONE_69"],
    "ascAppId": "TODO — asc apps list"
  },
IOS
      ;;
    android) cat <<ANDROID

  "android": {
    "package": "${package:-com.example.${name:l}}",
    "activity": ".MainActivity",
    "logTag": "$name",
    "track": "production"
  },
ANDROID
      ;;
  esac
}

write appkit.json <<MANIFEST
{
  "_": [
    "What $name declares to appkit. Every appkit command, the pre-commit hook",
    "and CI read this file; nothing else in the repo restates anything here.",
    "",
    "\`appkit\` is the oldest version that can run this repo — a floor, not a",
    "pin, which doctor checks and brew keeps you above.",
    "",
    "The locale rows are the only place a language is named — \`capture\` drives",
    "the app and names the folder a raw capture lands in, and the rest are each",
    "store's spelling of the same language."
  ],

  "appkit": "$(cat "$KIT_DIR/VERSION")",
  "name": "$name",
  "platform": "$platform",$([[ -n "$bundle" ]] && printf '\n  "bundleId": "%s",' "$bundle")
  "sources": ["$name"],

  "locales": [
$(manifest_locales)
  ],

  "capture": {
    "_": "Scene names, in the order the store lists them.",
    "scenes": [$(manifest_scenes)],
    "jobs": 1,
    "appearance": "dark"
  },
$(manifest_platform)
  "render": { "cards": "store/cards.json", "out": "store/screenshots" },

  "store": { "metadata": "store/metadata" }
}
MANIFEST

# --- what a scene is --------------------------------------------------------

case "$platform" in
  ios)
    write scripts/scenes.sh <<'SCENES'
# What a screenshot IS in this app. Sourced by `appkit capture`, which owns
# everything else — the device, the workers, the sharding, the progress line,
# and `snap_when_still`, the shutter that holds out for two identical frames.
#
# The scene LIST is appkit.json's; what belongs here is when a scene has actually
# arrived, which is a property of THIS app and of no other.

# The FLOOR under the wait, not the wait: two frames taken BEFORE a scene's way
# in begins agree exactly as well as two taken after it ends, so this has to
# reach past every animation's start.
settle_for() {
  case "$1" in
    *) printf '4' ;;
  esac
}

capture_scene() {
  local scene="$1" language="$2" output="$3" device="$4"
  platform_launch "$device" \
    -ScreenshotMode \
    -ScreenshotScene "$scene" \
    -AppleLanguages "($language)"
  sleep "$(settle_for "$scene")"

  if ! snap_when_still "$output" "$device"; then
    note_unsettled "$language/$scene"
    warn "  $language/$scene never held still over $STILL_TRIES frames"
  fi
}
SCENES
    ;;
  android)
    write scripts/scenes.sh <<'SCENES'
# What a screenshot IS in this app. Sourced by `appkit capture`, which owns
# everything else — the device, demo mode, the dark-mode pin, and
# `snap_when_still`, the shutter that holds out for two identical frames.
#
# The scene LIST is appkit.json's.

# A cold start can take fifteen seconds on an emulator, and the shell paints
# long before the seeded scene lands on top of it — so "not blank" is the wrong
# question. Have the app log a line when a scene is staged, and block on that.
STAGED="screenshot: staged"

capture_scene() {
  local scene="$1" language="$2" output="$3" device="$4"
  platform_launch "$device" \
    -e screenshotScene "$scene" \
    -e screenshotLanguage "$language"
  android_wait_for_log "$device" "$STAGED $scene\$"

  snap_when_still "$output" "$device" || note_unsettled "$language/$scene"

  # An ANR dialog is perfectly still and passes every other check, so it has to
  # be asked about separately.
  if android_is_anr "$device"; then
    warn "  $language/$scene hit an ANR — retrying"
    capture_scene "$scene" "$language" "$output" "$device"
  fi
}
SCENES
    ;;
esac

# --- the storyboard and the copy --------------------------------------------

if [[ ! -e "$ROOT_DIR/store/cards.json" || "$force" == true ]]; then
  mkdir -p "$ROOT_DIR/store"
  python3 - "$KIT_DIR/templates/cards.json" "$ROOT_DIR/store/cards.json" \
    "$name" "$locales" "$platform" <<'PY'
import json, sys

template, out, name, locales, platform = sys.argv[1:6]
board = json.loads(open(template).read())

languages = locales.split()
board["locales"] = [
    {"capture": language, "out": ("en-US" if language == "en" else language)}
    for language in languages
]
if platform == "android":
    board["card"] = {"width": 1242, "height": 2208}
    board["_"].append("")
    board["_"].append(
        "1242x2208 is exactly 9:16, the tallest Play accepts. An App Store card "
        "is taller and would be rejected here.")

# Keep every caption speaking every language, so CI passes on the first push.
for card in board["cards"]:
    for line in (card.get("caption") or {}).get("lines", []):
        text = line["text"]
        if isinstance(text, str):
            continue
        base = text.get("en") or next(iter(text.values()))
        line["text"] = {language: text.get(language, base) for language in languages}

open(out, "w").write(json.dumps(board, ensure_ascii=False, indent=2) + "\n")
print("  wrote store/cards.json")
PY
else
  warn "  kept existing store/cards.json"
fi

for language in $locales; do
  write "store/metadata/app/$language.json" <<META
{
  "name": "$name",
  "subtitle": "TODO — 30 characters",
  "shortDescription": "TODO — 80 characters, Play only"
}
META
  write "store/metadata/version/$language.json" <<META
{
  "description": "TODO — 4000 characters",
  "keywords": "TODO,comma,separated,no,spaces",
  "whatsNew": "TODO"
}
META
done

# --- CI ---------------------------------------------------------------------

if [[ -f "$KIT_DIR/ci/verify.yml" ]]; then
  mkdir -p "$ROOT_DIR/.github/workflows"
  if [[ ! -e "$ROOT_DIR/.github/workflows/verify.yml" || "$force" == true ]]; then
    cp "$KIT_DIR/ci/verify.yml" "$ROOT_DIR/.github/workflows/verify.yml"
    log "  wrote .github/workflows/verify.yml"
  fi
fi

# --- wire it up -------------------------------------------------------------

"$KIT_DIR/bin/appkit" sync

log ""
log "Next:"
log "  1. make the app project itself (Xcode / Android Studio / your framework)"
log "  2. add a debug-only screenshot mode that reads the scene from the launch"
log "  3. fill in the TODOs in store/metadata, and pull the live listing first"
log "     if this app is already on a store: appkit publish copy --pull"
log "  4. appkit capture --language ${locales%% *} && appkit render"
