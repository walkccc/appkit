# App Store Connect, through the `asc` CLI. Sourced after the manifest.
#
# Auth is one keychain entry for the whole account (`asc auth login`), not a
# private key in each working tree. A screenshot set uploads as one job.

asc_require() {
  command -v asc >/dev/null || die "asc not found — brew install asc"
  : "${ASC_APP_ID:?appkit.json must set ios.ascAppId (asc apps list --bundle-id)}"
  asc auth status >/dev/null 2>&1 ||
    die "asc is not authenticated — run:
  asc auth login --name TEAM --key-id KEY --issuer-id ISSUER --private-key AuthKey.p8"
}

# Upload every declared display size, for every locale. --path's immediate
# children must be locale directories.
#
# DEVICE_TYPES is a list because one locale folder can hold more than one
# display size: an app that ships a watch carries its 416×496 captures beside
# its phone cards, and asc matches by pixel size, uploading only the files that
# fit the type it was given. The type is decided by the card's OWN dimensions —
# Every card here is 1242×2688, which is IPHONE_65. That is a hard rule, not
# a default: one display size means one set to review.
asc_upload_screenshots() {
  local version="$1" dir="$2" device_type locales files
  [[ -d "$dir" ]] || die "no screenshots at $dir"
  : "${DEVICE_TYPES:?appkit.json must set ios.deviceTypes (see: asc screenshots sizes --all)}"
  locales="$(find "$dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  files="$(find "$dir" -name '*.png' | wc -l | tr -d ' ')"
  for device_type in "${DEVICE_TYPES[@]}"; do
    # asc fans this out across every locale in one call (see upload.sh for
    # why), so nothing prints again until it either lands or fails — a count
    # up front is the only way to tell "working" from "stuck".
    log "Uploading $device_type screenshots for $version ($files files, $locales locales)"
    asc screenshots upload \
      --app "$ASC_APP_ID" \
      --version "$version" \
      --path "$dir" \
      --device-type "$device_type" \
      --replace
  done
}

# `ready` is false when the approval names an older plan hash, and also when it
# leaves any planned key pending: apply is all-or-nothing, so a half-approved
# plan applies NOTHING rather than the approved half. Only consulted when the
# caller asked for --review.
asc_review_ready() {
  asc metadata status --review-dir "$1" 2>/dev/null | python3 -c 'import json, sys
try:
    print("yes" if json.load(sys.stdin).get("ready") else "no")
except Exception:
    print("no")'
}

# Plan, print the table, apply — one command, no pause. The table IS the
# review; asc still writes the artifact, but nothing waits on it. Pass
# --review as arg 3 to get the old two-step back: plan stops until
# `asc metadata approve` names this exact plan hash, for the locale or field
# where a wrong keyword actually costs something.
asc_push_metadata() {
  local version="$1" dir="$2" review="$ROOT_DIR/.asc/metadata/review" gated="" from=3
  [[ "${3:-}" == "--review" ]] && { gated=1; from=4; }
  [[ -d "$dir" ]] || die "no metadata at $dir"
  log "Planning metadata for $version"
  asc metadata plan --app "$ASC_APP_ID" --version "$version" --dir "$dir" --output table

  # Extra flags are sliced straight off "$@" rather than gathered into an
  # array: macOS ships bash 3.2, where "${arr[@]}" on an EMPTY array trips
  # `set -u` and apply never runs — the plan prints, the push silently does
  # nothing.
  if [[ -n "$gated" ]]; then
    if [[ "$(asc_review_ready "$review")" != yes ]]; then
      log "Nothing applied — this plan is not approved. Read the table above, then:"
      log "  asc metadata approve --review-dir ${review#"$ROOT_DIR"/} --all"
      log "  (re-run this command with --review to apply)"
      return 0
    fi
    log "Applying metadata for $version"
    asc metadata apply \
      --app "$ASC_APP_ID" \
      --version "$version" \
      --dir "$dir" \
      --review-dir "$review" \
      --confirm \
      "${@:$from}"
  else
    log "Applying metadata for $version"
    asc metadata apply \
      --app "$ASC_APP_ID" \
      --version "$version" \
      --dir "$dir" \
      "${@:$from}"
  fi
  log "App Store listing pushed for $version"
}

# --- the binary -------------------------------------------------------------
#
# Archive, export, upload and attach, in ONE asc call: local-build mode is given
# the project and does the xcodebuild half itself, resolving the build number
# against what Connect already holds. So the kit writes no chain here — what it
# supplies is the values, none of which is typed twice.
#
# Release, not CONFIGURATION: that row is what `appkit run` and `appkit capture`
# build,
# and an archive is Release by definition.
#
# Submission is the caller's separate flag. Attaching a build can be undone in
# the Connect UI; sending it for review cannot.
asc_ship_build() {
  local version="$1" project
  project="${PROJECT:-$(ios_project)}"
  log "Shipping $APP_NAME $version from $(basename "$project")"
  asc publish appstore \
    --app "$ASC_APP_ID" \
    --project "$project" \
    --scheme "$SCHEME" \
    --configuration Release \
    --version "$version" \
    --archive-path "$ROOT_DIR/.asc/artifacts/$APP_NAME.xcarchive" \
    --ipa-path "$ROOT_DIR/.asc/artifacts/$APP_NAME.ipa" \
    --wait \
    --output table \
    "${@:2}"
}
