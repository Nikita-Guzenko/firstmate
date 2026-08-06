#!/usr/bin/env bash
# tests/fm-done-requires-pr.test.sh - behavior tests for the rule that a `done:`
# line is not a completion without the PR that proves delivery.
#
# Seven sessions ended with a crew appending `done:` for work that had no PR:
# hero-studio-restore, ci-merge-group-trigger and a third on 2026-07-31, then
# call-sales-script, tg-pricelist-capture and call-sales-script again on
# 2026-08-06. Each time firstmate read the line, closed the task, and reported it
# to the captain; the costliest left branch fm/call-sales-prepayment unpushed, so
# the change existed only in the worker's worktree. bin/fm-brief.sh already
# stated the correct order in prose before all of them, which is why the fix is a
# machine test rather than more wording.
#
# The seventh case is the one to keep in mind while reading these tests: the crew
# that wrote this file did it too, hours after implementing the refusal, on its
# own unpushed commit. Knowing the rule does not stop the word `done` from
# attaching to whatever you just finished, so the check has to be mechanical.
#
# These cases drive the real classifier and the real drain script:
#   (a) the predicate itself, over every delivery mode and every near-miss claim
#   (b) scan_captain_relevant_statuses still SURFACES an unbacked done: but can
#       no longer render it as a clean completion
#   (c) bin/fm-wake-drain.sh prints a REJECTED DONE section on every drain,
#       including the empty-queue path, and stays silent for legitimate done:
#
# The crew-current-state half of the contract (an unbacked done: must never
# become `state: done`) lives with the rest of that reader's cases in
# tests/fm-crew-state.test.sh, where its git/pane/run fixtures already exist.
set -u

# shellcheck source=tests/wake-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/wake-helpers.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-classify-lib.sh"

DRAIN="$ROOT/bin/fm-wake-drain.sh"
TMP_ROOT=$(fm_test_tmproot fm-done-requires-pr)

PR_URL='https://github.com/nguzen/aln/pull/117'
MR_URL='https://gitlab.com/g/p/-/merge_requests/9'

# A state dir with one task's status log and (optionally) its recorded mode.
make_task() {  # <case> <id> <mode-or-empty> <status-line>
  local state="$TMP_ROOT/$1/state"
  mkdir -p "$state"
  printf '%s\n' "$4" > "$state/$2.status"
  [ -z "$3" ] || fm_write_meta "$state/$2.meta" \
    "window=fm:fm-$2" "worktree=$TMP_ROOT/$1/wt" "kind=ship" "mode=$3"
  printf '%s\n' "$state"
}

# (a) the predicate --------------------------------------------------------

test_predicate_rejects_unbacked_done_in_pr_modes() {
  local mode
  for mode in no-mistakes direct-PR; do
    status_done_is_unbacked 'done: implemented and committed' "$mode" \
      || fail "mode=$mode: a done: with no PR link was accepted as a completion"
    status_done_is_unbacked 'done: PR #123 opened, checks green' "$mode" \
      || fail "mode=$mode: a bare PR number was accepted as proof of delivery"
    status_done_is_unbacked 'done: ready in branch fm/x, PR to follow' "$mode" \
      || fail "mode=$mode: a branch name was accepted as proof of delivery"
  done
  pass "an unbacked done: is rejected in every PR-delivering mode"
}

test_predicate_accepts_a_real_pr_url() {
  status_done_is_unbacked "done: PR $PR_URL checks green" no-mistakes \
    && fail "a done: carrying its GitHub PR URL was wrongly rejected"
  status_done_is_unbacked "done: PR $MR_URL" direct-PR \
    && fail "a done: carrying its GitLab merge-request URL was wrongly rejected"
  pass "a done: carrying a full PR/MR URL passes"
}

test_predicate_leaves_non_pr_modes_alone() {
  status_done_is_unbacked 'done: ready in branch fm/feat' local-only \
    && fail "local-only, which has no PR by design, was constrained by the PR rule"
  status_done_is_unbacked 'done: the counter was never re-initialised' '' \
    && fail "a task with no recorded delivery mode (scout, charter) was constrained"
  status_done_is_unbacked 'done: routed work reconciled' secondmate \
    && fail "an unrecognized mode was constrained instead of left alone"
  pass "local-only, scout, and unrecognized modes keep their done:"
}

test_predicate_touches_no_other_verb() {
  local mode line
  for mode in no-mistakes direct-PR; do
    for line in 'paused: waiting on the upstream release' \
                'blocked: no credentials for the forge' \
                'needs-decision: REST or RPC' \
                'working: still implementing' \
                'failed: could not reproduce'; do
      status_done_is_unbacked "$line" "$mode" \
        && fail "mode=$mode: the PR rule wrongly fired on '$line'"
    done
  done
  pass "paused, blocked, needs-decision, working, and failed are untouched"
}

test_delivery_mode_is_read_from_meta() {
  local state
  state=$(make_task mode-read t1 no-mistakes 'done: committed')
  [ "$(task_delivery_mode "$state" t1)" = no-mistakes ] \
    || fail "the recorded mode= was not read from state/<id>.meta"
  [ -z "$(task_delivery_mode "$state" absent)" ] \
    || fail "a task with no meta must resolve to no delivery mode"
  pass "the delivery mode comes from the task's recorded metadata"
}

# (b) the captain-relevant surface -----------------------------------------

