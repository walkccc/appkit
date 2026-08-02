#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit publish — put something on a store. Three errands, kept apart because
# they cost very different things and fail in different ways.
#
#   appkit publish copy                 the listing text, every locale
#   appkit publish copy --check         count the fields and stop
#   appkit publish copy --pull          bring the LIVE listing down to compare
#   appkit publish shots                the store cards
#   appkit publish shots --anyway       …even if none of them changed
#   appkit publish build                the binary: an AAB onto a track, or an
#                                    archive built, uploaded and attached
#   appkit publish build --submit       …and sent for review
#   appkit publish build --dry-run      …or neither: print the plan and stop
#
# All three read the same tracked sources — store/metadata, store/screenshots —
# and the same locale table, and each one renames for whichever store it is
# talking to. Which stores an app is on is the manifest's locale rows: a row
# with an `appStore` key goes to Apple, a row with `play` goes to Google, and an
# app with only one kind of row simply never calls the other publisher.
#
# The copy is tracked, so `git diff -- store/metadata` before running is the
# answer to "what am I about to change on the store". What is NOT tracked is
# what the store currently shows — `--pull` is how you find that out, and it is
# worth doing before any edit, even a one-word one.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$KIT_DIR/lib/manifest.sh"
# shellcheck source=../store/metadata.sh
. "$KIT_DIR/store/metadata.sh"

what="${1:-}"
shift || true

check_only=false
pull=false
anyway=false
version=""
track="${PLAY_TRACK:-production}"
status="completed"
ship_args=()

while (($#)); do
  case "$1" in
    --check) check_only=true; shift ;;
    --pull) pull=true; shift ;;
    --anyway) anyway=true; shift ;;
    --track) track="$2"; shift 2 ;;
    --status) status="$2"; shift 2 ;;
    --submit) ship_args+=(--submit --confirm); shift ;;
    --dry-run) ship_args+=(--dry-run); shift ;;
    -h | --help) sed -n '5,28p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) version="$1"; shift ;;
  esac
done

use_platform
[[ -n "$version" ]] || version="$(platform_version)"
# The changelog folder the emitters look in. Exported because the Play emitter
# has no version argument of its own — a listing is not version-scoped, but its
# release notes are.
export PUBLISH_VERSION="$version"

on_app_store() { [[ -n "${ASC_LOCALES:-}" && -n "${ASC_APP_ID:-}" ]]; }
on_play() { [[ -n "${PLAY_LOCALES:-}" && -n "${ANDROID_PACKAGE:-}" ]]; }

stores() {
  local names=()
  on_app_store && names+=(appStore)
  on_play && names+=(play)
  printf '%s' "${names[*]}"
}

# --- the listing copy -------------------------------------------------------

