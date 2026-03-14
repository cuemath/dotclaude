---
name: redshift-query
description: Query Cuemath Redshift event tables (leap_events, leap_teacher_events, live_events) to diagnose issues
allowed-tools: Bash(ssh *), Bash(PGOPTIONS=*), Bash(kill *), Bash(lsof *), Bash(which *), Bash(find *), Bash(ls *), Read, Grep
argument-hint: "[query or question about events]"
---

# Redshift Query

Query Cuemath Redshift event analytics tables via SSH tunnel to diagnose issues by checking events.

## Connection Details

SSH tunnel through `torpedo.cuemath.com`, local port: `15439`.
DB user: `dbadmin`, password: `$REDSHIFT_PASSWORD` env var. Database: `cuemath`.

### User Config

**First, read `~/.claude/config.json`** to get the user's saved settings. Use `user.ssh_user`, `user.ssh_key`, and `redshift.redshift_password_env` fields.

If the config file doesn't exist or is missing these fields, ask the user for ALL missing fields at once and create/update `~/.claude/config.json`. This file is user-local (not in the shared skills directory) and shared across skills. The SSH username pattern is typically `firstnamelastname`.

```json
{
  "user": {
    "ssh_user": "firstnamelastname",
    "ssh_key": "~/.ssh/id_rsa"
  },
  "redshift": {
    "redshift_password_env": "REDSHIFT_PASSWORD"
  }
}
```

### psql Binary

`psql` may not be on `$PATH`. If `which psql` fails, find it:

```bash
which psql 2>/dev/null || find /opt/homebrew -name "psql" -type f 2>/dev/null | head -1
```

Use the full path to `psql` in all subsequent commands.

### REDSHIFT_PASSWORD

The `$REDSHIFT_PASSWORD` env var must be available in the Bash tool's shell. If the connection fails with "no password supplied", ask the user to provide the password directly so it can be passed inline as `PGPASSWORD=<password>`.

## Tables

All tables are in the `event_analytics` schema.

### Table Selection Guide

| Table                                 | App                              | Data Window        | Use When                                   |
| ------------------------------------- | -------------------------------- | ------------------ | ------------------------------------------ |
| `event_analytics.leap_events`         | leap-student                     | All historical     | Diagnosing student-side issues             |
| `event_analytics.leap_teacher_events` | leap-teacher                     | All historical     | Diagnosing teacher-side issues             |
| `event_analytics.live_events`         | Both leap-student & leap-teacher | Last 24 hours only | Checking recent/live issues for either app |

**Always prefer `live_events` when investigating issues from the last 24 hours** — it's smaller and faster. Fall back to `leap_events` or `leap_teacher_events` for older data.

### Schema: `event_analytics.leap_events` (leap-student)

| Column             | Type                        |
| ------------------ | --------------------------- |
| event_epoch        | bigint                      |
| event_ts           | timestamp without time zone |
| datestr            | varchar(10)                 |
| timezone           | varchar(50)                 |
| environment        | varchar(50)                 |
| app_id             | varchar(50)                 |
| app_version        | varchar(50)                 |
| user_type          | varchar(50)                 |
| user_id            | varchar(40)                 |
| guest_id           | varchar(36)                 |
| session_id         | varchar(64)                 |
| event_id           | varchar(100)                |
| event_name         | varchar(255)                |
| attributes         | super                       |
| browser_name       | varchar(100)                |
| os_name            | varchar(100)                |
| platform           | varchar(100)                |
| country            | varchar(100)                |
| city               | varchar(100)                |
| device             | varchar(100)                |
| server_epoch       | bigint                      |
| event_ts_ist       | timestamp without time zone |
| ip_addresses       | varchar(200)                |
| app_build_number   | bigint                      |
| student_service_id | varchar(40)                 |
| intelenrollment_id | varchar(40)                 |

### Schema: `event_analytics.leap_teacher_events` (leap-teacher)

| Column           | Type                        |
| ---------------- | --------------------------- |
| event_epoch      | bigint                      |
| event_ts         | timestamp without time zone |
| datestr          | varchar(10)                 |
| timezone         | varchar(50)                 |
| environment      | varchar(50)                 |
| app_id           | varchar(50)                 |
| app_version      | varchar(50)                 |
| user_type        | varchar(50)                 |
| user_id          | varchar(36)                 |
| guest_id         | varchar(36)                 |
| session_id       | varchar(36)                 |
| event_id         | varchar(36)                 |
| event_name       | varchar(255)                |
| attributes       | super                       |
| browser_name     | varchar(100)                |
| os_name          | varchar(100)                |
| platform         | varchar(100)                |
| country          | varchar(100)                |
| city             | varchar(100)                |
| device           | varchar(100)                |
| server_epoch     | bigint                      |
| event_ts_ist     | timestamp without time zone |
| ip_addresses     | varchar(200)                |
| app_build_number | bigint                      |

