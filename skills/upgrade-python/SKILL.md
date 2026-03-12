---
name: upgrade-python
description: Upgrade current Python microservice from 3.7 to 3.13. Analyzes the service, generates an upgrade doc, then applies all changes.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(source *), Bash(pip *), Bash(python *), Bash(ENV=*), Bash(mkdir *), Bash(ls *), Bash(gh pr *), Bash(kill *), Bash(aws codebuild*), Bash(docker build*), Bash(deactivate*)
argument-hint: "[analyze|apply]"
---

# Upgrade Python Microservice (3.7 → 3.13)

## Context

You are upgrading the current service from Python 3.7 to 3.13.

**Service name:** `!`basename $(pwd)``
**Current branch:** `!`git branch --show-current``
**Current Dockerfile:**
```
!`cat Dockerfile 2>/dev/null || echo "NO_DOCKERFILE"`
```
**Current requirements:**
```
!`cat requirements.txt 2>/dev/null || cat prod_requirements.txt 2>/dev/null || echo "NO_REQUIREMENTS"`
```
**Current manage.py:**
```
!`cat manage.py 2>/dev/null || echo "NO_MANAGE_PY"`
```
**Existing analysis doc:**
```
!`cat docs/python-3.13-upgrade.md 2>/dev/null || echo "NO_ANALYSIS_DOC"`
```

Refer to the **Reference** section at the bottom of this file for base image contents, code change patterns, and version tables.

---

## Phase Selection

- If `$ARGUMENTS` contains "analyze", or no analysis doc exists (`NO_ANALYSIS_DOC` above) → run **Phase 1**
- If `$ARGUMENTS` contains "apply", or analysis doc already exists → run **Phase 2**
- If neither, and analysis doc exists → tell the user and ask whether to re-analyze or apply

---

## Phase 1: Analyze

Generate the upgrade analysis document.

### Steps

1. **Scan the service** — read Dockerfile, requirements.txt (or prod_requirements.txt), manage.py, and all Python files under `app/`.

2. **Run the upgrade audit** — execute every grep in the table below against `app/` and `requirements.txt`. Record hits for the analysis doc.

   Run **every** row. For each, record the pattern ID, hit count, and file:line list. Zero-hit patterns confirm no action needed. Include all results in the analysis doc section 3.

   **A. Flask-Script / manage.py**

   | ID | Grep Command | If Found |
   |---|---|---|
   | A1 | `grep -rn 'flask_script\|from flask_script' app/ manage.py` | manage.py rewrite needed |
   | A2 | `grep -rn 'MigrateCommand' app/ manage.py` | manage.py rewrite needed |

   **B. Flask 3 / Werkzeug 3**

   | ID | Grep Command | If Found |
   |---|---|---|
   | B1 | `grep -rn 'from flask_sqlalchemy import BaseQuery' app/` | Replace with `from flask_sqlalchemy.query import Query` |
   | B2 | `grep -rn 'flask\.ext\.' app/` | Dead import, remove |
   | B3 | `grep -rn 'JSONEncoder' app/` | Remove custom encoder (Flask 3 native) |
   | B4 | `grep -rn 'json_encoder' app/` | Remove `app.json_encoder =` assignment |
   | B5 | `grep -rn 'flask_profiler\|Profiler(' app/` | Remove entirely (unmaintained) |

   **C. Werkzeug 3 — RequestParser**

   | ID | Grep Command | If Found |
   |---|---|---|
   | C1 | `grep -rn 'add_argument(' app/` | **Audit EVERY hit** — must have explicit `location=` |
   | C2 | `grep -rn 'add_argument(' app/ \| grep -v 'location='` | Missing `location=` — MUST FIX |
   | C3 | `grep -rn 'FileStorage' app/` | Check companion args use `location="form"` not `["json", "form"]` |

   **D. SQLAlchemy**

   | ID | Grep Command | If Found |
   |---|---|---|
   | D1 | `grep -rn 'engine\.execute(' app/` | Replace with context manager + `text()` |
   | D2 | `grep -rn 'MutableDict\|MutableList' app/` | Replace with `flag_modified()` |
   | D3 | `grep -rn '_mapper_zero' app/` | Replace with `column_descriptions[0]['entity']` |
   | D4 | `grep -rn '\.query\.get(' app/` | Replace with `db.session.get()` |

   **E. Python 3.13 stdlib**

   | ID | Grep Command | If Found |
   |---|---|---|
   | E1 | `grep -rn 'datetime\.utcnow\|datetime\.utcfromtimestamp' app/` | Replace with timezone-aware alternatives |
   | E2 | `grep -rn 'collections\.Mapping\|collections\.MutableMapping' app/` | Use `collections.abc` |
   | E3 | `grep -rn '_weakrefset' app/` | Use `from weakref import WeakSet` |
   | E4 | `grep -rn 'from __future__ import with_statement' app/` | Dead code, remove |
   | E5 | `grep -rn 'cached_property' app/ \| grep -v functools` | Replace with `functools.cached_property` |

   **F. Removed packages**

   | ID | Grep Command | If Found |
   |---|---|---|
   | F1 | `grep -rn 'import raven\|from raven' app/` | Remove (replaced by sentry-sdk) |
   | F2 | `grep -rn 'import six\|from six' app/` | Replace with builtins |
   | F3 | `grep -rn 'import boto[^3]\|from boto[^3]' app/` | Must upgrade to boto3 |
   | F4 | `grep -rn 'S3FileUploadField\|flask_admin_s3_upload' app/` | Remove (boto v2 dep) |

   **G. Sentry**

   | ID | Grep Command | If Found |
   |---|---|---|
   | G1 | `grep -rn 'configure_scope' app/` | Replace with `sentry_sdk.set_tag()` |
   | G2 | `grep -rn 'sentry_sdk\.init' app/` | Verify has `FlaskIntegration()` |

   **H. Redis**

   | ID | Grep Command | If Found |
   |---|---|---|
   | H1 | `grep -rn 'encoder\.__dict__' app/` | Use explicit attr access (redis 5.x `__slots__`) |

   **I. Marshmallow**

   | ID | Grep Command | If Found |
   |---|---|---|
   | I1 | `grep -rn '\.dump(.*\.data\|Meta.*strict' app/` | Marshmallow 2→3 migration needed |
   | I2 | `grep -rn 'class.*Schema\|@dataclass\|class_schema' app/` | Check for `unknown = EXCLUDE` on deserializing schemas |

   **J. Async workers**

   | ID | Grep Command | If Found |
   |---|---|---|
   | J1 | `grep -rn 'SQSListener\|sqs_listener\|handle_message' app/` | Needs `app.app_context()` wrapping |

   **K. PynamoDB**

   | ID | Grep Command | If Found |
   |---|---|---|
   | K1 | `grep -rln 'from pynamodb.models import Model' app/` | Check for serialize/deserialize method collisions |
   | K2 | `grep -rn 'def serialize\|def deserialize' app/` | Rename if on PynamoDB model (collides with PynamoDB 6) |

   **L. Requirements**

   | ID | Grep Command | If Found |
   |---|---|---|
   | L1 | `grep -n 'https://' requirements.txt prod_requirements.txt 2>/dev/null` | cp37 wheel URLs — replace with PyPI pins |
   | L2 | `grep -n 'sqlakeyset' requirements.txt prod_requirements.txt 2>/dev/null` | Verify actually imported; remove if unused |

