# Google Play, through the Play Developer API. Sourced after manifest.sh.
#
# Auth is a Google Cloud service-account key. The JWT is signed with openssl, so
# there is nothing to install — the key is JSON and the exchange is one POST.
#
# Everything goes through an EDIT, Play's own transaction: insert, change,
# commit. A run that dies halfway leaves the listing untouched.

PLAY_API="https://androidpublisher.googleapis.com/androidpublisher/v3"
PLAY_UPLOAD="https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
PLAY_TOKEN=""

play_require() {
  local key="$ROOT_DIR/$PLAY_KEY"
  : "${ANDROID_PACKAGE:?appkit.json must set android.package}"
  [[ -f "$key" ]] || die "no Play service-account key at $PLAY_KEY
  Create one in Google Cloud, invite it to the Play Console with release and
  store-presence permissions, and save the JSON there (it is gitignored)."
  command -v openssl >/dev/null || die "openssl not found"
  PLAY_KEY_FILE="$key"
}

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# A service-account assertion, exchanged for an hour's access token.
play_token() {
  [[ -z "$PLAY_TOKEN" ]] || {
    printf '%s' "$PLAY_TOKEN"
    return
  }
  local email pem now claims header signature assertion response
  email="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["client_email"])' "$PLAY_KEY_FILE")"
  pem="$(mktemp -t kit-play-key)"
  chmod 600 "$pem"
  python3 -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1]))["private_key"])' \
    "$PLAY_KEY_FILE" >"$pem"
  now="$(date +%s)"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | base64url)"
  claims="$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/androidpublisher","aud":"https://oauth2.googleapis.com/token","exp":%d,"iat":%d}' \
    "$email" "$((now + 3600))" "$now" | base64url)"
  signature="$(printf '%s.%s' "$header" "$claims" |
    openssl dgst -sha256 -sign "$pem" -binary | base64url)"
  rm -f "$pem"
  assertion="$header.$claims.$signature"

  response="$(curl -sS -X POST https://oauth2.googleapis.com/token \
    -d grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer \
    --data-urlencode "assertion=$assertion")"
  PLAY_TOKEN="$(python3 -c '
import json, sys
answer = json.load(sys.stdin)
if "access_token" not in answer:
    sys.exit(f"Play refused the service account: {answer}")
print(answer["access_token"])
' <<<"$response")" || die "$PLAY_TOKEN"
  printf '%s' "$PLAY_TOKEN"
}

play_api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -X "$method" -H "Authorization: Bearer $(play_token)" \
    -H "Content-Type: application/json" "$PLAY_API/applications/$ANDROID_PACKAGE$path" "$@"
}

# Play's transaction. Every change below is made inside one, and nothing is
# visible until it commits.
play_edit_begin() {
  PLAY_EDIT="$(play_api POST "/edits" | python3 -c '
import json, sys
answer = json.load(sys.stdin)
if "id" not in answer:
    sys.exit(f"could not open an edit: {answer}")
print(answer["id"])
')" || die "$PLAY_EDIT"
  log "Play edit $PLAY_EDIT"
}

play_edit_commit() {
  local answer
  answer="$(play_api POST "/edits/$PLAY_EDIT:commit")"
  python3 -c '
import json, sys
answer = json.load(sys.stdin)
if "id" not in answer:
    sys.exit(f"commit failed: {answer}")
' <<<"$answer" || die "the Play edit did not commit"
  log "Committed"
}

play_edit_abort() {
  [[ -z "${PLAY_EDIT:-}" ]] || play_api DELETE "/edits/$PLAY_EDIT" >/dev/null 2>&1 || true
  PLAY_EDIT=""
}

# The listing text for one locale. Play takes title, short and full description
# in one PUT; "what's new" hangs off a release and is pushed with it.
play_push_listing() {
  local locale="$1" file="$2"
  play_api PUT "/edits/$PLAY_EDIT/listings/$locale" --data-binary @"$file" |
    python3 -c '
import json, sys
answer = json.load(sys.stdin)
if "error" in answer:
    sys.exit(answer["error"].get("message", str(answer)))
' || die "Play refused the $locale listing"
  log "  $locale"
}

# Imagery is replaced wholesale per type, which is the behaviour to be careful
# about: deleting first and uploading nothing leaves the listing with none. So
# the files are counted before anything is deleted, and a type with no files is
# left alone rather than emptied.
play_push_images() {
  local locale="$1" kind="$2" dir="$3" file count=0
  local files=()
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$dir" -maxdepth 1 -name '*.png' | sort
  )
  ((${#files[@]})) || return 0
  play_api DELETE "/edits/$PLAY_EDIT/listings/$locale/$kind" >/dev/null
  for file in "${files[@]}"; do
    curl -sS -X POST -H "Authorization: Bearer $(play_token)" \
      -H "Content-Type: image/png" --data-binary @"$file" \
      "$PLAY_UPLOAD/applications/$ANDROID_PACKAGE/edits/$PLAY_EDIT/listings/$locale/$kind?uploadType=media" \
      >/dev/null || die "could not upload $file"
    count=$((count + 1))
    progress "$locale/$kind" "$count" "${#files[@]}"
  done
}

# The binary. Uploaded into the same edit, then assigned to a track with its
# release notes — which is the one place "what's new" belongs.
play_upload_bundle() {
  local aab="$1" answer
  [[ -f "$aab" ]] || die "no bundle at $aab"
  log "Uploading $(basename "$aab")"
  answer="$(curl -sS -X POST -H "Authorization: Bearer $(play_token)" \
    -H "Content-Type: application/octet-stream" --data-binary @"$aab" \
    "$PLAY_UPLOAD/applications/$ANDROID_PACKAGE/edits/$PLAY_EDIT/bundles?uploadType=media")"
  PLAY_VERSION_CODE="$(python3 -c '
import json, sys
answer = json.load(sys.stdin)
if "versionCode" not in answer:
    sys.exit(f"upload failed: {answer}")
print(answer["versionCode"])
' <<<"$answer")" || die "$PLAY_VERSION_CODE"
  log "  version code $PLAY_VERSION_CODE"
}

play_assign_track() {
  local track="$1" status="$2" notes="$3" body
  body="$(python3 - "$PLAY_VERSION_CODE" "$status" "$notes" <<'PY'
import json, pathlib, sys

code, status, notes = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
release = {"versionCodes": [code], "status": status}
if notes.exists():
    written = json.loads(notes.read_text())
    if written:
        release["releaseNotes"] = written
print(json.dumps({"releases": [release]}))
PY
  )"
  play_api PUT "/edits/$PLAY_EDIT/tracks/$track" --data-binary "$body" |
    python3 -c '
import json, sys
answer = json.load(sys.stdin)
if "error" in answer:
    sys.exit(answer["error"].get("message", str(answer)))
' || die "could not assign the track"
  log "Track $track ← $PLAY_VERSION_CODE ($status)"
}