### Schema: `event_analytics.live_events` (both apps, last 24h)

| Column           | Type                        |
| ---------------- | --------------------------- |
| event_epoch      | bigint                      |
| timezone         | varchar(50)                 |
| environment      | varchar(50)                 |
| app_id           | varchar(50)                 |
| app_version      | varchar(50)                 |
| user_type        | varchar(50)                 |
| user_id          | varchar(36)                 |
| guest_id         | varchar(36)                 |
| session_id       | varchar(36)                 |
| event_id         | varchar(36)                 |
| event_name       | varchar(255)                |
| attributes       | super                       |
| browser_name     | varchar(100)                |
| os_name          | varchar(100)                |
| platform         | varchar(100)                |
| country          | varchar(100)                |
| city             | varchar(100)                |
| device           | varchar(100)                |
| server_timestamp | bigint                      |
| ip_addresses     | varchar(200)                |
| app_build_number | bigint                      |
| event_ts_ist     | timestamp without time zone |

### Querying the `attributes` column

The `attributes` column is a Redshift `SUPER` type (semi-structured JSON). Access nested fields using dot notation:

```sql
-- Extract a top-level attribute
SELECT attributes.screen_name FROM event_analytics.leap_events WHERE ...

-- Use in WHERE clause
SELECT * FROM event_analytics.leap_events WHERE attributes.screen_name = 'HomeScreen' AND event_ts_ist BETWEEN '2026-03-14 00:00:00' AND '2026-03-14 23:59:59' LIMIT 10;

-- Cast if needed for comparison
SELECT * FROM event_analytics.leap_events WHERE attributes.class_id::varchar = '12345' AND event_ts_ist BETWEEN '2026-03-14 00:00:00' AND '2026-03-14 23:59:59' LIMIT 10;
```

### Query Performance Tips

- **Do NOT use `datestr`** — it is in UTC while `event_ts_ist` is in IST. For early-morning IST classes (before ~05:30 IST), the UTC date is the previous day, causing `datestr` filters to silently miss rows. Use `event_ts_ist` range instead.
- **Use `LIMIT`** on exploratory queries.
- **Use `event_ts_ist`** for IST timestamps (available in `leap_events` and `leap_teacher_events`, not in `live_events`).
- **Use `app_id`** to distinguish between apps in `live_events` (e.g., `app_id = 'leap.cuemath.com'` or `app_id = 'leap-teacher.cuemath.com'`).

## Steps

1. Read `~/.claude/config.json` to get SSH credentials and Redshift password env var.

2. Find the psql binary (see "psql Binary" section above). Store the path for use in step 4.

3. Kill any leftover tunnel on port 15439 from a previous run, then open a fresh one:

```bash
kill $(lsof -ti:15439) 2>/dev/null; ssh -f -N -L 15439:cuemath.cmiz7uaqdyex.ap-southeast-1.redshift.amazonaws.com:5439 <user.ssh_user>@torpedo.cuemath.com -i <user.ssh_key>
```

4. Run the query (use the full psql path from step 2):

```bash
PGOPTIONS='-c statement_timeout=600000' PGPASSWORD=$REDSHIFT_PASSWORD <psql_path> -h localhost -p 15439 -U dbadmin -d cuemath -c "<query>"
```

5. Always kill the tunnel when done:

```bash
kill $(lsof -ti:15439) 2>/dev/null
```

## Student ID in `leap_events`

In `leap_events`, `user_id` is the `student_service_id`, NOT the student DB ID. The student DB ID (commonly called `student_id`, or found in `leap_teacher_events` `attributes.studentId`) maps to the `intelenrollment_id` column.

**Always query `leap_events` and `live_events` (when `app_id='leap.cuemath.com'`) using both columns** to match regardless of ID type:

```sql
WHERE (user_id = '<id>' OR intelenrollment_id = '<id>')
```

`leap_teacher_events` does NOT have `intelenrollment_id` — always use `user_id` there.

## Mandatory Query Filters

Every query MUST include:

1. **User identifier:**
   - **`leap_teacher_events`**: `WHERE user_id = '<teacher_id>'`
   - **`leap_events`**: `WHERE (user_id = '<id>' OR intelenrollment_id = '<id>')` — always use the OR pattern
