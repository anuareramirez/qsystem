#!/bin/bash
# Post-commit production action checker
# Analyzes the last commit to detect if production actions are needed

PROJECT_DIR="/Users/anuareramirez/DEV/qsys/qsystem"
ACTIONS=""

# Get changed files from last commit in both submodules
BACKEND_CHANGES=$(cd "$PROJECT_DIR/qsystem-backend" && git diff --name-only HEAD~1 HEAD 2>/dev/null)
FRONTEND_CHANGES=$(cd "$PROJECT_DIR/qsystem-frontend" && git diff --name-only HEAD~1 HEAD 2>/dev/null)

ALL_CHANGES="$BACKEND_CHANGES
$FRONTEND_CHANGES"

# Check for new migrations
if echo "$BACKEND_CHANGES" | grep -q "migrations/.*\.py"; then
  ACTIONS="$ACTIONS\n⚠️  MIGRATIONS: New migration files detected. Run in production:\n   docker compose exec backend python manage.py migrate"
fi

# Check for requirements.txt changes
if echo "$BACKEND_CHANGES" | grep -q "requirements.txt"; then
  ACTIONS="$ACTIONS\n⚠️  DEPENDENCIES (backend): requirements.txt changed. Run in production:\n   docker compose build backend && docker compose up -d backend"
fi

# Check for package.json changes
if echo "$FRONTEND_CHANGES" | grep -q "package.json\|package-lock.json"; then
  ACTIONS="$ACTIONS\n⚠️  DEPENDENCIES (frontend): package.json changed. Run in production:\n   docker compose build frontend && docker compose up -d frontend"
fi

# Check for Docker config changes
if echo "$ALL_CHANGES" | grep -qE "Dockerfile|docker-compose"; then
  ACTIONS="$ACTIONS\n⚠️  DOCKER: Container config changed. Rebuild in production:\n   docker compose build && docker compose up -d"
fi

# Check for settings/config changes
if echo "$BACKEND_CHANGES" | grep -qE "settings/(prod|base)\.py"; then
  ACTIONS="$ACTIONS\n⚠️  SETTINGS: Production settings changed. Verify environment variables and restart:\n   docker compose restart backend"
fi

# Check for static file changes that need collectstatic
if echo "$BACKEND_CHANGES" | grep -qE "static/|staticfiles/"; then
  ACTIONS="$ACTIONS\n⚠️  STATIC FILES: Run collectstatic in production:\n   docker compose exec backend python manage.py collectstatic --noinput"
fi

# Check for new environment variables
if echo "$ALL_CHANGES" | grep -qE "\.env\.example|\.env\.template"; then
  ACTIONS="$ACTIONS\n⚠️  ENV VARS: Environment template changed. Check if new variables need to be set in production."
fi

# Check for crontab or scheduled task changes
if echo "$BACKEND_CHANGES" | grep -qE "crontab|celery|tasks\.py"; then
  ACTIONS="$ACTIONS\n⚠️  SCHEDULED TASKS: Task definitions changed. Update crontab/workers in production."
fi

# Output result
if [ -n "$ACTIONS" ]; then
  MESSAGE=$(echo -e "🚀 PRODUCTION ACTIONS REQUIRED:\n$ACTIONS")
  echo "{\"systemMessage\": $(echo "$MESSAGE" | jq -Rs .)}"
else
  echo "{\"systemMessage\": \"✅ No production actions needed for this commit.\"}"
fi