publish_copy() {
  [[ -d "$META_DIR" ]] || die "no listing copy at $META_DIR"
  local which
  which="$(stores)"
  if [[ -z "$which" ]]; then
    # Not on a store yet. The words still have somewhere to go: the product's
    # site renders them, and the privacy and support pages a listing will link
    # to are served from there.
    log "No store on this platform — exporting the copy bundle instead"
    exec "$KIT_DIR/commands/copy.sh" export
  fi

  log "Checking $META_DIR"
  metadata_check "$META_DIR" "$which" || die "fix the fields above before pushing"
  [[ "$check_only" == false ]] || exit 0

  if on_app_store; then
    # shellcheck source=../store/asc.sh
    . "$KIT_DIR/store/asc.sh"
    asc_require
    if [[ "$pull" == true ]]; then
      log "Pulling the live listing for $version into .asc/metadata-live"
      asc metadata pull --app "$ASC_APP_ID" --version "$version" \
        --dir "$ROOT_DIR/.asc/metadata-live"
      log "Compare it with $META_DIR before pushing — what is live is not what is tracked"
      exit 0
    fi
    local stage="$ROOT_DIR/.asc/metadata-build"
    metadata_stage_asc "$version" "$META_DIR" "$stage" "${ASC_LOCALE_MAP[@]:-}"
    asc_push_metadata "$version" "$stage"
  fi

  if on_play; then
    # shellcheck source=../store/play.sh
    . "$KIT_DIR/store/play.sh"
    play_require
    [[ "$pull" == false ]] || die "--pull is App Store only; read the Play listing in the Console"
    local stage="$ROOT_DIR/.play/metadata-build"
    metadata_stage_play "$META_DIR" "$stage" "${PLAY_LOCALE_MAP[@]:-}"
    play_edit_begin
    trap play_edit_abort EXIT
    local file
    for file in "$stage"/listings/*.json; do
      play_push_listing "$(basename "$file" .json)" "$file"
    done
    play_edit_commit
    trap - EXIT
    PLAY_EDIT=""
    log "Play listing pushed"
  fi
}

# --- the store cards --------------------------------------------------------

publish_shots() {
  [[ -d "$SHOTS_DIR" ]] || die "nothing to upload: $SHOTS_DIR does not exist"

  # The rendered cards are tracked, so git is the record of whether any screen
  # actually changed. Most releases change none, and an upload costs minutes.
  local changed
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain -- "$SHOTS_DIR")" ]]; then
    changed=true
    log "Screenshots changed — review the diff and commit"
  else
    changed=false
    log "No screenshot changes"
  fi
  # --anyway is for a version that has never had a set attached: on both stores
  # imagery persists on a version or a listing, so a new one starts with none.
  if [[ "$changed" == false && "$anyway" == false ]]; then
    log "Skipping the upload — pass --anyway to push this set to a version that has none"
    exit 0
  fi

  if on_app_store; then
    # shellcheck source=../store/asc.sh
    . "$KIT_DIR/store/asc.sh"
    asc_require
    asc_upload_screenshots "$version" "$SHOTS_DIR"
    log "Screenshots uploaded for $version"
  fi

  if on_play; then
    # shellcheck source=../store/play.sh
    . "$KIT_DIR/store/play.sh"
    play_require
    play_edit_begin
    trap play_edit_abort EXIT
    local locale dir
    for locale in "${PLAY_LOCALES[@]}"; do
      dir="$SHOTS_DIR/$locale"
      [[ -d "$dir" ]] || {
        warn "  no cards for $locale — leaving the live set alone"
        continue
      }
      play_push_images "$locale" phoneScreenshots "$dir"
      [[ -d "$dir/feature" ]] && play_push_images "$locale" featureGraphic "$dir/feature"
      [[ -d "$dir/icon" ]] && play_push_images "$locale" icon "$dir/icon"
    done
    play_edit_commit
    trap - EXIT
    PLAY_EDIT=""
    log "Play imagery uploaded"
  fi
}

# --- the binary -------------------------------------------------------------

publish_build() {
  [[ -n "$(stores)" ]] || die "no store to publish a build to — appkit.json declares neither an appStore nor a play locale"

  if on_app_store; then
    # shellcheck source=../store/asc.sh
    . "$KIT_DIR/store/asc.sh"
    asc_require
    asc_ship_build "$version" ${ship_args[@]+"${ship_args[@]}"}
  fi

  if on_play; then
    # shellcheck source=../store/play.sh
    . "$KIT_DIR/store/play.sh"
    play_require
    local stage="$ROOT_DIR/.play/metadata-build"
    metadata_stage_play "$META_DIR" "$stage" "${PLAY_LOCALE_MAP[@]:-}"
    play_edit_begin
    trap play_edit_abort EXIT
    play_upload_bundle "$ROOT_DIR/$ANDROID_AAB"
    play_assign_track "$track" "$status" "$stage/notes.json"
    play_edit_commit
    trap - EXIT
    PLAY_EDIT=""
    log "Play build $PLAY_VERSION_CODE on $track"
  fi
}

case "$what" in
  copy) publish_copy ;;
  shots | screenshots) publish_shots ;;
  build) publish_build ;;
  -h | --help | "") sed -n '5,28p' "$0" ;;
  *) die "unknown thing to publish: $what (copy | shots | build)" ;;
esac
