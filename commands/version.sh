#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit version — move the version, everywhere the platform writes it.
#
#   appkit version 1.3.0     set the marketing version, build +1
#   appkit version --build   build number only
#
# On iOS every target moves together: a build number that differs between an app
# and its extension is rejected at upload, after the archive. On Android the
# versionName and versionCode are one file, and Play refuses a code it has seen.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$KIT_DIR/lib/manifest.sh"

version=""
build_only=false

while (($#)); do
  case "$1" in
    --build) build_only=true; shift ;;
    -h | --help) sed -n '5,13p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) version="$1"; shift ;;
  esac
done

[[ "$build_only" == true || -n "$version" ]] || die "pass a version, e.g. 1.3.0 (or --build)"
[[ -z "$version" || "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "not a version: $version"

case "$PLATFORM" in
  ios)
    use_platform
    PBXPROJ="$(ios_project)/project.pbxproj"
    current="$(awk -F' = ' '/CURRENT_PROJECT_VERSION =/ { v=$2; gsub(/;$/,"",v); print v; exit }' "$PBXPROJ")"
    next=$((current + 1))
    if [[ -n "$version" ]]; then
      sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g" "$PBXPROJ"
      log "MARKETING_VERSION -> $version"
    fi
    sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $next;/g" "$PBXPROJ"
    log "CURRENT_PROJECT_VERSION -> $next"
    log "Now archive from Xcode; the listing goes up with: appkit publish copy"
    ;;
  android)
    GRADLE="$ROOT_DIR/app/build.gradle.kts"
    current="$(awk '/versionCode/ { print $NF; exit }' "$GRADLE")"
    next=$((current + 1))
    if [[ -n "$version" ]]; then
      sed -i '' -E "s/versionName = \"[^\"]+\"/versionName = \"$version\"/" "$GRADLE"
      log "versionName -> $version"
    fi
    sed -i '' -E "s/versionCode = [0-9]+/versionCode = $next/" "$GRADLE"
    log "versionCode -> $next"
    log "Now: appkit ship"
    ;;
  *) die "no version scheme for platform '$PLATFORM'" ;;
esac
