---
name: pr
description: Stage, commit, push, and create a PR from current changes
allowed-tools: Bash(git status), Bash(git add), Bash(git diff), Bash(git log), Bash(git commit), Bash(git checkout), Bash(git branch), Bash(git push), Bash(git push --force-with-lease), Bash(gh pr list), Bash(gh pr create), Bash(gh pr view), Bash(gh pr reopen)
argument-hint: ""
---

# Create PR

Stage, commit, push, and create a PR from current changes.

## Steps

1. Check for staged changes.
   - If files are already staged → use only those (do NOT stage additional files).
   - If nothing is staged → stage all modified files.
2. Check if the last commit has been pushed to the remote:
   - Run `git log origin/<branch>..HEAD --oneline` to see unpushed commits.
   - If there is exactly 1 unpushed commit → amend it (`git commit --amend`) with an updated message.
   - If there are 0 unpushed commits (i.e. last commit is already pushed) → create a new commit.
3. Create a descriptive commit message from the diff.
4. If not on a feature branch, create one with a descriptive name.
5. Push the branch. Use `--force-with-lease` if the commit was amended.
6. Check if a PR already exists for this branch (`gh pr list --head <branch> --state all`).
   - If an **open** PR exists → skip PR creation.
   - If a **closed** (not merged) PR exists → reopen it with `gh pr reopen <number>`.
   - If a **merged** PR exists → warn the user that these changes were already merged; do NOT create a duplicate PR.
   - If **no PR** exists → create one with a clear title and description.

Do NOT:

- Over-explain each step
- Ask for confirmation between steps
- Offer follow-up suggestions
