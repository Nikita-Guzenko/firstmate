#!/usr/bin/env bash
# Ensure a project worktree follows the agent-instruction file convention.
# AGENTS.md is the real project-wide working-rules file; CLAUDE.md is a
# relative symlink to it for compatibility. Creates a minimal AGENTS.md skeleton
# when neither file exists, promotes a real CLAUDE.md file when it is the only
# file present, and refuses to clobber distinct real files or wrong symlinks.
# Owns the canonical "## Maintaining this file" self-governance wording for
# project AGENTS.md files, appending it to created skeletons and promoted
# CLAUDE.md files that lack it, and migrating the exact legacy canonical block.
# This is a worktree utility for crewmates, not a supervision script, so it does
# not call fm-guard.sh.
# Usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]
set -eu

usage() {
  echo "usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]" >&2
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac
[ "$#" -le 1 ] || { usage; exit 1; }

DIR=${1:-.}
[ -d "$DIR" ] || { echo "error: not a directory: $DIR" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd -P)
cd "$DIR"

AGENTS=AGENTS.md
CLAUDE=CLAUDE.md

write_maintenance_section() {
  cat <<'EOF'
## Maintaining this file

Keep this file for project-wide working rules useful to almost every future agent session in this project.
Put a gotcha about one piece of code in that code: a comment at the line with the reason and the date, a lint rule, or a test.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
EOF
}

migrate_legacy_maintenance_section() {
  local contents legacy replacement
  legacy=$(cat <<'EOF'
## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
EOF
)
  replacement=$(write_maintenance_section)
  contents=$(cat "$AGENTS"; printf '\034')
  contents=${contents%$'\034'}
  case "$contents" in
    *"$legacy"*)
      contents=${contents/"$legacy"/"$replacement"}
      printf '%s' "$contents" > "$AGENTS" || return 2
      return 0
      ;;
  esac
  return 1
}

migrate_existing_maintenance_section() {
  local migration_status=0
  MAINTENANCE_MIGRATED=0
  migrate_legacy_maintenance_section || migration_status=$?
  if [ "$migration_status" -gt 1 ]; then
    return "$migration_status"
  fi
  if [ "$migration_status" -eq 0 ]; then
    MAINTENANCE_MIGRATED=1
  fi
}

ensure_maintenance_section() {
  local migration_status=0
  migrate_legacy_maintenance_section || migration_status=$?
  if [ "$migration_status" -eq 0 ]; then
    return 0
  fi
  if [ "$migration_status" -gt 1 ]; then
    return "$migration_status"
  fi
  if grep -Fqx '## Maintaining this file' "$AGENTS"; then
    return 0
  fi
  sep=''
  if [ -s "$AGENTS" ]; then
    if [ -n "$(tail -c 1 "$AGENTS")" ]; then
      sep=$'\n\n'
    else
      sep=$'\n'
    fi
  fi
  {
    printf '%s' "$sep"
    write_maintenance_section
  } >> "$AGENTS"
}

write_skeleton() {
  cat > "$AGENTS" <<'EOF'
# Project agent memory

This file is the project's committed home for project-wide working rules: build, test, release, and architecture conventions useful to almost every future agent session.

- Add such rules here as they are discovered through real work.
EOF
  ensure_maintenance_section
}

is_correct_claude_symlink() {
  [ -L "$CLAUDE" ] || return 1
  target=$(readlink "$CLAUDE")
  case "$target" in
    "$AGENTS"|"./$AGENTS") return 0 ;;
  esac
  [ -e "$AGENTS" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$CLAUDE" "$AGENTS" <<'PY'
import os
import sys
sys.exit(0 if os.path.realpath(sys.argv[1]) == os.path.realpath(sys.argv[2]) else 1)
PY
    return $?
  fi
  return 1
}

if [ -L "$AGENTS" ]; then
  echo "conflict: AGENTS.md is a symlink in $DIR; expected AGENTS.md to be the real file" >&2
  exit 1
fi
if [ -e "$AGENTS" ] && [ ! -f "$AGENTS" ]; then
  echo "conflict: AGENTS.md exists in $DIR but is not a regular file" >&2
  exit 1
fi

if [ -e "$AGENTS" ]; then
  if [ -L "$CLAUDE" ]; then
    if is_correct_claude_symlink; then
      migrate_existing_maintenance_section
      if [ "$MAINTENANCE_MIGRATED" -eq 1 ]; then
        echo "updated: migrated AGENTS.md maintenance section in $DIR"
      else
        echo "unchanged: AGENTS.md with CLAUDE.md -> AGENTS.md in $DIR"
      fi
      exit 0
    fi
    echo "conflict: CLAUDE.md is a symlink in $DIR but does not point to AGENTS.md" >&2
    exit 1
  fi
  if [ ! -e "$CLAUDE" ]; then
    migrate_existing_maintenance_section
    ln -s "$AGENTS" "$CLAUDE"
    if [ "$MAINTENANCE_MIGRATED" -eq 1 ]; then
      echo "updated: migrated AGENTS.md maintenance section and symlinked CLAUDE.md -> AGENTS.md in $DIR"
    else
      echo "symlinked: CLAUDE.md -> AGENTS.md in $DIR"
    fi
    exit 0
  fi
  if [ -f "$CLAUDE" ]; then
    echo "conflict: both AGENTS.md and CLAUDE.md are real files in $DIR; reconcile them manually" >&2
    exit 1
  fi
  echo "conflict: CLAUDE.md exists in $DIR but is not a regular file or symlink" >&2
  exit 1
fi

if [ -L "$CLAUDE" ]; then
  if is_correct_claude_symlink; then
    write_skeleton
    echo "created: AGENTS.md and kept CLAUDE.md -> AGENTS.md in $DIR"
    exit 0
  fi
  echo "conflict: CLAUDE.md is a symlink in $DIR but AGENTS.md is missing and the link does not point to AGENTS.md" >&2
  exit 1
fi

if [ -e "$CLAUDE" ]; then
  if [ -f "$CLAUDE" ]; then
    mv "$CLAUDE" "$AGENTS"
    ensure_maintenance_section
    ln -s "$AGENTS" "$CLAUDE"
    echo "promoted: moved CLAUDE.md to AGENTS.md and symlinked CLAUDE.md -> AGENTS.md in $DIR"
    exit 0
  fi
  echo "conflict: CLAUDE.md exists in $DIR but is not a regular file or symlink" >&2
  exit 1
fi

write_skeleton
ln -s "$AGENTS" "$CLAUDE"
echo "created: AGENTS.md and CLAUDE.md -> AGENTS.md in $DIR"
