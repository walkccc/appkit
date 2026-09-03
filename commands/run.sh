#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit run — build the app and put it on a device.
#
#   appkit run                            list the devices and stop
#   appkit run --device "Jay's iPhone"    build, install, launch there
#   appkit run --device "iPhone 17 Pro"   a simulator is a device too
#   appkit run --device "Apple Watch …"   and so is a watch: runs the watch app
#   appkit run --skip-build               use whatever is already built
#
# The device is always named. It is not read from appkit.json and there is no
# default: "which device" is a question about the machine in front of you, not
# about the app, and a default silently installs somewhere you weren't looking.
#
# Physical devices and simulators are one list. On iOS that means devicectl and
# simctl both, which is the difference between seeing your iPhone here and not.
#
# A repo on two platforms needs nothing extra. `appkit run` lists both machines
# and the name you pick says which one it is — a MacBook and an iPhone do not
# answer to the same name, so asking for a --platform as well would be asking
# you to say it twice. It exists as an override and nothing here needs it.
#
# Naming a watch simulator runs the watch app — a different scheme, SDK and
# bundle id, all of them appkit.json's ios.watch. Nothing in this file says so:
# the adapter answers with a third device kind and every step below follows it.
#
# NOTE: this builds. Every app repo forbids an agent from running it.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$APPKIT_DIR/lib/manifest.sh"

device=""
skip_build=false
platform=""

# Parsed before the adapter is loaded, because --platform is what decides which
# adapter that is.
while (($#)); do
  case "$1" in
    --device) [[ $# -ge 2 ]] || die "--device needs a name"; device="$2"; shift 2 ;;
    --platform) [[ $# -ge 2 ]] || die "--platform needs a name"; platform="$2"; shift 2 ;;
    --skip-build) skip_build=true; shift ;;
    help | -h | --help) appkit_usage "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see: appkit help run)" ;;
  esac
done

if [[ -z "$device" ]]; then
  log "Devices:"
  platform_list_all_devices
  log ""
  log "Pick one:  appkit run --device \"<name>\""
  exit 0
fi

# The named device decides the platform, unless one was named outright.
if [[ -z "$platform" && "${#PLATFORMS[@]:-1}" -gt 1 ]]; then
  platform="$(platform_for_device "$device")" ||
    die "no device called '$device' on ${PLATFORMS[*]} — run: appkit run"
fi

choose_platform "$platform"
platform_use_device "$device"
[[ "$skip_build" == true ]] || platform_build
platform_locate_app

log "Installing on $device"
platform_install "$DEVICE_ID"

log "Launching $BUNDLE_ID"
platform_launch "$DEVICE_ID"
