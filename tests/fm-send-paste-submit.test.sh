#!/usr/bin/env bash
# Long-steer / paste-collapse handling (incident fm-send-longmsg-loss) plus the
# claude 2.1.224 composer + busy rendering the fix depends on.
#
# A large or multiline steer delivered with `tmux send-keys -l` is caught by the
# harness's paste heuristic and collapsed into a "[Pasted text #N +M lines]" pill
# with a "paste again to expand" footer. That block's submission DEBOUNCES for a
# long, variable window (verified live, claude 2.1.224), so it cannot be submitted
# reliably: the old code raced it and silently lost the message while reporting a
# false "Enter swallowed".
#
# The fix never races a paste. It is pinned here hermetically (stateful fake tmux,
# no real agent):
#   1. fm-send refuses an oversized message BEFORE typing (size guard).
#   2. The shared submit core discards any burst that collapses anyway and reports
#      "too-large" (backstop) instead of pressing Enter into the debounce.
#   3. A submit is confirmed by the composer clearing OR the pane going busy; a
#      genuine swallow still reports "pending".
#   4. claude 2.1.224's NBSP-padded empty composer reads empty (not pending), and
#      its ellipsis spinner reads busy (its "esc to interrupt" footer is gone).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LIB="$ROOT/bin/fm-tmux-lib.sh"
SEND="$ROOT/bin/fm-send.sh"

# shellcheck source=bin/fm-tmux-lib.sh
. "$LIB"

TMP_ROOT=$(fm_test_tmproot fm-send-paste)

# A stateful fake tmux. It distinguishes the two read shapes the submit core uses:
#   - composer single-row read (carries -E): returns FM_FAKE_COMPOSER verbatim, so
#     fm_tmux_composer_state classifies it (a bare prompt = empty; anything else =
#     pending).
#   - tail read (has -S, no -E): serves fm_pane_is_busy and fm_tmux_composer_has_paste
#     off one capture. It includes FM_FAKE_PASTE_LINE (when set) so a paste is
#     "present", and a busy footer once the recorded Enter count reaches
#     FM_FAKE_BUSY_AFTER, modelling the turn starting.
# Every Enter bumps FM_FAKE_ENTERS; a Ctrl-U touches FM_FAKE_CU (clear marker).
# has-session / list-windows exit 0 so fm-send target resolution succeeds.
make_fake_tmux() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  send-keys)
    for a in "$@"; do
      if [ "$a" = "Enter" ]; then
        c=$(cat "$FM_FAKE_ENTERS" 2>/dev/null || echo 0)
        printf '%s\n' "$((c + 1))" > "$FM_FAKE_ENTERS"
      fi
      [ "$a" = "C-u" ] && [ -n "${FM_FAKE_CU:-}" ] && printf 'cu\n' >> "$FM_FAKE_CU"
    done
    exit 0 ;;
  display-message)
    for a in "$@"; do case "$a" in *cursor_y*) printf '%s\n' "${FM_FAKE_CY:-36}"; exit 0 ;; esac; done
    printf 'fakepane\n'; exit 0 ;;
  capture-pane)
    has_E=0
    for a in "$@"; do [ "$a" = "-E" ] && has_E=1; done
    if [ "$has_E" = 1 ]; then
      printf '%s\n' "${FM_FAKE_COMPOSER:-> }"
      exit 0
    fi
    [ -n "${FM_FAKE_PASTE_LINE:-}" ] && printf '%s\n' "$FM_FAKE_PASTE_LINE"
    c=$(cat "$FM_FAKE_ENTERS" 2>/dev/null || echo 0)
    if [ "$c" -ge "${FM_FAKE_BUSY_AFTER:-99999}" ]; then
      printf 'esc to interrupt\n'
    else
      printf 'idle output line\n'
    fi
    exit 0 ;;
  has-session|list-windows) exit 0 ;;
esac
exit 1
SH
  chmod +x "$fb/tmux"
  printf '%s\n' "$fb"
}

# --- fm_tmux_composer_has_paste ---------------------------------------------

