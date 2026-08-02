# The iOS adapter: simctl and Xcode behind the platform contract.
#
# Every function a kit command may call on a platform is named `platform_*`, and
# every one of them is defined here for iOS and in android.sh for Android. What
# is NOT here is what a scene is — that stays in the repo's scripts/scenes.sh,
# which calls these primitives.
#
#   platform_resolve            find the device, set UDID/RUNTIME/DEVICE_TYPE
#   platform_workers <n>        DEVICES=() — n devices for n parallel passes
#   platform_prepare <device>   boot it, pin the status bar, install the app
#   platform_build              build (interactive only; agents are forbidden)
#   platform_locate_app         set APP, warn if it predates the sources
#   platform_verify_languages   the bundle really carries every .lproj
#   platform_launch <device> …  cold-launch the app with arguments
#   platform_screenshot <d> <p> one frame to a file
#   platform_retire             put the workers away
#   platform_version            the version the store will see

platform_resolve() {
  : "${SIMULATOR:?appkit.json must set ios.simulator}"
  IFS=$'\t' read -r UDID RUNTIME DEVICE_TYPE < <(_ios_resolve_device "$SIMULATOR")
  [[ -n "$UDID" ]] || die "could not resolve $SIMULATOR"
  DEVICE_ID="$UDID"
}

# Resolve a simulator name to the UDID on the newest installed runtime — a plain
# name is ambiguous the moment two runtimes ship the same device. The runtime
# and the device type come back with it: the parallel passes create their own
# devices from those two, which is what a sharded capture depends on.
_ios_resolve_device() {
  local wanted="$1"
  xcrun simctl list -j devices available | python3 -c '
import json, sys
wanted = sys.argv[1]
data = json.load(sys.stdin)["devices"]
matches = [
    (runtime, device["udid"], device["deviceTypeIdentifier"])
    for runtime, devices in data.items()
    for device in devices
    if wanted in (device["name"], device["udid"])
]
if not matches:
    sys.exit(f"no available simulator named {wanted!r}")
matches.sort(key=lambda match: match[0])  # runtime ids sort by version
runtime, udid, kind = matches[-1]
print("\t".join((udid, runtime, kind)))
' "$wanted"
}

# The UDID of a device with this exact name on $RUNTIME, or nothing.
_ios_device_named() {
  xcrun simctl list -j devices available | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for device in json.load(sys.stdin)["devices"].get(runtime, []):
    if device["name"] == name:
        print(device["udid"])
        break
' "$1" "$RUNTIME"
}

