#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Move the version, everywhere the platform writes it.
#
#   appkit version           what this app is on, and what appkit is on
#   appkit version 1.3.0     set the marketing version
#   appkit version build     the build number only, +1
#
# On Android the versionName and versionCode are one file, and Play refuses a
# code it has already seen, so setting the version bumps the code under it too.
# On iOS the two are separate motions: `asc publish appstore` resolves
# CURRENT_PROJECT_VERSION against what Connect already holds at ship time, so
# it only moves on `appkit version build`.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$KIT_DIR/lib/manifest.sh"

usage() { kit_usage "$0"; }

version=""
build_only=false

while (($#)); do
  case "$1" in
    # A word, not a flag: `build` cannot be mistaken for a version number, and
    # the ones that can are rejected below.
    build | --build) build_only=true; shift ;;
    help | -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) version="$1"; shift ;;
  esac
done

# No argument reads rather than writes. Bumping is the destructive half and it
# says which number it is moving.
if [[ "$build_only" == false && -z "$version" ]]; then
  use_platform
  log "$APP_NAME $(platform_version) ($PLATFORM), on appkit $(cat "$KIT_DIR/VERSION")"
  log "  move it with: appkit version 1.3.0"
  exit 0
fi

[[ -z "$version" || "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "not a version: $version"

# Where the numbers are written is the platform's, and an unknown one is already
# refused by use_platform — which is why there is no third branch here saying so
# a second time.
use_platform
platform_set_version "$version"
log "Then: appkit ship"
