---
name: pr
description: Stage, commit, push, and create a PR from current changes
allowed-tools: Bash(git status), Bash(git add), Bash(git diff), Bash(git commit), Bash(git checkout), Bash(git branch), Bash(git push), Bash(gh pr create)
argument-hint: ""
---

# Create PR

Stage, commit, push, and create a PR from current changes.

## Steps

1. Check for staged changes. If none, stage all modified files.
2. Create a descriptive commit message from the diff.
3. If not on a feature branch, create one with a descriptive name.
4. Push the branch.
5. Create a PR with a clear title and description summarizing changes.

Do NOT:

- Over-explain each step
- Ask for confirmation between steps
- Offer follow-up suggestions
