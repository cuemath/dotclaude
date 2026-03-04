---
name: deploy_to_testenv
description: Trigger an AWS CodeBuild build using repo context (project, branch, test env) and return the console URL
allowed-tools: Bash(aws codebuild*), Bash(git branch*), Read, Grep
argument-hint: ""
---

# Deploy to Test Environment

Trigger an AWS CodeBuild build using context derived from the repo and return the console URL for monitoring.

## Steps

1. Read the `.codebuild-project` file in the repo root to get the CodeBuild project name (trim whitespace).

2. Read `.env.development.local` and grep for `VITE_DEV_SERVER_PROXY`. Extract the `testenvNN` portion from the URL using regex (e.g., from `https://leap.testenv37.cuemath.com` extract `testenv37`).

3. Get the current git branch:
```bash
git branch --show-current
```

4. Run the build:
```bash
aws codebuild start-build \
  --project-name "<project-name>" \
  --source-version "<current-branch>" \
  --environment-variables-override "name=testenv,value=<testenvNN>,type=PLAINTEXT" \
  --region ap-southeast-1
```

5. From the JSON response, extract:
   - `build.id` (format: `project:build-uuid`)
   - `build.buildNumber`
   - Account ID from `build.arn` (field 4 when split by `:`)

6. Construct the AWS Console URL:
```
https://ap-southeast-1.console.aws.amazon.com/codesuite/codebuild/<account-id>/projects/<project>/build/<build-id>/log
```
where `<build-id>` is the full `build.id` value (URL-encode the `:` as `%3A`).

7. Output the build number and clickable console URL to the user.
