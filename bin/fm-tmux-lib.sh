#!/usr/bin/env bash
# fm-tmux-lib.sh — shared tmux pane primitives for firstmate.
#
# ONE source of truth for: busy detection, composer-empty (pending-input)
# detection, and a verify-and-retry-Enter submit. Sourced by both the away-mode
# daemon (bin/fm-supervise-daemon.sh) and bin/fm-send.sh so the composer/submit
# logic cannot drift between the two.
#
# Why this exists (incident afk-invx-i5): the daemon's old composer check only
# recognized a BARE prompt glyph ("> ") as an empty composer. claude draws its
# input box with box-drawing borders ("│ > … │"), so every idle claude pane read
# as "pending input" and the away-mode daemon deferred 100% of escalations for
# 9.5 hours with no escape. The detector below strips the box borders before
# deciding, so a bordered-but-empty composer is correctly seen as empty. The same
# corrected detector backs the submit acknowledgement (a submit "landed" iff the
# composer is empty afterward), fixing the parallel false "Enter swallowed".
#
# Ghost text (incident composer-robust): claude renders a predicted-next-prompt
# "suggestion" as dim/faint text inside an otherwise-empty composer. A plain
# capture cannot tell it apart from text a human typed, so the old reader saw an
# idle pane as holding pending input and the daemon deferred injection / firstmate
# misjudged the pane. The composer reader now captures just the cursor line WITH
# ANSI styling (tmux capture-pane -e), drops dim/faint (SGR 2) runs, and decides on
# what is left, so ghost/placeholder text never counts as real input. The styled
# capture is consumed internally and parsed into a boolean here; it is NEVER
# surfaced (fm-peek and every human/LLM-facing path stay plain), and only the
# single composer row is captured, so no escape-laden pane bulk is produced. This
# is harness-generic: any harness that dims placeholder/ghost text benefits.
#
# Per-harness override: FM_COMPOSER_IDLE_RE matches an empty composer after
# dim-ghost and structural border stripping. FM_BUSY_REGEX overrides the busy
# footer set (mirrors fm-watch.sh / the daemon).
#
# All functions are `set -u` and `set -e` safe (guarded tmux calls, explicit
# returns) so they can be sourced into either context.

# Busy footers per harness (mirror fm-watch.sh). codex: "esc to interrupt";
# opencode: "esc interrupt"; pi: "Working..."; grok: "Ctrl+c:cancel" (grok's
# mid-turn cancel hint, shown iff a turn is running - verified grok 0.2.73).
# claude 2.1.224 dropped its "esc to interrupt" footer: a running turn now shows
# only a spinner line, a random gerund plus a U+2026 ellipsis (verified live:
# "✽ Sprouting…", "✻ Cogitating…"). The completed state is past tense with no
# ellipsis ("Cogitated for 4s"). Every claude spinner word is a gerund, so the
# "ing…" tail is the precise still-working signal; matching a bare letter before
# "…" also tripped on ordinary transcript text ending in an ellipsis. `grep -iE`
# folds case, so no [A-Z] anchor helps.
FM_TMUX_BUSY_REGEX_DEFAULT='esc (to )?interrupt|Working\.\.\.|Ctrl\+c:cancel|[A-Za-z]ing…'

# fm_tmux_strip_ghost: remove dim/faint (ANSI SGR 2) styled runs from one captured
# composer line, then drop any remaining escape sequences, leaving only the plain,
# normal-intensity text, the text a human actually typed. Dim/faint runs are
# ghost/placeholder text (e.g. claude's predicted-next-prompt suggestion) that
# fills an otherwise-empty composer and must never read as pending input. Reads the
# styled line on stdin (from `tmux capture-pane -e`) and prints plain text on
# stdout. LC_ALL=C makes awk walk bytes, so multibyte glyphs (e.g. ❯) and dim runs
# alike pass through or drop intact without locale-dependent character classes.
# A reset (SGR 0) or normal-intensity (SGR 22) ends a dim run; codes are processed
# left to right within a sequence so "ESC[0;2m" (reset then dim) reads as dim.
fm_tmux_strip_ghost() {
  LC_ALL=C awk '
    function sgr_code(v, b) {
      b = v
      sub(/:.*/, "", b)
      if (b == "") b = "0"
      return b
    }
    function skip_color_payload(a, p, k, mode, code) {
      if (index(a[p], ":") > 0) return p
      if (p >= k) return p
      mode = a[p + 1]
      code = sgr_code(mode)
      if (index(mode, ":") > 0) return p + 1
      if (code == "5") return p + 2
      if (code == "2") return p + 4
      return p + 1
    }
    {
      line = $0; out = ""; dim = 0; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\033") {            # ESC: consume a CSI ... final-byte sequence
          j = i + 1
          if (substr(line, j, 1) == "[") {
            j++; params = ""
            while (j <= n) {
              cc = substr(line, j, 1)
              if (cc ~ /[@-~]/) break
              params = params cc; j++
            }
            if (j <= n && substr(line, j, 1) == "m") {   # SGR: update dim/faint state
              if (params == "") params = "0"
              k = split(params, a, ";")
              for (p = 1; p <= k; p++) {
                v = a[p]; code = sgr_code(v)
                if (code == "38" || code == "48" || code == "58") {
                  p = skip_color_payload(a, p, k)
                } else if (code == "2") dim = 1
                else if (code == "0" || code == "22") dim = 0
              }
            }
            if (j <= n) { i = j + 1; continue }
          }
          i = i + 1; continue          # lone/other ESC: drop the ESC byte only
        }
        if (dim == 0) out = out c        # keep only normal-intensity bytes
        i++
      }
      print out
    }
  '
}