test_has_paste_detects_placeholder_and_footer() {
  local dir fb enters
  dir="$TMP_ROOT/has-paste"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir"); enters="$dir/enters"; : > "$enters"
  if ! PATH="$fb:$PATH" FM_FAKE_ENTERS="$enters" \
       FM_FAKE_PASTE_LINE='❯ [Pasted text #1 +15 lines]' \
       fm_tmux_composer_has_paste "fakepane"; then
    fail "has_paste did not detect a '[Pasted text #N]' pill"
  fi
  if ! PATH="$fb:$PATH" FM_FAKE_ENTERS="$enters" \
       FM_FAKE_PASTE_LINE='paste again to expand' \
       fm_tmux_composer_has_paste "fakepane"; then
    fail "has_paste did not detect the 'paste again to expand' footer hint"
  fi
  if PATH="$fb:$PATH" FM_FAKE_ENTERS="$enters" \
       fm_tmux_composer_has_paste "fakepane"; then
    fail "has_paste falsely reported a paste for ordinary pane content"
  fi
  pass "fm_tmux_composer_has_paste: detects pill and footer, false otherwise"
}

# --- submit core: discard a collapsed paste, confirm/pending otherwise -------

test_submit_core_discards_collapsed_paste() {
  local dir fb verdict cu
  dir="$TMP_ROOT/collapse"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir")
  cu="$dir/cu"; : > "$cu"
  # Typing collapsed the burst (paste pill present). The core must NOT press Enter
  # into the debounce: it discards (Ctrl-U) and reports too-large.
  verdict=$(PATH="$fb:$PATH" FM_FAKE_ENTERS="$dir/e" FM_FAKE_CU="$cu" \
            FM_FAKE_PASTE_LINE='❯ [Pasted text #1 +15 lines]' \
            FM_FAKE_COMPOSER='❯ ' \
            fm_tmux_submit_core fakepane "some long pasted text" 3 0.02 0.02)
  [ "$verdict" = too-large ] || fail "a collapsed paste must report too-large, got '$verdict'"
  [ -s "$cu" ] || fail "a collapsed paste must be discarded with Ctrl-U (none was sent)"
  [ ! -s "$dir/e" ] || fail "a collapsed paste must NOT be submitted (an Enter was sent)"
  pass "submit core: a collapsed paste is discarded and reported too-large, never submitted"
}

test_submit_core_normal_submits() {
  local dir fb verdict
  dir="$TMP_ROOT/core-normal"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir")
  # No paste: types, then Enter, composer clears -> empty.
  verdict=$(PATH="$fb:$PATH" FM_FAKE_ENTERS="$dir/e" \
            FM_FAKE_COMPOSER='❯ ' FM_FAKE_BUSY_AFTER=99999 \
            fm_tmux_submit_core fakepane "short steer" 3 0.02 0.02)
  [ "$verdict" = empty ] || fail "a normal short submit should report empty, got '$verdict'"
  pass "submit core: a normal short message submits and reports empty"
}

# run_enter_core <dir> <retries> -> echoes the verdict; enters count in <dir>/enters.
run_enter_core() {
  local dir=$1 retries=$2
  local fb enters
  fb=$(make_fake_tmux "$dir"); enters="$dir/enters"; : > "$enters"
  PATH="$fb:$PATH" FM_FAKE_ENTERS="$enters" \
    fm_tmux_submit_enter_core fakepane "$retries" 0.02
}

test_busy_transition_confirms_submit() {
  local dir verdict enters
  dir="$TMP_ROOT/busy-ack"; mkdir -p "$dir"
  # Composer never visibly clears (always pending), but the pane goes busy on the
  # 2nd Enter (a turn started = submit landed / queued into a busy pane).
  verdict=$(FM_FAKE_COMPOSER='❯ still here' FM_FAKE_BUSY_AFTER=2 \
            run_enter_core "$dir" 3)
  [ "$verdict" = empty ] || fail "a busy transition must confirm the submit, got '$verdict'"
  enters=$(cat "$dir/enters")
  [ "$enters" = 2 ] || fail "should stop on busy at the 2nd Enter, got $enters"
  pass "submit core: a started turn (busy) confirms the submit and stops further Enters"
}

test_genuine_swallow_reports_pending() {
  local dir verdict
  dir="$TMP_ROOT/stuck"; mkdir -p "$dir"
  # Composer always pending, pane never busy: a real swallow must surface as pending.
  verdict=$(FM_FAKE_COMPOSER='❯ still typing this out' FM_FAKE_BUSY_AFTER=99999 \
            run_enter_core "$dir" 3)
  [ "$verdict" = pending ] || fail "a genuinely stuck composer should report pending, got '$verdict'"
  pass "submit core: a genuine swallow (never busy, always pending) reports pending"
}

# --- claude 2.1.224 composer/busy rendering ---------------------------------