2. **`event_ts_ist` range** — always scope to the classroom session window:
   - **Student (leap_events / live_events with app_id='leap.cuemath.com')**: `event_ts_ist BETWEEN <class_start_time> AND <class_start_time + 1 hour>`
   - **Teacher (leap_teacher_events / live_events with app_id='leap-teacher.cuemath.com')**: `event_ts_ist BETWEEN <class_start_time - 5 minutes> AND <class_start_time + 1 hour>`

Ask the user for the student/teacher ID and `class_start_time` if not provided.

Example:

```sql
-- Student events (always use OR pattern for ID)
SELECT event_name, event_ts_ist, attributes
FROM event_analytics.leap_events
WHERE (user_id = 'abc123' OR intelenrollment_id = 'abc123')
  AND event_ts_ist BETWEEN '2026-03-14 16:00:00' AND '2026-03-14 17:00:00'
ORDER BY event_ts_ist
LIMIT 200;

-- Teacher events (user_id is always the teacher DB ID)
SELECT event_name, event_ts_ist, attributes
FROM event_analytics.leap_teacher_events
WHERE user_id = 'teacher456'
  AND event_ts_ist BETWEEN '2026-03-14 15:55:00' AND '2026-03-14 17:00:00'
ORDER BY event_ts_ist
LIMIT 200;
```

## Classroom Event Analysis

When diagnosing a class issue (invoked with a `user_id`, `user_type`, `class_date`, and `class_time_ist`), follow this structured approach:

### Step 1 — Get event names and timestamps (lightweight scan)

```sql
-- For teachers:
SELECT event_name, event_ts_ist
FROM event_analytics.leap_teacher_events
WHERE user_id = '<teacher_id>'
  AND event_ts_ist BETWEEN '<start>' AND '<end>'
ORDER BY event_ts_ist
LIMIT 300;

-- For students (always use OR pattern):
SELECT event_name, event_ts_ist
FROM event_analytics.leap_events
WHERE (user_id = '<student_id>' OR intelenrollment_id = '<student_id>')
  AND event_ts_ist BETWEEN '<start>' AND '<end>'
ORDER BY event_ts_ist
LIMIT 300;
```

Table selection: use `leap_teacher_events` for teachers, `leap_events` for students. Prefer `live_events` if the class was within the last 24 hours.

Time window: Teacher = `class_time - 5 min` to `class_time + 1 hour`. Student = `class_time` to `class_time + 1 hour`.

If no results, broaden to the full day to find when the user was actually active:

```sql
-- For teachers:
SELECT event_name, event_ts_ist
FROM event_analytics.leap_teacher_events
WHERE user_id = '<teacher_id>'
  AND event_ts_ist BETWEEN '<class_date> 00:00:00' AND '<class_date> 23:59:59'
ORDER BY event_ts_ist
LIMIT 50;

-- For students:
SELECT event_name, event_ts_ist
FROM event_analytics.leap_events
WHERE (user_id = '<student_id>' OR intelenrollment_id = '<student_id>')
  AND event_ts_ist BETWEEN '<class_date> 00:00:00' AND '<class_date> 23:59:59'
ORDER BY event_ts_ist
LIMIT 50;
```

### Step 2 — Get full attributes for all relevant events

Fetch all events excluding the noisy ones listed in "Events to Exclude":

```sql
-- For teachers:
SELECT event_name, event_ts_ist, attributes
FROM event_analytics.leap_teacher_events
WHERE user_id = '<teacher_id>'
  AND event_ts_ist BETWEEN '<start>' AND '<end>'
  AND event_name NOT ILIKE 'talk\_calculator\_%'
  AND event_name NOT ILIKE 'talk\_meter\_%'
  AND event_name NOT IN ('TEACHER_SPEAKING_TIME', 'STUDENT_SPEAKING_TIME')
ORDER BY event_ts_ist
LIMIT 300;

-- For students (always use OR pattern):
SELECT event_name, event_ts_ist, attributes
FROM event_analytics.leap_events
WHERE (user_id = '<student_id>' OR intelenrollment_id = '<student_id>')
  AND event_ts_ist BETWEEN '<start>' AND '<end>'
  AND event_name NOT ILIKE 'talk\_calculator\_%'
  AND event_name NOT ILIKE 'talk\_meter\_%'
  AND event_name NOT IN ('TEACHER_SPEAKING_TIME', 'STUDENT_SPEAKING_TIME')
ORDER BY event_ts_ist
LIMIT 300;
```

### Event Name Reference

#### App Lifecycle

- **`component_mounted`** with `attributes.component = 'App'` — App was reloaded or freshly opened. Multiple occurrences indicate the user retried/refreshed.

#### PubNub (Messaging via `mjq` package)

