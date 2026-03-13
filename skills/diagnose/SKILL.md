---
name: diagnose
description: Diagnose production issues from a Sentry URL, Slack URL, description, or screenshot
allowed-tools: Bash(cp ~/.kube/config /tmp/diagnose-kubeconfig*), Bash(rm -f /tmp/diagnose-kubeconfig*), Bash(KUBECONFIG=/tmp/diagnose-kubeconfig *), Bash(kubectl get *), Bash(kubectl describe *), Bash(kubectl logs *), Bash(kubectl top *), Bash(kubectl config *), Bash(kubectl exec * -- cat *), Bash(kubectl exec * -- ls *), Bash(kubectl exec * -- env *), Bash(kubectl exec * -- nslookup *), Bash(kubectl exec * -- ps *), Bash(kubectl exec * -- df *), Bash(kubectl exec * -- free *), Bash(kubectl exec * -- netstat *), Bash(kubectl exec * -- sh -c "which *"), Bash(aws sqs receive-message *), Bash(aws logs start-query *), Bash(aws logs get-query-results *), Bash(aws cloudwatch get-metric-*), Bash(aws sqs get-queue-attributes *), Bash(aws sqs list-queues *), Bash(aws rds describe-*), Bash(curl -s *), Bash(date *), Bash(sleep *), Bash(git -C * pull *), Bash(git -C * fetch *), Bash(git -C * rev-parse *), Bash(git pull *), Bash(ssh -f -N -L *), Bash(ssh -o *), Bash(aws sts get-caller-identity *), Bash(PGOPTIONS=*), Bash(kill *), Bash(lsof *), Bash(which *), Bash(find /opt/homebrew *), Bash(ls *), Bash(cat *), Read, Grep, Glob, mcp__slack__slack_get_channel_history, mcp__slack__slack_get_thread_replies, mcp__slack__slack_get_user_profile
argument-hint: "<sentry_url OR slack_url OR problem description OR screenshot>"
---

# Debug

Diagnose production issues — infrastructure, application, or both. Accepts a Sentry issue URL, a Slack message URL, a problem description, or a screenshot as input. Runs read-only diagnostics and returns a root cause diagnosis with a confidence percentage.

## Config

On first run, read `~/.claude/config.json` for saved settings. This is a shared config file used by all skills. If it doesn't exist or is missing fields needed by this skill, ask the user for ALL missing fields at once and create/update the file.

Required fields for this skill:

```json
{
  "user": {
    "ssh_user": "firstnamelastname",
    "ssh_key": "~/.ssh/id_rsa"
  },
  "db": {
    "db_password_env": "DB_PASSWORD"
  },
  "sentry": {
    "auth_token": "sntryu_...",
    "org": "cuemathcom",
    "project": "python"
  },
  "repos": {
    "backend": "/Users/dev/cuemath/web",
    "frontend": "/Users/dev/cuemath/react"
  }
  // If web/ and react/ are under the same parent (e.g. ~/workspaces/cuemath/),
  // just use that parent for both:
  //   "backend": "~/workspaces/cuemath/web"
  //   "frontend": "~/workspaces/cuemath/react"
}
```

### Field Usage

- **`sentry.*`**: Used to call the Sentry API for issue details and stacktraces
- **`user.*`**: Used for SSH tunnels when running DB queries during debugging
- **`db.*`**: Used for DB password env var
- **`repos.*`**: Used to resolve source code paths for services

### Repository Paths

The `repos` field maps repository names to local filesystem paths. The backend repo contains all microservices as subdirectories (e.g., `<backend>/intelenrollment/`, `<backend>/payment/`). The frontend repo contains all frontend apps (e.g., `<frontend>/CUEMATHAPP/`, `<frontend>/intel_student_react/`).

When you need to read code for a service, resolve the path as:
- **Backend service:** `<repos.backend>/<service_name>/`
- **Frontend app:** `<repos.frontend>/<app_name>/`

If a path doesn't exist, try the other repo path. If still not found, ask the user.

## Cluster Context

- **Production cluster:** `arn:aws:eks:ap-southeast-1:484426514402:cluster/cuemath-k8-prod`
- **Sync namespace:** `cuemath` (HTTP services)
- **Async namespace:** `cuemathasync` (SQS consumers)
- **Region:** `ap-southeast-1`
- **CloudWatch log group:** `/aws/containerinsights/cuemath-k8-prod/application`
- **CoreDNS:** 2 pods, iptables-mode kube-proxy, no NodeLocal DNSCache