test_nbsp_idle_composer_reads_empty() {
  local dir fb state
  dir="$TMP_ROOT/nbsp"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir")
  # Empty composer is the prompt glyph plus a U+00A0 non-breaking space -> empty,
  # not pending (the byte-level form of incident afk-invx-i5).
  state=$(PATH="$fb:$PATH" FM_FAKE_ENTERS="$dir/e" \
          FM_FAKE_COMPOSER="$(printf '\xe2\x9d\xaf\xc2\xa0')" \
          fm_tmux_composer_state "fakepane")
  [ "$state" = empty ] || fail "a NBSP-padded empty composer must read empty, got '$state'"
  state=$(PATH="$fb:$PATH" FM_FAKE_ENTERS="$dir/e" \
          FM_FAKE_COMPOSER="$(printf '\xe2\x9d\xaf\xc2\xa0fix finding 3')" \
          fm_tmux_composer_state "fakepane")
  [ "$state" = pending ] || fail "real text after a NBSP must stay pending, got '$state'"
  pass "composer_state: a NBSP-padded empty composer reads empty; real text stays pending"
}

test_claude_spinner_reads_busy() {
  local dir fb
  dir="$TMP_ROOT/spinner"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir")
  # The running spinner ("✽ Sprouting…") reads busy though it has no "esc to
  # interrupt"; the completed state ("Cogitated for 4s", no ellipsis) does not.
  if ! PATH="$fb:$PATH" FM_FAKE_ENTERS="$dir/e" FM_FAKE_PASTE_LINE='✽ Sprouting…' \
       fm_pane_is_busy "fakepane"; then
    fail "the claude 2.1.224 spinner '✽ Sprouting…' was not detected as busy"
  fi
  if PATH="$fb:$PATH" FM_FAKE_ENTERS="$dir/e" FM_FAKE_PASTE_LINE='✻ Cogitated for 4s' \
       fm_pane_is_busy "fakepane"; then
    fail "the completed state 'Cogitated for 4s' falsely read as busy"
  fi
  pass "fm_pane_is_busy: the claude 2.1.224 spinner reads busy, the done state does not"
}

# --- fm-send size guard (refuses before typing) -----------------------------

# run_send <fakebin> <home> <message> -> runs fm-send.sh against sess:win; echoes
# nothing, returns its exit code. Guard errors go to a captured stderr file.
run_send() {
  local fb=$1 home=$2 msg=$3
  env PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_SEND_SETTLE=0 \
    "$SEND" "sess:win" "$msg" 2>"$home/err"
}

test_send_refuses_oversized_message() {
  local dir fb home rc
  dir="$TMP_ROOT/guard-chars"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir"); home="$dir/home"; mkdir -p "$home/state"
  local big; big=$(printf 'x%.0s' $(seq 1 700))   # 700 > default 600
  run_send "$fb" "$home" "$big"; rc=$?
  [ "$rc" != 0 ] || fail "fm-send should refuse a 700-char inline message"
  assert_grep "too long to deliver inline" "$home/err" "the refusal must name the size limit"
  # No Enter was ever sent (refused before typing).
  [ ! -s "$dir/enters" ] || fail "an oversized message must be refused before any Enter"
  pass "fm-send: refuses an oversized inline message before typing, with a file-pointer directive"
}

test_send_refuses_too_many_lines() {
  local dir fb home rc msg
  dir="$TMP_ROOT/guard-lines"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir"); home="$dir/home"; mkdir -p "$home/state"
  msg=$(printf 'l%d\n' $(seq 1 10))   # 10 lines > default 8
  run_send "$fb" "$home" "$msg"; rc=$?
  [ "$rc" != 0 ] || fail "fm-send should refuse a 10-line inline message"
  assert_grep "10 lines" "$home/err" "the refusal must report the line count"
  pass "fm-send: refuses a many-line inline message (line guard)"
}

test_send_allows_short_message() {
  local dir fb home rc
  dir="$TMP_ROOT/guard-ok"; mkdir -p "$dir"
  fb=$(make_fake_tmux "$dir"); home="$dir/home"; mkdir -p "$home/state"
  # A normal short steer passes the guard and submits (composer clears -> empty).
  run_send "$fb" "$home" "fix findings 1 and 3, skip 2"; rc=$?
  [ "$rc" = 0 ] || fail "fm-send should deliver a short steer (exit $rc): $(cat "$home/err")"
  pass "fm-send: a short single-line steer passes the guard and delivers"
}

test_has_paste_detects_placeholder_and_footer
test_submit_core_discards_collapsed_paste
test_submit_core_normal_submits
test_busy_transition_confirms_submit
test_genuine_swallow_reports_pending
test_nbsp_idle_composer_reads_empty
test_claude_spinner_reads_busy
test_send_refuses_oversized_message
test_send_refuses_too_many_lines
test_send_allows_short_message
