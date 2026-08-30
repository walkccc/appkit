# The iOS adapter: simctl and Xcode behind the platform contract.
#
# Every function an appkit command may call on a platform is named
# `platform_*`, and every one of them is defined here for iOS and in android.sh
# for Android. What is NOT here is what a scene is — that stays in the repo's
# scripts/scenes.sh, which calls these primitives.
#
#   platform_resolve            find the device, set UDID/RUNTIME/DEVICE_TYPE
#   platform_workers <n>        DEVICES=() — n devices for n parallel passes
#   platform_install <device>   put the built app on it
#   platform_prepare <device>   boot it, pin the status bar, install the app
#   platform_build              build (interactive only; agents are forbidden)
#   platform_locate_app         set APP, warn if it predates the sources
#   platform_verify_languages   the bundle really carries every .lproj
#   platform_launch <device> …  cold-launch the app with arguments
#   platform_screenshot <d> <p> one frame to a file
#   platform_kick <device>      unstick a device that stopped answering
#   platform_retire             put the workers away
#   platform_list_devices       what `appkit run` with no --device prints
#   platform_use_device <name>  the one it was told to use; sets DEVICE_ID/KIND
#   platform_version            the version the store will see
#   platform_set_version <v>    move the marketing version; build is separate
#   platform_shared_files       extra rows for `appkit sync`, this platform's
#
# This list is the whole contract, and every name in it is defined in BOTH
# adapters — CONTRIBUTING.md carries the diff that proves it, because the gap is
# invisible until someone runs the one command that needs the missing half.
# platform_use_device was in this file only, so `appkit run --device` on Android
# died with "command not found".
#
# And the watch, which is iOS's alone — `ios_*`, not `platform_*`, the same way
# ios_project and ios_bundle_id are. Android has no counterpart to define as a
# no-op: Wear OS is a different shape and nothing here ships one. No appkit
# command calls these either: `appkit run` reaches them because
# platform_use_device sets DEVICE_KIND=watch, so the branch stays in the adapter
# and no command learns there is a watch.
#
#   ios_watch_resolve           WATCH_UDID from ios.watch.device
#   ios_watch_locate_app        WATCH_APP + WATCH_BUNDLE_ID from the build
#   ios_watch_prepare           boot it and install
#   ios_watch_launch …          cold-launch the watch app with arguments

# The one model every store capture is taken on, in every repo on appkit. Not
# a manifest key, on purpose: an iOS card is 1242x2688, and a capture off any
# other phone is a different picture scaled to fit — it composes, it uploads,
# and it is subtly wrong. It has already happened: three languages came off a
# Pro Max because a worker simulator outlived a change of model, and the only
# symptom anywhere was a re-shot warning that read as an animation.
CAPTURE_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"

# Which runtime and model a capture runs on: read off any available simulator
# of that model, on the newest runtime that has one — and if the machine has
# none, one made here. What it is CALLED does not matter and is never asked.
#
# The device this finds is NOT one of the shard devices. It answers "what would
# a capture be taken on", and `platform_workers` then makes that many of its own.
platform_resolve() {
  local runtime
  UDID=""
  RUNTIME=""
  DEVICE_TYPE=""
  IFS=$'\t' read -r UDID RUNTIME DEVICE_TYPE < <(_ios_capture_device) || true
  if [[ -z "$UDID" ]]; then
    runtime="$(_ios_newest_runtime)"
    [[ -n "$runtime" ]] ||
      die "no iOS simulator runtime installed — Xcode ▸ Settings ▸ Components"
    log "  no ${CAPTURE_DEVICE_TYPE##*.} simulator on this machine — making one"
    UDID="$(xcrun simctl create "${WORKER_NAME:-appkit capture} 1" \
      "$CAPTURE_DEVICE_TYPE" "$runtime")" ||
      die "could not make a ${CAPTURE_DEVICE_TYPE##*.} — this Xcode may be too old for it"
    RUNTIME="$runtime"
    DEVICE_TYPE="$CAPTURE_DEVICE_TYPE"
  fi
  DEVICE_ID="$UDID"
}