**Sandboxed kubectl context** — never modify the user's global kubeconfig. Shell env vars don't persist across Bash tool calls, so use the `KUBECONFIG` env var prefix on every kubectl command.

**Setup** — create an isolated kubeconfig copy and set context on it:
```bash
cp ~/.kube/config /tmp/diagnose-kubeconfig && KUBECONFIG=/tmp/diagnose-kubeconfig kubectl config use-context arn:aws:eks:ap-southeast-1:484426514402:cluster/cuemath-k8-prod
```

**Every kubectl command** must be prefixed with `KUBECONFIG=/tmp/diagnose-kubeconfig`:
```bash
KUBECONFIG=/tmp/diagnose-kubeconfig kubectl get pods -n cuemath
KUBECONFIG=/tmp/diagnose-kubeconfig kubectl describe hpa <service> -n cuemath
```

This ensures the user's global `~/.kube/config` stays untouched. If the skill crashes or is aborted, no cleanup is needed — the temp file is harmless.

**Cleanup** — after the diagnosis is complete:
```bash
rm -f /tmp/diagnose-kubeconfig
```

## Input Parsing

### Sentry URL
Extract the issue ID from the URL and fetch details via API:
```bash
# Issue summary
curl -s -H "Authorization: Bearer <sentry.auth_token>" \
  "https://sentry.io/api/0/issues/<issue_id>/" | python3 -m json.tool

# Latest event (full stacktrace, tags, context)
curl -s -H "Authorization: Bearer <sentry.auth_token>" \
  "https://sentry.io/api/0/issues/<issue_id>/events/latest/" | python3 -m json.tool
```

From the Sentry data, extract:
- Error type and message
- Service name (from tags or server_name)
- Frequency (count, firstSeen, lastSeen)
- Stacktrace (file, function, line number)
- Any relevant tags (environment, transaction, url)

### Slack Message URL
Parse the channel ID and message timestamp from the URL. Slack message URLs follow this pattern:
```
https://<workspace>.slack.com/archives/<channel_id>/p<timestamp_without_dot>
```

Convert the timestamp: remove the leading `p`, then insert a `.` so 6 digits come after it (e.g., `p1710234567890123` → `1710234567.890123`).

