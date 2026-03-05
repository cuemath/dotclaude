# dotclaude

Shared [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills for the team.

## Setup

```bash
git clone git@github.com:cuemath/dotclaude.git
cd dotclaude
./setup.sh
```

`setup.sh` symlinks each skill directory into `~/.claude/skills/` so Claude Code picks them up automatically.

## Available skills

| Skill | Description |
|-------|-------------|
| `deploy_to_testenv` | Trigger an AWS CodeBuild build using repo context (project, branch, test env) and return the console URL |
| `pr` | Stage, commit, push, and open a PR in one shot |
| `post_merge_cleanup` | Switch to master, delete the current feature branch, and pull latest changes |
| `update_team_skills` | Pull latest team skills from the dotclaude repo and run setup.sh to install new ones |

## Adding a new skill

1. Create `skills/<skill-name>/SKILL.md` following the [skill authoring docs](https://docs.anthropic.com/en/docs/claude-code/skills).
2. Commit and push.
3. Teammates run `./setup.sh` again (existing symlinks are skipped).
