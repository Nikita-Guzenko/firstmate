#!/usr/bin/env bash
# Behavior tests for /stow's inspect-then-update memory contract.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

test_stow_skill_task_note_contract() {
  local stow="$ROOT/.agents/skills/stow/SKILL.md"

  assert_grep 'tasks-axi show <id> --full' "$stow" "stow skill does not require inspecting task notes first"
  assert_grep 'tasks-axi update <id> --body-file <path>' "$stow" "stow skill does not require task body replacement"
  assert_grep '--archive-body' "$stow" "stow skill does not document recoverable task body archival"
  assert_grep 'Never append.' "$stow" "stow skill does not forbid append-first task notes"
  assert_no_grep 'carry that context into the replacement body' "$stow" "stow skill still preserves archive-only context in the replacement body"
  pass "stow skill task-note contract includes recoverable body archival"
}

test_task_lifecycle_backlog_note_contract() {
  local lifecycle="$ROOT/.agents/skills/task-lifecycle/SKILL.md"

  assert_grep 'tasks-axi show <id> --full' "$lifecycle" "task-lifecycle does not require inspecting task notes first"
  assert_grep 'tasks-axi update <id> --body-file <path>' "$lifecycle" "task-lifecycle does not require task body replacement"
  assert_grep '--archive-body' "$lifecycle" "task-lifecycle does not document recoverable task body archival"
  assert_no_grep 'carry that context into the replacement body' "$lifecycle" "task-lifecycle still preserves archive-only context in the replacement body"
  pass "task-lifecycle task-note contract includes recoverable body archival"
}

test_stow_skill_task_note_contract
test_task_lifecycle_backlog_note_contract
