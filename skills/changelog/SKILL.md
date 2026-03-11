---
name: changelog
description: Generate a descriptive changelog entry from the current branch's diff
allowed-tools: Bash(git *), Read, Grep, Edit, Write
argument-hint: ""
---

# Changelog Generator

Generate a structured CHANGELOG.md entry from the current feature branch's diff against master.

## Steps

1. Run `git branch --show-current` to get the current branch name. If it is `master` or `production`, abort immediately with: "ERROR: You must be on a feature branch to generate a changelog. Current branch is `<branch>`."

2. Read `package.json` in the project root and extract the `version` field.

3. Search the codebase for a codepush version constant by grepping for `CODEPUSH_PATCH_VERSION`. If found, extract the value and append it to the version (e.g., if version is `5.0.5` and codepush value is `v2`, the final version is `5.0.5.v2`). If not found, use the version from step 2 as-is.

4. Get today's date formatted as `DD-MM-YYYY`.

5. Run `git diff master...HEAD` to get the full diff of the feature branch against master.

6. Analyze the diff carefully and generate concise, human-readable changelog entries. Categorize them under the appropriate headings:
   - `### Changed` — modifications to existing behavior
   - `### Added` — new features or capabilities
   - `### Fixed` — bug fixes
   - `### Removed` — removed features or code
     Only include headings that have entries. Each entry should be a single bullet point describing the change from a user/product perspective.

7. Read the existing `CHANGELOG.md` if it exists. Insert the new version block immediately after the `# Changelog` header line (before any previous entries). If `CHANGELOG.md` does not exist, create one with the `# Changelog` header followed by the new version block.

The version block format is:

```
## [<version>] - DD-MM-YYYY

### Added
- Description of what was added

### Changed
- Description of what changed

### Fixed
- Description of what was fixed

### Removed
- Description of what was removed
```

## Do NOT

- Ask for confirmation between steps
- Over-explain each step
- Offer follow-up suggestions
- Include file paths or technical jargon in changelog entries — keep them human-readable
- Include empty category headings — only include categories that have entries
