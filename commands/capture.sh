#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit capture — the store scenes, one cold launch per scene per language.
#
#   appkit capture                   # every scene, every language
#   appkit capture --scene board     # narrow to one scene
#   appkit capture --language ja     # narrow to one language
#   appkit capture --build           # compile first, rather than reusing
#
# It reuses the build already on the machine. That is the default because it is
# what nearly every run wants — a set is photographed off the build you have
# just been looking at — and because building is the step every app repo here
# forbids an agent from taking. `--build` is how you ask for it anyway.
#
# How many devices run side by side is appkit.json's capture.jobs.
#
# The kit owns the harness: resolving the device, making the workers, booting
# them, checking the build is newer than the sources, sharding the languages
# across devices, the progress line, and the two-identical-frames shutter.
#
# The repo owns what a scene IS. scripts/scenes.sh must define capture_scene;
# it may also define pre_capture and post_capture, which run before the first
# launch and after the last one. The scene list is appkit.json's.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$KIT_DIR/lib/manifest.sh"
# shellcheck source=../lib/shard.sh
. "$KIT_DIR/lib/shard.sh"
use_platform

JOBS="${CAPTURE_JOBS:-1}"
WORKER_NAME="${WORKER_NAME:-$APP_NAME capture}"

WORK="$(mktemp -d -t kit-shots)"
TALLY="$WORK/tally"
UNSETTLED_LOG="$WORK/unsettled"
: >"$TALLY"
: >"$UNSETTLED_LOG"
trap 'rm -rf "$WORK"' EXIT

DEVICES=()
WORKERS=()

[[ -f "$ROOT_DIR/scripts/scenes.sh" ]] ||
  die "no scripts/scenes.sh in $ROOT_DIR — the repo declares what a scene is"
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/scenes.sh"

declare -F capture_scene >/dev/null ||
  die "scripts/scenes.sh must define capture_scene <scene> <language> <output> <device>"
((${#SCENES[@]})) || die "appkit.json must list capture.scenes"

# --- arguments --------------------------------------------------------------

build_first=false
want_scenes=()
want_languages=()

while (($#)); do
  case "$1" in
    --build) build_first=true; shift ;;
    --scene) [[ $# -ge 2 ]] || die "--scene needs a name"; want_scenes+=("$2"); shift 2 ;;
    --language) [[ $# -ge 2 ]] || die "--language needs a code"; want_languages+=("$2"); shift 2 ;;
    help | -h | --help) kit_usage "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see: appkit help capture)" ;;
  esac
done

# A name that isn't a scene reaches the app, which draws its default screen and
# files it under whatever was asked for — a shot that looks fine and is of the
# wrong thing. Check before the first launch.
known() {
  local wanted="$1" candidate
  shift
  for candidate in "$@"; do
    [[ "$candidate" == "$wanted" ]] && return 0
  done
  return 1
}

for scene in "${want_scenes[@]:-}"; do
  [[ -z "$scene" ]] || known "$scene" "${SCENES[@]}" ||
    die "unknown scene: $scene (one of ${SCENES[*]})"
done
for language in "${want_languages[@]:-}"; do
  [[ -z "$language" ]] || known "$language" "${LANGUAGES[@]}" ||
    die "unknown language: $language (one of ${LANGUAGES[*]})"
done

# Whether this run covers every scene, and so whether last time's captures are
# stale or are the rest of the set.
whole_set=true
((${#want_scenes[@]})) && { SCENES=("${want_scenes[@]}"); whole_set=false; }
((${#want_languages[@]})) && LANGUAGES=("${want_languages[@]}")

# --- run --------------------------------------------------------------------

platform_resolve

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "appkit.json's capture.jobs must be 1 or more"
# A device with no language to photograph is a boot nobody needed.
((JOBS <= ${#LANGUAGES[@]})) || JOBS=${#LANGUAGES[@]}

[[ "$build_first" == false ]] || platform_build
platform_locate_app
platform_verify_languages

# The model, when the platform pins one — iOS does, and it is the whole point
# of the line: a run that says which phone it is on cannot quietly change phone.
device_label="${CAPTURE_DEVICE_TYPE:-}"
log "Preparing ${device_label##*.} ×$JOBS"
platform_workers "$JOBS"
prepare_all

declare -F pre_capture >/dev/null && pre_capture

log "Capturing ${#SCENES[@]} scenes × ${#LANGUAGES[@]} languages → $OUT_DIR"
run_shards || die "a language pass failed — see the error above"

declare -F post_capture >/dev/null && post_capture

# One set, one screen size. Nothing further down can tell: the composer scales
# whatever it is given, so a mixed set makes cards that look right and are not,
# and the only symptom is a card that will not reproduce — which reads as an
# animation and sends you after the wrong thing entirely.
mixed="$(python3 - "$OUT_DIR" <<'SIZES'
import pathlib, struct, sys

root = pathlib.Path(sys.argv[1])
sizes = {}
for path in sorted(root.rglob("*.png")):
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24:
        continue
    sizes.setdefault(struct.unpack(">II", header[16:24]), []).append(
        str(path.relative_to(root)))

if len(sizes) > 1:
    for (width, height), files in sorted(sizes.items(), key=lambda pair: -len(pair[1])):
        shown = ", ".join(files[:4]) + (" …" if len(files) > 4 else "")
        print(f"  {width}x{height}: {len(files)} — {shown}")
SIZES
)"
if [[ -n "$mixed" ]]; then
  warn "Captures are NOT all one size:"
  printf '%s\n' "$mixed" >&2
  warn "  delete the odd ones and shoot those languages again — the cards would"
  warn "  compose from a scaled picture and nothing downstream would say so."
fi

# Said again at the end, because a warning thirty launches ago has scrolled off
# and this is the one thing that decides whether the set reproduces.
if [[ -s "$UNSETTLED_LOG" ]]; then
  warn "Never held still: $(sort "$UNSETTLED_LOG" | tr '\n' ' ')"
  warn "  those scenes have something animating in them, and their cards will"
  warn "  differ run to run — find what moves rather than widening the tolerance."
fi

platform_retire

log "Captures in $OUT_DIR"
