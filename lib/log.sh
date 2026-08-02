# Progress reporting shared by every kit command. Sourced, never executed.

TTY=false
if [[ -t 1 ]]; then TTY=true; fi

clear_line() { if [[ "$TTY" == true ]]; then printf '\r\033[K'; fi; }
log() { clear_line; printf '==> %s\n' "$*"; }
warn() { clear_line; printf '==> %s\n' "$*" >&2; }
die() {
  clear_line
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Run a command, swallowing its output unless it fails. simctl narrates every
# screenshot on stderr ("Note: No display specified…", "Wrote screenshot to…"),
# and adb is no quieter — which buries a 45-launch run in noise the progress
# line already covers.
quiet() {
  local output
  if ! output="$("$@" 2>&1)"; then
    clear_line
    printf '%s\n' "$output" >&2
    return 1
  fi
}

# `==>   zh-Hant  4/7`, rewritten as each scene lands. On a non-tty only the
# final count prints, so a log file gets one line per pass instead of hundreds.
progress() {
  local label="$1" finished="$2" total="$3"
  if [[ "$TTY" == true ]]; then
    printf '\r==>   %-9s %2d/%d' "$label" "$finished" "$total"
    if ((finished == total)); then printf '\n'; fi
  elif ((finished == total)); then
    printf '==>   %-9s %d/%d\n' "$label" "$finished" "$total"
  fi
}

# Snap until two consecutive frames are byte-identical, and keep that pair.
#
# The app never says it has settled, so the shutter asks the screen. Two
# identical frames is a sound signal because both capture paths are
# deterministic: a screen nobody is animating renders the same bytes every
# frame. A fixed sleep can only guess.
#
# Nonzero when it never held still. The frame is kept anyway — a shot that will
# not reproduce is worth looking at — but the caller says so.
STILL_GAP="${STILL_GAP:-0.6}"
STILL_TRIES="${STILL_TRIES:-10}"

snap_when_still() {
  local output="$1" device="$2" previous="$1.settling" attempt
  mkdir -p "$(dirname "$output")"
  platform_screenshot "$device" "$output"
  for ((attempt = 1; attempt <= STILL_TRIES; attempt++)); do
    mv -f "$output" "$previous"
    sleep "$STILL_GAP"
    platform_screenshot "$device" "$output"
    if cmp -s "$previous" "$output"; then
      rm -f "$previous"
      return 0
    fi
  done
  rm -f "$previous"
  return 1
}

# Said by capture_scene when a shot would not hold still, and read back at the
# end of the run — a warning thirty launches ago has scrolled off, and this is
# the one thing that decides whether the set reproduces.
note_unsettled() {
  [[ -n "${UNSETTLED_LOG:-}" ]] || return 0
  printf '%s\n' "$*" >>"$UNSETTLED_LOG"
}