# udid, runtime, type — for the newest runtime carrying CAPTURE_DEVICE_TYPE.
_ios_capture_device() {
  xcrun simctl list -j devices available | python3 -c '
import json, sys
wanted = sys.argv[1]
data = json.load(sys.stdin)["devices"]
matches = [
    (runtime, device["udid"])
    for runtime, devices in data.items()
    for device in devices
    if device["deviceTypeIdentifier"] == wanted
]
if matches:
    matches.sort(key=lambda match: match[0])  # runtime ids sort by version
    runtime, udid = matches[-1]
    print("\t".join((udid, runtime, wanted)))
' "$CAPTURE_DEVICE_TYPE"
}

_ios_newest_runtime() {
  xcrun simctl list -j runtimes available | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS"]
if runtimes:
    runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".") if p.isdigit()])
    print(runtimes[-1]["identifier"])
'
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

# The UDID *and model* of a device with this exact name on $RUNTIME, or nothing.
#
# The model comes back because the name alone is not enough: a worker made for
# an earlier ios.simulator keeps the model it was created as, and reusing it
# photographs its share of the languages at another screen size. Nothing
# downstream says "wrong device" — the cards compose, and what you get is a
# re-shot warning and a set that will not reproduce.
_ios_device_named() {
  xcrun simctl list -j devices available | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for device in json.load(sys.stdin)["devices"].get(runtime, []):
    if device["name"] == name:
        print("\t".join((device["udid"], device["deviceTypeIdentifier"])))
        break
' "$1" "$RUNTIME"
}

