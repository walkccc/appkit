# The app manifest. Sourced first by every appkit command.
#
# One file per repo — appkit.json — flattened here into shell variables, and read
# directly by the Swift renderer too.
#
# APPKIT_DIR is where appkit is installed; ROOT_DIR is the repo, found by
# walking up for appkit.json before this file is sourced.

APPKIT_DIR="${APPKIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# shellcheck source=./log.sh
. "$APPKIT_DIR/lib/log.sh"

[[ -n "${ROOT_DIR:-}" ]] ||
  die "no appkit.json in $PWD or any directory above it — this is not an app repo"

MANIFEST="${MANIFEST:-$ROOT_DIR/appkit.json}"

[[ -f "$MANIFEST" ]] || die "no appkit.json at $ROOT_DIR — see appkit's README"

# Flatten the manifest to shell assignments. Everything a command might want is
# exported here rather than re-read per command: one python start-up per run,
# and a typo in a key name fails once, loudly, at the top.
#
# NO APOSTROPHES below, in comments or strings. The heredoc is nested inside a
# command substitution, and bash matches the closing paren by scanning quotes:
# a lone ' inside makes `bash -n` fail with "unexpected EOF", pointing at the
# end of the file rather than at the line that did it.
eval "$(
  python3 - "$MANIFEST" <<'PY'
import json, pathlib, shlex, sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
out = []


def put(name, value):
    if value is None or value == "":
        return
    out.append(f"{name}={shlex.quote(str(value))}")


def put_list(name, values):
    if not values:
        return
    out.append(f"{name}=({' '.join(shlex.quote(str(v)) for v in values)})")


# One repo, one platform, until a product ships on two of them out of one tree.
# `platform` takes a list for that case and the FIRST is the primary: it is what
# doctor, sync and capture answer to, and what a command uses when nothing on the
# command line says otherwise.
platform = manifest.get("platform", "ios")
platforms = platform if isinstance(platform, list) else [platform]
if not platforms:
    raise SystemExit("appkit.json: platform is an empty list")
platform = platforms[0]
# The oldest appkit that can run this repo. A floor, not a pin: doctor fails
# below it and says nothing above it.
put("APPKIT_VERSION", manifest.get("appkit"))
put("APP_NAME", manifest["name"])
put("PLATFORM", platform)
put_list("PLATFORMS", platforms)
put("BUNDLE_ID", manifest.get("bundleId"))
put_list("SOURCE_DIRS", manifest.get("sources") or [manifest["name"]])

capture = manifest.get("capture") or {}
put_list("SCENES", capture.get("scenes") or [])
put("CAPTURE_JOBS", capture.get("jobs") or 1)
put("APPEARANCE", capture.get("appearance"))

# The locale table, one row per language the store set is shot in. `capture` is
# what drives the app (a BCP 47 code, and the folder a raw capture lands in);
# the rest are the spellings each store insists on. A store the app is not on
# simply has no key, and its fan-out skips the row.
locales = manifest.get("locales") or []
put_list("LANGUAGES", [row["capture"] for row in locales])
for store in ("appStore", "play"):
    put_list(
        f"{'ASC' if store == 'appStore' else 'PLAY'}_LOCALES",
        [row[store] for row in locales if row.get(store)],
    )
    # capture code -> store code, as a lookup a shell function can read.
    pairs = [f"{row['capture']}={row[store]}" for row in locales if row.get(store)]
    put_list(f"{'ASC' if store == 'appStore' else 'PLAY'}_LOCALE_MAP", pairs)

ios = manifest.get("ios") or {}
put("SCHEME", ios.get("scheme") or manifest["name"])
put("CONFIGURATION", ios.get("configuration") or "Debug")
# The display sizes `asc screenshots upload` is called for, once each. Not the
# device a capture is TAKEN on — that is pinned in platform/ios.sh — and not the
# one `appkit run` installs to, which is named on the command line and nowhere
# else, because "which device" is a question about the machine in front of you.
put_list("DEVICE_TYPES", ios.get("deviceTypes") or [])
put("ASC_APP_ID", ios.get("ascAppId"))
put("PROJECT_HINT", ios.get("project"))

