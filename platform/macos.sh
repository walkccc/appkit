# The macOS adapter: SwiftPM and this Mac, behind the contract ios.sh answers.
#
# Three shapes differ from both phone platforms, and they are why this is an
# adapter rather than a flag on ios.sh:
#
# - **The device is the machine appkit is running on.** Nothing to boot, nothing
#   to create, nothing to install onto — an app "on" this Mac is a directory. So
#   platform_workers hands back one device, platform_prepare only clears what is
#   already running, and platform_install means /Applications.
# - **SwiftPM emits a bare executable, not a bundle.** Every other platform's
#   build hands appkit something the OS can launch; here the .app is assembled
#   HERE. That assembly — Info.plist, icon, PkgInfo, the SwiftPM resource
#   bundles, the signature — is the whole of what the two hand-written build.sh
#   scripts this replaced were doing, and the four ways they disagreed.
# - **The signature is load-bearing at DEVELOPMENT time**, which is true on no
#   other platform here. See macos_sign.
#
# SwiftPM, not xcodebuild: both Mac apps on appkit are packages, and a
# speculative xcodebuild path is one nobody would have run. Adding it later is a
# change inside platform_build and platform_locate_app, and nowhere else.

: "${BUNDLE_ID:?appkit.json must set bundleId — macOS needs it to write Info.plist}"

# For appkit_tool, which compiles window-id. Sourced here rather than added to
# capture.sh: it is this adapter that needs a compiled helper, and no command
# should have to know that one platform does.
# shellcheck source=../lib/pictures.sh
. "$APPKIT_DIR/lib/pictures.sh"

# Xcode configuration names are capitalised where SwiftPM's are not, and
# macos.configuration is written in SwiftPM's spelling because that is what it
# has always meant. One place converts.
macos_xcode_config() {
  local config="${MACOS_CONFIG:-release}"
  printf '%s%s\n' "$(printf '%s' "${config:0:1}" | tr '[:lower:]' '[:upper:]')" "${config:1}"
}

# Where the bundle is. Two answers, because there are two ways to get one.
#
# Assembled by appkit under build/ when this repo is a SwiftPM package — not at
# the repo root: one of the two scripts this replaced wrote Yap.app beside
# Package.swift, which meant a stray .app in `git status` and one more line in
# that repo's own ignore file.
#
# Handed over finished by Xcode when macos.project is declared, in the same
# DerivedData every other Xcode build in this repo uses.
if [[ -n "${MACOS_PROJECT:-}" ]]; then
  MACOS_APP="${MACOS_APP:-$DERIVED_DATA_PATH/Build/Products/$(macos_xcode_config)/$APP_NAME.app}"
else
  MACOS_APP="${MACOS_APP:-$ROOT_DIR/build/$APP_NAME.app}"
fi

# The one self-signed certificate appkit makes, shared by every Mac app on it.
# Shared because the designated requirement it produces is per-app anyway — the
# bundle id is the other half of the match — so a certificate per app would be
# the same grant, made three times, expiring on three different days.
MACOS_SELF_SIGNED="appkit Local Signing"
MACOS_KEYCHAIN="${MACOS_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

# --- the device -------------------------------------------------------------
#
# There is one, it is this Mac, and it cannot be created or booted. DEVICE_ID is
# set to the computer name purely so the progress lines and `--device` have
# something true to print.

platform_resolve() {
  DEVICE_ID="$(scutil --get ComputerName 2>/dev/null || hostname)"
  UDID="$DEVICE_ID"
  DEVICE_KIND=mac
}

# One pass. A second copy of a Mac app would be a second window on the same
# screen, racing the first for the front — and the front window is what a
# capture photographs. Said out loud rather than silently ignored, the same way
# Android does it: a capture.jobs copied from an iOS manifest would otherwise
# look like it did something.
platform_workers() {
  local wanted="$1"
  DEVICES=("$DEVICE_ID")
  WORKERS=()
  ((wanted == 1)) || warn "  macOS captures on one screen — ignoring capture.jobs $wanted"
  JOBS=1
}

platform_list_devices() {
  printf '  this Mac:\n'
  printf '    %s — %s, macOS %s\n' \
    "$(scutil --get ComputerName 2>/dev/null || hostname)" \
    "$(sysctl -n hw.model 2>/dev/null || echo Mac)" \
    "$(sw_vers -productVersion)"
}

# `appkit run --device` exists because iOS has a real choice to make. Here the
# only true answer is this machine, so anything else is refused rather than
# quietly redirected — a run that installs somewhere you weren't looking is the
# failure --device was introduced to prevent.
platform_use_device() {
  local wanted="$1" this
  this="$(scutil --get ComputerName 2>/dev/null || hostname)"
  case "$wanted" in
    "$this" | localhost | mac | "this Mac") ;;
    *) die "macOS builds run on this Mac, and '$wanted' is not it ($this) — run: appkit run" ;;
  esac
  DEVICE_ID="$this"
  UDID="$this"
  DEVICE_KIND=mac
}

# Quit whatever copy is already running, so the next launch is the build that
# was just made. `open` ACTIVATES a running instance rather than replacing it,
# so a surviving process keeps serving the previous build — including whatever
# permission state it latched at launch, which is the confusing half.
#
# No appearance pin here, unlike iOS and Android — see macos_appearance_args for
# where it goes instead, and why it cannot go on the "device".
platform_prepare() {
  macos_quit
}

# What `appkit run` means by installing: /Applications, where a Mac app lives.
# Deliberately NOT called by platform_prepare — a capture runs the app out of
# build/, and a screenshot pass that quietly replaced the copy in /Applications
# would be a real change to the machine made by a read-only-sounding command.
platform_install() {
  local destination="/Applications/$APP_NAME.app"
  macos_quit
  rm -rf "$destination"
  cp -R "$MACOS_APP" "$destination"
  APP="$destination"
}

platform_launch() {
  local device="$1"
  shift
  macos_appearance_args
  macos_quit
  # -n: a new instance, every time. Without it `open` hands the arguments to
  # whatever is already running, which ignores them — the scene never changes
  # and every capture in the set is of the first one.
  open -n "$APP" --args "$@" ${MACOS_APPEARANCE_ARGS[@]+"${MACOS_APPEARANCE_ARGS[@]}"}
}

