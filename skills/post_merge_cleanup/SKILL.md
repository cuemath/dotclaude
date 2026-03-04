---
name: post_merge_cleanup
description: Switch to master, delete the current feature branch, and pull latest changes
allowed-tools: Bash(git branch*), Bash(git checkout*), Bash(git pull*)
argument-hint: ""
---

# Post-Merge Cleanup

Switch to master, delete the old feature branch, and pull latest changes.

## Steps

1. Get the current branch name:

```bash
git branch --show-current
```

2. If already on `master`, report that there's nothing to clean up and stop.

3. Checkout master:

```bash
git checkout master
```

4. Delete the old feature branch:

```bash
git branch -D <branch>
```

5. Pull latest changes:

```bash
git pull
```

6. Report what happened concisely: which branch was deleted and that master is up to date.

Do NOT:

- Ask for confirmation between steps
- Over-explain each step
- Offer follow-up suggestions
