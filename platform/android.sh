# The Android adapter: adb and Gradle behind the same contract ios.sh answers.
#
# The shapes that differ from iOS are worth naming, because they are why the
# contract is functions and not one script with an `if`:
#
# - **There is one device.** simctl makes as many simulators as there are
#   languages; an emulator is a VM the machine has one or two of, and a phone on
#   a cable is one. So platform_workers hands back the single device and the
#   harness shards over it serially.
# - **The status bar is set by broadcast, not by a flag.** SystemUI's demo mode
#   is the answer to `simctl status_bar override`, and it is stickier: the
#   disable-flag it needs outlives the process, so it has to be undone.
# - **A launch carries intent extras**, not `-NSUserDefaults` arguments.
# - **The screen can be covered by the system.** An ANR dialog is perfectly
#   still, so the two-identical-frames test passes with Android's own "app isn't
#   responding" in the shot. It has to be asked about separately.

: "${ANDROID_PACKAGE:?appkit.json must set android.package}"

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="${ADB:-$ANDROID_HOME/platform-tools/adb}"
[[ -x "$ADB" ]] || ADB="$(command -v adb || true)"

# Gradle chokes on a modern system JDK; Android Studio ships one that works.
# Set, not defaulted: the JDK already on PATH is usually the broken one.
_ANDROID_STUDIO_JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
[[ -d "$_ANDROID_STUDIO_JBR" ]] && export JAVA_HOME="$_ANDROID_STUDIO_JBR"

platform_resolve() {
  [[ -x "$ADB" ]] || die "adb not found — install the Android SDK platform-tools"
  DEVICE_ID="${ANDROID_SERIAL:-${DEVICE_ID:-}}"
  if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  fi
  [[ -n "$DEVICE_ID" ]] || die "no adb device — boot an emulator or plug a phone in"
  "$ADB" -s "$DEVICE_ID" wait-for-device
  UDID="$DEVICE_ID"
}

# One device, so one pass. Said out loud rather than silently ignored: a
# capture.jobs copied from an iOS appkit.json would otherwise look like it did
# something.
platform_workers() {
  local wanted="$1"
  DEVICES=("$DEVICE_ID")
  WORKERS=()
  ((wanted == 1)) || warn "  Android captures on one device — ignoring capture.jobs $wanted"
  JOBS=1
}

# The 9:41 status bar, and everything else that would date a shot.
#
# Two of these are less obvious than they look:
#
# - `wifi … -e fully true` is what removes the little "!" beside the bars. Demo
#   mode's default is *connected but no internet*, and SystemUI draws that
#   warning over the icon — on every shot in the set.
# - **Demo mode cannot hide notification icons.** `notifications -e visible
#   false` is a no-op on the modern status bar, so whatever the device is
#   nagging about rides along in the frame: on a stock emulator that is Safety
#   Center's slashed shield, sitting right next to the clock. The disable flag
#   is the mechanism that does work, and it is stronger — it hides the whole
#   notification area, so tomorrow's different warning needs no different fix.
platform_install() {
  local device="$1"
  log "  installing"
  quiet "$ADB" -s "$device" install -r -d "$APP"
  # Wake and unlock, or the app launches behind a black screen.
  "$ADB" -s "$device" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  "$ADB" -s "$device" shell wm dismiss-keyguard >/dev/null 2>&1 || true
}

platform_list_devices() { "$ADB" devices -l; }

platform_prepare() {
  local device="$1" demo="am broadcast -a com.android.systemui.demo"
  "$ADB" -s "$device" shell settings put global sysui_demo_allowed 1
  quiet "$ADB" -s "$device" shell "$demo -e command enter"
  quiet "$ADB" -s "$device" shell "$demo -e command clock -e hhmm 0941"
  quiet "$ADB" -s "$device" shell "$demo -e command battery -e level 100 -e plugged false"
  quiet "$ADB" -s "$device" shell "$demo -e command network -e wifi show -e level 4 -e fully true"
  quiet "$ADB" -s "$device" shell "$demo -e command network -e mobile hide"
  quiet "$ADB" -s "$device" shell cmd statusbar send-disable-flag notification-icons
  case "${APPEARANCE:-}" in
    dark) quiet "$ADB" -s "$device" shell cmd uimode night yes ;;
    light) quiet "$ADB" -s "$device" shell cmd uimode night no ;;
  esac
  platform_install "$device"
}

