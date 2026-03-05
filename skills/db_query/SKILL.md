---
name: db_query
description: Connect to a Cuemath analytics replica database via SSH tunnel and run a read-only SQL query
allowed-tools: Bash(ssh *), Bash(PGOPTIONS=*), Bash(kill *), Bash(lsof *), Read, Grep
argument-hint: "[service_name] [query or question]"
---

# DB Query

Connect to a Cuemath PostgreSQL analytics replica via SSH tunnel and run a read-only SQL query.

## Connection Details

SSH tunnel through `torpedo.cuemath.com`, key: `~/.ssh/id_ed25519`, local port: `15432`.
User: `dbadmin`, password: `$DB_PASSWORD` env var. All replicas are read-only.

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

2. Open the SSH tunnel:

```bash
ssh -f -N -L 15432:<rds_host>:5432 torpedo.cuemath.com -i ~/.ssh/id_ed25519
```

3. Run the query:

```bash
PGOPTIONS='-c statement_timeout=300000' PGPASSWORD=$DB_PASSWORD psql -h localhost -p 15432 -U dbadmin -d <db_name> -c "<query>"
```

4. Always kill the tunnel when done:

```bash
kill $(lsof -ti:15432)
```

## Query Guardrails

- NEVER run `SELECT * FROM <table>` without a `WHERE` clause — ask the user for confirmation first
- Use `COUNT`/aggregates when the user asks "how many" — don't fetch and count rows
- NEVER hardcode the database password — always use `$DB_PASSWORD`
- Always kill the SSH tunnel after the query session

Do NOT:

- Over-explain each step
- Ask for confirmation between steps (except for the guardrails above)
- Offer follow-up suggestions