3. **Check requirements.txt** for:
   - Packages already included in the base image (see Reference section below for list)
   - Packages with no Python 3.13 wheel (check against reference.md known-incompatible list)
   - `flask-script` → must remove
   - `raven` → must remove
   - `boto==` (v2) → must remove/replace
   - `flask-profiler` → must remove (unmaintained, incompatible with Flask 3)
   - `sqlakeyset` → check if actually imported; remove if unused
   - `flask_admin_s3_upload` → uses boto v2, must remove (also remove dependent admin views/forms)
   - cp37 `.whl` file URLs → replace with standard PyPI package pins
   - Unused packages (audit imports before keeping) — e.g., `Flask-Mail`, `humanize`, `natsort`, `requests-oauthlib` were removed from inteladmingateway as unused

4. **Check internal package dependencies** — which of cachehandler, authhandler, cueutil, publishsubscribe, requestlogger, servicecaller does this service use?

5. **Create `docs/python-3.13-upgrade.md`** following this structure:

```markdown
# Python 3.13 Upgrade Analysis — `{service_name}` Microservice

**Date:** {today}
**Service:** `{service_name}`
**Upgrade path:** Python 3.7 → 3.13

---

## Summary of Changes

{Brief paragraph listing all required changes}

---

## 1. Base Image Change

| Item | Current | Target |
|---|---|---|
| Dockerfile `FROM` | {current base image} | `484426514402.dkr.ecr.ap-southeast-1.amazonaws.com/flask-sqlalchemy:supervisor-python3.13` |
| Python version | 3.7 | 3.13 |

---

## 2. Dependency Table

| Package | Current Version | Target Version | Notes |
|---|---|---|---|
| ... | ... | ... | ... |

**Removed packages:** {list packages to remove and why}
**Internal packages:** {list git packages and their status}

---

## 3. Required Code Changes

### 3.1 {Change title} — {RISK LEVEL}

**File:** `{path}`
**Why:** {reason}

**Before:**
\`\`\`python
{current code}
\`\`\`

**After:**
\`\`\`python
{replacement code}
\`\`\`

---

## 4. Risk Assessment

| Change | Risk | Mitigation |
|---|---|---|
| ... | LOW/MEDIUM/HIGH | ... |

---

## 5. Testing Checklist

- [ ] `pip install -r requirements.txt` succeeds (Python 3.13 venv)
- [ ] App starts without import errors
- [ ] Health check endpoint responds
- [ ] Unit tests pass (if applicable)
- [ ] Docker build succeeds locally
- [ ] DB migrations run
- [ ] Deploy to testenv and verify
```

6. **Stop and show the user** a summary. Ask them to review `docs/python-3.13-upgrade.md` before proceeding to Phase 2.

---

## Phase 2: Apply

Apply all changes from the analysis document.

### Steps

1. **Verify environment:** Ensure `ENV` is set to `local` (or unset). Abort if pointed at staging/production.

2. **Create upgrade branch:**

```bash
git checkout master && git pull
git checkout -b python-3.13-upgrade
```

If branch already exists, check it out instead.

3. **Update Dockerfile** — change only the FROM line to:

```
FROM 484426514402.dkr.ecr.ap-southeast-1.amazonaws.com/flask-sqlalchemy:supervisor-python3.13
```

Leave everything else (COPY, WORKDIR, ENTRYPOINT) untouched.

