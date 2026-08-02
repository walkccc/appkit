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
    # --confirm is asc's interactive guard on the deletes --replace does, and it
    # is answered here because the decision was already made upstream: --dry-run
    # returns from upload.sh before this function is ever reached.
    asc screenshots upload \
      --app "$ASC_APP_ID" \
      --version "$version" \
      --path "$dir" \
      --device-type "$device_type" \
      --replace --confirm
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

# A localization the stage does not mention is staged as it LIVES, so that it
# plans as unchanged.
#
# asc diffs the whole canonical tree at once, and an absent file is not read as
# "leave this one alone" — it is read as "this localization is missing
# locally", which plans a delete for it and makes apply refuse the entire
# change set with "--allow-deletes is required". A notes push stages no
# app-info half at all (see store/metadata.sh), so the DEFAULT upload could
# never apply anything: five deletes nobody asked for, standing in front of
# five release notes that never went up. The same hole swallows any locale
# Connect has and the manifest does not declare, on either scope.
#
# Copying the live values in closes it without teaching asc anything: each
# mirrored file diffs to nothing, which is what "unchanged" has to look like on
# the wire. Deleting a localization stays deliberately outside what an upload
# can do — that is a Connect UI errand, or a hand-written
# `asc metadata apply --allow-deletes`.
asc_mirror_untouched() {
  local version="$1" stage="$2" mirror="$ROOT_DIR/.asc/metadata-mirror"
  rm -rf "$mirror"
  # Discarded: pull narrates every file it wrote, and this tree is scaffolding
  # for the diff rather than an answer to anything the caller asked for.
  asc metadata pull --app "$ASC_APP_ID" --version "$version" --dir "$mirror" >/dev/null
  python3 - "$mirror" "$stage" <<'MIRROR'
import pathlib, shutil, sys

mirror, stage = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

copied = 0
for live in sorted(mirror.rglob("*.json")):
    staged = stage / live.relative_to(mirror)
    # Never over a staged file: that one is what the push is FOR.
    if staged.exists():
        continue
    staged.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(live, staged)
    copied += 1
if copied:
    print(f"  {copied} untouched localization(s) staged as they live")
MIRROR
  rm -rf "$mirror"
}

# Plan, print the table, apply — one command, no pause. The table IS the
# review; asc still writes the artifact, but nothing waits on it.
#
#   --review   the old two-step back: plan stops until `asc metadata approve`
#              names this exact plan hash, for the locale or field where a
#              wrong keyword actually costs something.
#   --dry-run  the plan and nothing else. Apply is never reached, so the table
#              above the stop is the whole of what a real run would send.
asc_push_metadata() {
  local version="$1" dir="$2" review="$ROOT_DIR/.asc/metadata/review" gated="" dry="" arg
  # Read off "$@" rather than taken by position: --review was arg 3, and the
  # second flag had nowhere to go. macOS ships bash 3.2, where "${arr[@]}" on
  # an EMPTY array trips `set -u`, so a caller with no flags to pass has to
  # reach here as no arguments at all — hence ${arr[@]+"${arr[@]}"} at the one
  # call site that builds a list.
  for arg in "${@:3}"; do
    case "$arg" in
      --review) gated=1 ;;
      --dry-run) dry=1 ;;
      *) die "asc_push_metadata: unknown flag $arg" ;;
    esac
  done
  [[ -d "$dir" ]] || die "no metadata at $dir"
  log "Planning metadata for $version"
  asc metadata plan --app "$ASC_APP_ID" --version "$version" --dir "$dir" --output table

  if [[ -n "$dry" ]]; then
    log "dry run — nothing applied. The table above is the whole change set."
    return 0
  fi

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
      --confirm
  else
    log "Applying metadata for $version"
    asc metadata apply \
      --app "$ASC_APP_ID" \
      --version "$version" \
      --dir "$dir"
  fi
  log "App Store listing pushed for $version"
}

