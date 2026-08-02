#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit distribute — the binary, onto the internet rather than onto a store.
#
#   appkit distribute               build, sign, notarize, staple, archive
#   appkit distribute --skip-build  re-sign and send what is already built
#   appkit distribute --out DIR     where the archive lands (default: build/)
#
# The sibling of `appkit ship`, and the difference is who vouches for the app.
# A store does its own gatekeeping; a download has to arrive carrying Apple's
# verdict inside it, or the person who downloaded it cannot open it at all.
#
# Two files come out, for two different readers: a .dmg, which is what a person
# downloads and drags to /Applications, and a .zip, which is what the in-app
# updater unpacks. Both are universal, signed, notarized and stapled. Ends by
# printing each one with its sha256 — what an appcast and a download page need.
#
# Needs a Developer ID Application certificate and, once per Mac, notarization
# credentials in the keychain. Both are named in full by the error you get for
# not having them.
#
# NOTE: this builds. Every app repo forbids an agent from running it.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$APPKIT_DIR/lib/manifest.sh"

SKIP_BUILD=false
DIST_DIR=""

while (($#)); do
  case "$1" in
    --skip-build) SKIP_BUILD=true; shift ;;
    --out) [[ $# -ge 2 ]] || die "--out needs a directory"; DIST_DIR="$2"; shift 2 ;;
    help | -h | --help) appkit_usage "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see: appkit help distribute)" ;;
  esac
done

# Absolute, because the platform writes it and the platform does not run from
# the directory the flag was typed in.
[[ -z "$DIST_DIR" || "$DIST_DIR" == /* ]] || DIST_DIR="$PWD/$DIST_DIR"

use_platform
platform_distribute