# One frame of the app's front window, by window id — not the whole screen.
#
# The screen is the wrong unit twice over: it carries your desktop and menu bar
# into the shot, and it is whatever panel this Mac has, so a set shot on a 14"
# and a set shot on a Studio Display are different pictures. A window is the
# same pixels on both.
#
# -o drops the drop shadow. A shadow is composited against the desktop behind
# it, which makes the capture non-deterministic — the one property the whole
# still-frame shutter depends on.
platform_screenshot() {
  local device="$1" output="$2" window
  window="$("$(appkit_tool window-id)" "$BUNDLE_ID" 2>/dev/null || true)"
  [[ -n "$window" ]] || die "no on-screen window for $BUNDLE_ID.
  A menu-bar-only app (LSUIElement) has none to photograph, and a window that
  has not opened yet needs a longer settle in scripts/scenes.sh."
  quiet screencapture -x -o -l "$window" "$output"
}

# No SpringBoard, and nothing to restart but the app. A Mac app that stopped
# drawing is one relaunch away from drawing again.
platform_kick() {
  macos_appearance_args
  macos_quit
  open -n "$APP" --args ${MACOS_APPEARANCE_ARGS[@]+"${MACOS_APPEARANCE_ARGS[@]}"}
  sleep 2
}

platform_retire() { macos_quit; }

# --- helpers the contract does not name -------------------------------------

macos_quit() {
  pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
  pkill -x "$APP_NAME" 2>/dev/null || true
  # pkill returns the moment the signal is sent, not when the process is gone,
  # and `open -n` on a still-dying app races its own teardown.
  local waited=0
  while pgrep -x "$APP_NAME" >/dev/null 2>&1 && ((waited < 20)); do
    sleep 0.25
    waited=$((waited + 1))
  done
}

# Arguments every launch carries, as an array rather than a string: a string
# would be word-split by whoever expanded it, which is a bug waiting for the
# first argument with a space in it.
#
# Appearance goes in as a LAUNCH ARGUMENT because AppKit reads -Key value pairs
# off argv into NSUserDefaults exactly as UIKit does — so it dresses this one
# process dark without touching the machine's own setting. iOS and Android pin
# appearance on the device because the device is a simulator or a phone; here it
# is the Mac you are looking at, and `defaults write -g AppleInterfaceStyle`
# would flip your real desktop to take a screenshot.
MACOS_APPEARANCE_ARGS=()
macos_appearance_args() {
  MACOS_APPEARANCE_ARGS=()
  case "${APPEARANCE:-}" in
    dark) MACOS_APPEARANCE_ARGS=(-AppleInterfaceStyle Dark) ;;
    light) MACOS_APPEARANCE_ARGS=(-AppleInterfaceStyle Light) ;;
  esac
}

# --- build, and the bundle around it ----------------------------------------

# Universal only for the build that is leaving this Mac. `appkit run` compiles
# for the architecture it is running on: the second slice doubles a build
# somebody is waiting for, and no Mac here would run it. A download has no such
# luxury — macOS 14 runs on Intel too, and an arm64-only archive is a download
# that cannot be opened by the people least equipped to work out why.
macos_arch_args() {
  MACOS_ARCH_ARGS=()
  if [[ "${MACOS_DISTRIBUTING:-false}" == true ]]; then
    MACOS_ARCH_ARGS=(--arch arm64 --arch x86_64)
  fi
}

platform_build() {
  if [[ -n "${MACOS_PROJECT:-}" ]]; then
    macos_xcodebuild
    return
  fi
  macos_swiftpm_build
}

# The Xcode half. Nothing to assemble: xcodebuild produces the whole bundle —
# Info.plist, icon, resources, signature — the way it does on iOS, which is the
# entire reason a repo would declare macos.project rather than keep a second
# build system for sources its iOS targets already compile.
#
# The signature it applies is this machine's. Distribution wants Developer ID
# with a timestamp and the hardened runtime, so macos_sign runs over the top for
# that one case, exactly as macos_assemble does on the other path.
macos_xcodebuild() {
  local logfile config
  config="$(macos_xcode_config)"
  log "Building $MACOS_SCHEME ($config)"
  logfile="$(mktemp -t appkit-build)"
  if ! xcodebuild \
    -project "$ROOT_DIR/$MACOS_PROJECT" \
    -scheme "$MACOS_SCHEME" \
    -configuration "$config" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination 'platform=macOS' \
    -allowProvisioningUpdates \
    build >"$logfile" 2>&1; then
    tail -40 "$logfile" >&2
    rm -f "$logfile"
    die "build failed"
  fi
  rm -f "$logfile"
  [[ "${MACOS_DISTRIBUTING:-false}" == true ]] && macos_sign
  return 0
}

macos_swiftpm_build() {
  local logfile
  macos_arch_args
  log "Building $MACOS_PRODUCT ($MACOS_CONFIG${MACOS_ARCH_ARGS+, universal})"
  logfile="$(mktemp -t appkit-build)"
  if ! swift build -c "$MACOS_CONFIG" --package-path "$ROOT_DIR" \
    ${MACOS_ARCH_ARGS[@]+"${MACOS_ARCH_ARGS[@]}"} \
    --product "$MACOS_PRODUCT" >"$logfile" 2>&1; then
    tail -40 "$logfile" >&2
    rm -f "$logfile"
    die "build failed"
  fi
  rm -f "$logfile"
  macos_assemble
}

