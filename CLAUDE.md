# CLAUDE.md

Shared Claude Code skills repository for the Cuemath team. Skills are symlinked into `~/.claude/skills/` so Claude Code picks them up automatically across all projects.

## Repo Structure

```
setup.sh                        # Symlinks skills into ~/.claude/skills/
skills/
  <skill-name>/
    SKILL.md                    # Skill definition (YAML front matter + instructions)
```

## Commands

```bash
./setup.sh          # Symlink all skills into ~/.claude/skills/
./setup.sh --pull   # Pull latest from remote master first, then symlink
```

Existing symlinks are skipped. If a non-symlink directory exists at the target, it is also skipped (remove it manually first).

## Current Skills

| Skill | Trigger | Description |
|---|---|---|
| `pr` | `/pr` | Stage, commit, push, and create a PR |
| `deploy-to-testenv` | `/deploy-to-testenv` | Trigger AWS CodeBuild build and return console URL |
| `post-merge-cleanup` | `/post-merge-cleanup` | Checkout master, delete feature branch, pull latest |
| `update-team-skills` | `/update-team-skills` | Pull latest dotclaude repo and run setup.sh |
| `db-query` | `/db-query [service] [query]` | Connect to a Cuemath analytics replica via SSH tunnel and run a SQL query |
| `cloudwatch-query` | `/cloudwatch-query [service_or_log_group] [query]` | Query CloudWatch Logs Insights for a Cuemath service or log group |

## Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md`
2. Include YAML front matter with required fields:
   ```yaml
   ---
   name: <skill-name>
   description: One-line description
   allowed-tools: Bash(command pattern), Read, Grep, ...
   argument-hint: ""
   ---
   ```
3. Write clear step-by-step instructions below the front matter
4. Commit, push, and have teammates run `./setup.sh`

## Skill Authoring Conventions

- **`allowed-tools`**: Whitelist only the tools the skill needs. Use glob patterns for Bash commands (e.g., `Bash(git branch*)`)
- **Steps**: Number them explicitly so Claude follows the exact sequence
- **End with "Do NOT" rules** to prevent common unwanted behaviors (over-explaining, asking for confirmation between steps, offering follow-up suggestions)
- **Keep skills focused**: one skill = one workflow
- **No confirmation prompts** between steps unless destructive — skills should execute fluidly
