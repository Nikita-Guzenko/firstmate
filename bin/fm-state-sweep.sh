#!/usr/bin/env bash
# Remove orphaned runtime state left by tasks that died without teardown.
# Usage: fm-state-sweep.sh [--apply] [--home DIR]
#          Default is a DRY RUN that prints what it would remove and exits 0.
#          --apply actually removes. --home limits the sweep to one home
#          (default: every ~/firstmate-* home with a state/ dir).
#
# Two kinds of residue accumulate, both invisible until they cause a symptom:
#
#   1. ORPHANED SIGNALS - a <id>.status or <id>.turn-ended whose <id>.meta is gone.
#      bin/fm-teardown.sh removes these correctly, so they only appear when a task
#      dies WITHOUT teardown (killed session, crashed harness). Nothing then ever
#      clears the marker, and fm-watch.sh's scan_signals globs it on every poll, so
#      it wakes firstmate forever. One such file sat in firstmate-invoicesnap from
#      2026-08-14 doing exactly that; fm-watch.sh now skips meta-less signals, and
#      this sweep is what actually removes them.
#
#   2. LEAKED WATCHER BOOKKEEPING - .seen-<id>_status, .seen-<id>_turn-ended, and
#      .hb-surfaced-<id>. Teardown did not remove these before 2026-08-24, so every
#      task ever run left permanent residue; 756 files had accumulated in one home.
#      Teardown now cleans them going forward - this sweep clears the backlog.
#
# Never touches a file whose task still has a .meta: an in-flight task's
# bookkeeping is load-bearing, and deleting .seen-* mid-flight would replay old
# signals as new wakes.
#
# Exit: 0 nothing to do (or dry run), 1 removed something (with --apply), 2 could not look.
set -uo pipefail

APPLY=0
ONE_HOME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --home)  ONE_HOME=${2:-}; shift 2 ;;
    *) echo "usage: fm-state-sweep.sh [--apply] [--home DIR]" >&2; exit 64 ;;
  esac
done

if [ -n "$ONE_HOME" ]; then
  HOMES="$ONE_HOME"
else
  HOMES=$(ls -d "$HOME"/firstmate-* 2>/dev/null)
fi
[ -n "$HOMES" ] || { echo "fm-state-sweep: no firstmate homes found" >&2; exit 2; }

TOTAL=0
CHECKED=0

for home in $HOMES; do
  state="$home/state"
  [ -d "$state" ] || continue
  CHECKED=$((CHECKED + 1))
  victims=""

  # 1. Signal files with no surviving .meta.
  for f in "$state"/*.status "$state"/*.turn-ended "$state"/*.check.sh; do
    [ -e "$f" ] || continue
    b=$(basename "$f"); id=${b%%.*}
    [ -f "$state/$id.meta" ] && continue
    victims="$victims $f"
  done

  # 2. Watcher bookkeeping whose task is gone. The signal-file name is embedded
  #    with dots mapped to underscores (.seen-<id>_status), so strip the known
  #    suffix rather than splitting on '_' - task ids themselves contain dashes,
  #    and a wrong split would spare real orphans or delete live ones.
  for f in "$state"/.seen-* "$state"/.hb-surfaced-*; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    case "$b" in
      .seen-*_status)     id=${b#.seen-}; id=${id%_status} ;;
      .seen-*_turn-ended) id=${b#.seen-}; id=${id%_turn-ended} ;;
      .hb-surfaced-*)     id=${b#.hb-surfaced-} ;;
      *) continue ;;
    esac
    [ -n "$id" ] || continue
    [ -f "$state/$id.meta" ] && continue
    victims="$victims $f"
  done

  # shellcheck disable=SC2086  # deliberate word-splitting: victims is a space-joined list
  set -- $victims
  n=$#
  [ "$n" -gt 0 ] || continue
  TOTAL=$((TOTAL + n))

  if [ "$APPLY" = 1 ]; then
    rm -f "$@"
    echo "$(basename "$home"): removed $n orphaned state file(s)"
  else
    echo "$(basename "$home"): would remove $n orphaned state file(s)"
    for v in "$@"; do echo "    $(basename "$v")"; done
  fi
done

[ "$CHECKED" -gt 0 ] || { echo "fm-state-sweep: no readable state dirs" >&2; exit 2; }
[ "$TOTAL" -gt 0 ] || exit 0
[ "$APPLY" = 1 ] || { echo "dry run - re-run with --apply to remove"; exit 0; }
exit 1