# SwiftPM's executable, wrapped in the directory layout macOS will launch.
#
# Every step here was in both of the build.sh scripts this replaces, and they
# disagreed on all of them: where the bundle goes, whether Info.plist is a
# template or a literal, whether the icon is built, and whether the dependency
# resource bundles are copied at all — one script did and one did not, which is
# a crash on the first Bundle.module lookup rather than a missing picture.
macos_assemble() {
  local bin_path resource
  # The same architecture flags, because they move the answer: a universal build
  # lands in .build/apple/Products/Release and a native one in
  # .build/arm64-apple-macosx/release. Asked without them, this finds the
  # previous native build and quietly assembles a bundle around it.
  macos_arch_args
  bin_path="$(swift build -c "$MACOS_CONFIG" --package-path "$ROOT_DIR" \
    ${MACOS_ARCH_ARGS[@]+"${MACOS_ARCH_ARGS[@]}"} --show-bin-path)"
  [[ -x "$bin_path/$MACOS_PRODUCT" ]] ||
    die "no $MACOS_PRODUCT executable at $bin_path — is macos.product right?"

  log "Assembling $(basename "$MACOS_APP")"
  rm -rf "$MACOS_APP"
  mkdir -p "$MACOS_APP/Contents/MacOS" "$MACOS_APP/Contents/Resources"

  cp "$bin_path/$MACOS_PRODUCT" "$MACOS_APP/Contents/MacOS/$APP_NAME"
  chmod +x "$MACOS_APP/Contents/MacOS/$APP_NAME"

  macos_write_plist
  printf 'APPL????' >"$MACOS_APP/Contents/PkgInfo"

  # SwiftPM emits a dependency's resources as sibling .bundle directories, and
  # Bundle.module resolves them from Contents/Resources inside an app bundle.
  # Missing, the app builds, launches, and dies on the first lookup.
  shopt -s nullglob
  for resource in "$bin_path"/*.bundle; do
    cp -R "$resource" "$MACOS_APP/Contents/Resources/"
  done
  shopt -u nullglob

  for resource in ${MACOS_RESOURCES[@]+"${MACOS_RESOURCES[@]}"}; do
    [[ -e "$ROOT_DIR/$resource" ]] || die "macos.resources names $resource, which does not exist"
    cp -R "$ROOT_DIR/$resource" "$MACOS_APP/Contents/Resources/"
  done

  macos_write_icon
  macos_write_profile
  macos_write_frameworks
  macos_sign
}

# The .xcframework a SwiftPM binary dependency ships, unwrapped into the one
# place dyld looks for it inside an app bundle.
#
# SwiftPM links against an .xcframework but will not embed it — embedding is the
# half Xcode does, and neither Mac app here has an Xcode project. Without this
# the app builds, signs and verifies, then dies at launch with "Library not
# loaded: @rpath/Sparkle.framework/Versions/B/Sparkle", which reads like a
# broken dependency rather than a missing copy step.
macos_write_frameworks() {
  local name artifacts xcframework slice
  # Declared-and-empty rather than ${#...}: a repo with no frameworks has no
  # MACOS_FRAMEWORKS at all — the manifest writes a list only when it has one —
  # and `set -u` makes reading an unset array fatal rather than empty.
  local wanted=(${MACOS_FRAMEWORKS[@]+"${MACOS_FRAMEWORKS[@]}"})
  ((${#wanted[@]})) || return 0

  artifacts="$ROOT_DIR/.build/artifacts"
  mkdir -p "$MACOS_APP/Contents/Frameworks"
  for name in "${wanted[@]}"; do
    xcframework="$(find "$artifacts" -type d -name "$name.xcframework" 2>/dev/null | head -1)"
    [[ -n "$xcframework" ]] ||
      die "macos.frameworks names $name, and no $name.xcframework is under
  .build/artifacts — is it still a dependency in Package.swift?"

    # Prefer the slice with both architectures, so a universal app does not get
    # a framework that is half of one. Sparkle ships exactly one macos slice and
    # it is universal; the preference costs nothing and is not a guess.
    slice="$(find "$xcframework" -maxdepth 1 -type d -name 'macos-*x86_64*' | head -1)"
    [[ -n "$slice" ]] ||
      slice="$(find "$xcframework" -maxdepth 1 -type d -name 'macos*' | head -1)"
    [[ -n "$slice" ]] ||
      die "$name.xcframework carries no macOS slice"

    rm -rf "$MACOS_APP/Contents/Frameworks/$name.framework"
    cp -R "$slice/$name.framework" "$MACOS_APP/Contents/Frameworks/" ||
      die "could not copy $name.framework out of $(basename "$xcframework")"
    log "  framework ($name)"
  done

  # And the executable has to be told where to look. SwiftPM links against the
  # .xcframework where it found it and leaves an rpath pointing into .build —
  # true on this Mac, meaningless on anybody else's. Best effort: a second
  # -add_rpath of a path already present fails, which is what a rebuilt bundle
  # would hit and is not an error.
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$MACOS_APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
}

# The repo's Info.plist, with the two values appkit.json already carries
# substituted in. A plist with no placeholders passes through unchanged, so a
# repo that spells its own name out is not forced to stop.
macos_write_plist() {
  local template="$ROOT_DIR/$MACOS_PLIST"
  [[ -f "$template" ]] || die "no Info.plist at $MACOS_PLIST (set macos.infoPlist)"
  sed -e "s/__APP_NAME__/$APP_NAME/g" \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    "$template" >"$MACOS_APP/Contents/Info.plist"

  # The bundle id is what TCC files a permission grant under and what `open`
  # resolves, so a template that forgot the placeholder is worth catching here
  # rather than as a permission that silently attaches to the wrong app.
  local written
  written="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$MACOS_APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$written" == "$BUNDLE_ID" ]] ||
    die "Info.plist says CFBundleIdentifier '$written', appkit.json says '$BUNDLE_ID'"
}

# The app icon, in whichever of the two forms a repo keeps it.
#
# Both are real and neither is wrong, which is why this takes either:
#
#   "icon": "Resources/Yap.icns"        a FINISHED icns, committed
#   "icon": "Resources/AppIcon.png"     a 1024 master, cut here
#
# A finished .icns is the better default — cutting one can need tools the build
# otherwise does not (Yap's comes out of librsvg), and paying for those on every
# build to reproduce a file that changes twice a year is the wrong trade. A
# master is right when the icon is DRAWN BY A PROGRAM in this repo, which is
# Framedly's: there, `iconCommand` regenerates it first, and without that every
# build would ship whatever PNG was last committed.
#
# Best effort throughout: an app with no icon runs fine, and a repo that has not
# drawn one yet should not be unable to build.
macos_write_icon() {
  local source destination named iconset pair size name
  [[ -n "${MACOS_ICON:-}" ]] || return 0

  if [[ -n "${MACOS_ICON_CMD:-}" ]]; then
    (cd "$ROOT_DIR" && eval "$MACOS_ICON_CMD") >/dev/null 2>&1 ||
      warn "  macos.iconCommand failed — using the icon already on disk"
  fi

  source="$ROOT_DIR/$MACOS_ICON"
  [[ -f "$source" ]] || {
    warn "  no icon at $MACOS_ICON — building without one"
    return 0
  }

  # CFBundleIconFile is what macOS actually looks up, and the two repos here
  # spell it differently ("Yap", "AppIcon"). Writing AppIcon.icns regardless
  # produces a bundle with an icon file nothing references and no icon on it —
  # which looks exactly like a build that failed to make one.
  named="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' \
    "$MACOS_APP/Contents/Info.plist" 2>/dev/null || true)"
  named="${named:-AppIcon}"
  named="${named%.icns}"
  destination="$MACOS_APP/Contents/Resources/$named.icns"

  if [[ "$MACOS_ICON" == *.icns ]]; then
    cp "$source" "$destination"
    log "  icon ($named.icns)"
    return 0
  fi

  iconset="$(mktemp -d -t appkit-iconset)/$named.iconset"
  mkdir -p "$iconset"
  for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
    "128 128x128" "256 128x128@2x" "256 256x256" \
    "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    size="$1"
    name="$2"
    sips -z "$size" "$size" "$source" --out "$iconset/icon_$name.png" >/dev/null 2>&1
  done
  if iconutil -c icns "$iconset" -o "$destination" 2>/dev/null; then
    log "  icon ($named.icns)"
  else
    warn "  iconutil could not build an .icns from $MACOS_ICON"
  fi
  rm -rf "$(dirname "$iconset")"
}

# The profile Apple issued for this App ID, in the one place macOS looks for it.
#
# Most entitlements are a claim the system simply believes. A restricted one —
# every com.apple.developer.* key, so Sign in with Apple, iCloud, push — is a
# claim it checks, against a profile Apple signed for this bundle id. Missing,
# nothing warns: the build succeeds, `codesign --verify` passes, the app
# installs, and then launchd says
#
#   Launch failed. ... NSPOSIXErrorDomain Code=163 "Launchd job spawn failed"
#
# because AMFI killed the process at exec. Nothing appears in the log under the
# app's name, and deleting the entitlement "fixes" it, which sends you looking
# at the capability rather than at what authorizes it. Worse, it is not a
# local-only failure to shrug at: distribute would notarize that bundle and
# every download would die the same way.
#
# Before macos_sign, never after. The profile is sealed into the signature like
# any other file in the bundle, so adding it to an already-signed app breaks the
# seal instead of fixing the launch.
macos_write_profile() {
  local profile restricted

  # No profile named. Silence is right for the app that needs none — but an app
  # that declares a restricted entitlement and no profile is the failure above,
  # already built, and this is the last place holding both halves of it.
  if [[ -z "${MACOS_PROVISIONING_PROFILE:-}" ]]; then
    [[ -n "${MACOS_ENTITLEMENTS:-}" ]] || return 0
    # `|| true` because no match is grep's exit 1, and this script runs under
    # `pipefail`: without it, an entitlements file that declares nothing
    # restricted — the common case, and the one this branch exists to pass over
    # in silence — aborts the whole build with no message at all.
    restricted="$(grep -o 'com\.apple\.developer\.[A-Za-z.-]*' \
      "$ROOT_DIR/$MACOS_ENTITLEMENTS" 2>/dev/null | sort -u | tr '\n' ' ' || true)"
    [[ -n "$restricted" ]] || return 0
    warn "  $MACOS_ENTITLEMENTS declares ${restricted% }, which macOS grants only"
    warn "  through a provisioning profile. Without one it kills the app at launch:"
    warn "      Launch failed. ... \"Launchd job spawn failed\" (POSIX 163)"
    warn "  Download the profile for this App ID from the developer portal, keep it"
    warn "  in the repo, and name it as macos.provisioningProfile."
    return 0
  fi

  profile="$ROOT_DIR/$MACOS_PROVISIONING_PROFILE"
  [[ -f "$profile" ]] ||
    die "macos.provisioningProfile names $MACOS_PROVISIONING_PROFILE, which does not exist"

  cp "$profile" "$MACOS_APP/Contents/embedded.provisionprofile"
  log "  profile ($MACOS_PROVISIONING_PROFILE)"
}

# --- signing ----------------------------------------------------------------
#
# On iOS a development signature is a formality. Here it decides whether the app
# keeps its permissions between builds, which is why this is the longest thing
# in the file.
#
# TCC pins a grant — Accessibility, Screen Recording, the microphone — to the
# app's DESIGNATED REQUIREMENT. Signed ad-hoc, that requirement is
# `cdhash H"..."`, a hash of the binary, so every rebuild is a brand-new app to
# TCC and the grant is silently dropped while System Settings still shows the
# toggle switched on. Signed with a real certificate it becomes
#
#   identifier "com.example.App" and anchor apple generic and
#     certificate leaf[subject.CN] = "..."
#
# which has no cdhash in it, so it survives every rebuild — and matches on the
# certificate's NAME rather than its hash, so renewing the certificate does not
# break it either.
#
# Both build.sh scripts this replaced carried a version of that paragraph. Only
# one of them did anything about it; the other told you to run `tccutil reset`
# after each build.

# Explicit override, then a real Apple certificate, then the one appkit can
# make, then ad-hoc. Developer ID sorts above Apple Development because it is
# the one that also works on somebody else's Mac, and for TCC's purposes they
# are equally stable.
macos_identity() {
  local identities found
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return
  fi
  if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
    printf '%s' "$MACOS_SIGN_IDENTITY"
    return
  fi
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for found in "Developer ID Application" "Apple Development" "$MACOS_SELF_SIGNED"; do
    local match
    match="$(grep -m1 -F "$found" <<<"$identities" | sed -n 's/.*"\(.*\)".*/\1/p')"
    [[ -n "$match" ]] && {
      printf '%s' "$match"
      return
    }
  done
  printf '%s' "-"
}

