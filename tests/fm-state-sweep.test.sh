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

# Wait up to <limit> 0.1s ticks for <pid> to exit; 0 if it exited, 1 if still alive.
wait_for_exit() {
  local pid=$1 limit=${2:-40} i=0
  while [ "$i" -lt "$limit" ]; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

reap() { kill "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; }

# fm-watch.sh's per-wake scan_signals must not surface a signal whose task has no
# .meta, or the orphan wakes firstmate on every poll until someone notices (10 days,
# in the real case). Drive a real watcher against a fixture that carries an orphaned
# .status AND .turn-ended (both captain-relevant-shaped) alongside one live task with
# a .meta, and assert only the live task's signal reaches the durable wake queue.
test_watcher_skips_orphaned_signals() {
  local home state out pid drain
  home="$TMP_ROOT/home-watch"
  state="$home/state"
  mkdir -p "$state"

  # Orphan: no .meta, so nothing will ever clear these markers.
  printf 'blocked: no perms\n' > "$state/orphan.status"
  : > "$state/orphan.turn-ended"
  # Live task: has a .meta, and a captain-relevant status the watcher MUST surface.
  printf 'window=fm-live\n' > "$state/live-task.meta"
  printf 'done: PR https://example.test/pr/7\n' > "$state/live-task.status"

  out="$home/watch.out"
  FM_STATE_OVERRIDE="$state" FM_POLL=1 FM_SIGNAL_GRACE=1 \
    FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$ROOT/bin/fm-watch.sh" > "$out" 2>&1 &
  pid=$!
  # The live task's captain-relevant signal surfaces and exits the watcher; the
  # orphan must never do so.
  wait_for_exit "$pid" 60 || { reap "$pid"; fail "watcher never surfaced the live task's signal: $(cat "$out")"; }

  drain=$(FM_STATE_OVERRIDE="$state" "$ROOT/bin/fm-wake-drain.sh" 2>/dev/null || true)
  assert_contains "$drain" "live-task.status" "watcher did not queue the live task's captain-relevant signal"
  assert_not_contains "$drain" "orphan.status" "watcher queued an orphaned (meta-less) .status signal"
  assert_not_contains "$drain" "orphan.turn-ended" "watcher queued an orphaned (meta-less) .turn-ended signal"

  pass "fm-watch.sh surfaces a live task's signal but never an orphan whose task has no .meta"
}

# Teardown owns removal on the happy path; the sweep only backstops crashes. Run a
# real fm-teardown.sh against a fixture seeded with the three bookkeeping files and
# assert they are gone afterward - a scout task with --force reaches the state-file
# cleanup without needing a live worktree or backend.
test_teardown_cleans_watcher_bookkeeping() {
  local home state out
  home="$TMP_ROOT/home-teardown"
  state="$home/state"
  mkdir -p "$state" "$home/data/gone-task"

  fm_write_meta "$state/gone-task.meta" \
    "window=fm-gone" \
    "worktree=$home/nonexistent-wt" \
    "project=$home/nonexistent-proj" \
    "harness=echo" \
    "kind=scout" \
    "backend=tmux"
  : > "$state/gone-task.status"
  : > "$state/gone-task.turn-ended"
  : > "$state/.seen-gone-task_status"
  : > "$state/.seen-gone-task_turn-ended"
  : > "$state/.hb-surfaced-gone-task"

  out=$(FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_STATE_OVERRIDE="$state" \
    FM_DATA_OVERRIDE="$home/data" FM_CONFIG_OVERRIDE="$home/config" \
    "$ROOT/bin/fm-teardown.sh" gone-task --force 2>&1) \
    || fail "fm-teardown.sh exited non-zero: $out"

  assert_absent "$state/.seen-gone-task_status" "teardown left .seen-<id>_status behind"
  assert_absent "$state/.seen-gone-task_turn-ended" "teardown left .seen-<id>_turn-ended behind"
  assert_absent "$state/.hb-surfaced-gone-task" "teardown left .hb-surfaced-<id> behind"
  # The task's own state files must also be gone (sanity that teardown really ran).
  assert_absent "$state/gone-task.meta" "teardown did not remove the task meta"

  pass "fm-teardown.sh removes the .seen-*/.hb-surfaced-* bookkeeping it creates"
}

test_sweep_removes_orphans_and_spares_live_tasks
test_sweep_is_idempotent_and_silent_when_clean
test_watcher_skips_orphaned_signals
test_teardown_cleans_watcher_bookkeeping
