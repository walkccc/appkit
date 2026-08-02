#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit copy — the product's words, before any store sees them.
#
#   appkit copy check              lengths, and every language's coverage
#   appkit copy export             one JSON bundle, for a surface with no store
#   appkit copy note 1.3.0         start a changelog entry for every language
#
# `appkit publish copy` is the outward-facing half — this half never talks to
# anything. It exists because the mistakes worth catching are the quiet ones: a
# language missing a release note ships the previous release's words, and a
# privacy policy that differs between the site and the listing is nobody's
# error message.
#
# The privacy and support pages the STORES link to live in this tree too: they
# are canonical here and served from wherever the product's site is.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$KIT_DIR/lib/manifest.sh"
# shellcheck source=../store/metadata.sh
. "$KIT_DIR/store/metadata.sh"
# shellcheck source=../store/copy.sh
. "$KIT_DIR/store/copy.sh"

what="${1:-check}"
shift || true

version=""
while (($#)); do
  case "$1" in
    -h | --help) sed -n '5,20p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) version="$1"; shift ;;
  esac
done

[[ -d "$META_DIR" ]] || die "no copy at $META_DIR"

resolve_version() {
  [[ -n "$version" ]] && return 0
  version="$(copy_latest_version "$META_DIR" 2>/dev/null || true)"
  [[ -n "$version" ]] && return 0
  use_platform
  version="$(platform_version)"
}

# Which stores' limits apply. An app not on a store yet has none, and is checked
# for coverage only — its copy still has to exist in every language.
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
    copy_coverage "$META_DIR" "${LANGUAGES[*]}" "$version" ||
      die "fill the gaps above, or say in the commit why a language is behind"
    ;;

  export)
    copy_export "$META_DIR" "${LANGUAGES[*]}" "$ROOT_DIR/${COPY_OUT:-store/copy.json}"
    ;;

  # A release note per language, stubbed, so the gap is a file to fill rather
  # than something to remember. English is left empty on purpose: a stub that
  # says "TODO" reads as finished text to a translator.
  note)
    resolve_version
    dir="$META_DIR/changelog/$version"
    mkdir -p "$dir"
    made=0
    for language in "${LANGUAGES[@]}"; do
      path="$dir/$language.md"
      [[ -e "$path" ]] && continue
      : >"$path"
      made=$((made + 1))
    done
    log "changelog/$version: $made new, ${#LANGUAGES[@]} language(s) total"
    log "  write the English one first, then translate — appkit copy check will"
    log "  name any that stay empty."
    ;;

  -h | --help) sed -n '5,20p' "$0" ;;
  *) die "unknown command: $what (check | export | note)" ;;
esac
