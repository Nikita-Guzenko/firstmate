#!/usr/bin/env bash
# Unit tests for bin/fm-spawn.sh's spawn_path_is_project_worktree - the positive
# worktree-identity check added after the 2026-08-25 foreign-cwd race incident:
# the pane-cwd poll captured a FOREIGN firstmate home (the tmux session's initial
# cwd, itself a git repo) as the task worktree, and the negative-only validation
# ("is a git toplevel and differs from the primary") let the spawn proceed.
# Identity is positive: shared git common dir (treehouse/git-worktree pools), or
# an identical origin URL (independent-clone backends). Anything else is refused.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-worktree-identity)

# Extract the function under test verbatim from the script so the test never
# drifts from the shipped implementation.
eval "$(sed -n '/^spawn_path_is_project_worktree() {/,/^}/p' "$SPAWN")"
type spawn_path_is_project_worktree >/dev/null 2>&1 \
  || fail "could not extract spawn_path_is_project_worktree from $SPAWN"

fm_git_identity

# Layout: an origin, a project clone, a linked worktree of the clone, an
# independent second clone of the same origin, and a foreign unrelated repo.
ORIGIN="$TMP_ROOT/origin.git"
PROJ="$TMP_ROOT/project"
LINKED="$TMP_ROOT/linked-wt"
SECOND="$TMP_ROOT/second-clone"
FOREIGN="$TMP_ROOT/foreign-home"

git init -q --bare "$ORIGIN"
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
seed=$(mktemp -d "$TMP_ROOT/seed.XXXXXX")
git -C "$seed" init -q -b main
git -C "$seed" commit -q --allow-empty -m seed
git -C "$seed" remote add origin "$ORIGIN"
git -C "$seed" push -q origin main

git clone -q "$ORIGIN" "$PROJ"
git -C "$PROJ" worktree add -q --detach "$LINKED" >/dev/null
git clone -q "$ORIGIN" "$SECOND"
git -C "$FOREIGN" init -q -b main 2>/dev/null || { mkdir -p "$FOREIGN" && git -C "$FOREIGN" init -q -b main; }
git -C "$FOREIGN" commit -q --allow-empty -m foreign

# PROJ_COMMON_DIR/PROJ_ORIGIN_URL are consumed by the eval-extracted
# spawn_path_is_project_worktree as globals; shellcheck cannot see through the
# sed/eval extraction above, hence the disables.
# shellcheck disable=SC2034
PROJ_COMMON_DIR=$(git -C "$PROJ" rev-parse --path-format=absolute --git-common-dir)
# shellcheck disable=SC2034
PROJ_ORIGIN_URL=$(git -C "$PROJ" remote get-url origin)

test_linked_worktree_shares_common_dir_accepts() {
  spawn_path_is_project_worktree "$LINKED" \
    || fail "linked worktree of the project clone must be accepted (shared common dir)"
  pass "linked git worktree of the project clone is accepted via shared common dir"
}

test_independent_clone_same_origin_accepts() {
  spawn_path_is_project_worktree "$SECOND" \
    || fail "independent clone of the same origin must be accepted (origin URL match)"
  pass "independent clone of the same origin is accepted via origin URL"
}

test_foreign_repo_rejects() {
  if spawn_path_is_project_worktree "$FOREIGN"; then
    fail "foreign unrelated repo must be rejected (this is the 2026-08-25 incident shape)"
  fi
  pass "foreign repo with different common dir and no matching origin is rejected"
}

test_non_repo_path_rejects() {
  local plain="$TMP_ROOT/plain-dir"
  mkdir -p "$plain"
  if spawn_path_is_project_worktree "$plain"; then
    fail "non-repo path must be rejected"
  fi
  pass "non-repo path is rejected"
}

test_linked_worktree_shares_common_dir_accepts
test_independent_clone_same_origin_accepts
test_foreign_repo_rejects
test_non_repo_path_rejects