# The watchOS app, when there is one: a second scheme, a second bundle and a
# second simulator of a model the phone pass knows nothing about. Named in the
# manifest rather than in a repo script because it IS a device the store takes
# imagery for — deviceTypes already carries the matching display type.
#
# The device is a NAME, where the phone is a pin: one card size is why appkit
# fixes the phone, and which watch to shoot is a decision each app makes.
watch = ios.get("watch") or {}
put("WATCH_SCHEME", watch.get("scheme"))
put("WATCH_DEVICE", watch.get("device"))
put("WATCH_BUNDLE_ID", watch.get("bundleId"))

# macOS. The keys are about ASSEMBLING a bundle, which no other platform needs:
# SwiftPM emits a bare executable, so the .app around it — its Info.plist, its
# icon, the resources beside it — is appkit's to build rather than the
# toolchain's to hand over.
macos = manifest.get("macos") or {}
# An Xcode project instead of a SwiftPM package. Declaring it changes which of
# the two things platform_build does: xcodebuild hands over a finished .app, so
# none of the assembly keys below apply and appkit does not go looking for them.
# A repo whose iOS app already needs an .xcodeproj gets its Mac app out of the
# same one rather than keeping a second build system for the same sources.
put("MACOS_PROJECT", macos.get("project"))
put("MACOS_SCHEME", macos.get("scheme") or manifest["name"])
# The SwiftPM product to build. Defaults to the app name and is separate from
# it because a product may be lowercase where the app is not.
put("MACOS_PRODUCT", macos.get("product") or manifest["name"])
put("MACOS_CONFIG", macos.get("configuration") or "release")
put("MACOS_PLIST", macos.get("infoPlist") or "Resources/Info.plist")
# The 1024 master, and optionally what regenerates it. Two keys rather than one
# because an icon drawn by a program is a build step and an icon checked into
# the repo is a file, and appkit has to be told which this is.
put("MACOS_ICON", macos.get("icon"))
put("MACOS_ICON_CMD", macos.get("iconCommand"))
# Files copied into Contents/Resources beside the SwiftPM bundles. Repo-relative.
put_list("MACOS_RESOURCES", macos.get("resources") or [])
# Binary frameworks a SwiftPM dependency ships as an .xcframework, copied into
# Contents/Frameworks and signed before the app around them is. Named rather
# than discovered: .build/artifacts keeps every artifact SwiftPM has ever
# fetched, so a glob would happily embed a package this app stopped depending on
# two commits ago.
put_list("MACOS_FRAMEWORKS", macos.get("frameworks") or [])
# An explicit signing identity, when the machine has several and the right one
# is not the first `security find-identity` prints. Usually absent: the adapter
# resolves one, and CODESIGN_IDENTITY overrides for a single run.
put("MACOS_SIGN_IDENTITY", macos.get("signIdentity"))
# The entitlements plist, and with it the hardened runtime — one key, because
# outside the App Sandbox they are one decision. An entitlement like
# com.apple.security.device.audio-input does nothing until the runtime is
# hardened, and a hardened runtime with no entitlements silently takes the
# microphone away from an app that needs it. Declared here means BOTH, on every
# build, so a capability the runtime withholds fails on this Mac rather than on
# somebody elses laptop after notarization.
put("MACOS_ENTITLEMENTS", macos.get("entitlements"))
# The provisioning profile Apple issued for this App ID, copied into the bundle
# before it is signed. Needed by the entitlements the previous key cannot carry
# alone: a com.apple.developer.* one — Sign in with Apple, iCloud, push — is
# RESTRICTED, meaning macOS does not take it on trust and checks a profile
# instead. Absent, the app is built, signed, installed, and then killed
# at exec, which arrives as "Launchd job spawn failed" and reads like a broken
# binary rather than a missing file.
put("MACOS_PROVISIONING_PROFILE", macos.get("provisioningProfile"))

