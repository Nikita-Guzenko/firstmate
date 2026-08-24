#!/usr/bin/env bash
# Behavior tests for fm-state-sweep.sh and the orphan guards it backstops.
#
# The bug: a task that dies WITHOUT teardown leaves <id>.turn-ended behind, and
# fm-watch.sh's scan_signals globs it on every poll, so it wakes firstmate forever.
# One such marker sat in a live home from 2026-08-14 doing exactly that, and
# teardown separately leaked .seen-*/.hb-surfaced-* for every task ever run (1399
# files fleet-wide when first measured).
#
# What must hold, and what these cases pin:
#   - an orphan (no .meta) is swept
#   - a LIVE task's state is never touched, including its .seen-*/.hb-surfaced-*
#     bookkeeping (deleting that mid-flight replays old signals as fresh wakes)
#   - a task id containing '_' is parsed correctly (a naive split on '_' would
#     delete .seen-multi_word-id_status for a live task)
#   - the default run is a DRY RUN that removes nothing
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-state-sweep-tests)

# A home with one live task (has .meta), one dead task (no .meta), and a live
# task whose id contains an underscore.
make_state_fixture() {
  local home=$1 state
  state="$home/state"
  mkdir -p "$state"

  printf 'window=fm-live\n' > "$state/live-task.meta"
  : > "$state/live-task.status"
  : > "$state/live-task.turn-ended"
  : > "$state/.seen-live-task_status"
  : > "$state/.seen-live-task_turn-ended"
  : > "$state/.hb-surfaced-live-task"

  : > "$state/dead-task.status"
  : > "$state/dead-task.turn-ended"
  : > "$state/.seen-dead-task_status"
  : > "$state/.seen-dead-task_turn-ended"
  : > "$state/.hb-surfaced-dead-task"

  printf 'window=fm-multi\n' > "$state/multi_word-id-k3.meta"
  : > "$state/.seen-multi_word-id-k3_status"

  printf '%s\n' "$state"
}

test_sweep_removes_orphans_and_spares_live_tasks() {
  local home state out
  home="$TMP_ROOT/home-apply"
  state=$(make_state_fixture "$home")

  out=$("$ROOT/bin/fm-state-sweep.sh" --home "$home" 2>&1)
  printf '%s\n' "$out" | grep -q "would remove 5" \
    || fail "dry run should report exactly 5 orphans, got: $out"
  [ -f "$state/dead-task.status" ] \
    || fail "dry run must not delete anything"

  "$ROOT/bin/fm-state-sweep.sh" --home "$home" --apply >/dev/null 2>&1

  # The dead task is gone, bookkeeping included.
  for gone in dead-task.status dead-task.turn-ended \
              .seen-dead-task_status .seen-dead-task_turn-ended .hb-surfaced-dead-task; do
    [ -e "$state/$gone" ] && fail "orphan $gone survived the sweep"
  done

  # The live task is untouched - deleting its .seen-* would replay old signals.
  for kept in live-task.meta live-task.status live-task.turn-ended \
              .seen-live-task_status .seen-live-task_turn-ended .hb-surfaced-live-task; do
    [ -e "$state/$kept" ] || fail "live task file $kept was wrongly swept"
  done

  # An id containing '_' must not be mis-parsed into a different (absent) task.
  [ -e "$state/.seen-multi_word-id-k3_status" ] \
    || fail "underscore-containing task id was mis-parsed and swept"

  pass "fm-state-sweep removes orphaned state and never touches a live task"
}

test_sweep_is_idempotent_and_silent_when_clean() {
  local home out rc
  home="$TMP_ROOT/home-clean"
  mkdir -p "$home/state"
  printf 'window=fm-only\n' > "$home/state/only-task.meta"
  : > "$home/state/only-task.status"
  : > "$home/state/.seen-only-task_status"

  out=$("$ROOT/bin/fm-state-sweep.sh" --home "$home" 2>&1); rc=$?
  [ "$rc" = 0 ] || fail "clean home should exit 0, got $rc"
  [ -z "$out" ] || fail "clean home should print nothing, got: $out"

  pass "fm-state-sweep is silent and exits 0 when there is nothing to remove"
}

# fm-watch.sh must not surface a signal whose task has no .meta, or the orphan
# wakes firstmate on every poll until someone notices (10 days, in the real case).
# shellcheck disable=SC2016  # matching literal shell source text; must not expand
test_watcher_skips_orphaned_signals() {
  grep -q 'id=\$(basename "\$f"); id=\${id%%\.\*}' "$ROOT/bin/fm-watch.sh" \
    || fail "fm-watch.sh scan_signals no longer derives the task id from the signal file"
  grep -q '\[ -f "\$STATE/\$id.meta" \] || continue' "$ROOT/bin/fm-watch.sh" \
    || fail "fm-watch.sh scan_signals no longer skips signals whose task has no .meta"
  pass "fm-watch.sh ignores signal files whose task has no .meta"
}

# Teardown owns removal on the happy path; the sweep only backstops crashes.
# shellcheck disable=SC2016  # matching literal shell source text; must not expand
test_teardown_cleans_watcher_bookkeeping() {
  grep -q '\.seen-\${ID}_status' "$ROOT/bin/fm-teardown.sh" \
    || fail "fm-teardown.sh no longer removes .seen-<id>_status"
  grep -q '\.seen-\${ID}_turn-ended' "$ROOT/bin/fm-teardown.sh" \
    || fail "fm-teardown.sh no longer removes .seen-<id>_turn-ended"
  grep -q '\.hb-surfaced-\$ID' "$ROOT/bin/fm-teardown.sh" \
    || fail "fm-teardown.sh no longer removes .hb-surfaced-<id>"
  pass "fm-teardown.sh removes the watcher bookkeeping it creates"
}

test_sweep_removes_orphans_and_spares_live_tasks
test_sweep_is_idempotent_and_silent_when_clean
test_watcher_skips_orphaned_signals
test_teardown_cleans_watcher_bookkeeping