# The flags every signature inside this bundle shares. Entitlements are
# deliberately not among them: they are the app's claim about itself, and a
# framework signed with the app's would be asking for the microphone.
macos_codesign_args() {
  local identity="$1"
  MACOS_CODESIGN_ARGS=(--force --sign "$identity")

  # Hardened runtime: always for a build that is leaving this Mac, and also
  # whenever the app declares entitlements — outside the sandbox those are one
  # decision, and an entitlement without it is inert. Never ad-hoc: nothing
  # downstream trusts such a signature, so the restrictions would be paid for
  # and bought nothing.
  if [[ "$identity" != "-" ]] &&
    { [[ "${MACOS_DISTRIBUTING:-false}" == true ]] || [[ -n "${MACOS_ENTITLEMENTS:-}" ]]; }; then
    MACOS_CODESIGN_ARGS+=(--options runtime)
  fi

  # A secure timestamp is a network round trip to Apple, which is the wrong
  # trade on the build somebody is waiting for. Notarization refuses a signature
  # without one, so the distribute path turns it on for the build it sends.
  if [[ "${MACOS_DISTRIBUTING:-false}" == true ]]; then
    MACOS_CODESIGN_ARGS+=(--timestamp)
  else
    MACOS_CODESIGN_ARGS+=(--timestamp=none)
  fi
}