# Demo mode and the disable flag are device state, not process state, so a run
# that died mid-capture would otherwise leave the phone with no notification
# icons until it was rebooted.
platform_retire() {
  local device="${DEVICE_ID:-}"
  [[ -n "$device" ]] || return 0
  "$ADB" -s "$device" shell "am broadcast -a com.android.systemui.demo -e command exit" >/dev/null 2>&1 || true
  "$ADB" -s "$device" shell cmd statusbar send-disable-flag none >/dev/null 2>&1 || true
  "$ADB" -s "$device" shell cmd uimode night auto >/dev/null 2>&1 || true
  "$ADB" -s "$device" shell am force-stop "$ANDROID_PACKAGE" >/dev/null 2>&1 || true
}

# Cold every time: the intent carries the scene, so the process has to be new to
# read it. Arguments are `-e key value` pairs, which is the repo's business.
platform_launch() {
  local device="$1"
  shift
  "$ADB" -s "$device" shell am force-stop "$ANDROID_PACKAGE"
  "$ADB" -s "$device" logcat -c
  quiet "$ADB" -s "$device" shell am start -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY" "$@"
}

platform_screenshot() {
  "$ADB" -s "$1" exec-out screencap -p >"$2"
}

# There is no SpringBoard to kick; restarting SystemUI is the nearest thing and
# is what clears a status bar that has got itself stuck.
platform_kick() {
  local device="$1"
  "$ADB" -s "$device" shell am crash com.android.systemui >/dev/null 2>&1 || true
  sleep 3
  platform_prepare "$device"
}

# Block until the app says a scene is on the glass. A cold start pays for
# whatever the app loads at launch, which is a couple of seconds on a phone and
# fifteen on an emulator — so the wait cannot be a fixed sleep, and cannot be
# inferred from the pixels either, because the shell paints long before the
# seeded scene lands on top of it. The app says when it is ready instead.
android_wait_for_log() {
  local device="$1" pattern="$2" timeout="${3:-90}" waited=0
  until "$ADB" -s "$device" logcat -d -s "$ANDROID_LOG_TAG:W" | grep -q "$pattern"; do
    sleep 1
    waited=$((waited + 1))
    ((waited < timeout)) ||
      die "never saw '$pattern' in ${timeout}s — check: adb logcat -s $ANDROID_LOG_TAG:W AndroidRuntime:E"
  done
}

# Is the system's "isn't responding" dialog on the glass? It has to be asked,
# because every other check says yes: the scene stages, the app says so, the
# screen settles — and it settles *because* the dialog is up and nothing behind
# it is moving.
android_is_anr() {
  "$ADB" -s "$1" shell dumpsys window 2>/dev/null |
    grep -qi "mCurrentFocus.*Application Not Responding"
}

platform_locate_app() {
  APP="${APP:-$ROOT_DIR/$ANDROID_APK}"
  [[ -f "$APP" ]] || die "no debug APK at $APP — drop --skip-build"
  log "Capturing $APP"
  BUNDLE_ID="$ANDROID_PACKAGE"
}

# Android has no per-language folder inside the artifact to check, so the
# equivalent of iOS's .lproj audit is left to the app: a scene launched with a
# language the app doesn't ship falls back, and the app is expected to say so.
platform_verify_languages() { :; }

platform_build() {
  log "Building $APP_NAME"
  (cd "$ROOT_DIR" && ./gradlew --quiet assembleDebug) || die "build failed"
}

platform_version() {
  local version
  version="$(awk -F'"' '/versionName/ { print $2; exit }' "$ROOT_DIR/app/build.gradle.kts" 2>/dev/null)"
  [[ -n "$version" ]] || die "could not read versionName from app/build.gradle.kts"
  printf '%s' "$version"
}
