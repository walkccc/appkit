#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# appkit run — build the app and put it on a device.
#
#   appkit run                            list the devices and stop
#   appkit run --device "Jay's iPhone"    build, install, launch there
#   appkit run --device "iPhone 17 Pro"   a simulator is a device too
#   appkit run --skip-build               use whatever is already built
#
# The device is always named. It is not read from appkit.json and there is no
# default: "which device" is a question about the machine in front of you, not
# about the app, and a default silently installs somewhere you weren't looking.
#
# Physical devices and simulators are one list. On iOS that means devicectl and
# simctl both, which is the difference between seeing your iPhone here and not.
#
# NOTE: this builds. Every app repo forbids an agent from running it.
# ============================================================================

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/manifest.sh
. "$KIT_DIR/lib/manifest.sh"
use_platform

device=""
skip_build=false

while (($#)); do
  case "$1" in
    --device) [[ $# -ge 2 ]] || die "--device needs a name"; device="$2"; shift 2 ;;
    --skip-build) skip_build=true; shift ;;
    help | -h | --help) kit_usage "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see: appkit help run)" ;;
  esac
done

if [[ -z "$device" ]]; then
  log "Devices:"
  platform_list_devices
  log ""
  log "Pick one:  appkit run --device \"<name>\""
  exit 0
fi

platform_use_device "$device"
[[ "$skip_build" == true ]] || platform_build
platform_locate_app

log "Installing on $device"
platform_install "$DEVICE_ID"

log "Launching $BUNDLE_ID"
platform_launch "$DEVICE_ID"
