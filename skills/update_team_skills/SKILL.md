---
name: update_team_skills
description: Pull latest team skills from the dotclaude repo and run setup.sh to install new ones
allowed-tools: Bash(readlink *), Bash(git -C * pull), Bash(*/setup.sh), Bash(ls *)
argument-hint: ""
---

# Update Team Skills

Pull the latest shared skills from the dotclaude repo and run setup to install any new ones.

Execute these steps immediately without explanation or planning:

## Steps

1. Resolve the dotclaude repo path by reading an existing symlink in `~/.claude/skills/`:

```bash
readlink -f ~/.claude/skills/pr
```

Strip the trailing `skills/pr/` portion to get the repo root. If that symlink doesn't exist, fall back to listing `~/.claude/skills/` and reading the first symlink found:

```bash
ls -la ~/.claude/skills/
```

2. Pull latest changes:

```bash
git -C <repo-root> pull
```

3. Run setup to link any new skills:

```bash
bash <repo-root>/setup.sh
```

4. Report concisely what happened: new skills linked, already up-to-date, or any errors.

Do NOT:
- Over-explain each step
- Ask for confirmation between steps
- Offer follow-up suggestions
