#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_DIR:-$HOME/.codex}"
CLAUDE_SKILLS="${CLAUDE_DIR}/skills"
CODEX_SKILLS="${CODEX_DIR}/skills"

if ! mkdir -p "$CLAUDE_SKILLS" 2>/dev/null; then
    echo "Warning: unable to create $CLAUDE_SKILLS; skipping Codex skills link." >&2
    exit 0
fi

if [ -L "$CODEX_SKILLS" ]; then
    TARGET=$(readlink "$CODEX_SKILLS")
    if [ "$TARGET" = "$CLAUDE_SKILLS" ]; then
        exit 0
    fi
    echo "Warning: $CODEX_SKILLS points to $TARGET (expected $CLAUDE_SKILLS)." >&2
    exit 0
fi

if [ -e "$CODEX_SKILLS" ]; then
    echo "Warning: $CODEX_SKILLS exists and is not a symlink; leaving as-is." >&2
    exit 0
fi

if ! mkdir -p "$CODEX_DIR" 2>/dev/null; then
    echo "Warning: unable to create $CODEX_DIR; skipping Codex skills link." >&2
    exit 0
fi

if ln -s "$CLAUDE_SKILLS" "$CODEX_SKILLS" 2>/dev/null; then
    echo "Linked $CODEX_SKILLS -> $CLAUDE_SKILLS" >&2
else
    echo "Warning: failed to create symlink $CODEX_SKILLS -> $CLAUDE_SKILLS." >&2
fi