test_unbacked_done_still_surfaces_but_carries_the_refusal() {
  local state out
  state=$(make_task surface t2 no-mistakes 'done: implemented and committed')
  out=$(scan_captain_relevant_statuses "$state")
  assert_contains "$out" "t2" "an unbacked done: must still surface to the supervisor"
  assert_contains "$out" "DONE REJECTED" "the rendered line must carry the refusal marker"
  assert_contains "$out" "not a completion" "the rendered line must carry the reason"
  # Deterministic rendering keeps consumer dedup signatures stable.
  [ "$out" = "$(scan_captain_relevant_statuses "$state")" ] \
    || fail "the rendered line is not deterministic across scans"
  pass "an unbacked done: surfaces with its refusal instead of as a clean completion"
}

test_legitimate_done_lines_render_unchanged() {
  local state out
  state=$(make_task surface-ok t3 no-mistakes "done: PR $PR_URL checks green")
  out=$(scan_captain_relevant_statuses "$state")
  assert_not_contains "$out" "DONE REJECTED" "a backed done: must render unchanged"
  state=$(make_task surface-local t4 local-only 'done: ready in branch fm/t4')
  out=$(scan_captain_relevant_statuses "$state")
  assert_not_contains "$out" "DONE REJECTED" "a local-only done: must render unchanged"
  pass "backed and local-only done: lines render exactly as before"
}

# (c) the drain surface ----------------------------------------------------

test_drain_reports_a_rejected_done_on_an_empty_queue() {
  local dir state out
  dir=$(make_case drain-rejected)
  state="$dir/state"
  out="$dir/drain.out"
  printf 'done: implemented the fix and committed\n' > "$state/call-sales.status"
  fm_write_meta "$state/call-sales.meta" "window=fm:fm-call-sales" \
    "worktree=$dir/wt" "kind=ship" "mode=no-mistakes"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed on a rejected done"

  grep -F 'REJECTED DONE' "$out" >/dev/null \
    || fail "an unbacked done: produced no REJECTED DONE section: $(cat "$out")"
  grep -F 'call-sales' "$out" >/dev/null || fail "the rejected task was not named"
  grep -F 'do not close these tasks' "$out" >/dev/null \
    || fail "the section did not tell the supervisor not to close the task"
  grep -F 'bin/fm-send.sh fm-call-sales' "$out" >/dev/null \
    || fail "the section carried no ready-to-send steer, so the crew learns nothing"
  pass "an unbacked done: is re-surfaced on every drain with its steer"
}

test_drain_is_silent_for_legitimate_done_lines() {
  local dir state out
  dir=$(make_case drain-clean)
  state="$dir/state"
  out="$dir/drain.out"
  printf 'done: PR %s checks green\n' "$PR_URL" > "$state/shipped.status"
  fm_write_meta "$state/shipped.meta" "window=fm:fm-shipped" \
    "worktree=$dir/wt" "kind=ship" "mode=no-mistakes"
  printf 'done: ready in branch fm/local\n' > "$state/local.status"
  fm_write_meta "$state/local.meta" "window=fm:fm-local" \
    "worktree=$dir/wt" "kind=ship" "mode=local-only"
  printf 'done: the counter was never re-initialised\n' > "$state/scout.status"
  fm_write_meta "$state/scout.meta" "window=fm:fm-scout" "worktree=$dir/wt" "kind=scout"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed with no rejected done"

  if grep -F 'REJECTED DONE' "$out" >/dev/null; then
    fail "a backed, local-only, or scout done: was wrongly rejected: $(cat "$out")"
  fi
  pass "the drain stays silent for backed, local-only, and scout completions"
}

test_drain_keeps_rejecting_until_the_pr_exists() {
  local dir state out
  dir=$(make_case drain-persists)
  state="$dir/state"
  out="$dir/drain.out"
  printf 'done: implemented and committed\n' > "$state/tg-pricelist.status"
  fm_write_meta "$state/tg-pricelist.meta" "window=fm:fm-tg-pricelist" \
    "worktree=$dir/wt" "kind=ship" "mode=no-mistakes"

  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "first drain failed"
  grep -F 'REJECTED DONE' "$out" >/dev/null || fail "first drain did not reject"
  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "second drain failed"
  grep -F 'REJECTED DONE' "$out" >/dev/null \
    || fail "the rejection was seen once and then forgotten"

  printf 'done: PR %s checks green\n' "$PR_URL" >> "$state/tg-pricelist.status"
  FM_STATE_OVERRIDE="$state" "$DRAIN" > "$out" || fail "drain failed after the PR landed"
  if grep -F 'REJECTED DONE' "$out" >/dev/null; then
    fail "the rejection persisted after the crew reported its PR: $(cat "$out")"
  fi
  pass "the rejection persists until the crew reports its PR, then clears"
}

test_predicate_rejects_unbacked_done_in_pr_modes
test_predicate_accepts_a_real_pr_url
test_predicate_leaves_non_pr_modes_alone
test_predicate_touches_no_other_verb
test_delivery_mode_is_read_from_meta
test_unbacked_done_still_surfaces_but_carries_the_refusal
test_legitimate_done_lines_render_unchanged
test_drain_reports_a_rejected_done_on_an_empty_queue
test_drain_is_silent_for_legitimate_done_lines
test_drain_keeps_rejecting_until_the_pr_exists

echo "all fm-done-requires-pr tests passed"