# --- the binary -------------------------------------------------------------
#
# Archive, export, upload and attach, in ONE asc call: local-build mode is given
# the project and does the xcodebuild half itself, resolving the build number
# against what Connect already holds. So appkit writes no chain here — what it
# supplies is the values, none of which is typed twice.
#
# Release, not CONFIGURATION: that row is what `appkit run` and `appkit capture`
# build,
# and an archive is Release by definition.
#
# Submission is the caller's separate flag. Attaching a build can be undone in
# the Connect UI; sending it for review cannot.
#
# WHICH project and WHICH artifact is the platform's to say, through
# platform_publish_args. It used to be `$(ios_project)` inlined right here —
# the one iOS-shaped call left in a shared file, which on any other App Store
# platform is not a wrong answer but "ios_project: command not found".
asc_ship_build() {
  local version="$1" submit="" dry="" arg status=0
  for arg in "${@:2}"; do
    case "$arg" in
      --submit) submit=1 ;;
      --dry-run) dry=1 ;;
    esac
  done
  platform_publish_args
  log "Shipping $APP_NAME $version"
  asc publish appstore \
    --app "$ASC_APP_ID" \
    "${PUBLISH_ARGS[@]}" \
    --configuration Release \
    --version "$version" \
    --archive-path "$ROOT_DIR/.asc/artifacts/$APP_NAME.xcarchive" \
    --wait \
    --output table \
    "${@:2}" || status=$?

  # Nothing to second-guess without --submit: asc either shipped the binary or
  # did not. Its own code, not a `die`, because its error is already on screen.
  if [[ -z "$submit" ]]; then
    ((status == 0)) || exit "$status"
    return 0
  fi

  # With --submit, asc sends and then re-reads the submission to confirm it —
  # a read that loses to Connect's own lag and fails with "does not contain
  # target version" for a submission holding exactly that version, AFTER the
  # send went through. An exit code cannot tell that apart from a real failure.
  # The STATE can, and asc_send_for_review is already the thing that reads it,
  # so it gets the last word here instead of sitting unreachable behind
  # `set -e` — which is how a sent 1.4.1 came back as a failed run.
  ((status == 0)) ||
    warn "asc exited $status — asking Connect what it actually holds"
  asc_send_for_review "$version" "$dry"
}

# --- the send ---------------------------------------------------------------
#
# READY_FOR_REVIEW is the DRAFT state, and that naming is the whole trap: the
# submission exists and holds the version as its one item, and Connect shows it
# as a "Draft Submission" behind a "Submit for Review" button nobody has
# pressed. WAITING_FOR_REVIEW is the state that means it went.
#
# `asc publish appstore --submit --confirm` creates that submission, adds the
# item, and only then POSTs the send — and a run has ended between the two,
# exiting on a submission it had merely prepared. Nothing in the exit code says
# which half happened, so the STATE is the check: a draft found here is sent,
# not reported as shipped.
#
# It fails in the other direction too, and that one reads worse: asc's own
# post-send validation re-reads the submission's items, loses to Connect's lag,
# and exits non-zero with "does not contain target version" naming the version
# the submission does hold. The send went. The run says it did not.
#
# Both are the same lesson — the exit code is not the outcome — so both end
# here, and this function reports the outcome rather than the attempt.
#
# Re-running the whole ship is NOT the recovery. asc's next run finds the draft,
# calls the version already submitted and returns before it attaches anything —
# so the archive and the upload happen again, for a build that is then left
# hanging. `appkit ship --submit-only` is the cheap half, and lands here.

# The newest review submission as "<id> <state>" — two empty fields when the app
# has none.
asc_submission() {
  asc review status --app "$ASC_APP_ID" 2>/dev/null | python3 -c 'import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
s = d.get("latestSubmission") or {}
print(s.get("id", ""), s.get("state", ""))'
}

# Which app versions a submission actually holds — asked of the ITEMS rather
# than of the app's current version record, because those two disagree exactly
# when it matters: a draft left over from the last release sits under a version
# record that has already moved on, and this send cannot be taken back.
asc_submission_versions() {
  asc review items-list --submission "$1" \
    --include appStoreVersion --fields state,appStoreVersion --output json 2>/dev/null |
    python3 -c 'import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(" ".join(sorted({
    r.get("attributes", {}).get("versionString", "")
    for r in d.get("included") or []
    if r.get("type") == "appStoreVersions"
})))'
}

asc_send_for_review() {
  local want="$1" dry="${2:-}" id state holds
  read -r id state < <(asc_submission)
  [[ -n "$id" ]] ||
    die "no review submission for $want — attach a build first: appkit ship"
  # Before the state, not just before the send: "already sent" is a claim about
  # THIS version, and the newest submission is only evidence of it once it is
  # known to hold it. Read the other way round, a publish that died before it
  # attached anything would find last release's WAITING_FOR_REVIEW and report
  # the failed run as shipped.
  holds="$(asc_submission_versions "$id")"
  [[ "$holds" == "$want" ]] ||
    die "submission $id holds ${holds:-no app version}, not $want — resolve it in Connect"
  if [[ "$state" != READY_FOR_REVIEW ]]; then
    log "Already sent — submission $id is $state"
    return 0
  fi
  if [[ -n "$dry" ]]; then
    log "Would send submission $id ($want) for review"
    return 0
  fi
  log "Sending $want for review"
  asc review submissions-submit --id "$id" --confirm >/dev/null
  read -r id state < <(asc_submission)
  [[ "$state" != READY_FOR_REVIEW ]] ||
    die "submission $id is still a draft — Connect did not accept the send"
  log "$APP_NAME $want sent for review ($state)"
}