# One device per parallel pass, all of them appkit's own, made from the resolved
# device's type and runtime rather than borrowed. Kept between runs (a first boot
# costs ~30s) and shut down at the end.
#
# Slot 0 is a worker like every other slot, and that is the whole of this
# function's care. It used to be the resolved device — which can BE one of these
# workers, since they are simulators of exactly the model being resolved for. Two
# slots then held one UDID, two shards launched the app on one simulator at once
# (`simctl launch --terminate-running-process`: last launch wins), and one
# language came back photographed in the other's. Nothing downstream can see it:
# the size is right, the frames are still, and the cards compose.
platform_workers() {
  local wanted="$1" index udid kind
  DEVICES=()
  WORKERS=()
  WORKERS_CREATED=()
  for ((index = 1; index <= wanted; index++)); do
    # `read` is fed an empty line when there is no such device, which is the
    # ordinary first run — so it must not take the script out under `set -e`.
    udid=""
    kind=""
    IFS=$'\t' read -r udid kind < <(_ios_device_named "$WORKER_NAME $index") || true
    # A worker of the wrong model is worse than no worker: it takes a third of
    # the languages at another screen size and nothing further down knows.
    # Replace it rather than borrow it — it is appkit's own device, named by
    # appkit, and the manifest has just said what it should be.
    if [[ -n "$udid" && "$kind" != "$DEVICE_TYPE" ]]; then
      log "  $WORKER_NAME $index is a ${kind##*.}, not a ${DEVICE_TYPE##*.} — replacing it"
      xcrun simctl delete "$udid" || die "could not delete the stale capture simulator $udid"
      udid=""
    fi
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
  # watchOS has no status bar to carry another app's breadcrumb, and no
  # launchctl to ask for one.
  [[ "${DEVICE_KIND:-simulator}" == watch ]] || _ios_clear_foreground "$device"
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

# The device this run targets, by name or UDID: physical, simulated, or a watch.
# Sets DEVICE_ID and DEVICE_KIND; everything downstream branches on the kind
# rather than guessing from the name.
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

  # A watch is a third kind and not a simulator with an unusual name: it takes
  # the watch scheme, the watchOS SDK and its own bundle id. Resolved as an
  # ordinary simulator it built the phone scheme against `platform=iOS
  # Simulator` holding a watch UDID, and xcodebuild's answer — "no available
  # devices matched" — named the device rather than the mistake.
  if [[ "$DEVICE_TYPE" == *Apple-Watch* ]]; then
    ios_watch_require
    DEVICE_KIND=watch
    WATCH_UDID="$DEVICE_ID"
  fi
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

# --- the watch --------------------------------------------------------------
#
# A watchOS app is a second scheme built for a second SDK onto a second
# simulator, and none of it is shardable: watch scenes are a handful, not a
# hundred, and the model is the app's own choice rather than appkit's pinned
# one. So these are primitives a repo's script drives, not a pass appkit runs.
#
# What appkit does own is the awkward half — which build products directory
# holds a watch app, and which of the two bundle ids in it is the watch's.

ios_watch_require() {
  [[ -n "${WATCH_SCHEME:-}" ]] ||
    die "appkit.json declares no ios.watch.scheme — this app has no watch app"
}

# By NAME, unlike the phone. A watch model is a real choice — the card size it
# files under is its own display type — so the manifest says which, and this
# fails loudly rather than inventing one: a set shot on a 41mm where the cards
# expect 46mm is the same silent size mismatch the phone pass is pinned against.
ios_watch_resolve() {
  ios_watch_require
  # Only this path needs the model: `appkit run --device` was told which watch,
  # and a repo whose watch is never captured owes the manifest no name.
  [[ -n "${WATCH_DEVICE:-}" ]] ||
    die "appkit.json declares no ios.watch.device (e.g. \"Apple Watch Series 11 (46mm)\")"
  local udid runtime kind
  IFS=$'\t' read -r udid runtime kind < <(_ios_resolve_device "$WATCH_DEVICE") || true
  [[ -n "${udid:-}" ]] || die "no simulator named '$WATCH_DEVICE'
  Xcode ▸ Window ▸ Devices and Simulators makes one, or change
  ios.watch.device in appkit.json to a model this machine has."
  WATCH_UDID="$udid"
}

# The watch build sits under a watchsimulator SDK directory rather than the
# iphonesimulator one, which is the whole reason this is not platform_locate_app
# with an argument. Xcode's own DerivedData is searched too, for the same reason
# as the phone: ⌘B does not write into .build/.
ios_watch_locate_app() {
  ios_watch_require
  local candidate stamp newest=0
  WATCH_APP=""
  while IFS= read -r candidate; do
    [[ -d "$candidate" ]] || continue
    stamp="$(stat -f%m "$candidate")"
    if ((stamp > newest)); then
      newest="$stamp"
      WATCH_APP="$candidate"
    fi
  done < <(
    printf '%s\n' "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-watchsimulator/$WATCH_SCHEME.app"
    ls -d "$HOME"/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/"$CONFIGURATION"-watchsimulator/"$WATCH_SCHEME".app 2>/dev/null || true
  )
  [[ -n "$WATCH_APP" ]] || die "no $CONFIGURATION build of $WATCH_SCHEME found.
  Build the $WATCH_SCHEME scheme in Xcode (⌘B) — the phone scheme does not
  produce it."
  # Read off the bundle rather than guessed: a watch app's id is the phone's
  # with a suffix, and which suffix is the project's business, not a pattern.
  WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-$(ios_bundle_id "$WATCH_APP" "")}"
  [[ -n "$WATCH_BUNDLE_ID" ]] ||
    die "could not read a bundle id from $WATCH_APP — set ios.watch.bundleId"
}

# No status bar override and no appearance: watchOS takes neither. The 9:41 in
# the corner is the watch face's own, which is why a repo that wants it there
# repaints it onto the capture afterwards.
ios_watch_prepare() {
  quiet xcrun simctl bootstatus "$WATCH_UDID" -b
  quiet xcrun simctl install "$WATCH_UDID" "$WATCH_APP"
}

