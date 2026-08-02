#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Put something on a store. Three errands, kept apart because they cost very
# different things and fail in different ways.
#
#   appkit upload metadata          what's new, every locale — plans, prints
#                                   the diff, applies, no pause
#   appkit upload metadata --all    …the whole listing instead: name, subtitle,
#                                   description, keywords, promo, URLs
#   appkit upload metadata --review …but stop for `asc metadata approve` first
#   appkit upload screenshots       the store cards
#   appkit ship                     the binary: an AAB onto a track, or an
#                                   archive built, uploaded and attached
#   appkit ship --submit            …and sent for review
#   appkit ship --submit-only       …only that last step, for a build already
#                                   attached
#   … --dry-run                     …or none of it: print what would go and
#                                   stop. Reads on all three errands.
#
# All three read the same tracked sources — store/metadata, store/screenshots —
# and the same locale table, and each one renames for whichever store it is
# talking to. Which stores an app is on is the manifest's locale rows: a row
# with an `appStore` key goes to Apple, a row with `play` goes to Google, and an
# app with only one kind of row simply never calls the other publisher.
#
# Every locale goes up in ONE run per store rather than a loop here: asc fans a
# screenshot upload out across the locale directories under --path itself, and
# every Play change happens inside one edit. A shard per language would trade
# that atomicity for nothing.
#
# The words are tracked, so `git diff -- store/metadata` before running is the
# answer to "what am I about to change on the store". What is NOT tracked is
# what the store currently shows — `appkit pull metadata` is how you find that
# out, and it is worth doing before any edit, even a one-word one.
#
# Which is also why the App Store half sends only what's new by default: a
# release changes the notes and nothing else, and the pull-before-you-push rule
# only ever gets broken on the fields nobody meant to touch. Rewording the
# listing is `--all`, on purpose. Play is deliberately NOT scoped this way: its
# release notes hang off a track release rather than off the listing, so they go
# up with `appkit ship`, and what this command sends Google stays what it always
# was — the listing, whole.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$APPKIT_DIR/lib/manifest.sh"
# shellcheck source=../store/metadata.sh
. "$APPKIT_DIR/store/metadata.sh"

usage() { appkit_usage "$0"; }

what="${1:-}"
shift || true

version=""
track="${PLAY_TRACK:-production}"
status="completed"
review=""
dry_run=""
scope="notes"
submit_only=""
ship_args=()

while (($#)); do
  case "$1" in
    --track) track="$2"; shift 2 ;;
    --status) status="$2"; shift 2 ;;
    --submit) ship_args+=(--submit --confirm); shift ;;
    --submit-only) submit_only="1"; shift ;;
    --dry-run) dry_run="1"; ship_args+=(--dry-run); shift ;;
    --review) review="1"; shift ;;
    --all) scope="all"; shift ;;
    help | -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) version="$1"; shift ;;
  esac
done

# Before the platform is asked anything: `appkit help upload` must answer in a
# repo whose project does not exist yet, which is exactly when it is read.
case "$what" in
  help | -h | --help | "") usage; exit 0 ;;
  metadata | screenshots | build) ;;
  *) die "unknown thing to upload: $what (metadata | screenshots)" ;;
esac

use_platform
[[ -n "$version" ]] || version="$(platform_version)"
# The changelog folder the emitters look in. Exported because the Play emitter
# has no version argument of its own — a listing is not version-scoped, but its
# release notes are.
export UPLOAD_VERSION="$version"

on_app_store() { [[ -n "${ASC_LOCALES:-}" && -n "${ASC_APP_ID:-}" ]]; }
on_play() { [[ -n "${PLAY_LOCALES:-}" && -n "${ANDROID_PACKAGE:-}" ]]; }

stores() {
  local names=()
  on_app_store && names+=(appStore)
  on_play && names+=(play)
  # :- because macOS ships bash 3.2, where "${arr[*]}" on an EMPTY array trips
  # set -u. An app on NEITHER store is the empty case, and until a Mac app
  # joined appkit there was none — so `appkit ship` printed a bash error about
  # an unbound variable immediately before the real message explaining itself.
  printf '%s' "${names[*]:-}"
}

# --- the listing text -------------------------------------------------------

