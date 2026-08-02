#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit new — stand up a repo on appkit, from nothing.
#
#   appkit new ios      --name Tefuda --bundle com.example.Tefuda
#   appkit new macos    --name Framedly --bundle app.framedly.recorder
#   appkit new android  --name Tefuda --package com.example.tefuda
#
#   --locales "en ja zh-Hant"   the languages this app ships (default: en)
#   --scenes  "home detail"     the store scenes (default: two placeholders)
#   --force                     overwrite files that already exist
#
# Writes the files a repo on appkit owns, then syncs, then commits — `git
# init` if there's no repo yet, one commit if there is. It does NOT create
# the app — Xcode, Android Studio and your framework of choice still make the
# project. What this makes is the pipeline around it, which is the part that is
# the same every time and the part nobody enjoys copying out of a sibling repo.
#
# Copying a sibling repo is exactly what this replaces: every time it happened
# here, something app-specific came across with it — a locale table, a settle
# floor measured against another app's animations, a scene name for a screen
# this app does not have.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The one command that scaffolds INTO the current directory rather than into the
# repo above it: there is no appkit.json yet, so there is nothing to walk up to.
# `mkdir tefuda-ios && cd tefuda-ios && appkit new ios --name Tefuda`.
ROOT_DIR="$PWD"
# shellcheck source=../lib/log.sh
. "$APPKIT_DIR/lib/log.sh"

platform="${1:-}"
shift || true
case "$platform" in
  ios | macos | android) ;;
  help | -h | --help)
    appkit_usage "$0"
    exit 0
    ;;
  *) die "usage: appkit new <ios|macos|android> --name <Name> [...]" ;;
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
# Every other platform can read a bundle id off something the toolchain built.
# macOS cannot: appkit WRITES the Info.plist, so the id has to come from here or
# there is nothing to write — and a wrong one is a permission grant filed under
# an app that does not exist.
[[ "$platform" != macos || -n "$bundle" ]] ||
  die "--bundle is required on macOS (e.g. --bundle com.example.${name})"
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

# `appkit sync` sets core.hooksPath below, which needs a repo to set it IN —
# so this has to exist before that runs, not after. Safe to call on a repo
# that already has one; git just leaves it alone.
if ! git -C "$ROOT_DIR" rev-parse --git-dir &>/dev/null; then
  git -C "$ROOT_DIR" init -q
  log "  git init"
fi

manifest_locales() {
  local first=true language store
  for language in $locales; do
    [[ "$first" == true ]] || printf ',\n'
    first=false
    # `en` is the one code both stores rename; everything else is already what
    # they call it, and a row only carries the stores this app is on.
    store="$language"
    [[ "$language" == "en" ]] && store="en-US"
    # macOS files with iOS here: the Mac App Store is App Store Connect, and a
    # locale is spelled the same way on it.
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
    "_": [
      "deviceTypes is the display size a card is FILED under, and it follows",
      "the card's own dimensions: store/cards.json writes 1242x2688, which is",
      "IPHONE_65. The 6.9-inch set is a different shape, and asc will happily",
      "file one as the other."
    ],
    "scheme": "$name",
    "deviceTypes": ["IPHONE_65"],
    "ascAppId": "TODO — asc apps list --bundle-id"
  },
IOS
      ;;
    macos) cat <<MACOS

  "macos": {
    "_": [
      "SwiftPM emits a bare executable, so the .app around it is appkit's to",
      "assemble: \`infoPlist\` is the template it fills in (__APP_NAME__ and",
      "__BUNDLE_ID__ are substituted), \`resources\` are the files copied in",
      "beside the SwiftPM resource bundles, and \`icon\` is the 1024 master.",
      "",
      "\`iconCommand\` is for an icon that is DRAWN by a program rather than",
      "checked in. Without it the master on disk is used as-is."
    ],
    "product": "$name",
    "configuration": "release",
    "infoPlist": "Resources/Info.plist",
    "resources": []
  },

  "ios": {
    "_": [
      "The Mac App Store is App Store Connect, so a macOS repo declares the",
      "same two keys an iOS one does. DESKTOP is the only display type Apple",
      "files Mac imagery under, and it accepts 1280x800, 1440x900, 2560x1600",
      "and 2880x1800 — store/cards.json draws the last of those."
    ],
    "deviceTypes": ["DESKTOP"],
    "ascAppId": "TODO — asc apps list --bundle-id"
  },