# One device per parallel pass, made from the resolved device's own type and
# runtime rather than borrowed. Kept between runs (a first boot costs ~30s) and
# shut down at the end.
platform_workers() {
  local wanted="$1" index udid
  DEVICES=("$UDID")
  WORKERS=()
  WORKERS_CREATED=()
  for ((index = 2; index <= wanted; index++)); do
    udid="$(_ios_device_named "$WORKER_NAME $index")"
    if [[ -z "$udid" ]]; then
      udid="$(xcrun simctl create "$WORKER_NAME $index" "$DEVICE_TYPE" "$RUNTIME")" ||
        die "could not create a capture simulator"
      WORKERS_CREATED+=("$WORKER_NAME $index")
    fi
    DEVICES+=("$udid")
    WORKERS+=("$udid")
  done
  ((${#WORKERS_CREATED[@]} == 0)) ||
    log "  made ${#WORKERS_CREATED[@]} capture simulator(s) — first boot is slow, later runs reuse them"
}

# A capture taken while another app is still running foreground carries its
# "◀ AppName" breadcrumb in the status bar, and the breadcrumb stays until that
# app exits. Terminate every third-party app so each launch starts clean.
_ios_clear_foreground() {
  local device="$1"
  xcrun simctl spawn "$device" launchctl list 2>/dev/null |
    { grep -o 'UIKitApplication:[^[:space:]]*' || true; } |
    sed -E 's/^UIKitApplication:([^[]+).*/\1/' |
    sort -u |
    while read -r bundle; do
      [[ "$bundle" == com.apple.* ]] && continue
      xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
    done
  sleep 1
}

# Boot and install. The device is booted through simctl and never through
# `open -a Simulator`, because a booted runtime renders whether or not anything
# is watching it — the window is a viewer, not the renderer.
platform_install() {
  local device="$1"
  if [[ "${DEVICE_KIND:-simulator}" == physical ]]; then
    xcrun devicectl device install app --device "$device" "$APP"
    return
  fi
  quiet xcrun simctl bootstatus "$device" -b
  quiet xcrun simctl install "$device" "$APP"
  _ios_clear_foreground "$device"
}

# …and, for a capture, pin everything the status bar would otherwise date the
# shot with. Kept apart from the install: `appkit run` is somebody looking at the
# app, and a dev run that silently froze the clock at 9:41 would be a small lie
# told every time.
platform_prepare() {
  local device="$1"
  quiet xcrun simctl bootstatus "$device" -b
  # 12-hour time so --time renders Apple's "9:41" rather than a 24-hour "09:41";
  # the simulator's region otherwise decides.
  xcrun simctl spawn "$device" defaults write "Apple Global Domain" \
    AppleICUForce24HourTime -bool false
  xcrun simctl status_bar "$device" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100
  [[ -n "${APPEARANCE:-}" ]] && quiet xcrun simctl ui "$device" appearance "$APPEARANCE"
  platform_install "$device"
}

# Physical devices AND simulators, in one list, because "which device" does not
# mean two different questions to the person asking. simctl cannot see a phone
# on a cable and devicectl cannot see a simulator, so both are asked.
platform_list_devices() {
  local physical
  physical="$(xcrun devicectl list devices 2>/dev/null |
    awk 'NR > 2 && NF { print }' || true)"
  if [[ -n "$physical" ]]; then
    printf '  physical:\n'
    printf '%s\n' "$physical" | sed 's/^/    /'
  else
    printf '  physical: none paired (plug one in and trust it)\n'
  fi
  printf '  simulators:\n'
  xcrun simctl list devices available |
    awk '/^-- /{runtime = $0; next} /\(/{ if (runtime != "") print "    " $0 }' |
    sed 's/ (Shutdown)//'
}

# The device this run targets, by name or UDID, physical or simulated. Sets
# DEVICE_ID and DEVICE_KIND; everything downstream branches on the kind rather
# than guessing from the name.
platform_use_device() {
  local wanted="$1" udid
  udid="$(xcrun devicectl list devices 2>/dev/null | python3 -c '
import re, sys

wanted = sys.argv[1]
for line in sys.stdin.read().splitlines()[2:]:
    if not line.strip():
        continue
    # Name is the first column; the UDID is the long hyphenated field.
    found = re.search(r"[0-9A-Fa-f-]{36}", line)
    if not found:
        continue
    name = line[: found.start()].split("  ")[0].strip()
    if wanted in (name, found.group(0)):
        print(found.group(0))
        break
' "$wanted" || true)"
  if [[ -n "$udid" ]]; then
    DEVICE_ID="$udid"
    DEVICE_KIND=physical
    return 0
  fi

  IFS=$'\t' read -r UDID RUNTIME DEVICE_TYPE < <(_ios_resolve_device "$wanted") || true
  [[ -n "${UDID:-}" ]] || die "no device or simulator named '$wanted' — run: appkit run"
  DEVICE_ID="$UDID"
  DEVICE_KIND=simulator
}

platform_launch() {
  local device="$1"
  shift
  if [[ "${DEVICE_KIND:-simulator}" == physical ]]; then
    xcrun devicectl device process launch --device "$device" "$BUNDLE_ID"
    return
  fi
  quiet xcrun simctl launch --terminate-running-process "$device" "$BUNDLE_ID" "$@"
}

platform_screenshot() {
  quiet xcrun simctl io "$1" screenshot --type=png "$2"
}

# SpringBoard restart, for when the home indicator's fade stalls half-drawn on a
# starved device. Waits for the device to answer a screenshot again.
platform_kick() {
  local device="$1" waited=0
  xcrun simctl spawn "$device" launchctl kickstart -k user/foreground/com.apple.SpringBoard \
    >/dev/null 2>&1 || true
  until xcrun simctl io "$device" screenshot --type=png "$WORK/kick.png" >/dev/null 2>&1; do
    sleep 0.5
    waited=$((waited + 1))
    ((waited < 40)) || break
  done
}

# The workers are shut down and kept. Deleting them would mean re-creating and
# re-booting one per language on the next run, which is minutes; a shut-down
# simulator costs disk and nothing else.
platform_retire() {
  local device
  ((${#WORKERS[@]:-0})) || return 0
  for device in "${WORKERS[@]}"; do
    # Already-shut-down is an error simctl prints and this run does not care about.
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
  done
}

# --- the project ------------------------------------------------------------

ios_project() {
  local projects=() project
  [[ -z "${PROJECT_HINT:-}" ]] || {
    printf '%s' "$ROOT_DIR/$PROJECT_HINT"
    return
  }
  while IFS= read -r -d '' project; do
    projects+=("$project")
  done < <(find "$ROOT_DIR" -maxdepth 3 -name '*.xcodeproj' -type d -print0)

  case "${#projects[@]}" in
    0) die "no .xcodeproj under $ROOT_DIR; set ios.project in appkit.json" ;;
    1) printf '%s' "${projects[0]}" ;;
    *) die "multiple .xcodeproj under $ROOT_DIR; set ios.project in appkit.json" ;;
  esac
}

# MARKETING_VERSION out of the Xcode project, so a release doesn't have to be
# told twice what it is.
platform_version() {
  local project version
  project="${PROJECT:-$(ios_project)}"
  version="$(awk -F' = ' '/MARKETING_VERSION =/ { v=$2; gsub(/;$/,"",v); gsub(/"/,"",v); print v; exit }' \
    "$project/project.pbxproj")"
  [[ -n "$version" ]] || die "could not read MARKETING_VERSION from $project"
  printf '%s' "$version"
}