android = manifest.get("android") or {}
put("ANDROID_PACKAGE", android.get("package"))
put("ANDROID_ACTIVITY", android.get("activity") or ".MainActivity")
put("ANDROID_APK", android.get("apk") or "app/build/outputs/apk/debug/app-debug.apk")
put("ANDROID_AAB", android.get("aab") or "app/build/outputs/bundle/release/app-release.aab")
put("ANDROID_LOG_TAG", android.get("logTag") or manifest["name"])
put("PLAY_KEY", android.get("playKey") or ".secrets/play-key.json")
put("PLAY_TRACK", android.get("track") or "production")


render = manifest.get("render") or {}
put("RENDER_CMD", render.get("command"))
put("CARDS_FILE", render.get("cards"))
put("SHOTS_DIR_REL", render.get("out") or "store/screenshots")
put("DITHER", render.get("dither") or 3)

store = manifest.get("store") or {}
put("META_DIR_REL", store.get("metadata") or "store/metadata")

# Links this repo declines: a config it EXTENDS rather than restates, like a
# .prettierrc with an extra plugin. Declared, so it is not read as drift.
sync = manifest.get("sync") or {}
put_list("SYNC_SKIP", sync.get("skip") or [])


print("\n".join(out))
PY
)"

: "${PLATFORM:?appkit.json must set platform (ios | macos | android)}"
: "${APP_NAME:?appkit.json must set name}"

SHOTS_DIR="${SHOTS_DIR:-$ROOT_DIR/$SHOTS_DIR_REL}"
META_DIR="${META_DIR:-$ROOT_DIR/$META_DIR_REL}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/.screenshots}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"

# The platform adapter, loaded on demand — a command that never touches a device
# should not pay for one. Sourcing an adapter is cheap and safe either way:
# neither needs its toolchain present to LOAD, and android.sh leaves ADB empty
# rather than dying when adb is missing, so doctor runs without an SDK.
use_platform() {
  local name="${1:-$PLATFORM}"
  [[ -f "$APPKIT_DIR/platform/$name.sh" ]] || die "no platform adapter for '$name'"
  # shellcheck disable=SC1090
  . "$APPKIT_DIR/platform/$name.sh"
}

# The adapter a command was asked for, checked against what the repo says it is.
#
# An empty name is the repo's primary, which is every repo that ships on one
# platform and therefore nearly all of them. Naming one it does not declare is
# an error rather than a load: platform/macos.sh exists in every install, and
# sourcing it in an Android repo would answer questions about a Mac app that is
# not there.
# Which of this repo's platforms owns the device somebody named.
#
# A device name already says which machine it is: nobody has a MacBook and an
# iPhone answering to the same one. So a repo on two platforms needs no second
# flag to repeat it — every adapter is asked, and the first that recognises the
# name is the one loaded for real.
#
# The asking happens in a SUBSHELL. Sourcing an adapter defines the whole
# platform_* contract over whatever was there before, so a probe that ran in
# this shell would leave the last one asked loaded rather than the one that
# said yes. platform_use_device is a pure resolve on both — it looks a name up
# and dies if it is not there, and boots nothing — which is what makes it safe
# to call speculatively.
platform_for_device() {
  local wanted="$1" name
  for name in "${PLATFORMS[@]:-$PLATFORM}"; do
    if (
      use_platform "$name"
      platform_use_device "$wanted"
    ) >/dev/null 2>&1; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  return 1
}

# Every device this repo could install to, whichever platform it is on. One
# list, because "which device" is a question about the machine in front of you
# and the answer does not come in two halves.
platform_list_all_devices() {
  local name
  for name in "${PLATFORMS[@]:-$PLATFORM}"; do
    (
      use_platform "$name"
      platform_list_devices
    )
  done
}

choose_platform() {
  local wanted="${1:-}" name
  if [[ -z "$wanted" ]]; then
    use_platform
    return
  fi
  for name in "${PLATFORMS[@]:-$PLATFORM}"; do
    if [[ "$name" == "$wanted" ]]; then
      use_platform "$wanted"
      return
    fi
  done
  die "appkit.json does not say this repo is on '$wanted' — it declares: ${PLATFORMS[*]:-$PLATFORM}"
}
