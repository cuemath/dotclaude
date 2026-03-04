# dotclaude

Shared [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for the team.

## Setup

```bash
git clone git@github.com:<org>/dotclaude.git ~/code/work/dotclaude
cd ~/code/work/dotclaude
./setup.sh
```

`setup.sh` symlinks each skill directory into `~/.claude/skills/` so Claude Code picks them up automatically.

## Available skills

| Skill | Description |
|-------|-------------|
| `deploy_to_testenv` | Trigger an AWS CodeBuild build using repo context (project, branch, test env) and return the console URL |
| `pr` | Stage, commit, push, and open a PR in one shot |

## Adding a new skill

1. Create `skills/<skill-name>/SKILL.md` following the [skill authoring docs](https://docs.anthropic.com/en/docs/claude-code/skills).
2. Commit and push.
3. Teammates run `./setup.sh` again (existing symlinks are skipped).
