#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# The product's words, before any store sees them.
#
#   appkit check metadata          lengths, and every language's coverage
#   appkit pull metadata           what the listing says RIGHT NOW, to compare
#
# `appkit upload metadata` is the outward-facing half. `pull` only reads, and
# `check` touches nothing. They exist because the mistakes worth catching here
# are the quiet ones: a language missing a release note ships the previous
# release's words, and nobody notices for months.
#
# The privacy and support pages the STORES link to live in this tree too: they
# are canonical here and served from wherever the product's site is.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$KIT_DIR/lib/manifest.sh"
# shellcheck source=../store/metadata.sh
. "$KIT_DIR/store/metadata.sh"

usage() { kit_usage "$0"; }

what="${1:-check}"
shift || true

version=""
while (($#)); do
  case "$1" in
    help | -h | --help) usage; exit 0 ;;
    # The object of the verb, spelled out at the call site: `appkit check
    # metadata`, not `appkit check`. Swallowed here so a version can follow it.
    metadata) shift ;;
    -*) die "unknown option: $1" ;;
    *) version="$1"; shift ;;
  esac
done

[[ -d "$META_DIR" ]] || die "no metadata at $META_DIR"

resolve_version() {
  [[ -n "$version" ]] && return 0
  version="$(metadata_latest_version "$META_DIR" 2>/dev/null || true)"
  [[ -n "$version" ]] && return 0
  use_platform
  version="$(platform_version)"
}

# Which stores' limits apply. An app not on a store yet has none, and is checked
# for coverage only — its words still have to exist in every language.
stores() {
  local names=()
  [[ -n "${ASC_LOCALES:-}" ]] && names+=(appStore)
  [[ -n "${PLAY_LOCALES:-}" ]] && names+=(play)
  printf '%s' "${names[*]}"
}

case "$what" in
  check)
    resolve_version
    which="$(stores)"
    if [[ -n "$which" ]]; then
      log "Checking lengths for: $which"
      metadata_check "$META_DIR" "$which" || die "fix the fields above"
    else
      log "No store on this platform — checking coverage only"
    fi
    log "Checking coverage at $version"
    metadata_coverage "$META_DIR" "${LANGUAGES[*]}" "$version" ||
      die "fill the gaps above, or say in the commit why a language is behind"
    ;;

  # What the store shows RIGHT NOW, which is not what is tracked: someone
  # tightens a subtitle in App Store Connect during a review and it never comes
  # back to the repo. Worth doing before editing a word, even one word.
  pull)
    resolve_version
    [[ -n "${ASC_LOCALES:-}" && -n "${ASC_APP_ID:-}" ]] ||
      die "pull reads App Store Connect, and this app declares no appStore locale or no ios.ascAppId
  (Play has no read API for a listing — read that one in the Play Console)"
    # shellcheck source=../store/asc.sh
    . "$KIT_DIR/store/asc.sh"
    asc_require
    log "Pulling the live listing for $version into .asc/metadata-live"
    asc metadata pull --app "$ASC_APP_ID" --version "$version" \
      --dir "$ROOT_DIR/.asc/metadata-live"
    log "Compare it with ${META_DIR#"$ROOT_DIR"/} before editing — live is not tracked"
    ;;

  help | -h | --help) usage ;;
  *) die "unknown thing to do with metadata: $what (check | pull)" ;;
esac
