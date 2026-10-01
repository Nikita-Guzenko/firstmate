#!/usr/bin/env bash
# Behavior contract for the read-only /whytask skill.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

test_whytask_skill_contract() {
  local skill="$ROOT/.agents/skills/whytask/SKILL.md"

  assert_grep 'name: whytask' "$skill" "whytask skill name is missing"
  assert_grep 'user-invocable: true' "$skill" "whytask is not user-invocable"
  assert_grep 'tasks-axi show <id> --full' "$skill" "whytask does not inspect the durable task record"
  assert_grep 'tasks-axi list --state in_flight' "$skill" "whytask does not resolve the sole in-flight task"
  assert_grep 'Purpose' "$skill" "whytask does not answer task purpose"
  assert_grep 'Value of success' "$skill" "whytask does not answer completion value"
  assert_grep 'Success criteria' "$skill" "whytask does not define observable success"
  assert_grep '`/whytask` is strictly read-only.' "$skill" "whytask does not preserve its read-only boundary"
  assert_grep 'never changes task state' "$skill" "whytask permits task-state mutation"
  pass "whytask skill selects one task and explains purpose, value, and success read-only"
}

test_whytask_trigger_and_catalog() {
  assert_grep 'On `/whytask [<id>]`, load the `whytask` skill' "$ROOT/AGENTS.md" \
    "AGENTS.md does not declare the whytask load trigger"
  assert_grep '| `/whytask [id]`' "$ROOT/README.md" \
    "README does not catalog the whytask command"
  pass "whytask is discoverable from the runtime trigger and built-in skill catalog"
}

test_whytask_skill_contract
test_whytask_trigger_and_catalog