MACOS
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

  "appkit": "$(cat "$APPKIT_DIR/VERSION")",
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
  macos)
    write scripts/scenes.sh <<'SCENES'
# What a screenshot IS in this app. Sourced by `appkit capture`, which owns
# everything else — quitting the last copy, the settle, and `snap_when_still`,
# the shutter that holds out for two identical frames.
#
# The scene LIST is appkit.json's; what belongs here is when a scene has
# actually arrived, which is a property of THIS app and of no other.
#
# A macOS capture photographs the app's FRONT WINDOW, so the settle has to
# outlast the window actually opening — a cold `open -n` returns long before
# there is anything on screen, and window-id fails rather than photographing
# the wrong thing.

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

    # The bundle appkit assembles is built around this. Written here because a
    # macOS repo cannot build at all without one, unlike the iOS and Android
    # scaffolds where the IDE has already made the equivalent.
    write Resources/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- __APP_NAME__ and __BUNDLE_ID__ are substituted by `appkit run` from
	     appkit.json, so neither name is written twice. Everything else here is
	     this app's own. -->
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>__APP_NAME__</string>
	<key>CFBundleIdentifier</key>
	<string>__BUNDLE_ID__</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>__APP_NAME__</string>
	<key>CFBundleDisplayName</key>
	<string>__APP_NAME__</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<!-- `appkit version` moves both of these; nothing else should. -->
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST
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

# --- the storyboard and the words -------------------------------------------

if [[ ! -e "$ROOT_DIR/store/cards.json" || "$force" == true ]]; then
  mkdir -p "$ROOT_DIR/store"
  python3 - "$APPKIT_DIR/templates/cards.json" "$ROOT_DIR/store/cards.json" \
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
elif platform == "macos":
    board["card"] = {"width": 2880, "height": 1800}
    board["_"].append("")
    board["_"].append(
        "2880x1800 is the largest of the four sizes App Store Connect files "
        "under DESKTOP, and the only landscape card shape in appkit.")

# Keep every caption speaking every language, so CI passes on the first push.
for card in board["cards"]:
    for line in (card.get("caption") or {}).get("lines", []):
        text = line["text"]
        if isinstance(text, str):
            continue
        base = text.get("en") or next(iter(text.values()))
        line["text"] = {language: text.get(language, base) for language in languages}

open(out, "w").write(json.dumps(board, ensure_ascii=False, indent=2) + "\n")
PY
  log "  wrote store/cards.json"
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

# --- wire it up -------------------------------------------------------------

"$APPKIT_DIR/bin/appkit" sync

# The first commit, made here rather than left for the end user, so that
# everything appkit wrote lands as one commit before the app's own code
# exists — a later `git blame` on any of it points here, not at whatever
# unrelated commit happened to touch the file next.
git -C "$ROOT_DIR" add -A
if git -C "$ROOT_DIR" diff --cached --quiet; then
  warn "  nothing new to commit"
else
  git -C "$ROOT_DIR" commit -q -m "chore: \`appkit new $platform\`"
  log "  committed: chore: \`appkit new $platform\`"
fi

log ""
log "Next:"
log "  1. make the app project itself (Xcode / Android Studio / your framework)"
log "  2. wire a debug-only screenshot mode into it — appkit-add-screenshots-mode"
log "  3. make the store's app record, and put its id in appkit.json"
log "  4. appkit pull metadata         if this app is already on a store"
log "  5. fill in the TODOs in store/metadata, then: appkit check metadata"
log "  6. appkit make screenshots"