macos_sign() {
  local identity args entitlements framework

  identity="$(macos_identity)"

  if [[ "$identity" == "-" ]]; then
    warn "  no signing certificate — signing ad-hoc, which means macOS will drop"
    warn "  this app's permissions on every rebuild. Fix it once with:"
    warn "      appkit setup signing"
  else
    log "  signing as $identity"
  fi

  macos_codesign_args "$identity"

  # Inside out, and this is the ordering that is invisible when you get it
  # wrong. A signature seals what the bundle held at the moment it was made, so
  # an app signed before the framework inside it carries a seal describing a
  # file that has since changed — `codesign --verify --deep` says so, and
  # notarization refuses it.
  shopt -s nullglob
  for framework in "$MACOS_APP/Contents/Frameworks"/*.framework; do
    macos_sign_framework "$framework" "$identity"
  done
  shopt -u nullglob

  args=("${MACOS_CODESIGN_ARGS[@]}")
  if [[ -n "${MACOS_ENTITLEMENTS:-}" ]]; then
    entitlements="$ROOT_DIR/$MACOS_ENTITLEMENTS"
    [[ -f "$entitlements" ]] ||
      die "macos.entitlements names $MACOS_ENTITLEMENTS, which does not exist"
    args+=(--entitlements "$entitlements")
    log "  entitlements ($MACOS_ENTITLEMENTS)"
  fi

  # No --deep: what is nested here was signed above, on its own terms, and
  # Apple discourages it anyway.
  if ! codesign "${args[@]}" "$MACOS_APP" 2>/dev/null; then
    die "signing as '$identity' failed — the certificate may have expired, or its
  private key may not be in the keychain. Check:
      security find-identity -v -p codesigning
  Or name another one for this run:
      CODESIGN_IDENTITY='...' appkit run --device \"\$(scutil --get ComputerName)\""
  fi
}

# Everything inside a framework that is code in its own right, deepest first,
# and then the framework. Sparkle is why this exists: Autoupdate, Updater.app
# and the XPC services it carries are separate executables that codesign does
# not reach on its own, and each one Apple finds unsigned is a rejected
# notarization rather than a warning.
macos_sign_framework() {
  local framework="$1" identity="$2" inner
  log "  signing $(basename "$framework")"

  # Under Versions/ only. Everything at the top of a framework is a symlink into
  # it, and signing through those would sign the same file several times.
  while IFS= read -r inner; do
    codesign "${MACOS_CODESIGN_ARGS[@]}" "$inner" 2>/dev/null ||
      die "could not sign ${inner#"$MACOS_APP"/} as '$identity'"
  done < <(find "$framework/Versions" -depth -type d \
    \( -name '*.app' -o -name '*.xpc' \) 2>/dev/null)

  # The bare Mach-O files beside them — Sparkle's Autoupdate, and the library
  # the framework is named after.
  while IFS= read -r inner; do
    file -b "$inner" 2>/dev/null | grep -q 'Mach-O' || continue
    codesign "${MACOS_CODESIGN_ARGS[@]}" "$inner" 2>/dev/null ||
      die "could not sign ${inner#"$MACOS_APP"/} as '$identity'"
  done < <(find "$framework/Versions" -maxdepth 2 -type f -perm -u+x 2>/dev/null)

  codesign "${MACOS_CODESIGN_ARGS[@]}" "$framework" 2>/dev/null ||
    die "could not sign $(basename "$framework") as '$identity'"
}

# A code-signing certificate in the login keychain, for a machine with no Apple
# one. `appkit setup signing` calls this; nothing else does.
#
# To undo: Keychain Access > login > Certificates > delete "appkit Local Signing".
platform_setup_signing() {
  local tmp
  if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$MACOS_SELF_SIGNED"; then
    log "\"$MACOS_SELF_SIGNED\" already exists — nothing to do."
    return 0
  fi

  tmp="$(mktemp -d)"
  log "Generating \"$MACOS_SELF_SIGNED\""
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -subj "/CN=$MACOS_SELF_SIGNED" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null ||
    die "openssl could not generate a certificate"

  # The three algorithm flags are not optional and not cosmetic. OpenSSL 3
  # defaults a PKCS#12 to AES-256-CBC with a SHA-256 MAC; macOS's Security
  # framework reads neither, and `security import` rejects the file with
  # "MAC verification failed during PKCS12 import (wrong password?)" — a message
  # about the password, for a file whose password is fine. The older triplet is
  # what it accepts.
  #
  # The password is a throwaway rather than empty for the same reason: an
  # empty-password p12 is its own edge case in both tools, and this file is
  # deleted three lines below.
  openssl pkcs12 -export -out "$tmp/id.p12" \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:appkit \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null ||
    die "openssl could not package the certificate"

  # -T /usr/bin/codesign and -A are what stop the keychain prompting on every
  # single build afterwards.
  security import "$tmp/id.p12" -k "$MACOS_KEYCHAIN" -P appkit -T /usr/bin/codesign -A ||
    die "could not import the certificate into $MACOS_KEYCHAIN"

  log "Marking it trusted — macOS will ask for your login password, which is expected"
  security add-trusted-cert -r trustRoot -k "$MACOS_KEYCHAIN" "$tmp/cert.pem" ||
    die "could not mark the certificate as trusted"

  rm -rf "$tmp"
  log "Done. Every Mac app on appkit will use it from the next build."
}

# --- distributing outside a store -------------------------------------------
#
# What has to be true before a .app opens by double-click on the Mac of somebody
# who has never heard of you: signed with a Developer ID Application
# certificate, hardened runtime on, a secure timestamp in the signature,
# notarized by Apple, and the resulting ticket STAPLED into the bundle. Miss any
# one and Gatekeeper says "Apple could not verify..." with no way forward a
# normal person will find.
#
# One ordering here is easy to get wrong and invisible when you do. The ticket
# is stapled to the .app, and the archive that was submitted was made BEFORE
# there was a ticket to staple — so the zip is built twice, and the SECOND one
# is what ships. Ship the first and it passes every check you can run on a
# machine with a network, then fails on a laptop on a plane, because stapling is
# what makes Apple's verdict travel with the file.

# Machine-wide, like the signing certificate and for the same reason: notarizing
# is an account talking to Apple, not an app, and one profile serves every Mac
# app on appkit. NOTARY_PROFILE overrides for a machine that keeps several.
MACOS_NOTARY_PROFILE="${NOTARY_PROFILE:-appkit-notary}"

platform_distribute() {
  local version out zip dmg identity

  macos_require_developer_id
  # Read by macos_sign, which is reached through platform_build below.
  MACOS_DISTRIBUTING=true

  if [[ "${SKIP_BUILD:-false}" == true ]]; then
    [[ -d "$MACOS_APP" ]] ||
      die "no bundle at ${MACOS_APP#"$ROOT_DIR"/} — drop --skip-build"
    # The bundle on disk was signed for this Mac: no timestamp, and no hardened
    # runtime unless it declares entitlements. Re-signing is the whole of what
    # --skip-build skips the build to get to.
    log "Re-signing $(basename "$MACOS_APP") for distribution"
    macos_sign
  else
    platform_build
  fi

  version="$(platform_version)"
  out="${DIST_DIR:-$ROOT_DIR/build}"
  mkdir -p "$out"
  zip="$out/$APP_NAME-$version.zip"
  dmg="$out/$APP_NAME-$version.dmg"

  macos_archive "$zip"
  macos_notarize "$zip"

  log "Stapling the ticket into the bundle"
  quiet xcrun stapler staple "$MACOS_APP" ||
    die "notarization succeeded but the ticket would not staple — retry, this is
  usually Apple's side not having published it yet"
  macos_archive "$zip"

  # And again, for the image. Two submissions rather than one, because a ticket
  # is stapled to a FILE: the .dmg needs its own for the Gatekeeper check that
  # happens when it is mounted, and the app inside needs its own for the laptop
  # that opens it on a plane six months later. The image is built from the
  # already-stapled bundle, so the app carries both.
  identity="$(macos_identity)"
  log "Building $(basename "$dmg")"
  macos_dmg "$dmg"
  quiet codesign --force --sign "$identity" --timestamp "$dmg" ||
    die "could not sign $(basename "$dmg") — notarization will not take it unsigned"
  macos_notarize "$dmg"
  quiet xcrun stapler staple "$dmg" ||
    die "the image was notarized but the ticket would not staple — retry"

  macos_verify_distribution "$zip" "$dmg"
}

# The disk image a person downloads, as opposed to the archive the updater
# unpacks. Both ship, and they are for different readers.
#
# Not a zip, and the reason is App Translocation. A .app unzipped into
# ~/Downloads and opened there runs from a randomised read-only path, and every
# permission macOS grants it is filed under that path — so Accessibility, which
# this kind of app cannot work without, is granted once and gone by the next
# launch, with nothing on screen to say why. An image with an /Applications
# alias in it is how a Mac says where the app goes, and an app dragged there is
# translocated by nothing.
#
# Which is why the window is LAID OUT rather than left to Finder, and that is
# not decoration: this window is the whole of the install instructions. Two
# icons in the top left corner at whatever size Finder last used read as two
# folders, and the one thing a person must do — drag the left one onto the right
# one — is not said anywhere. They open the app where it landed instead, and it
# runs translocated: Sparkle refuses those outright, so it also never updates.
#
# Laid out, and nothing else. No background picture, and that is a decision:
# a picture has to live somewhere on the volume, the somewhere is a .background
# folder, and Finder gives any item it can see a row of the icon grid to itself
# — a row below the two icons, which is a window that opens with a scroll bar
# down the side of it and a folder in it nobody was meant to see. Two icons and
# the space between them say the same sentence. They also follow the Mac into
# Dark Mode, which one static picture can never do.

# The window that opens when the image mounts, in points, and the two icons in
# it. One layout for every app on appkit, because the sentence it draws is the
# same one in all of them.
MACOS_DMG_WIDTH=640
MACOS_DMG_HEIGHT=400
MACOS_DMG_ICON=128
MACOS_DMG_APP_X=170
MACOS_DMG_ALIAS_X=470
MACOS_DMG_ROW_Y=190

macos_dmg() {
  local dmg="$1" staging writable attached mount
  staging="$(mktemp -d -t appkit-dmg)"
  # ditto again, not cp: the bundle has a stapled ticket in its extended
  # attributes by now, and an image built from a copy that lost them is an
  # image whose app has to phone Apple to open.
  ditto "$MACOS_APP" "$staging/$(basename "$MACOS_APP")" ||
    die "could not stage $MACOS_APP for the image"
  ln -s /Applications "$staging/Applications"

  rm -f "$dmg"
  # Writable first, and the image that ships is a conversion of it. A window's
  # layout is a .DS_Store, .DS_Store is written by FINDER and by nothing else,
  # and Finder can only write one into an image it can mount read-write.
  writable="$staging.rw.dmg"
  rm -f "$writable"
  # -size, because hdiutil sizes an image to exactly what it was handed and
  # Finder needs somewhere to put the .DS_Store afterwards.
  quiet hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -fs HFS+ \
    -format UDRW -size "$(($(du -sk "$staging" | cut -f1) + 20480))k" -ov "$writable" ||
    die "could not build the writable image"

  attached="$(hdiutil attach "$writable" -readwrite -noverify -noautoopen)" ||
    die "could not mount the writable image"
  # Where it actually mounted, rather than /Volumes/$APP_NAME. A volume of that
  # name may already be there — the copy last release left on somebody's desktop
  # — and macOS silently mounts this one as "Shaberu 1" beside it.
  mount="$(printf '%s\n' "$attached" | awk -F'\t' '$NF ~ /^\/Volumes\// { print $NF }' | tail -1)"
  [[ -n "$mount" ]] || die "the writable image mounted nowhere"

  # Made by mounting read-write, and gone before Finder is asked to lay anything
  # out. Not tidiness: an item Finder can see when it writes the .DS_Store is
  # given a row of the grid to itself, and that row outlives the file — the
  # window ships with a scroll bar down the side pointing at nothing.
  rm -rf "$mount/.fseventsd" "$mount/.Trashes" "$mount/.TemporaryItems"

  macos_dmg_window "$(basename "$mount")" "$(basename "$MACOS_APP")" ||
    warn "could not lay the image window out — shipping it as Finder left it"

  macos_dmg_detach "$mount"

  # And again, on a mount Finder is not told about. fseventsd puts its log back
  # on any volume mounted read-write — including the one Finder was just laying
  # out — so the delete above keeps it out of the .DS_Store and this one keeps
  # it out of the image.
  attached="$(hdiutil attach "$writable" -readwrite -noverify -noautoopen -nobrowse)" ||
    die "could not remount the writable image"
  mount="$(printf '%s\n' "$attached" | awk -F'\t' '$NF ~ /^\/Volumes\// { print $NF }' | tail -1)"
  [[ -n "$mount" ]] || die "the writable image mounted nowhere"
  rm -rf "$mount/.fseventsd" "$mount/.Trashes" "$mount/.TemporaryItems"
  macos_dmg_detach "$mount"

  # HFS+ rather than APFS: an APFS image is unreadable to a Mac older than the
  # app supports anyway, and gains nothing here. UDZO is the compressed,
  # read-only format every download is.
  quiet hdiutil convert "$writable" -format UDZO -imagekey zlib-level=9 -o "$dmg" ||
    die "could not build $dmg"
  rm -f "$writable"
  rm -rf "$staging"
}

# The layout, asked for in the only language that can write a .DS_Store.
#
# Cosmetic, and so deliberately not fatal — the caller warns and ships the image
# anyway. The failure this protects against is a Mac that has not yet been asked
# whether the terminal may control Finder, or has been asked and told no: an
# icon position is not worth ending a release that is otherwise built, signed
# and notarized.
macos_dmg_window() {
  local volume="$1" app="$2"
  osascript - "$volume" "$app" \
    "$MACOS_DMG_WIDTH" "$MACOS_DMG_HEIGHT" "$MACOS_DMG_ICON" \
    "$MACOS_DMG_APP_X" "$MACOS_DMG_ALIAS_X" "$MACOS_DMG_ROW_Y" >/dev/null <<'APPLESCRIPT'
on run argv
  set volumeName to item 1 of argv
  set appName to item 2 of argv
  set windowWidth to (item 3 of argv) as integer
  set windowHeight to (item 4 of argv) as integer
  set iconSize to (item 5 of argv) as integer
  set appX to (item 6 of argv) as integer
  set aliasX to (item 7 of argv) as integer
  set rowY to (item 8 of argv) as integer

  tell application "Finder"
    tell disk volumeName
      open
      set theWindow to container window
      set current view of theWindow to icon view
      set toolbar visible of theWindow to false
      set statusbar visible of theWindow to false
      -- Finder measures a window frame from the top of its title bar and the
      -- icons hang from the top of the CONTENT below it, so the frame is the
      -- layout plus that bar: 32 points, measured rather than assumed.
      set the bounds of theWindow to {240, 180, 240 + windowWidth, 180 + windowHeight + 32}
      set theOptions to the icon view options of theWindow
      -- Without this Finder arranges the window by kind and the two positions
      -- below are quietly ignored.
      set arrangement of theOptions to not arranged
      set icon size of theOptions to iconSize
      set text size of theOptions to 13
      set position of item appName of theWindow to {appX, rowY}
      set position of item "Applications" of theWindow to {aliasX, rowY}
      -- Finder writes the .DS_Store on its own schedule; closing the window is
      -- what makes it do so now, and the pause is for it to finish.
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT
}

# Finder holds the volume open for a moment after it is done with it, and an
# eject that lands in that moment fails with "resource busy". Wait, then insist.
macos_dmg_detach() {
  local mount="$1" attempt
  sync
  for ((attempt = 0; attempt < 10; attempt++)); do
    quiet hdiutil detach "$mount" && return 0
    sleep 1
  done
  quiet hdiutil detach "$mount" -force ||
    die "the writable image would not unmount ($mount)"
}

# Notarization is the one thing the fallback ladder in macos_identity cannot
# cover for. Apple Development signs an app for YOUR machines; the self-signed
# certificate signs it for this one. Neither can be notarized, and both fail
# late — after a build, an upload and a wait — with a message about the
# submission rather than about the certificate.
macos_require_developer_id() {
  local identity
  identity="$(macos_identity)"
  case "$identity" in
    "Developer ID Application"*)
      log "Distributing as $identity"
      ;;
    *)
      die "notarization needs a Developer ID Application certificate, and the one
  appkit resolved is '$identity'.

  It comes from a PAID Apple Developer Program membership, and only the Account
  Holder can issue one:
      Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application

  Then check it landed, and that its private key came with it:
      security find-identity -v -p codesigning"
      ;;
  esac
}

# ditto, not zip(1). A .app is a tree of symlinks and extended attributes, and
# ditto is the only archiver here that preserves both — a bundle round-tripped
# through zip(1) can arrive with a signature that no longer verifies, which
# looks like a signing bug rather than a packaging one.
macos_archive() {
  local zip="$1"
  rm -f "$zip"
  ditto -c -k --keepParent "$MACOS_APP" "$zip" ||
    die "could not archive $MACOS_APP"
}

macos_notarize() {
  local zip="$1" output="" status=0 id
  log "Notarizing $(basename "$zip") — Apple usually answers within a few minutes"

  output="$(xcrun notarytool submit "$zip" \
    --keychain-profile "$MACOS_NOTARY_PROFILE" --wait 2>&1)" || status=$?
  printf '%s\n' "$output"

  # Both checks: notarytool has exited 0 on a submission whose status is Invalid,
  # so the exit code alone would ship a rejected build.
  if ((status == 0)) && grep -q 'status: Accepted' <<<"$output"; then
    return 0
  fi

  # The submission id is the only way to the actual reason — the summary says
  # "Invalid" and nothing else. Fetched here so the failure is self-contained.
  id="$(sed -n 's/^ *id: *\([0-9a-fA-F-]\{36\}\).*/\1/p' <<<"$output" | head -1)"
  if [[ -n "$id" ]]; then
    warn "  why Apple rejected it:"
    xcrun notarytool log "$id" --keychain-profile "$MACOS_NOTARY_PROFILE" 2>&1 |
      sed 's/^/  /' >&2 || true
  fi

  die "notarization failed.
  If it could not authenticate at all, the keychain profile is missing. Make it
  once per Mac, with an App Store Connect API key (Keys tab, Developer role):
      xcrun notarytool store-credentials \"$MACOS_NOTARY_PROFILE\" \\
        --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>"
}

