# Compiling appkit's Swift tools, and the gate that decides whether a rendered
# card actually changed. Sourced after manifest.sh.

# Compile one of appkit's Swift tools, or hand back the binary from last time.
# `swift file.swift` compiles it again on every run, and the renderer draws
# dozens of three-megapixel cards.
#
# The binaries land in the APP repo's .build/bin: appkit itself is installed
# read-only under the brew prefix, and a per-repo cache also means an upgrade
# cannot hand a repo yesterday's renderer.
appkit_tool() {
  local name="$1" source="" candidate
  local binary="$ROOT_DIR/.build/bin/$name"
  # render/ holds the tools every platform's cards go through; platform/ holds
  # the ones only one platform needs — window-id is macOS's, and there is no
  # iOS or Android counterpart to put beside it.
  for candidate in "$APPKIT_DIR/render/$name.swift" "$APPKIT_DIR/platform/$name.swift"; do
    [[ -f "$candidate" ]] && {
      source="$candidate"
      break
    }
  done
  [[ -n "$source" ]] || die "no such appkit tool: $name"
  if [[ ! -x "$binary" || "$source" -nt "$binary" ]]; then
    mkdir -p "$(dirname "$binary")"
    swiftc -O -o "$binary" "$source" >&2 || die "could not compile $source"
  fi
  printf '%s' "$binary"
}

# The renderer rewrites every card, so put back the bytes git already has
# wherever the picture did not change — otherwise a set reports changes nobody
# can see and `git status` stops answering "did any screen change".
#
# Said out loud: a card held at the old bytes is a card that will not be
# uploaded. So a run that puts any back at all had a scene that would not hold
# still, and that is worth chasing rather than tolerating.
settle_unchanged() {
  local dir="${1:-$SHOTS_DIR}" tolerance="${2:-${DITHER:-3}}"
  local relative tmp pairs path restored=0
  relative="${dir#"$ROOT_DIR"/}"
  tmp="$(mktemp -d -t appkit-cards)"
  pairs="$tmp/pairs"
  : >"$pairs"
  while IFS= read -r path; do
    # A card that is new rather than changed has nothing at HEAD to go back to.
    git -C "$ROOT_DIR" show "HEAD:$path" >"$tmp/${path//\//_}" 2>/dev/null || continue
    printf '%s\t%s\n' "$tmp/${path//\//_}" "$path" >>"$pairs"
  done < <(git -C "$ROOT_DIR" diff --name-only HEAD -- "$relative")

  if [[ -s "$pairs" ]]; then
    while IFS= read -r path; do
      git -C "$ROOT_DIR" checkout HEAD -- "$path"
      restored=$((restored + 1))
    done < <(cd "$ROOT_DIR" && "$(appkit_tool same-picture)" --tolerance "$tolerance" <"$pairs")
  fi
  rm -rf "$tmp"

  ((restored == 0)) ||
    log "Put back $restored card(s) whose picture didn't change (±$tolerance)"
}