PubNub events use three prefixes: `CHANNEL_*`, `PUBLISH_*`, `SUBSCRIBER_*`. Multiple publish/subscribe failures indicate the platform messaging is broken — check `attributes` for failure reasons.

#### AV (Audio/Video)

AV events follow the naming convention `av_*`, `media_*`, `cue_*`, or `ivs_*`. The provider is identified by `attributes.provider`:

- `'cuecall'` — Cuemath's own calling system
- `'ivs'` — Amazon IVS
- `'tokbox'` — Vonage/TokBox

#### Critical Script Loading

These scripts are **required for the platform to function** — the app will not work without them. Each has a family of events with suffixes like `_loading`, `_loaded`, `_failed`, `_fallback_failed`:

- **`mathjax_script_*`** — MathJax rendering engine (e.g., `mathjax_script_loading`, `mathjax_script_loaded`, `mathjax_script_failed`)
- **`av_sdk_*`** — AV SDK loading for TokBox or IVS (e.g., `av_sdk_loading`, `av_sdk_loaded`, `av_sdk_loading_failed`)
- **`worksheet_v3_script_*`** — Learnosity worksheet/assessment script (e.g., `worksheet_v3_script_loading`, `worksheet_v3_script_loaded`, `worksheet_v3_script_failed`, `worksheet_v3_script_fallback_failed`)

#### Events to Exclude

Noisy events — filter these out in queries. Add to this list as needed:

```
talk_calculator_%
talk_meter_%
TEACHER_SPEAKING_TIME
STUDENT_SPEAKING_TIME
```

#### Classroom Entry

- **`av_call_requested`** — Fired when "Enter Class" is clicked.

#### User Interactions

- **`clicked`** — Fired when any clickable element is tapped. `attributes.name` contains the button/element name.
- **`page_viewed`** — Fired when a page is viewed. `attributes.page_name` identifies which page, `attributes.pattern` contains the route pattern.

### Key event patterns

| Event                                                                                                                      | Indicates                                                       |
| -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `av_sdk_loading_failed`                                                                                                    | AV SDK (TokBox/IVS) could not load — network issue or CDN block |
| `CHANNEL_*_FAILED` events (e.g., `CHANNEL_METADATA_FETCH_FAILED`, `CHANNEL_TIMETOKEN_FETCH_FAILED`, `CHANNEL_INIT_FAILED`) | PubNub messaging failed — network issue                         |
| `CHANNEL_GOT_STATUS_EVENT` with `PNNetworkIssuesCategory` in attributes                                                    | Confirmed network connectivity problem                          |
| `CHANNEL_RECONNECTION_TIMEOUT`                                                                                             | PubNub gave up reconnecting — prolonged network loss            |
| `PUBLISH_POST_FAILED`                                                                                                      | Message send failed — check `attributes` for reason             |
| `SUBSCRIBER_RETRY_FAILED`                                                                                                  | Subscriber retry exhausted — messaging is broken                |
| `mathjax_script_failed`                                                                                                    | MathJax failed to load — math rendering will not work           |
| `worksheet_v3_script_failed` + `worksheet_v3_script_fallback_failed`                                                       | Learnosity CDN unreachable — worksheets will not work           |
| `media_manager_destroyed` without preceding `av_session_connected`                                                         | AV never connected before being torn down                       |
| Multiple `component_mounted` (with `attributes.component='App'`) repeating                                                 | User reloading the app — retrying due to failures               |
| `av_call_requested` without subsequent `av_session_connected`                                                              | User clicked "Enter Class" but AV never connected               |
| `SCREEN_DIMENSIONS` changes                                                                                                | User may have switched devices                                  |

### Correlation rules

- If AV, PubNub, AND worksheet scripts all failed → almost certainly a **user-side network issue**
- If only AV failed but PubNub works → likely a **provider-specific issue** (Tokbox/IVS CDN)
- If issues are on one side only (teacher but not student, or vice versa) → **user-side problem**
- If both teacher and student have the same failures → **platform-side issue**
- Count app reload attempts to gauge severity and duration of impact

## Query Guardrails

- NEVER run `SELECT *` without `WHERE` clause or `LIMIT` — these tables are massive
- ALWAYS include user identifier and `event_ts_ist` range — see Mandatory Query Filters above
- Use `COUNT`/aggregates when the user asks "how many" — don't fetch and count rows
- NEVER hardcode the database password — always use `$REDSHIFT_PASSWORD`
- Always kill the SSH tunnel after the query session. Do not ask whether to run this command or not.

Do NOT:

- Over-explain each step
- Ask for confirmation between steps (except for the guardrails above)
- Offer follow-up suggestions