macos_verify_distribution() {
  local zip="$1" dmg="${2:-}" file sum

  log "Verifying what Gatekeeper will see"
  quiet codesign --verify --strict --verbose=2 "$MACOS_APP" ||
    die "the signature does not verify — do not ship this build"
  quiet xcrun stapler validate "$MACOS_APP" ||
    die "the ticket is not stapled — a Mac that is offline would refuse this build"
  # --type execute is what a .app is assessed as. The notarization docs say
  # --type install, which is for installer packages: it answers a question
  # nobody asked here and can pass while a double-click still fails.
  quiet spctl --assess --type execute --verbose=4 "$MACOS_APP" ||
    die "Gatekeeper refuses the app even though Apple accepted it"

  # What the binary actually runs on, printed because it is the one property of
  # a download nobody notices is wrong until an Intel Mac says the app "is not
  # supported on this type of Mac".
  log "Done. Anyone can open this one."
  log "  $(lipo -archs "$MACOS_APP/Contents/MacOS/$APP_NAME" 2>/dev/null || echo unknown)"
  for file in "$zip" ${dmg:+"$dmg"}; do
    [[ -f "$file" ]] || continue
    sum="$(shasum -a 256 "$file" | cut -d' ' -f1)"
    log "  $file ($(du -h "$file" | cut -f1))"
    log "    sha256 $sum"
  done
}

