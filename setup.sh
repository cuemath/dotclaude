#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
SKILLS_DST="$HOME/.claude/skills"

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
