#!/usr/bin/env bash
set -euo pipefail

DO_PULL=false
for arg in "$@"; do
  case "$arg" in
    --pull) DO_PULL=true ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
SKILLS_DST="$HOME/.claude/skills"

# --- Try to update from remote master ---
if [ "$DO_PULL" = true ]; then
  (
    cd "$REPO_DIR"
    git fetch origin master 2>/dev/null || true

    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [ "$BRANCH" != "master" ]; then
      echo "dotclaude: on branch '$BRANCH', skipping update."
    else
      LOCAL=$(git rev-parse HEAD 2>/dev/null)
      REMOTE=$(git rev-parse origin/master 2>/dev/null)

      if [ "$LOCAL" != "$REMOTE" ]; then
        echo "dotclaude: remote master is ahead, attempting pull..."
        if git pull --ff-only origin master 2>/dev/null; then
          echo "dotclaude: updated to latest master."
        else
          echo "dotclaude: pull failed (likely local changes), skipping update."
        fi
      else
        echo "dotclaude: already up to date."
      fi
    fi
  )
fi

# --- Symlink skills ---
mkdir -p "$SKILLS_DST"

for skill_dir in "$SKILLS_SRC"/*/; do
  skill_name="$(basename "$skill_dir")"
  target="$SKILLS_DST/$skill_name"

  if [ -L "$target" ]; then
    echo "skip: $skill_name (symlink already exists)"
  elif [ -e "$target" ]; then
    echo "skip: $skill_name (directory already exists — remove it first to use symlink)"
  else
    ln -s "$skill_dir" "$target"
    echo "linked: $skill_name -> $skill_dir"
  fi
done

echo "Done."
