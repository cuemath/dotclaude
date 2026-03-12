---
name: cloudwatch-query
description: Query CloudWatch Logs Insights for a Cuemath service or log group. Use when checking service logs, log counts, error rates, or verifying service activity.
allowed-tools: Bash(aws logs start-query *), Bash(aws logs get-query-results *), Bash(date *), Bash(sleep *)
argument-hint: "[service_name_or_log_group] [query or question]"
---

# CloudWatch Query

Query CloudWatch Logs Insights for a Cuemath K8s service or any log group.

## Default Config

- **Production log group:** `/aws/containerinsights/cuemath-k8-prod/application`
- **Service filter (sync):** `filter @logStream like 'containers.<service_name>-' and @logStream like '_cuemath_'`
- **Service filter (async):** `filter @logStream like 'containers.<service_name>-' and @logStream like '_cuemathasync_'`
- Stream names follow the pattern: `service-application.var.log.containers.<service>-<pod>_cuemath_<service>-<hash>`. Use the above filters to match reliably.
- **Default time range:** last 1 hour (if user doesn't specify, ask them for a time range)
- **Default query:** count logs matching the service

## Steps

1. **Parse arguments.** Determine:
   - **Log group:** If the argument starts with `/`, use it as a custom log group. Otherwise, use the default production log group and treat the argument as a service name.
   - **Time range:** Look for natural language like "last 7 days", "last 24 hours", "last 1 hour". Default to last 1 hour. If the user didn't specify a time range, ask them before running the query.
   - **Cost guardrail:** If the computed time range exceeds **24 hours**, warn the user that CloudWatch Logs Insights charges $0.005/GB scanned and larger windows scan more data. Ask for confirmation before proceeding.
   - **Query:** If the user provided a quoted CW Insights query string, use it directly. Otherwise, construct a query based on what the user is asking (count, errors, recent logs, etc.).

2. **Compute start and end timestamps** using macOS `date`:

```bash
# Examples (adjust -v flag as needed):
date -v-1H +%s    # 1 hour ago (default)
date -v-7d +%s    # 7 days ago
date -v-24H +%s   # 24 hours ago
date -v-4w +%s    # 4 weeks ago
date +%s           # now

# "Today" (midnight of current day — do NOT use date -v-0d which returns current time):
date -j -f '%Y-%m-%d %H:%M:%S' "$(date +%Y-%m-%d) 00:00:00" +%s  # midnight today
```

3. **Construct the query.** For service-name lookups on the default log group, always include the logStream filter. Use the sync filter by default; use the async filter only if the user explicitly asks about async/worker logs.

   - **Log count (default):**
     ```
     filter @logStream like 'containers.<service>-' and @logStream like '_cuemath_' | stats count(*) as logCount
     ```
   - **Recent errors:**
     ```
     filter @logStream like 'containers.<service>-' and @logStream like '_cuemath_' and @message like /(?i)error/ | fields @timestamp, @message | sort @timestamp desc | limit 20
     ```
   - **Custom query (user-provided):** Use as-is, but prepend the logStream filter if using the default log group with a service name.

4. **Discover log format (when needed).** If the query requires `parse`, regex extraction, or filtering on structured fields (e.g., extracting user IDs, request paths, status codes), first run a small sample query to see the actual log format:
   ```
   filter @logStream like 'containers.<service>-' and @logStream like '_cuemath_' | fields @message | sort @timestamp desc | limit 5
   ```
   Inspect the returned messages to understand the format before constructing `parse` patterns or field-specific filters. Skip this step for simple count or grep-style queries.

5. **Run the query:**

```bash
aws logs start-query \
  --region ap-southeast-1 \
  --log-group-name '<log_group>' \
  --start-time <start_epoch> \
  --end-time <end_epoch> \
  --query-string '<query>' \
  --output json
```

Extract the `queryId` from the response.

6. **Poll for results.** Wait 2 seconds, then check:

```bash
sleep 2 && aws logs get-query-results --region ap-southeast-1 --query-id '<query_id>' --output json
```

If `status` is not `Complete`, wait another 3 seconds and retry. Poll up to 5 times total before reporting a timeout.

7. **Present results** in a clean formatted table or summary. For count queries, just show the count. For field queries, show a markdown table.

   After presenting results, extract `bytesScanned` from the `statistics` field in the `get-query-results` response. Convert to MB (÷ 1048576) or GB (÷ 1073741824) and compute estimated cost at $0.005/GB. Always show in bold, all caps:
   ```
   **DATA SCANNED: X.XX MB (~$0.00)**
   ```

## Do NOT:

- Over-explain each step
- Ask for confirmation between steps
- Offer follow-up suggestions
- Use `--output table` — always use `--output json` and format the results yourself for cleaner presentation
- Run queries spanning more than 24 hours without warning the user about CloudWatch scan costs