4. **Update requirements.txt** — apply all changes from the analysis doc. All services use `requirements.txt` as the source of truth (the build pipeline generates `prod_requirements.txt` from it):
   - Upgrade pinned versions to 3.13-compatible versions per the dependency table
   - Remove deprecated packages (flask-script, raven, boto v2, etc.)
   - Remove packages already in the base image (see Reference section below for the full list — includes Flask, SQLAlchemy, Werkzeug, gevent, greenlet, psycopg2-binary, Flask-RESTful, Flask-Admin, WTForms, SQLAlchemy-Utils, OpenTelemetry stack, and more)
   - Keep internal git packages (cueutil, publishsubscribe, requestlogger, servicecaller, cachehandler, authhandler)
   - Keep transitive deps needed by internal packages (boto3, requests, etc.)
   - Add section comments like the economy service uses

5. **Rewrite manage.py** — replace flask-script with Flask CLI:
   - Use `FlaskGroup` + `click` pattern
   - Preserve any custom commands (test, seed, etc.)
   - Do NOT add a custom `runserver` command — Flask CLI provides `flask run` natively
   - Reference economy's manage.py at `/Users/shubham.vats/workspace/microservices/economy/manage.py`

6. **Apply all code changes** listed in the analysis doc section 3, in order of risk:
   - **LOW first:** `from __future__` removal, `raven` removal, dead import cleanup
   - **MEDIUM next:** `datetime.utc*` replacements, `engine.execute()` → context manager, `six` removal, `cached_property` stdlib swap
   - **HIGH last:** `BaseQuery` replacement, marshmallow 2→3 migration, `MutableDict`/`MutableList` replacement
   - **Async workers:** Check `app/asyncapi/` or `app/async/` or `app/utils/sqs_listener.py` — wrap `handle_message` body and `listener.listen()` with `with app.app_context():` if not already wrapped (flask-script auto-pushed context; Flask CLI does not)
   - When removing a URL-routed package (e.g., flask-profiler), also search for references to its URL paths in bypass/whitelist arrays (e.g., `bypass_paths` in `request_gateway.py`) and remove those entries

7. **Local Testing (venv):**

```bash
# a. Activate shared Python 3.13 venv
# NOTE: Adjust this path if your Python 3.13 venv is in a different location
source ~/workspace/virtualenvs/python3_13/bin/activate

# b. Install dependencies
pip install -r requirements.txt

# c. Verify app starts and routes load
ENV=local python -c "from app import app; [print(r.rule, r.methods) for r in app.url_map.iter_rules()]"

# d. Run unit tests (if they exist)
ENV=testing python manage.py test
# If no test command exists or tests dir is missing, skip and note it.

# e. Deactivate venv
deactivate
```

Report pass/fail for each sub-step before proceeding.

8. **Local Docker Build:**

```bash
# a. Build the Docker image locally
docker build -t {service_name}:python3.13 .
```

Report whether the build succeeded or failed. If failed, fix the issues and retry.

9. **Deploy to TestEnv:**

Ask the user for their testenv number (e.g., `testenv37`). Then:

```bash
# a. Build the Docker image for the branch using CodeBuild
aws codebuild start-build \
  --project-name ms-build-image \
  --environment-variables-override \
    "name=service,value={service_name},type=PLAINTEXT" \
    "name=servicebranch,value=python-3.13-upgrade,type=PLAINTEXT" \
  --region ap-southeast-1

# b. Wait for the build to complete (poll or tell user to monitor the console URL)

# c. Deploy the built image to testenv
aws codebuild start-build \
  --project-name testenv-update \
  --environment-variables-override \
    "name=testenv_name,value={testenv_number},type=PLAINTEXT" \
    "name=microservices,value={service_name}:python-3.13-upgrade,type=PLAINTEXT" \
  --region ap-southeast-1
```

Output the AWS Console URLs for both builds so the user can monitor. Tell user to verify the service at `https://www.{testenv_number}.cuemath.com`.

10. **Commit and push:**

```bash
git add -A
git commit -m "Upgrade {service_name} to Python 3.13

- Replace base image with flask-sqlalchemy:supervisor-python3.13
- Upgrade all dependencies to 3.13-compatible versions
- Rewrite manage.py from flask-script to Flask CLI
- Apply code fixes per docs/python-3.13-upgrade.md"
git push -u origin python-3.13-upgrade
```

11. **Create PR:**

```bash
gh pr create --title "Upgrade {service_name} to Python 3.13" --body "$(cat <<'EOF'
## Summary

Upgrades {service_name} from Python 3.7 to Python 3.13.

### Changes
- Base image → `flask-sqlalchemy:supervisor-python3.13`
- All dependencies upgraded to 3.13-compatible versions
- `manage.py` rewritten from flask-script to Flask CLI
- Code fixes applied per `docs/python-3.13-upgrade.md`

### Testing
- [ ] `pip install -r requirements.txt` — passes
- [ ] App starts without import errors
- [ ] Health check endpoint responds
- [ ] Unit tests pass (if applicable)
- [ ] Docker build succeeds locally
- [ ] DB migrations run
- [ ] Deploy to testenv and verify

See `docs/python-3.13-upgrade.md` for full analysis.
EOF
)"
```
---

## Do NOT