ios_default_app_name() {
  local project="$1" scheme="$2" scheme_path buildable=""
  scheme_path="$project/xcshareddata/xcschemes/$scheme.xcscheme"
  if [[ -f "$scheme_path" ]]; then
    buildable="$(awk -F'"' '/BuildableName =/ && $2 ~ /\.app$/ { sub(/\.app$/, "", $2); print $2; exit }' "$scheme_path")"
  fi
  printf '%s' "${buildable:-$scheme}"
}

# The authoritative id to launch is the built app's own CFBundleIdentifier —
# reading it avoids picking a sibling extension's id (the widget or share
# extension), which is what a naive "first id in the pbxproj" scan does.
ios_bundle_id() {
  local app_path="$1" fallback="$2" plist id=""
  plist="$app_path/Info.plist"
  if [[ -f "$plist" ]]; then
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  fi
  printf '%s' "${id:-$fallback}"
}

# The app to capture: the newest of this kit's own build products and Xcode's.
# Two places because ⌘B does not write into .build/ — a set is usually captured
# off the build already on the machine, and demanding one from `xcodebuild`
# instead would rebuild the whole app just to photograph it.
platform_locate_app() {
  local candidate stamp newest=0 newest_source dir
  APP=""
  local sdk="iphonesimulator"
  [[ "${DEVICE_KIND:-simulator}" == physical ]] && sdk="iphoneos"
  while IFS= read -r candidate; do
    [[ -x "$candidate/$APP_NAME" ]] || continue
    stamp="$(stat -f%m "$candidate/$APP_NAME")"
    if ((stamp > newest)); then
      newest="$stamp"
      APP="$candidate"
    fi
  done < <(
    printf '%s\n' "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-$sdk/$APP_NAME.app"
    ls -d "$HOME"/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/"$CONFIGURATION"-"$sdk"/"$APP_NAME".app 2>/dev/null || true
  )
  [[ -n "$APP" ]] || die "no $CONFIGURATION build of $APP_NAME found.
  Build it in Xcode (⌘B), or pass --build, which builds into
  $DERIVED_DATA_PATH"

  # A capture only ever shows what was last compiled, so say when that was and
  # whether anything has been edited since. Loud, because the failure is silent:
  # every scene comes back looking exactly right and none of them is the change
  # being checked.
  newest_source=0
  for dir in "${SOURCE_DIRS[@]}"; do
    [[ -d "$ROOT_DIR/$dir" ]] || continue
    stamp="$(find "$ROOT_DIR/$dir" -name '*.swift' -exec stat -f%m {} + 2>/dev/null | sort -rn | head -1)"
    [[ -n "$stamp" ]] && ((stamp > newest_source)) && newest_source="$stamp"
  done
  log "Capturing $APP"
  if ((newest_source > newest)); then
    warn "  the app is OLDER than the sources — build it again, or these are last build's scenes"
  fi
  BUNDLE_ID="${BUNDLE_ID:-$(ios_bundle_id "$APP" "")}"
}

# A bundle carries one <lang>.lproj per language, compiled from the string
# catalog. --skip-build happily reuses one built before a language was added:
# the app then falls back to English and the run files a full set of English
# captures under the new language's folder — invisible until it is on the store.
# Fail before the first launch instead.
platform_verify_languages() {
  local language missing=()
  for language in "${LANGUAGES[@]}"; do
    [[ -d "$APP/$language.lproj" ]] || missing+=("$language.lproj")
  done
  if ((${#missing[@]})); then
    die "the app bundle predates the manifest's locales — missing ${missing[*]}
  at $APP
  Rebuild without --skip-build. If it still fails, knownRegions in the
  project doesn't cover every language."
  fi
}

# Silent on success — a passing build says nothing beyond "** BUILD SUCCEEDED **".
# On failure the tail carries the compiler diagnostics.
#
# Every app repo forbids running this from an agent; it exists for the release
# capture the user has explicitly asked for, and --skip-build is the usual path.
platform_build() {
  local logfile project destination
  project="${PROJECT:-$(ios_project)}"
  if [[ "${DEVICE_KIND:-simulator}" == physical ]]; then
    destination="platform=iOS,id=$DEVICE_ID"
  else
    destination="platform=iOS Simulator,id=${DEVICE_ID:-$UDID}"
  fi
  log "Building $SCHEME"
  logfile="$(mktemp -t kit-build)"
  if ! xcodebuild \
    -project "$project" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "$destination" \
    -allowProvisioningUpdates \
    build >"$logfile" 2>&1; then
    tail -40 "$logfile" >&2
    rm -f "$logfile"
    die "build failed"
  fi
  rm -f "$logfile"
}
