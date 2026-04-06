---
name: test
description: Run tests for the QSystem project. Usage: /test (auto-detect), /test backend, /test frontend, /test all, /test migrations
user_invocable: true
---

# Test Runner Skill

Run the appropriate test suite based on the argument provided.

## Parse the argument

The user may pass an argument: `$ARGUMENTS`

- If empty or "auto": detect what changed and run the appropriate tests
- If "backend" or "back" or "b": run backend tests only
- If "frontend" or "front" or "f": run frontend tests only
- If "all" or "full": run both backend and frontend tests
- If "migrations" or "migrate" or "m": run migration checks only
- If it contains an app name (e.g., "core", "ventas", "users"): run tests for that specific Django app

## Pre-flight check

Before running any tests, verify Docker is running:
```bash
docker compose ps --format json 2>/dev/null | head -1
```

If Docker is not running, tell the user to start it with `docker compose --profile dev up -d` and stop.

## Auto-detect mode

When no argument is given, detect what changed:
```bash
# Check backend changes
cd /Users/anuareramirez/DEV/qsys/qsystem/qsystem-backend && git diff --name-only HEAD 2>/dev/null && git diff --name-only --cached 2>/dev/null

# Check frontend changes
cd /Users/anuareramirez/DEV/qsys/qsystem/qsystem-frontend && git diff --name-only HEAD 2>/dev/null && git diff --name-only --cached 2>/dev/null
```

- If only `.py` files changed → run backend tests
- If only `.jsx/.js/.ts/.tsx/.css` files changed → run frontend tests
- If both changed → run all
- If model files changed → also run migration check
- If nothing detected → run all

## Backend tests

```bash
# If a specific app was detected or provided:
docker compose exec backend python manage.py test apps.<app_name> -v 2

# If multiple apps or general:
docker compose exec backend python manage.py test -v 2
```

Extract the Django app name from the file path: `src/apps/<app_name>/...`

## Frontend tests

```bash
cd /Users/anuareramirez/DEV/qsys/qsystem/qsystem-frontend && npx vitest run --reporter=verbose 2>&1
```

Also run lint:
```bash
cd /Users/anuareramirez/DEV/qsys/qsystem/qsystem-frontend && npm run lint 2>&1
```

## Migration check

```bash
docker compose exec backend python manage.py makemigrations --check --dry-run
docker compose exec backend python manage.py migrate --check
```

## Output

Report results concisely:

```
## Test Results [scope]

Backend: PASS/FAIL (X tests, Y failures)
Frontend: PASS/FAIL (X tests, Y failures)
Lint: PASS/FAIL
Migrations: PASS/FAIL

[Only show error details for failures]
```