- Over-explain each step
- Skip the analysis phase — always generate/verify the doc first
- Apply changes without a written analysis doc
- Remove packages that internal packages depend on (boto3, requests, six if still needed by botocore)
- Make changes beyond what the analysis doc specifies
- Proceed from Phase 1 to Phase 2 without user confirmation
- Modify the base image's pre-installed packages in requirements.txt (they're already there)

---

# Reference

## Base Image Contents

Image: `484426514402.dkr.ecr.ap-southeast-1.amazonaws.com/flask-sqlalchemy:supervisor-python3.13`

### Pre-installed System Packages (Alpine)
- supervisor, nginx, bash, curl, git, gcc, musl-dev, libffi-dev, openssl-dev

### Pre-installed Python Packages (DO NOT add to requirements.txt)

**Core Infrastructure:**
| Package | Version |
|---|---|
| supervisor | 4.2.5 |
| greenlet | 3.1.1 |
| gevent | 24.11.1 |
| psycopg2-binary | 2.9.10 |
| psycogreen | 1.0.2 |

**Flask Web Framework:**
| Package | Version |
|---|---|
| Flask | 3.0.0 |
| Werkzeug | 3.0.1 |
| Jinja2 | 3.1.3 |
| MarkupSafe | 2.1.3 |

**Database ORM:**
| Package | Version |
|---|---|
| SQLAlchemy | 1.4.53 |
| Flask-SQLAlchemy | 3.0.5 |
| Flask-Migrate | 4.0.5 |
| Alembic | 1.13.1 |
| Mako | 1.3.0 |
| python-editor | 1.0.4 |
| SQLAlchemy-Utils | 0.41.1 |
| sqlalchemy-migrate | 0.13.0 |
| Tempita | 0.5.2 |
| sqlparse | 0.4.4 |

**Flask Extensions:**
| Package | Version |
|---|---|
| flask-restful | 0.3.10 |
| aniso8601 | 9.0.1 |
| pytz | 2024.1 |
| flask-admin | 1.6.1 |
| wtforms | 3.1.2 |
| WTForms-Alchemy | 0.18.0 |
| WTForms-Components | 0.10.5 |
| validators | 0.22.0 |

**Compression & Serialization:**
| Package | Version |
|---|---|
| lz4 | 4.3.3 |
| msgpack | 1.1.2 |

**OpenTelemetry Instrumentation:**
| Package | Version |
|---|---|
| opentelemetry-api | 1.22.0 |
| opentelemetry-sdk | 1.22.0 |
| opentelemetry-instrumentation | 0.43b0 |
| opentelemetry-exporter-otlp-proto-http | 1.22.0 |
| opentelemetry-instrumentation-urllib | 0.43b0 |
| opentelemetry-instrumentation-flask | 0.43b0 |
| opentelemetry-instrumentation-botocore | 0.43b0 |
| opentelemetry-instrumentation-jinja2 | 0.43b0 |
| opentelemetry-instrumentation-psycopg2 | 0.43b0 |
| opentelemetry-instrumentation-redis | 0.43b0 |
| opentelemetry-instrumentation-requests | 0.43b0 |
| opentelemetry-instrumentation-sqlalchemy | 0.43b0 |

If a service's requirements.txt pins any of these, **remove them** — the base image already provides them.

**Note:** `gunicorn` and `sentry-sdk` are NOT in the base image. Services that need them must include them in their own requirements.txt.

---

## Economy Service Reference (Successfully Upgraded)

### Dockerfile Pattern
Only change the `FROM` line. Leave everything else (COPY, WORKDIR, ENTRYPOINT) untouched — the build pipeline handles `prod_requirements.txt` generation from `requirements.txt`.

```dockerfile
# Change FROM line to:
FROM 484426514402.dkr.ecr.ap-southeast-1.amazonaws.com/flask-sqlalchemy:supervisor-python3.13
```

### requirements.txt Pattern
```
# --- AWS SDK and dependencies ---
boto3==1.35.71
botocore==1.35.71
python-dateutil==2.8.1
s3transfer==0.10.4
six==1.16.0

# --- HTTP Requests ---
requests==2.32.3
certifi==2024.8.30
chardet==5.2.0
idna==3.10
urllib3==2.2.3

# --- Gunicorn & Greenlet Support ---
gunicorn==23.0.0
psycogreen==1.0.2

# --- Sentry Error Tracking ---
sentry-sdk==2.18.0

# --- OAuth Support ---
oauthlib==3.1.0
requests-oauthlib==1.2.0

# --- Serialization & Validation ---
marshmallow==3.23.1

# --- Redis Client ---
redis==5.2.0

# --- Documentation Utilities ---
docutils==0.15.2

# --- Internal Repositories ---
git+https://techadmin_cuemath:${APP_PASSWORD}@bitbucket.org/cuelearn/cueutil.git
git+https://techadmin_cuemath:${APP_PASSWORD}@bitbucket.org/cuelearn/publishsubscribe.git
git+https://techadmin_cuemath:${APP_PASSWORD}@bitbucket.org/cuelearn/requestlogger.git
git+https://techadmin_cuemath:${APP_PASSWORD}@bitbucket.org/cuelearn/servicecaller.git
```

**Key notes:**
- `gunicorn` and `sentry-sdk` are NOT in the base image — they must be included in the service's requirements.txt if needed
- `six` is kept because `botocore` still depends on it
- Group packages by function with section comments
- Internal git packages always go at the bottom

