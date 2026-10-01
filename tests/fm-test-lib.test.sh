#!/usr/bin/env bash
# Behavior tests for the shared test helper lifecycle.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

test_command_substitution_temp_root_is_cleaned() {
  local created_root
  created_root=$(FM_TEST_LIB="$ROOT/tests/lib.sh" bash -c '
    set -u
    . "$FM_TEST_LIB"
    root=$(fm_test_tmproot fm-test-lib-probe)
    touch "$root/evidence"
    printf "%s\n" "$root"
  ')

  [ ! -e "$created_root" ] \
    || fail "fm_test_tmproot leaked a command-substitution temp root after process exit: $created_root"
  pass "fm_test_tmproot cleans command-substitution temp roots on process exit"
}

test_command_substitution_temp_root_is_cleaned

echo "# all fm-test-lib tests passed"
