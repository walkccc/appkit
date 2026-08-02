#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit setup — the one-time machine setup a platform needs.
#
#   appkit setup signing    a code-signing certificate, so the OS stops
#                           forgetting this app's permissions on every build
#
# Machine-wide, not per-repo: what this makes is a keychain entry every app on
# appkit then signs with. It is still run from inside a repo, because that is
# where you are standing when you hit the problem it solves, and because the
# platform is what decides whether there is anything to do at all.
#
# Run it once per Mac. Running it again says so and changes nothing.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$APPKIT_DIR/lib/manifest.sh"

what="${1:-}"
shift || true

case "$what" in
  help | -h | --help | "")
    appkit_usage "$0"
    exit 0
    ;;
  signing) ;;
  *) die "unknown thing to set up: $what (signing)" ;;
esac

use_platform
platform_setup_signing