### manage.py Pattern (Flask CLI)
```python
import click

from flask.cli import FlaskGroup

from app import app


def create_app():
    """Application factory for Flask CLI."""
    return app


@click.group(cls=FlaskGroup, create_app=create_app)
def cli():
    """Service management commands."""
    pass


if __name__ == "__main__":
    cli()
```

**Adaptation notes:**
- Do NOT add a custom `runserver` command — Flask CLI provides `flask run` natively
- Only import `Migrate` and `db` if the service has migrations:
  ```python
  from flask_migrate import Migrate
  from app import app, db
  migrate = Migrate(app, db)
  ```
- If the service has a `test` command, add it:
  ```python
  @cli.command()
  def test():
      """Run the unit tests."""
      import unittest
      tests = unittest.TestLoader().discover('./tests', pattern='*.py')
      result = unittest.TextTestRunner(verbosity=2).run(tests)
      if result.wasSuccessful():
          return 0
      return 1
  ```
- If the service has `seed`, `shell`, or other custom commands, preserve them using `@cli.command()`
- The `create_app` factory and `FlaskGroup` pattern ensures `flask db upgrade` works correctly

---

## Common Code Change Patterns

### 1. flask_script → Flask CLI
**Before:**
```python
from flask_script import Manager, Server
from flask_migrate import Migrate, MigrateCommand

manager = Manager(app)
manager.add_command('db', MigrateCommand)
manager.add_command("runserver", Server(...))

@manager.command
def test():
    ...

if __name__ == "__main__":
    manager.run()
```
**After:** See manage.py pattern above.

### 2. BaseQuery → flask_sqlalchemy.query.Query
**Before:**
```python
from flask_sqlalchemy import BaseQuery

class QueryWithSoftDelete(BaseQuery):
    ...
```
**After:**
```python
from flask_sqlalchemy.query import Query

class QueryWithSoftDelete(Query):
    ...
```

### 3. db.engine.execute() → context manager
**Before:**
```python
row = db.engine.execute("SELECT 1")
```
**After:**
```python
from sqlalchemy import text

with db.engine.connect() as conn:
    row = conn.execute(text("SELECT 1"))
```

### 4. datetime.utcnow() → datetime.now(UTC)
**Before:**
```python
from datetime import datetime
now = datetime.utcnow()
```
**After:**
```python
from datetime import datetime, timezone
now = datetime.now(timezone.utc)
```

**Note:** If the codebase stores naive datetimes (no timezone info) in the database, use `.replace(tzinfo=None)` to maintain backward compatibility:
```python
now = datetime.now(timezone.utc).replace(tzinfo=None)
```
This was the pattern used in inteladmingateway where existing DB columns expect naive UTC datetimes.

### 5. datetime.utcfromtimestamp() → fromtimestamp(tz=UTC)
**Before:**
```python
dt = datetime.utcfromtimestamp(ts)
```
**After:**
```python
from datetime import datetime, timezone
dt = datetime.fromtimestamp(ts, tz=timezone.utc)
```

### 6. Remove raven
**Before:**
```python
from raven.contrib.flask import Sentry
sentry = Sentry(app)
```
**After:** Remove entirely. `sentry-sdk` auto-instruments Flask via `sentry_sdk.init()`.

### 7. Remove from __future__ import with_statement
Just delete the line. It's a no-op in Python 3.

### 8. collections.Mapping → collections.abc.Mapping
**Before:**
```python
import collections
isinstance(x, collections.Mapping)
```
**After:**
```python
import collections.abc
isinstance(x, collections.abc.Mapping)
```

### 9. six.text_type → str
**Before:**
```python
from six import text_type
s = text_type(value)
```
**After:**
```python
s = str(value)
```

### 10. MutableDict/MutableList → flag_modified
**Before:**
```python
from sqlalchemy.ext.mutable import MutableDict, MutableList
meta = db.Column(MutableDict.as_mutable(JSON))
```
**After:**
```python
from sqlalchemy.orm.attributes import flag_modified
meta = db.Column(JSON)
# When mutating:
obj.meta['key'] = 'value'
flag_modified(obj, 'meta')
db.session.commit()
```

### 11. marshmallow 2.x → 3.x
Key breaking changes:
- `Schema.dump()` / `Schema.load()` no longer return `(data, errors)` tuples — they return data directly and raise `ValidationError`
- `Meta.strict = True` is removed (strict is always on in 3.x)
- `fields.FormattedString` → removed
- `Schema().dump(obj).data` → `Schema().dump(obj)`
- `@post_load` returns the object directly
- **Unknown fields rejected by default** — marshmallow 2.x silently ignored fields not defined in the schema; 3.x raises `ValidationError`. Any schema that deserializes data from DB JSONB columns, external APIs, or SQS messages must opt into ignoring unknown fields.

#### Unknown fields fix — `marshmallow_dataclass` / `class_schema` pattern
Common in our codebase when using `marshmallow_dataclass` or `marshmallow.class_schema()`:

**Before:**
```python
from marshmallow_dataclass import dataclass

@dataclass
class MonthlyProgressReportDTO:
    student_name: str
    total_classes: int
    # ...
```

**After:**
```python
from marshmallow import EXCLUDE
from marshmallow_dataclass import dataclass

@dataclass
class MonthlyProgressReportDTO:
    student_name: str
    total_classes: int
    # ...

    class Meta:
        unknown = EXCLUDE
```

#### Unknown fields fix — standard `Schema` subclass pattern
**Before:**
```python
from marshmallow import Schema, fields

class UserEventSchema(Schema):
    event_type = fields.String()
    timestamp = fields.DateTime()
```

