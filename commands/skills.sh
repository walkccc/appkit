#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Link appkit's skills into ~/.claude/skills, once per machine.
#
#   appkit skills          link them; safe to re-run
#
# These are the ONLY thing appkit links rather than copies, and the reason is
# the opposite of the reason everything else is copied: a skill is the same
# instruction in every repo, it is read by an agent on this laptop and by
# nobody else, and a copy per repo means three repos go dirty every time a
# sentence in it changes.
#
# The link points at brew's `opt` path, not at the Cellar directory this script
# resolved to — `opt/appkit` is the symlink brew moves on an upgrade, so
# `brew upgrade appkit` is the whole of an update and there is nothing to
# re-run. A checkout outside brew links to itself, which is what you want while
# editing them.
# ============================================================================

APPKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/log.sh
. "$APPKIT_DIR/lib/log.sh"

usage() { appkit_usage "$0"; }

while (($#)); do
  case "$1" in
    help | -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

# A checkout links to itself; only the brew-installed copy redirects to `opt`.
# The test is whether THIS program is the installed one — asking brew where
# appkit lives says nothing about which appkit is running, and answering it the
# other way round links a checkout's skills to whatever brew last installed.
source_root="$APPKIT_DIR/skills"
if prefix="$(brew --prefix appkit 2>/dev/null)" && [[ -d "$prefix/libexec/skills" ]]; then
  installed="$(cd "$prefix" && pwd -P)"
  [[ "$APPKIT_DIR" == "$installed"* ]] && source_root="$prefix/libexec/skills"
fi

mkdir -p "$DEST"

linked=0
for dir in "$source_root"/*/; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  link="$DEST/$name"
  target="${dir%/}"

  if [[ -L "$link" ]]; then
    [[ "$(readlink "$link")" == "$target" ]] && continue
    rm -f "$link"
  elif [[ -e "$link" ]]; then
    # A real directory here is either a hand-made skill of the same name or the
    # copy an older appkit left behind. Both are the user's to move, not this
    # script's to delete.
    die "$link is a directory, not a link — move it aside, then re-run"
  fi

  ln -s "$target" "$link"
  log "  $name -> $target"
  linked=$((linked + 1))
done

if ((linked)); then
  log "appkit skills: $linked linked, in $DEST"
  log "  they follow $source_root — nothing to re-run when it changes"
else
  log "appkit skills: already linked, in $DEST"
fi