# --- what a command finds afterwards ----------------------------------------

platform_locate_app() {
  local stamp newest_source=0 dir
  APP="${APP:-$MACOS_APP}"
  [[ -d "$APP" ]] || die "no bundle at ${APP#"$ROOT_DIR"/} — drop --skip-build"
  [[ -x "$APP/Contents/MacOS/$APP_NAME" ]] ||
    die "$APP has no executable at Contents/MacOS/$APP_NAME"

  # The same warning iOS gives, and for the same reason: a capture only ever
  # shows what was last compiled, and every scene comes back looking exactly
  # right whether or not it contains the change being checked.
  stamp="$(stat -f%m "$APP/Contents/MacOS/$APP_NAME")"
  for dir in "${SOURCE_DIRS[@]}"; do
    [[ -d "$ROOT_DIR/$dir" ]] || continue
    local newest
    newest="$(find "$ROOT_DIR/$dir" -name '*.swift' -exec stat -f%m {} + 2>/dev/null | sort -rn | head -1)"
    [[ -n "$newest" ]] && ((newest > newest_source)) && newest_source="$newest"
  done
  log "Capturing $APP"
  if ((newest_source > stamp)); then
    warn "  the app is OLDER than the sources — build it again, or these are last build's scenes"
  fi
}

# A macOS bundle carries its .lproj under Contents/Resources rather than at the
# top level, which is the only thing that differs from the iOS check.
platform_verify_languages() {
  local language missing=()
  for language in "${LANGUAGES[@]}"; do
    [[ -d "$APP/Contents/Resources/$language.lproj" ]] || missing+=("$language.lproj")
  done
  if ((${#missing[@]})); then
    die "the app bundle predates the manifest's locales — missing ${missing[*]}
  at $APP/Contents/Resources
  Rebuild without --skip-build. If it still fails, the package does not carry
  a string catalog for every language in appkit.json."
  fi
}

# --- the version ------------------------------------------------------------
#
# In the Info.plist, which for a SwiftPM app is the only place either number is
# written. Read and written with PlistBuddy rather than sed: a plist is XML, and
# the two keys sit next to each other with identical-looking values.

macos_plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$ROOT_DIR/$MACOS_PLIST" 2>/dev/null || true
}

platform_version() {
  local version
  version="$(macos_plist_get CFBundleShortVersionString)"
  [[ -n "$version" ]] ||
    die "no CFBundleShortVersionString in $MACOS_PLIST"
  printf '%s' "$version"
}

# Both numbers, the same way Android moves both: a Mac app has no counterpart to
# `asc publish appstore` resolving the build number against Connect at ship
# time, so nothing else would ever move CFBundleVersion.
platform_set_version() {
  local version="$1" plist current next
  plist="$ROOT_DIR/$MACOS_PLIST"
  [[ -f "$plist" ]] || die "no Info.plist at $MACOS_PLIST"

  current="$(macos_plist_get CFBundleVersion)"
  [[ "$current" =~ ^[0-9]+$ ]] ||
    die "CFBundleVersion in $MACOS_PLIST is '$current', which is not a number to bump"
  next=$((current + 1))

  if [[ -n "$version" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
    log "CFBundleShortVersionString -> $version"
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$plist"
  log "CFBundleVersion -> $next"
}

# --- shipping ---------------------------------------------------------------
#
# The one place a Mac app on appkit stops short, said here rather than
# discovered as a broken command.
#
# `asc publish appstore` archives an XCODE PROJECT. A SwiftPM app does not have
# one, so there is nothing to hand it — and the gap is not a missing flag, it is
# that the Mac App Store wants a .pkg signed with a 3rd Party Mac Developer
# Installer certificate, which is a different chain from anything else here.
#
# Everything BEFORE the binary already works on macOS: `appkit upload
# screenshots` files DESKTOP cards through the same asc call iOS uses, and
# `appkit upload metadata` never had a platform in it at all. It is only the
# archive step that has no macOS shape yet.
platform_publish_args() {
  die "appkit cannot ship a SwiftPM Mac app to the Mac App Store yet.
  \`asc publish appstore\` archives an .xcodeproj, and this app is a package.

  The two ways out:
    - Outside the store: \`appkit distribute\` — signed, notarized, stapled,
      and a sha256 for whoever is serving the download. This is the one that
      works today.
    - Mac App Store: wrap the package in an Xcode project, then archive and
      upload from it, which is not automated here. \`appkit upload metadata\`
      and \`appkit upload screenshots\` already work against the same record."
}

# Swift is formatted, so a Mac repo takes the shared .swiftformat — the same row
# iOS takes, for the same reason.
platform_shared_files() {
  printf '%s\n' '.swiftformat|config/.swiftformat'
}