**After:**
```python
from marshmallow import Schema, fields, EXCLUDE

class UserEventSchema(Schema):
    class Meta:
        unknown = EXCLUDE

    event_type = fields.String()
    timestamp = fields.DateTime()
```

**Which schemas need this:** Any schema that deserializes data where the source may contain fields not defined in the schema — DB JSONB columns, external API responses, SQS message bodies. Schemas used only for serialization (dump) or where the input is fully controlled do not need it.

### 12. configure_scope → new sentry-sdk API
**Before:**
```python
from sentry_sdk import configure_scope
with configure_scope() as scope:
    scope.set_tag("key", "value")
```
**After:**
```python
import sentry_sdk
sentry_sdk.set_tag("key", "value")
```

### 13. cached_property → functools.cached_property
**Before:**
```python
from app.utils.cached_property import cached_property
```
**After:**
```python
from functools import cached_property
```

### 14. Query.get() → session.get()
**Before:**
```python
user = User.query.get(user_id)
```
**After:**
```python
user = db.session.get(User, user_id)
```

### 15. Redis 5.x Encoder compatibility
In redis 5.x, `Encoder` uses `__slots__`. If any code accesses `encoder.__dict__`, replace with explicit attribute access:
```python
# Before
encoder_kwargs = encoder.__dict__
# After
encoder_kwargs = {
    'encoding': encoder.encoding,
    'encoding_errors': encoder.encoding_errors,
    'decode_responses': encoder.decode_responses,
}
```

### 16. `_weakrefset` → `weakref`
**Before:**
```python
from _weakrefset import WeakSet
```
**After:**
```python
from weakref import WeakSet
```

### 17. `_mapper_zero()` in soft-delete queries
**Before:**
```python
db.class_mapper(self._mapper_zero().class_)
```
**After:**
```python
self.column_descriptions[0]['entity']
```

### 18. flask-profiler removal
```python
# Remove import
from flask_profiler import Profiler
# Remove instantiation
profiler = Profiler(app)
# Also remove from requirements.txt and any URL bypass lists (e.g., bypass_paths in request_gateway.py)
```

### 19. sentry_sdk.init without FlaskIntegration
**Before:**
```python
sentry_sdk.init(app.config['SENTRY_DSN'])
```
**After:**
```python
from sentry_sdk.integrations.flask import FlaskIntegration
sentry_sdk.init(dsn=app.config['SENTRY_DSN'], integrations=[FlaskIntegration()])
```

### 20. RequestParser arguments without explicit location
In Werkzeug < 2.3, `request.json` silently returned `None` for non-JSON requests. In Werkzeug 3.x (included in the base image), it raises `UnsupportedMediaType` or `BadRequest`. Flask-RESTful's `RequestParser` checks multiple locations by default (including `json`), so any `add_argument` without explicit `location` can fail on GET requests.

**Before:**
```python
parser = RequestParser()
parser.add_argument('is_refund_enabled', type=boolean, required=False, default=False)
```

**After:**
```python
parser = RequestParser()
parser.add_argument('is_refund_enabled', type=boolean, required=False, default=False, location='args')
```