# fm_tmux_composer_state: classify the cursor/composer line of <target> as
#   empty   - no pending input (blank, a bare prompt, a busy footer, or only dim
#             ghost/placeholder text). Safe to inject; also the positive
#             acknowledgement that a submit landed.
#   pending - real, unsubmitted text on the cursor line (a human mid-typing, or a
#             previous injection whose Enter was swallowed). Defer / retry.
#   unknown - the pane could not be read (tmux error). The caller decides.
#
# The cursor line is captured WITH ANSI styling (capture-pane -e) and bounded to
# the single composer row (-S/-E), then run through fm_tmux_strip_ghost so dim/faint
# ghost text drops out before classification. The styled capture is internal only,
# never surfaced. The detector then strips the harness's box-drawing composer
# borders ("│ … │", heavy "┃", or a plain ASCII "|") using literal-string
# substitution (bash 3.2 safe, locale-independent — no \u escapes, no multibyte
# character classes), and asks whether anything real is left.
fm_tmux_composer_state() {  # <target> -> empty|pending|unknown
  local target=$1 cy raw line stripped
  cy=$(tmux display-message -p -t "$target" '#{cursor_y}' 2>/dev/null) || { printf 'unknown'; return 0; }
  case "$cy" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  raw=$(tmux capture-pane -e -p -t "$target" -S "$cy" -E "$cy" 2>/dev/null) || { printf 'unknown'; return 0; }
  line=$(printf '%s\n' "$raw" | fm_tmux_strip_ghost)
  # Strip the composer box borders (literal glyphs — no character classes).
  stripped=${line//│/}      # U+2502 light vertical (claude)
  stripped=${stripped//┃/}  # U+2503 heavy vertical
  stripped=${stripped//|/}  # ASCII pipe
  # Drop U+00A0 non-breaking space. claude 2.1.224 pads its empty composer as
  # "❯ " (a NBSP after the prompt glyph, verified live), and [:space:] does
  # NOT include U+00A0, so without this the bare-prompt check below misses and
  # every idle claude composer reads as pending — re-triggering incident
  # afk-invx-i5 (the daemon deferring all escalations) at the byte level. The
  # literal two bytes 0xC2 0xA0 keep this bash 3.2 safe (no \u escape).
  stripped=${stripped//$'\xc2\xa0'/}
  # Trim surrounding whitespace.
  stripped="${stripped#"${stripped%%[![:space:]]*}"}"
  stripped="${stripped%"${stripped##*[![:space:]]}"}"
  # Nothing left inside the box = empty composer.
  [ -n "$stripped" ] || { printf 'empty'; return 0; }
  if [ -n "${FM_COMPOSER_IDLE_RE:-}" ] \
     && printf '%s' "$stripped" | grep -qiE "$FM_COMPOSER_IDLE_RE"; then
    printf 'empty'; return 0
  fi
  # Just a bare prompt glyph = empty composer (idle).
  case "$stripped" in
    '>'|'❯'|'$'|'%'|'#') printf 'empty'; return 0 ;;
  esac
  # A busy footer landing on the cursor line is not pending input.
  if printf '%s' "$stripped" | grep -qiE "${FM_BUSY_REGEX:-$FM_TMUX_BUSY_REGEX_DEFAULT}"; then
    printf 'empty'; return 0
  fi
  printf 'pending'; return 0
}

# fm_pane_input_pending: 0 (pending) if the cursor line holds real unsubmitted
# text, 1 otherwise. An unreadable pane is treated as NOT pending (fail-safe:
# the same bias the old daemon used — an unknown pane defers nothing here).
fm_pane_input_pending() {  # <target>
  [ "$(fm_tmux_composer_state "$1")" = pending ]
}

# fm_pane_is_busy: 0 if the pane's last few non-blank lines show a busy footer
# (an agent mid-turn). Scans a 40-line tail like fm-watch.sh.
fm_pane_is_busy() {  # <target>
  local win=$1 tail40
  tail40=$(tmux capture-pane -p -t "$win" -S -40 2>/dev/null) || return 1
  printf '%s' "$tail40" | grep -v '^[[:space:]]*$' | tail -6 \
    | grep -qiE "${FM_BUSY_REGEX:-$FM_TMUX_BUSY_REGEX_DEFAULT}"
}

# fm_tmux_composer_has_paste: 0 if <target>'s composer currently holds a collapsed
# bracketed paste. claude catches a large/multiline burst (as `send-keys -l` of a
# long steer delivers) with its paste heuristic and collapses it to a
# "[Pasted text #N +M lines]" pill with a "paste again to expand" footer hint, and
# DEBOUNCES its submission: the Enter that would submit it is swallowed for a window
# that is both long and variable (~1-5s, verified live claude 2.1.224), so an
# inline paste cannot be submitted reliably at all. The capture is anchored to the
# composer region (the cursor row downward) so a stale "[Pasted text #N]" pill still
# visible up in the transcript cannot be mistaken for the live composer's contents.
# An unreadable pane is treated as no-paste (return 1).
fm_tmux_composer_has_paste() {  # <target>
  local cy tail
  cy=$(tmux display-message -p -t "$1" '#{cursor_y}' 2>/dev/null) || return 1
  case "$cy" in ''|*[!0-9]*) return 1 ;; esac
  [ "$cy" -gt 0 ] && cy=$((cy - 1))
  tail=$(tmux capture-pane -p -t "$1" -S "$cy" 2>/dev/null) || return 1
  printf '%s' "$tail" | grep -qiE '\[Pasted text #[0-9]|paste again to expand'
}

# fm_tmux_clear_composer: discard whatever is in <target>'s composer (Ctrl-U), used
# to abandon a collapsed paste we refuse to submit so it cannot ride into a later
# turn. Verified live: Ctrl-U clears the pill AND the "paste again to expand" footer.
fm_tmux_clear_composer() {  # <target>
  tmux send-keys -t "$1" C-u 2>/dev/null || true
}

# fm_tmux_submit_core: type <text> into <target> ONCE, then submit with Enter,
# verifying the submit landed. Retries Enter ONLY — never retypes, because a
# swallowed Enter leaves our text in the composer and retyping would duplicate
# it. Echoes the final verdict on stdout (empty|pending|unknown|send-failed|too-large)
# so callers can pick their own success policy:
#   - the daemon clears its buffer only on "empty" (strict: an unknown pane must
#     not be mistaken for a delivered escalation).
#   - fm-send fails on "pending" (a positively-confirmed swallow) and on "too-large".
#
# too-large: the burst collapsed into a bracketed paste, whose submission debounces
# unpredictably and cannot be driven reliably (incident fm-send-longmsg-loss). Rather
# than race it — which silently loses the message or falsely reports success — the
# collapsed block is DISCARDED and "too-large" returned so the caller routes the
# content through a file plus a short pointer instead. fm-send also refuses oversized
# text before it ever types (its own size guard); this is the shared-core backstop
# for anything that collapses below that guard.
#
# Two submit acknowledgements, both reported as "empty" so no consumer learns a new
# success token:
#   1. the composer cleared (the original tmux ACK), or
#   2. the pane went BUSY after Enter (a turn started). A running turn is proof the
#      text was accepted — submitted, or queued into a mid-turn pane — regardless of
#      the cursor line, and closes a claude 2.1.224 race where a just-submitted turn
#      has not yet cleared the composer. Checking busy first, and stopping the instant
#      it goes busy, also prevents a trailing Enter from submitting a second turn.
fm_tmux_submit_enter_core() {  # <target> <retries> <enter-sleep>
  local target=$1 retries=$2 sleep_s=$3 i=0 state
  while :; do
    tmux send-keys -t "$target" Enter 2>/dev/null || true
    sleep "$sleep_s"
    if fm_pane_is_busy "$target"; then printf 'empty'; return 0; fi
    state=$(fm_tmux_composer_state "$target")
    [ "$state" = pending ] || { printf '%s' "$state"; return 0; }
    i=$((i + 1))
    [ "$i" -lt "$retries" ] || { printf 'pending'; return 0; }
  done
}

fm_tmux_submit_core() {  # <target> <text> <retries> <enter-sleep> <settle>
  local target=$1 text=$2 retries=$3 sleep_s=$4 settle=$5
  tmux send-keys -t "$target" -l "$text" 2>/dev/null || { printf 'send-failed'; return 0; }
  sleep "$settle"
  # If the burst collapsed into a bracketed paste, it cannot be submitted reliably;
  # discard it and report too-large rather than race the debounce and lose it.
  if fm_tmux_composer_has_paste "$target"; then
    fm_tmux_clear_composer "$target"
    printf 'too-large'; return 0
  fi
  fm_tmux_submit_enter_core "$target" "$retries" "$sleep_s"
}
