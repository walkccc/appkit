# Photographing the languages side by side, a device each. This is the one
# capture capability the kit owns outright; what a scene IS stays with the repo.
#
# Language i always lands on device i % JOBS, so a set is comparable with the
# last one taken the same way. No queue — the passes take the same time.
#
# A platform with one device (Android) sets JOBS to 1 in platform_workers
# and the same code runs serially, which is why there is no second harness.

# One language pass, and under several jobs one process of several. Calls the
# repo's capture_scene, the only part of a shot the kit does not decide.
capture_shard() {
  local slot="$1" device="$2" language scene taken index=0
  for language in "${LANGUAGES[@]}"; do
    if ((index % JOBS != slot)); then
      index=$((index + 1))
      continue
    fi
    index=$((index + 1))
    # Start a full pass from a fresh folder: an interrupted run leaves last
    # time's PNGs here and nothing downstream can tell them apart. A --scene run
    # is topping up a set rather than replacing one, so it leaves the rest alone.
    #
    # A repo that compares each capture against the previous run's needs the old
    # set kept rather than deleted, so it may define rotate_language instead.
    if [[ "$whole_set" == true ]]; then
      if declare -F rotate_language >/dev/null; then
        rotate_language "$language"
      else
        rm -rf "${OUT_DIR:?}/$language"
      fi
    fi
    taken=0
    for scene in "${SCENES[@]}"; do
      capture_scene "$scene" "$language" "$OUT_DIR/$language/$scene.png" "$device"
      taken=$((taken + 1))
      printf '.' >>"$TALLY"
      ((JOBS == 1)) && progress "$language" "$taken" "${#SCENES[@]}"
    done
    ((JOBS > 1)) && log "  $language ${#SCENES[@]}/${#SCENES[@]}"
  done
  # The caller reads this as the shard's verdict, so it must not be whatever the
  # last `((…))` evaluated to.
  return 0
}

# Side by side there is no one language to count, so the line counts scenes: the
# size of $TALLY is how far along the run is.
watch_shards() {
  local total=$((${#SCENES[@]} * ${#LANGUAGES[@]})) finished alive pid
  while :; do
    alive=false
    for pid in "$@"; do
      if kill -0 "$pid" 2>/dev/null; then alive=true; fi
    done
    finished="$(stat -f%z "$TALLY" 2>/dev/null || echo 0)"
    ((finished >= total)) || progress "capturing" "$finished" "$total"
    [[ "$alive" == true ]] || break
    sleep 0.5
  done
  progress "capturing" "$total" "$total"
}

# Where a language was photographed, so a re-shoot lands on the same device.
device_for() {
  local language="$1" index=0 candidate
  for candidate in "${LANGUAGES[@]}"; do
    if [[ "$candidate" == "$language" ]]; then
      printf '%s' "${DEVICES[$((index % JOBS))]}"
      return 0
    fi
    index=$((index + 1))
  done
}

# Boot every shard device at once and install the app on each.
prepare_all() {
  local device prepared=() pid
  if ((${#DEVICES[@]} == 1)); then
    platform_prepare "${DEVICES[0]}"
    return
  fi
  for device in "${DEVICES[@]}"; do
    platform_prepare "$device" &
    prepared+=($!)
  done
  for pid in "${prepared[@]}"; do
    wait "$pid" || die "a capture device would not come up"
  done
}

# Run every shard and wait. Nonzero if any pass failed.
run_shards() {
  local slot shards=() pid failed=false
  if ((JOBS == 1)); then
    capture_shard 0 "${DEVICES[0]}" || failed=true
    [[ "$failed" == false ]]
    return
  fi
  for ((slot = 0; slot < JOBS; slot++)); do
    capture_shard "$slot" "${DEVICES[$slot]}" &
    shards+=($!)
  done
  watch_shards "${shards[@]}"
  for pid in "${shards[@]}"; do
    wait "$pid" || failed=true
  done
  [[ "$failed" == false ]]
}
