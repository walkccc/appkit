# The app manifest. Sourced first by every appkit command.
#
# One file per repo — appkit.json — flattened here into shell variables, and read
# directly by the Swift renderer too.
#
# KIT_DIR is where appkit is installed; ROOT_DIR is the repo, found by walking up
# for appkit.json before this file is sourced.

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# shellcheck source=./log.sh
. "$KIT_DIR/lib/log.sh"

[[ -n "${ROOT_DIR:-}" ]] ||
  die "no appkit.json in $PWD or any directory above it — this is not an app repo"

MANIFEST="${MANIFEST:-$ROOT_DIR/appkit.json}"

[[ -f "$MANIFEST" ]] || die "no appkit.json at $ROOT_DIR — see appkit's README"

# Flatten the manifest to shell assignments. Everything a command might want is
# exported here rather than re-read per command: one python start-up per run,
# and a typo in a key name fails once, loudly, at the top.
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


platform = manifest.get("platform", "ios")
# The oldest appkit that can run this repo. A floor, not a pin: doctor fails
# below it and says nothing above it.
put("KIT_VERSION", manifest.get("appkit"))
put("APP_NAME", manifest["name"])
put("PLATFORM", platform)
put("BUNDLE_ID", manifest.get("bundleId"))
put_list("SOURCE_DIRS", manifest.get("sources") or [manifest["name"]])

tokens = manifest.get("tokens") or {}
put("TOKENS_DIR", tokens.get("dir"))
put_list("KIT_TOKENS", tokens.get("files") or [])

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
put("SIMULATOR", ios.get("simulator"))
put("DEVICE", ios.get("device"))
put_list("DEVICE_TYPES", ios.get("deviceTypes") or [])
put("ASC_APP_ID", ios.get("ascAppId"))
put("PROJECT_HINT", ios.get("project"))

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
put("COPY_OUT", store.get("copyOut"))

# Links this repo declines: a config it EXTENDS rather than restates, like a
# .prettierrc with an extra plugin. Declared, so it is not read as drift.
sync = manifest.get("sync") or {}
put_list("SYNC_SKIP", sync.get("skip") or [])


print("\n".join(out))
PY
)"

: "${PLATFORM:?appkit.json must set platform (ios | android)}"
: "${APP_NAME:?appkit.json must set name}"

SHOTS_DIR="${SHOTS_DIR:-$ROOT_DIR/$SHOTS_DIR_REL}"
META_DIR="${META_DIR:-$ROOT_DIR/$META_DIR_REL}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/.screenshots}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"

# The platform adapter, loaded on demand: a command that only reads the
# manifest (doctor, version) must not need adb installed to run.
use_platform() {
  local name="${1:-$PLATFORM}"
  [[ -f "$KIT_DIR/platform/$name.sh" ]] || die "no platform adapter for '$name'"
  # shellcheck disable=SC1090
  . "$KIT_DIR/platform/$name.sh"
}