ios_watch_launch() {
  quiet xcrun simctl launch --terminate-running-process \
    "$WATCH_UDID" "$WATCH_BUNDLE_ID" "$@"
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

# Move the marketing version alone. The build number is a separate motion —
# `appkit version build` — because `asc publish appstore` resolves the real
# CURRENT_PROJECT_VERSION against what Connect already holds at ship time, so
# nothing here needs to guess it or spend one on every version bump.
platform_set_version() {
  local version="$1" pbxproj current next
  pbxproj="$(ios_project)/project.pbxproj"
  [[ -f "$pbxproj" ]] || die "no project.pbxproj at $pbxproj"
  if [[ -n "$version" ]]; then
    sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g" "$pbxproj"
    log "MARKETING_VERSION -> $version"
    return
  fi
  current="$(awk -F' = ' '/CURRENT_PROJECT_VERSION =/ { v=$2; gsub(/;$/,"",v); print v; exit }' "$pbxproj")"
  [[ -n "$current" ]] || die "no CURRENT_PROJECT_VERSION in $pbxproj — set one in Xcode first"
  next=$((current + 1))
  sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $next;/g" "$pbxproj"
  log "CURRENT_PROJECT_VERSION -> $next"
}

# What `asc publish appstore` needs to archive this app: the project, the scheme
# and where the exported artifact goes. An array rather than a printed string,
# because a project path with a space in it is not hypothetical.
platform_publish_args() {
  PUBLISH_ARGS=(
    --project "${PROJECT:-$(ios_project)}"
    --scheme "$SCHEME"
    --ipa-path "$ROOT_DIR/.asc/artifacts/$APP_NAME.ipa"
  )
}

# Nothing to do. Xcode owns signing on iOS — `-allowProvisioningUpdates` in
# platform_build is the whole of it, and a certificate appkit made would not
# be one Apple accepts for a device build anyway.
#
# Defined rather than absent because macOS genuinely needs it, and a contract
# function that exists in one adapter is invisible until somebody runs the one
# command that wants the missing half.
platform_setup_signing() {
  log "iOS signing is Xcode's — Settings ▸ Accounts, then a device build."
  log "  Nothing for appkit to set up."
}

# There is no outside-the-store on iOS. Ad Hoc and Enterprise distribution both
# exist and neither is this: one is a list of UDIDs, the other is a membership
# most teams cannot buy. Refused rather than approximated.
platform_distribute() {
  die "an iOS app is distributed through the App Store — that is \`appkit ship\`.
  \`appkit distribute\` is for a Mac app handed out as a download."
}

# Swift is formatted, so an iOS repo takes the shared .swiftformat. Which shared
# files a repo gets is the platform's answer and not a branch in `appkit sync`:
# the same rule as everything else here.
platform_shared_files() {
  printf '%s\n' '.swiftformat|config/.swiftformat'
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

# The app to capture: the newest of appkit's own build products and Xcode's.
# Two places because ⌘B does not write into .build/ — a set is usually captured
# off the build already on the machine, and demanding one from `xcodebuild`
# instead would rebuild the whole app just to photograph it.
platform_locate_app() {
  local candidate stamp newest=0 newest_source dir
  APP=""
  # The watch app is another SDK's build product under another bundle id, and
  # ios_watch_locate_app already knows both.
  if [[ "${DEVICE_KIND:-simulator}" == watch ]]; then
    ios_watch_locate_app
    APP="$WATCH_APP"
    BUNDLE_ID="$WATCH_BUNDLE_ID"
    log "Using $APP"
    return
  fi
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
  local logfile project destination scheme="$SCHEME"
  project="${PROJECT:-$(ios_project)}"
  case "${DEVICE_KIND:-simulator}" in
    physical) destination="platform=iOS,id=$DEVICE_ID" ;;
    watch)
      scheme="$WATCH_SCHEME"
      destination="platform=watchOS Simulator,id=$DEVICE_ID"
      ;;
    *) destination="platform=iOS Simulator,id=${DEVICE_ID:-$UDID}" ;;
  esac
  log "Building $scheme"
  logfile="$(mktemp -t appkit-build)"
  if ! xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
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