**Notes:**
- Use `location='args'` for query string parameters (GET requests)
- Use `location='json'` for JSON body parameters (POST/PUT requests)
- Use `location='form'` for form-encoded body parameters
- **CRITICAL:** Run `grep -rn 'add_argument(' app/` and audit **every** hit — verify each has an explicit `location=`. In inteladmingateway, 2 of 3 post-merge hotfixes were missed `add_argument` calls (PR #317 at 29 min post-merge, PR #319 at 3 days post-merge).

### 20b. RequestParser `location=["json", "form"]` on multipart/file-upload endpoints
When an endpoint accepts `multipart/form-data` (file uploads via `FileStorage`), Werkzeug 3.x raises HTTP 415 if `RequestParser` tries to access `request.json` — which happens when `location=["json", "form"]` is used. Change text-field arguments to `location="form"` on any endpoint that also has a `FileStorage` argument.

**Before:**
```python
class BTLEventReportUpload(BaseResource):
    post_req_parser = reqparse.RequestParser()
    post_req_parser.add_argument("event_id", type=str, location=["json", "form"], required=True)
    post_req_parser.add_argument("visible_event_name", type=str, location=["json", "form"])
    post_req_parser.add_argument("file", type=FileStorage, location="files", required=True)
    post_req_parser.add_argument("meta_data", type=str, location=["json", "form"], required=True)
```

**After:**
```python
class BTLEventReportUpload(BaseResource):
    post_req_parser = reqparse.RequestParser()
    post_req_parser.add_argument("event_id", type=str, location="form", required=True)
    post_req_parser.add_argument("visible_event_name", type=str, location="form")
    post_req_parser.add_argument("file", type=FileStorage, location="files", required=True)
    post_req_parser.add_argument("meta_data", type=str, location="form", required=True)
```

**Notes:**
- Any endpoint with `type=FileStorage, location="files"` receives `multipart/form-data` — companion text args MUST NOT include `"json"` in their location list
- Grep pattern to find these: `grep -rn 'FileStorage\|location=\["json", "form"\]' app/`
- This is silent in staging (only fails when the frontend actually uploads a file), so it easily escapes pre-merge testing

### 21. Custom JSONEncoder removal
Flask 3.x natively handles UUID and datetime serialization. Custom `JSONEncoder` subclasses that only add UUID/datetime support can be removed.

**Before:**
```python
from flask.json import JSONEncoder
from uuid import UUID

class CustomJSONEncoder(JSONEncoder):
    def default(self, obj):
        if isinstance(obj, UUID):
            return str(obj)
        return super().default(obj)

app.json_encoder = CustomJSONEncoder
```

**After:**
Remove the class entirely and the `app.json_encoder = ...` line. Flask 3.x handles this natively.

**Notes:**
- If the encoder handles types beyond UUID/datetime, extract only those custom handlers into a new provider
- Also check `app/__init__.py` for the `json_encoder` assignment

### 22. SQS listener / async worker app context
flask-script's `Manager.run()` auto-pushed the Flask app context. Flask CLI does not. Any SQS listener or async worker that accesses `app.config`, database models, or service calls needs explicit context.

**Before:**
```python
class Listener(SQSListener):
    def handle_message(self, body, event_type):
        getattr(AsyncListener, event_type.lower())(body)

    @classmethod
    def start(cls):
        listener = Listener(...)
        listener.listen()
```

**After:**
```python
class Listener(SQSListener):
    def handle_message(self, body, event_type):
        with app.app_context():
            getattr(AsyncListener, event_type.lower())(body)

    @classmethod
    def start(cls):
        with app.app_context():
            listener = Listener(...)
            listener.listen()
```

**Notes:**
- Check `app/asyncapi/`, `app/async/`, `app/utils/sqs_listener.py`
- Both `handle_message` AND the listener startup need wrapping
- ~20 services have SQS listeners that will need this fix

### 23. cp37/cp38 wheel URLs in requirements.txt
Old requirements often pin S3-hosted cp37 binary wheels. These are incompatible with Python 3.13.

**Before:**
```
https://wmznlejcfq.s3-ap-southeast-1.amazonaws.com/static/pythonwheels/lz4-3.1.0-cp37-cp37m-linux_x86_64.whl
https://wmznlejcfq.s3-ap-southeast-1.amazonaws.com/static/pythonwheels/cffi-1.14.1-cp37-cp37m-linux_x86_64.whl
```

**After:**
```
# lz4 and msgpack are in the base image — remove entirely
# For cffi, cryptography, pycryptodome — install from PyPI:
cffi==1.17.1
cryptography==44.0.0
```

**Notes:**
- `lz4` and `msgpack` are pre-installed in the base image — just remove them
- `cffi`, `cryptography`, `pycryptodome` have 3.13-compatible wheels on PyPI
- Search for any URL starting with `https://` in requirements.txt

### 24. flask_admin_s3_upload and dependent admin views
`flask_admin_s3_upload` depends on boto v2 which is incompatible with Python 3.13. Remove the package and any admin views/forms that use `S3FileUploadField`.

**Steps:**
1. Remove `flask_admin_s3_upload` from requirements.txt
2. Grep for `S3FileUploadField` — identify forms/views using it
3. If the admin view is unused/obsolete → delete the view, form, and its registration in `urls.py` / `__init__.py`
4. If the admin view is still needed → rewrite the S3 upload using boto3 directly

**Notes:**
- Flask-Admin itself is still needed — only remove views that depend on `flask_admin_s3_upload`
- In economy, badge admin views were deleted because they were unused for 3+ years
- Always verify with the user whether specific admin views are still in use before deleting
- Also found in: concepts, gameunit, cuestore, inapp-notification, helpcenter

### 25. PynamoDB 4→6 — Model.serialize() method collision
PynamoDB 6 added `serialize()` to the `Model` base class (used internally by `save()`). Any PynamoDB model subclass that defines its own `serialize()` will shadow it, causing `save()` to fail silently with an empty exception.

**Detect:**
```bash
grep -rn 'def serialize' app/ | grep -v '__pycache__'
# Cross-reference with PynamoDB model files:
grep -rln 'from pynamodb.models import Model' app/
```

**Fix:** Rename the custom method to `to_dict()` and update all callers.

**Notes:**
- This caused a production outage in reporter (all card creation failed silently for ~1 hour)
- The error message is empty — Sentry shows "(No error message)" making it hard to diagnose
- Also check for other PynamoDB Model method names that could collide: `serialize`, `deserialize`, `_serialize`, `_deserialize`

---

## Internal Package Dependencies

| Package | Python 3.13 Status | Notes |
|---|---|---|
| `cueutil` | Compatible | Verified in economy, concepts, inteladmingateway upgrades |
| `publishsubscribe` | Compatible | Verified in economy, concepts upgrades |
| `requestlogger` | Compatible | Verified in economy, concepts upgrades |
| `servicecaller` | Compatible | Verified in economy, concepts, inteladmingateway upgrades |
| `cachehandler` | Compatible | Verified in concepts upgrade |
| `authhandler` | Compatible | Verified in inteladmingateway upgrade |

All internal packages have been verified compatible with Python 3.13 through previous service upgrades.

---

## Packages Known to Need Version Bumps for 3.13

| Package | Min 3.13-compatible Version |
|---|---|
| boto3 | 1.35.x |
| botocore | 1.35.x |
| s3transfer | 0.10.x |
| gunicorn | 23.0.0 |
| gevent | 24.2.1 |
| greenlet | 3.1.x |
| sentry-sdk | 2.0.0+ |
| requests | 2.32.x |
| certifi | 2024.x |
| chardet | 5.2.0 |
| idna | 3.7+ |
| urllib3 | 2.2.x |
| redis | 5.2.0 |
| marshmallow | 3.22+ |
| marshmallow-sqlalchemy | 1.1.0+ |
| flask-marshmallow | 1.2.0+ |
| Flask-Caching | 2.3.x |
| tzlocal | 5.2+ |
| oauthlib | 3.2.2 |
| docutils | 0.21+ (or keep 0.15.2 — still works) |
| python-dateutil | 2.9.0+ |

---

## Packages to Remove (Incompatible / Replaced)

| Package | Reason |
|---|---|
| flask-script | Abandoned, no Python 3.10+ support. Use Flask CLI. |
| raven | EOL Sentry SDK. Replaced by sentry-sdk. |
| boto (v2) | EOL. Use boto3. |
| flask_admin_s3_upload | Uses boto v2. Remove or rewrite with boto3. |
| cp37 wheel files | lz4, msgpack etc. — install from PyPI instead. |
| flask-profiler | Unmaintained, incompatible with Flask 3. Remove entirely. |
| sqlakeyset | Often has zero imports in service code; verify before keeping. Incompatible with SQLAlchemy 1.4+ at old versions. |

---

## Services Already Upgraded (for reference)

| Service           | PRs                                                                                                                                                                                                                                                                        |
|-------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| economy           | [PR #35](https://github.com/cuemath/economy/pull/35/)                                                                                                                                                                                                                      |
| inteladmingateway | [PR #314](https://github.com/cuemath/inteladmingateway/pull/314/), [PR #317](https://github.com/cuemath/inteladmingateway/pull/317/), [PR #318](https://github.com/cuemath/inteladmingateway/pull/318/), [PR #319](https://github.com/cuemath/inteladmingateway/pull/319/) | 
| reporter          | [PR #89](https://github.com/cuemath/reporter/pull/89/), [PR #91](https://github.com/cuemath/reporter/pull/91/)                                                                                                                                                             |

---

## Post-Upgrade Verification Checklist

After the main upgrade PR is merged, run these checks to catch latent bugs that surface only in production traffic patterns. These are derived from inteladmingateway hotfixes PR #317, #318, #319.

### 1. RequestParser completeness audit

Run this grep and verify **every** match has an explicit `location=` parameter:

```bash
grep -rn 'add_argument(' app/ | grep -v 'location='
```

Any hit without `location=` will fail on GET requests (Werkzeug 3.x). Pay extra attention to:
- **GET endpoints** — need `location='args'`
- **File-upload endpoints** — text fields alongside `FileStorage` must use `location="form"`, NOT `location=["json", "form"]` (causes 415)

### 2. DST / timezone cache bugs

Check for `@lru_cache` on any method that computes timezone offsets. These caches become stale after DST transitions because multiple IANA zones temporarily share the same UTC offset.

```bash
grep -rn 'lru_cache' app/ | grep -i 'tz\|timezone\|offset'
```

**Fix pattern:** Add a short-circuit that returns the timezone as-is if it's already a canonical IANA zone name, bypassing the offset-based reverse-lookup entirely. See [PR #318](https://github.com/cuemath/inteladmingateway/pull/318/) for the `TimezoneMapper.normalize_timezone` fix.

### 3. Marshmallow unknown fields audit

Marshmallow 3.x rejects unknown fields by default. Any schema that deserializes DB JSONB data, external API responses, or SQS messages will raise `ValidationError` at runtime if the source contains fields not in the schema.

```bash
grep -rn 'class.*Schema\|@dataclass\|class_schema' app/ | grep -v '__pycache__'
```

For each schema found, check if it deserializes external/DB data (used in `.load()` calls). If so, ensure it has `unknown = EXCLUDE` in its `Meta` class. See pattern 11 above for before/after examples.

**Note:** This bug is silent until the specific code path runs with data containing extra fields — it won't surface in import checks or basic smoke tests.

### 4. Silent Werkzeug failure endpoints

These request types trigger Werkzeug 3.x strictness and may fail silently in staging (only hit by real user traffic):

- **GET with query params** — `request.json` access raises `BadRequest` / `UnsupportedMediaType`
- **multipart/form-data** (file uploads) — `request.json` access raises 415
- **form-encoded POST** — less common but same class of failure

**Test each endpoint type post-deploy:**
```bash
# GET with query params
curl -s -o /dev/null -w "%{http_code}" "https://www.<env>.cuemath.com/<service>/api/endpoint?param=value"

# File upload (multipart)
curl -s -o /dev/null -w "%{http_code}" -F "file=@test.txt" -F "field=value" "https://www.<env>.cuemath.com/<service>/api/upload-endpoint"
```

Any 400/415 response on previously-working endpoints indicates a missed RequestParser `location` fix.

### 5. PynamoDB Model method name collisions

PynamoDB 6 added methods to the `Model` base class. Any custom method on a PynamoDB model subclass that shares a name will shadow the internal method.

```bash
# Find all PynamoDB models
pynamo_files=$(grep -rln 'from pynamodb.models import Model' app/)
# Check for method name collisions
for f in $pynamo_files; do grep -n 'def serialize\|def deserialize\|def _serialize\|def _deserialize' "$f"; done
```

Any hits need renaming (e.g., `serialize` → `to_dict`). This caused a silent production outage in reporter — `card.save()` failed with empty exception messages.
