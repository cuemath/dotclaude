---
name: db_query
description: Connect to a Cuemath analytics replica database via SSH tunnel and run a read-only SQL query
allowed-tools: Bash(ssh *), Bash(PGOPTIONS=*), Bash(kill *), Bash(lsof *), Bash(which *), Bash(find *), Bash(ls *), Read, Grep
argument-hint: "[service_name] [query or question]"
---

# DB Query

Connect to a Cuemath PostgreSQL analytics replica via SSH tunnel and run a read-only SQL query.

## Connection Details

SSH tunnel through `torpedo.cuemath.com`, local port: `15432`.
DB user: `dbadmin`, password: `$DB_PASSWORD` env var. All replicas are read-only.

### User Config

**First, read `~/.claude/config.json`** to get the user's saved settings. Use `user.ssh_user`, `user.ssh_key`, and `db.db_password_env` fields.

If the config file doesn't exist or is missing these fields, ask the user for ALL missing fields at once and create/update `~/.claude/config.json`. This file is user-local (not in the shared skills directory) and shared across skills. The SSH username pattern is typically `firstnamelastname`.

```json
{
  "user": {
    "ssh_user": "firstnamelastname",
    "ssh_key": "~/.ssh/id_rsa"
  },
  "db": {
    "db_password_env": "DB_PASSWORD"
  }
}
```

### psql Binary

`psql` may not be on `$PATH`. If `which psql` fails, find it:
```bash
which psql 2>/dev/null || find /opt/homebrew -name "psql" -type f 2>/dev/null | head -1
```
Use the full path to `psql` in all subsequent commands.

### DB_PASSWORD

The `$DB_PASSWORD` env var must be available in the Bash tool's shell. If the connection fails with "no password supplied", ask the user to provide the password directly so it can be passed inline as `PGPASSWORD=<password>`.

### RDS Hostnames

| Cluster | Analytics Replica Hostname |
|---|---|
| CONCEPTS | conceptsanalyticsreplica.ckhhr136b02o.ap-southeast-1.rds.amazonaws.com |
| GODZILLA | godzillaanalyticsreplica.ckhhr136b02o.ap-southeast-1.rds.amazonaws.com |
| HULK | hulkanalyticsreplica.ckhhr136b02o.ap-southeast-1.rds.amazonaws.com |
| INTEL | intelanalyticsreplica.ckhhr136b02o.ap-southeast-1.rds.amazonaws.com |
| INTELENROLLMENT | intelenrollmentanalyticsreplica.ckhhr136b02o.ap-southeast-1.rds.amazonaws.com |
| SINDHU | sindhuanalyticsreplica.ckhhr136b02o.ap-southeast-1.rds.amazonaws.com |
| THOR | thoranalyticsreplica.ckhhr136b02o.ap-southeast-1.rds.amazonaws.com |

### Service-to-Cluster Mapping

The canonical mapping lives in `cueutil/cueutil/settings/manager/config.py` (`SERVICE_TO_CONFIG` dict). Key groupings:

| Cluster | Services |
|---|---|
| THOR | auth, exam, cuestore, orders, enrollment, event, task, segment, commontool, practicesession, schoolquiz, credit, assessment, ads, modelserver |
| HULK | location, parent_student, enquiry, pause, pricing, payment, apigateway, attendance, notification, compliance, gameunit, moment, learnosity, urlshortner, webbackend, growthevent, helpcenter, payout, website, webapigateway, training, inteladmingateway, studenttasks, downloadcenter, asset, questionbank, cuemathgateway, crcard, schoolmath, foundationcenter, referral, cuecoin, feedback, licence, economy, demo, reporter, sfgateway |
| INTEL | intel, teacher, leadsquare, ptm, circle, chatbackend, crmgateway |
| SINDHU | classroom, eventprocessor |
| CONCEPTS | concepts |
| INTELENROLLMENT | intelenrollment |
| GODZILLA | communication |

Database name = service name (lowercase). If unsure which cluster a service belongs to, look it up in the config file above.

## Steps

1. Identify the target service and its RDS hostname from the tables above.

2. Find the psql binary (see "psql Binary" section above). Store the path for use in step 4.

3. Kill any leftover tunnel on port 15432 from a previous run, then open a fresh one:

```bash
kill $(lsof -ti:15432) 2>/dev/null; ssh -f -N -L 15432:<rds_host>:5432 <user.ssh_user>@torpedo.cuemath.com -i <user.ssh_key>
```

4. Run the query (use the full psql path from step 2):

```bash
PGOPTIONS='-c statement_timeout=300000' PGPASSWORD=$DB_PASSWORD <psql_path> -h localhost -p 15432 -U dbadmin -d <db_name> -c "<query>"
```

5. Always kill the tunnel when done:

```bash
kill $(lsof -ti:15432) 2>/dev/null
```

## Query Guardrails

- NEVER run `SELECT * FROM <table>` without a `WHERE` clause — ask the user for confirmation first
- Use `COUNT`/aggregates when the user asks "how many" — don't fetch and count rows
- NEVER hardcode the database password — always use `$DB_PASSWORD`
- Always kill the SSH tunnel after the query session. Do not ask whether to run this command or not. 

Do NOT:

- Over-explain each step
- Ask for confirmation between steps (except for the guardrails above)
- Offer follow-up suggestions