1. **Fetch the message thread** using `mcp__slack__slack_get_thread_replies` with the extracted `channel_id` and `thread_ts`. This returns the parent message and all replies.
2. **If no thread replies** (the message isn't a thread parent), fetch recent channel history with `mcp__slack__slack_get_channel_history` and find the message by timestamp.
3. **Resolve user names** for any `<@U...>` mentions using `mcp__slack__slack_get_user_profile` so the context is human-readable.

From the Slack message(s), extract:
- Problem description and symptoms
- Service names, error messages, or Sentry URLs mentioned
- Screenshots or links shared in the thread
- Time range or when the issue was first reported

If the Slack thread contains a Sentry URL, continue with Sentry URL parsing as well.

### Problem Description (text)
Parse for: service names, error types, time ranges, symptoms.

### Screenshot
Read the screenshot using the Read tool (it supports images). Extract: error messages, service names, metrics, timestamps, graph trends.

## Core Principle: Never Assume — Always Verify

Never assume anything. Always verify. Always verify.

- Before concluding which endpoint a client calls, verify with production logs (CloudWatch, request logs). Multiple API versions coexist — older ones may be dead code.
- Before fixing code, confirm it's the code that actually runs in production. Trace from the actual client request URL (from logs) to the handler, THEN fix that handler.
- Before concluding how data flows, verify with actual data.
- If you can verify a claim, verify it. Don't skip verification to save time — wrong assumptions waste more time than checking.

## Debugging Framework

### Phase 1: PLAN

Before running any commands, output a numbered debugging plan:

```
DEBUGGING PLAN
==============
Problem: <1-line summary of reported issue>
Symptoms: <list extracted symptoms>

Steps:
1. <what you'll check first and why>
2. <what you'll check next>
3. ...

Estimated commands: ~N
```

Wait for the user to approve or adjust the plan before proceeding.

### Phase 2: PREFLIGHT

Based on the approved plan, determine which tool categories are needed and check **only those**:

| Category | When needed | Check |
|----------|-------------|-------|
| **Repo paths** | Always | `ls <repos.backend> <repos.frontend>` |
| **Sentry** | Input is a Sentry URL, or plan includes Sentry search | `curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer <token>" "https://sentry.io/api/0/organizations/cuemathcom/"` |
| **kubectl + AWS** | Plan includes pod/HPA/CloudWatch/SQS checks | `which kubectl aws`, `aws sts get-caller-identity`, `KUBECONFIG=/tmp/diagnose-kubeconfig kubectl get nodes --no-headers 2>&1 | head -1` |
| **SSH + psql** | Plan includes DB queries | `which psql`, `ssh -o ConnectTimeout=5 -o BatchMode=yes <ssh_user>@torpedo.cuemath.com echo ok` |

Run the relevant checks in parallel. If any fail, print what's missing and how to fix it — but only block the steps that depend on the failing tool. If the diagnosis can proceed with just code reading + Sentry, do that.

```
PREFLIGHT
=========
[✓] Repo paths exist
[✓] Sentry token valid
[—] kubectl/AWS: skipped (not needed for this diagnosis)
[—] SSH/psql: skipped (not needed for this diagnosis)
```

### Phase 3: TRIAGE

Gather baseline data from all relevant sources. Run commands in parallel where possible.

**Always run (regardless of issue type):**

1. Fetch Sentry issue details (if URL provided) or search for recent errors:
```bash
curl -s -H "Authorization: Bearer <token>" \
  "https://sentry.io/api/0/organizations/<org>/issues/?query=<service_or_error>&sort=date&limit=10"
```

2. Sample recent error logs from CloudWatch:
```bash
# Fetch 10 recent error logs to see actual error messages
aws logs start-query --region ap-southeast-1 \
  --log-group-name '/aws/containerinsights/cuemath-k8-prod/application' \
  --start-time $(date -v-1H +%s) --end-time $(date +%s) \
  --query-string "filter @logStream like 'containers.<service>-' and @logStream like '_cuemath_' and @message like /(?i)(error|exception|traceback)/ | fields @timestamp, @message | sort @timestamp desc | limit 10" \
  --output json
```

3. Read the relevant source code for the affected service (resolve from `repos` config).

**For connection/infra symptoms, also run:**

4. Pod status in both namespaces:
```bash
kubectl get hpa -n cuemath 2>/dev/null | head -30
kubectl get hpa -n cuemathasync 2>/dev/null | head -30
```

5. Recent scaling events for the affected service:
```bash
kubectl describe hpa <service> -n <namespace> | tail -30
```

6. Error count in CloudWatch (last 1 hour):
```bash
aws logs start-query --region ap-southeast-1 \
  --log-group-name '/aws/containerinsights/cuemath-k8-prod/application' \
  --start-time $(date -v-1H +%s) --end-time $(date +%s) \
  --query-string "filter @logStream like 'containers.<service>-' and @logStream like '_cuemath_' and @message like /(?i)(error|exception|traceback)/ | stats count(*) as errorCount by bin(5m)" \
  --output json
```

7. Node count and recent autoscaler activity:
```bash
kubectl get nodes --no-headers | wc -l
kubectl get events -A --sort-by='.lastTimestamp' --field-selector reason=ScaledUp 2>/dev/null | tail -20
```

8. SQS queue depths:
```bash
aws sqs get-queue-attributes --region ap-southeast-1 \
  --queue-url https://sqs.ap-southeast-1.amazonaws.com/484426514402/<queue_name> \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --output json
```

9. DLQ message counts for affected queues (append `_dlq` to queue name).

**For application/error symptoms, also run:**

10. Additional Sentry context — related issues, release info, affected users count.

11. Detailed CloudWatch log analysis — trace request flow, check upstream/downstream errors.

**Output a TRIAGE SUMMARY** after this phase:
```
TRIAGE SUMMARY
==============
- Pods: <status>
- Scaling: <recent HPA activity>
- Errors: <count and trend>
- Queues: <depths, DLQ counts>
- Sentry: <issue summary if available>
```

### Phase 4: HYPOTHESIZE

Based on triage data, form hypotheses. For each hypothesis, state:
- What it is
- What evidence supports it so far
- What evidence you need to confirm or rule it out
- Current confidence %

Common hypothesis patterns:

| Symptom | Likely Hypotheses |
|---------|-------------------|
| `socket.gaierror [Errno -3]` | DNS resolution failure (conntrack race, CoreDNS overload) |
| `ConnectionError` to specific service | Target service down, target service overloaded, network policy |
| `OperationalError` / DB timeouts | DB overload, long-running queries, connection pool exhaustion |
| `OOMKilled` in pod events | Memory leak, undersized limits, data spike |
| HTTP 5xx from service | Application bug, dependency failure, resource exhaustion |
| SQS DLQ messages growing | Processing errors, downstream dependency failure |
| HPA scaling to max | Traffic spike, resource-heavy processing, inefficient code |

Present hypotheses ranked by likelihood:
```
HYPOTHESES
==========
1. [65%] <hypothesis> — supported by: <evidence>. Need to verify: <what>
2. [20%] <hypothesis> — supported by: <evidence>. Need to verify: <what>
3. [15%] <hypothesis> — ...
```

### Phase 5: VERIFY

For each hypothesis (starting with highest confidence), run targeted diagnostics to confirm or rule it out.

**Before reading any source code:** Ensure the local repo has the latest code. For each repo path in `repos` config, check if local master is behind remote and pull if needed:
```bash
git -C <repo_path> fetch origin master 2>/dev/null && \
  if [ "$(git -C <repo_path> rev-parse master)" != "$(git -C <repo_path> rev-parse origin/master)" ]; then
    git -C <repo_path> pull --rebase --autostash 2>/dev/null || echo "WARN: Could not pull latest for <repo_path>. Using local code (may be stale)."
  fi
```

Then resolve the service directory:
- Backend: `<repos.backend>/<service_name>/`
- Frontend: `<repos.frontend>/<app_name>/`

Use Read, Grep, Glob to examine relevant source files (e.g., the file/function from a Sentry stacktrace).

**Verification strategies by hypothesis type:**

**DNS/Network failures:**
- Check CoreDNS health: CloudWatch query for coredns SERVFAIL/errors
- Check resolv.conf inside affected pod: `kubectl exec <pod> -n <ns> -- cat /etc/resolv.conf`
- Check if nscd is running: `kubectl exec <pod> -n <ns> -- sh -c "which nscd 2>/dev/null || echo 'not installed'"`
- Check kube-proxy mode: `kubectl get configmap kube-proxy -n kube-system -o yaml | grep mode`
- Check DNS query volume trend in CloudWatch

**DB overload:**
- RDS instance metrics: `aws cloudwatch get-metric-statistics` for CPUUtilization, DatabaseConnections, ReadLatency, WriteLatency
- Check for long-running queries via DB analytics replica (use SSH tunnel pattern from db-query skill)
- Check connection pool settings in service code

**Application errors:**
- Read the stacktrace from Sentry
- Pull latest code and read the failing file/function
- Trace the call chain to understand what triggered the error
- Check if it's a recent code change: `git -C <service_dir> log --oneline -10`

**SQS processing failures:**
- Sample DLQ messages: `aws sqs receive-message` (with `--max-number-of-messages 1 --visibility-timeout 0` to peek without consuming)
- Check what event types are failing
- Trace the processing code for that event type

**After each verification step, update confidence:**
```
VERIFICATION UPDATE
===================
Hypothesis 1: [65% -> 90%] — confirmed by <new evidence>
Hypothesis 2: [20% -> 5%] — contradicted by <new evidence>
```

### Mandatory: Production Data Over Code Reasoning

Code tells you what SHOULD happen. Only DB queries, CloudWatch logs, and Sentry data tell you what ACTUALLY happens. **Every factual claim in the diagnosis MUST be backed by production data — never by code reading alone.**

Before concluding any of the following, you MUST run the corresponding query:

| Claim | Required verification |
|-------|----------------------|
| "Service X is/isn't receiving event Y" | Query event DB (`eventtype_subscriber`, `event` tables) or CloudWatch logs for the service |
| "Record/config X exists/doesn't exist in DB" | Query the relevant service DB via db-query skill |
| "Data is/isn't being created/processed" | Query the downstream service DB to check actual state |
| "This code path is/isn't being triggered" | Check CloudWatch logs for that service |
| "The intent/purpose of config X was Y" | Verify with event DB routing AND check downstream effects in the target service DB |

**If you have DB access (db-query skill) and CAN verify a claim with a query, you MUST run the query. Do not substitute code analysis for a query you can run. Do not present a diagnosis until every verifiable claim has been checked against production data.**

### Phase 6: SELF-CHECK

Before presenting the final diagnosis, challenge it:

1. **Does the diagnosis explain ALL observed symptoms?** If any symptom is unexplained, the diagnosis is incomplete.
2. **Is there an alternative explanation?** Consider if a different root cause could produce the same symptoms.
3. **Does the timeline make sense?** The cause must precede the effect.
4. **Can you verify without side effects?** If there's a safe way to confirm, do it.
5. **Is every claim backed by production data?** For each factual statement in the diagnosis, ask: "Did I verify this from DB/logs, or did I infer it from code?" If inferred from code and a DB query could confirm it — go back and run the query before proceeding.

If after self-check, confidence is still < 95%:
```
DIAGNOSIS: INCONCLUSIVE
========================
Best hypothesis: <hypothesis> at <N%> confidence
What's missing: <what additional data would reach 95%>
Suggested next steps: <what to check manually>
```

### Phase 7: DIAGNOSIS

Only present if confidence >= 95%.

```
DIAGNOSIS [confidence: N%]
===========================
Root Cause: <1-2 sentence root cause>

Evidence:
- <evidence 1>
- <evidence 2>
- <evidence 3>

Event Chain:
<trigger> -> <step 1> -> <step 2> -> ... -> <observed symptoms>

Impact:
- <what was affected>
- <error counts, duration, data loss>

Action Items:
- [ ] <immediate fix>
- [ ] <short-term fix>
- [ ] <long-term prevention>
```

## Service-to-Cluster Mapping (for DB queries)

| Cluster | Services |
|---------|----------|
| THOR | auth, exam, cuestore, orders, enrollment, event, task, segment, commontool, practicesession, assessment, credit |
| HULK | location, parent_student, enquiry, pause, pricing, payment, apigateway, attendance, notification, compliance, gameunit, website, webapigateway, demo |
| INTEL | intel, teacher, leadsquare, ptm, circle, chatbackend |
| SINDHU | classroom, eventprocessor |
| CONCEPTS | concepts |
| INTELENROLLMENT | intelenrollment |
| GODZILLA | communication |

DB connection uses SSH tunnel through `torpedo.cuemath.com`, local port `15432`. See db-query skill for full connection details.

## SQS Queue Names

Common queue URL pattern: `https://sqs.ap-southeast-1.amazonaws.com/484426514402/<service_name>`

Common queues: `payment`, `pricing`, `intelenrollment`, `parent_student`, `classroom`, `teacher`, `communication`, `leadsquare.fifo`, `auth`, `commontool`

DLQ pattern: append `_dlq` (e.g., `intelenrollment_dlq`)

## CloudWatch Query Patterns

- **Service log stream filter (sync):** `filter @logStream like 'containers.<service>-' and @logStream like '_cuemath_'`
- **Service log stream filter (async):** `filter @logStream like 'containers.<service>-' and @logStream like '_cuemathasync_'`
- **Error count by 5min bins:** `... | stats count(*) as errors by bin(5m)`
- **Connection error breakdown:** `... and @message like /ConnectionError/ | parse @message /host=(?<target_host>[^,\s]+)/ | stats count(*) by target_host`
- **Log volume trendline:** `... | stats count(*) as logCount by bin(5m) | sort bin asc`

Always use `--output json` and format results yourself. Show data scanned cost after CloudWatch queries.

## Safety Rules

**READ-ONLY ONLY. These rules are non-negotiable:**

- NEVER run `kubectl apply`, `kubectl delete`, `kubectl scale`, `kubectl restart`, `kubectl rollout`, `kubectl edit`, `kubectl patch`, `kubectl create`
- NEVER run `aws` commands that create, update, delete, or modify any resource
- NEVER run `aws sqs delete-message`, `aws sqs purge-queue`, or `aws sqs send-message`
- `kubectl exec` is ONLY for read commands inside pods: `cat`, `ls`, `env`, `nslookup`, `ps`, `df`, `free`, `netstat`. NEVER run commands that change pod state
- DB queries go to analytics replicas only (read-only by design). NEVER use `SELECT *` without `WHERE` and `LIMIT`
- `aws sqs receive-message` must always include `--visibility-timeout 0` to avoid hiding messages from real consumers
- Always kill SSH tunnels after DB queries: `kill $(lsof -ti:15432)`
- `git pull` is the ONLY git write operation allowed. No commits, pushes, checkouts, or resets

## Do NOT:

- Present a diagnosis with confidence < 95% as if it were conclusive
- Run any command that modifies system state
- Skip the PLAN phase — always show the plan and wait for approval
- Skip the SELF-CHECK phase — always challenge your own diagnosis
- Ask for confirmation between diagnostic steps (only before the initial plan)
- Over-explain each command you're running
- Offer follow-up suggestions after the diagnosis
- Run CloudWatch queries spanning > 24 hours without warning about scan costs ($0.005/GB)