upload_metadata() {
  [[ -d "$META_DIR" ]] || die "no listing text at $META_DIR"
  local which
  which="$(stores)"
  [[ -n "$which" ]] ||
    die "no store to upload to — appkit.json declares neither an appStore nor a play locale"

  # Always checked, never as a flag: an upload that stops on a field the store
  # would have refused has already changed the locales before it.
  log "Checking $META_DIR"
  metadata_check "$META_DIR" "$which" || die "fix the fields above before uploading"

  if on_app_store; then
    # shellcheck source=../store/asc.sh
    . "$APPKIT_DIR/store/asc.sh"
    asc_require
    local stage="$ROOT_DIR/.asc/metadata-build"
    metadata_stage_asc "$version" "$scope" "$META_DIR" "$stage" "${ASC_LOCALE_MAP[@]:-}"
    # A notes push with nothing to say would plan an empty change set and report
    # success, which reads exactly like a release whose notes went up.
    if [[ "$scope" == notes ]] && ! compgen -G "$stage/version/$version/*.json" >/dev/null; then
      die "no what's new for $version — write ${META_DIR#"$ROOT_DIR"/}/changelog/$version/<language>.md, or pass --all to push the rest of the listing"
    fi
    # After that check, never before it: mirroring fills the stage with live
    # copies, and a stage that answers "yes, there are notes here" with somebody
    # else's is how a release ships the previous one's words.
    asc_mirror_untouched "$version" "$stage"
    local push=()
    [[ -n "$review" ]] && push+=(--review)
    [[ -n "$dry_run" ]] && push+=(--dry-run)
    # ${arr[@]+"${arr[@]}"} and not "${arr[@]}": bash 3.2 again (store/asc.sh).
    asc_push_metadata "$version" "$stage" ${push[@]+"${push[@]}"}
  fi

  if on_play; then
    # shellcheck source=../store/play.sh
    . "$APPKIT_DIR/store/play.sh"
    play_require
    local stage="$ROOT_DIR/.play/metadata-build"
    metadata_stage_play "$META_DIR" "$stage" "${PLAY_LOCALE_MAP[@]:-}"
    local file
    # asc plans before it applies; Play has no such half — an edit opens, the
    # listings go in, it commits. So the stop is here, at the staged tree, which
    # is the whole of what would be sent.
    if [[ -n "$dry_run" ]]; then
      for file in "$stage"/listings/*.json; do
        log "  would push $(basename "$file" .json)"
      done
      log "dry run — nothing sent to Play. Read ${stage#"$ROOT_DIR"/} for the exact text."
      return 0
    fi
    play_edit_begin
    trap play_edit_abort EXIT
    for file in "$stage"/listings/*.json; do
      play_push_listing "$(basename "$file" .json)" "$file"
    done
    play_edit_commit
    trap - EXIT
    PLAY_EDIT=""
    log "Play listing uploaded"
  fi
}

# --- the store cards --------------------------------------------------------

upload_screenshots() {
  [[ -d "$SHOTS_DIR" ]] || die "nothing to upload: $SHOTS_DIR does not exist"

  # The set goes up every time it is asked for. This used to be gated on git
  # reporting the tracked cards dirty — most releases change none, and an upload
  # costs minutes — but imagery persists PER VERSION on both stores, so a fresh
  # version starts with none and the gate turned the usual case into a silent
  # no-op. Minutes are cheaper than a version that ships with no cards.
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain -- "$SHOTS_DIR")" ]]; then
    warn "Screenshots differ from HEAD — review the diff and commit"
  fi

  # Neither publisher has a plan step for imagery — the cards replace what is
  # live the moment the call lands. So --dry-run stops before the first one,
  # having said what it counted.
  if [[ -n "$dry_run" ]]; then
    local cards locales
    cards="$(find "$SHOTS_DIR" -name '*.png' | wc -l | tr -d ' ')"
    locales="$(find "$SHOTS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    log "Would upload $cards card(s) across $locales locale(s) for $version to: $(stores)"
    log "dry run — nothing sent"
    return 0
  fi

  if on_app_store; then
    # shellcheck source=../store/asc.sh
    . "$APPKIT_DIR/store/asc.sh"
    asc_require
    asc_upload_screenshots "$version" "$SHOTS_DIR"
    log "Screenshots uploaded for $version"
  fi

  if on_play; then
    # shellcheck source=../store/play.sh
    . "$APPKIT_DIR/store/play.sh"
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

upload_build() {
  [[ -n "$(stores)" ]] || die "no store to ship a build to — appkit.json declares neither an appStore nor a play locale"

  # The send is the App Store's alone, and it is its own errand because the
  # expensive half — archive, upload, attach — is already done by the time it
  # can fail. Re-running the whole ship to retry it costs a build number and
  # attaches nothing (see store/asc.sh).
  if [[ -n "$submit_only" ]]; then
    on_app_store ||
      die "--submit-only is an App Store errand — this app declares no appStore locale"
    # shellcheck source=../store/asc.sh
    . "$APPKIT_DIR/store/asc.sh"
    asc_require
    asc_send_for_review "$version" "$dry_run"
    return 0
  fi

  if on_app_store; then
    # shellcheck source=../store/asc.sh
    . "$APPKIT_DIR/store/asc.sh"
    asc_require
    asc_ship_build "$version" ${ship_args[@]+"${ship_args[@]}"}
  fi

  if on_play; then
    # shellcheck source=../store/play.sh
    . "$APPKIT_DIR/store/play.sh"
    play_require
    local stage="$ROOT_DIR/.play/metadata-build"
    metadata_stage_play "$META_DIR" "$stage" "${PLAY_LOCALE_MAP[@]:-}"
    # asc reads --dry-run itself; Play has no such half, so the stop is here.
    # Without it the flag documented as "print the plan and stop" uploaded the
    # bundle and committed the edit — a real release, from the safe-looking verb.
    if [[ -n "$dry_run" ]]; then
      log "Would upload $(basename "$ANDROID_AAB") to $track ($status)"
      log "dry run — nothing sent"
      return 0
    fi
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
  metadata) upload_metadata ;;
  screenshots) upload_screenshots ;;
  # Reached as `appkit ship`, which is the name it is documented under: the
  # binary is a different kind of errand from a picture or a paragraph.
  build) upload_build ;;
esac
