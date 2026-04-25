# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Environment

**All development runs through Docker. Do not run servers locally.**

```bash
# Start all services with hot reload
docker-compose --profile dev up -d

# Stop services
docker-compose down
```

- Frontend (Vite): http://localhost:5173 (hot reload via `frontend-dev` container)
- Backend (Django): http://localhost:8003
- PostgreSQL: localhost:5432

The `.env` file lives at the project root and Docker reads it automatically. Running `npm run dev` locally will NOT pick up these env vars correctly.

## Common Commands

```bash
# Backend
docker-compose exec backend python manage.py migrate
docker-compose exec backend python manage.py createsuperuser
docker-compose exec backend python manage.py shell
docker-compose exec backend python manage.py test apps.core -v 2
docker-compose logs -f backend

# Frontend
docker-compose logs -f frontend-dev
cd qsystem-frontend && npm run lint

# Rebuild a service after dependency changes
docker-compose build backend
```

### Testing

Backend uses pytest with Django (`pytest.ini` at backend root):
```bash
docker-compose exec backend python manage.py test                           # all tests
docker-compose exec backend python manage.py test apps.core -v 2            # specific app
docker-compose exec backend python manage.py test apps.core.tests.TestName  # specific class
```

Frontend uses vitest:
```bash
cd qsystem-frontend && npm test              # run tests
cd qsystem-frontend && npm run test:coverage # with coverage
```

## Git Workflow - Submodules

This is a monorepo with two git submodules:
- `qsystem-frontend` → `anuareramirez/qsystem-frontend`
- `qsystem-backend` → `anuareramirez/qsystem-backend`

**Always use `commit-helper.sh` for commits:**
```bash
./commit-helper.sh frontend "feat: add login component"
./commit-helper.sh backend "fix: migration issue"
./commit-helper.sh both "feat: new endpoint and UI"
```

The script commits in the submodule(s), updates the monorepo reference, and pushes everything. Do NOT use `git commit` directly from the root.

Commit message convention: `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `test:`, `chore:`

## Architecture

```
React (Vite + Tailwind 4) ──REST API──▶ Django REST Framework ──▶ PostgreSQL 15
     JWT in HttpOnly cookies              Soft deletes + audit trail
```

### Backend (`qsystem-backend/`)

Django project rooted at `src/`. Settings split into `src/settings/{base,dev,prod,test}.py`.

Django apps under `src/apps/`:
- **authentication** - JWT auth (login, logout, token refresh)
- **users** - User model with 5 roles: `admin`, `seller` (vendedor), `customer` (cliente), `data_entry` (capturista, has M2M `plazas`), `administrative` (administrativo)
- **core** - Main business models: Vendedor, Plaza, Instructor, CursoCatalogo, CursoAgendado, etc.
- **ventas** - Sales/quotations: CotizacionCerrada, PartidaCotizacion
- **logistica** - Logistics management
- **contabilidad** - Accounting
- **mailings** - Email sending (SMTP + Microsoft Graph API)
- **imports** - Bulk CSV/Excel import system

API URL structure: `/api/{app_name}/...` (see `src/urls.py`)

**BaseModel** (`src/apps/core/models.py`): All models inherit from this. Provides `id`, `state`, `created_date`, `modified_date`, `deleted_date` (soft delete), and `created_by`. Uses `simple_history` for audit trails.

### Frontend (`qsystem-frontend/`)

React 19 + Vite + Tailwind CSS 4. No TypeScript (JSX files).

Key directories under `src/`:
- `api/` - Axios-based API service modules (one per domain)
- `contexts/` - AuthContext, QuotationContext, TrashModeContext, ThemeContext, plus state contexts for accounting/logistics/sales
- `hooks/` - Custom hooks (useAuth, useDebounce, useBreakpoint, useFetch, useInstructorAvailability, etc.)
- `pages/` - Route pages organized by: auth, dashboard, errors, management, modules
- `components/` - UI components: calendar, dashboard, datetime, forms, layout, modals, pdf, tables, ui
- `router/` - React Router with ProtectedRoute and RoleRoute for role-based access

Auth: JWT tokens stored in HttpOnly cookies. Axios interceptor in `src/api/axios.jsx` auto-refreshes on 401.

Role-based landing routes (see `src/router/index.jsx`):
- `admin` → `/management`
- `seller` → `/sales`
- `data_entry` → `/sales`
- `administrative` → `/accounting`
- `customer` → `/home`

### Quotation Workflow

Status flow: borrador → enviada → aceptada/rechazada/vencida

### Instructor Availability

Two-level system: regular weekly schedule (DisponibilidadInstructor) + specific date blocks (BloqueDisponibilidad).

## Claude Code Hooks

Configured in `~/.claude/settings.json`:
- **PostToolUse** (Edit/Write): auto-formats Python files with `ruff format` + `ruff check --fix`
- **PostToolUse** (Edit/Write): auto-formats frontend files (.jsx, .tsx, .js, .ts, .css, .html, .json) with `prettier --write`
- **Stop**: plays Glass.aiff notification sound when Claude finishes responding
- **Notification**: plays notification sound on system notifications
- **PermissionRequest**: plays notification sound when waiting for user approval

## Claude Code Agents

Custom agents in `.claude/agents/`:
- **code-reviewer**: Quality review of Django and React code (read-only)
- **codebase-analyzer**: Architecture analysis and feature planning (read-only)
- **django-researcher**: DRF pattern research and API planning (read-only)
- **docker-aws-researcher**: Docker/AWS infrastructure analysis (read-only)
- **test-runner**: Smart test orchestrator — detects what changed and runs pytest (Docker), vitest, migration checks, or all
- **migration-planner**: Analyzes migration impact, dependency maps, conflict resolution, rollback plans
- **commit-assistant**: Handles submodule workflow — analyzes changes, generates commit message, runs `commit-helper.sh`
- **security-auditor**: OWASP Top 10 audit, JWT security, permissions, injection, data exposure

## Permissions

Auto-allowed: git, docker-compose (exec/ps/up/build/logs), npm, npx, pip3, python3, commit-helper.sh, Read, Edit, Write, Glob, Grep.
Requires confirmation: `docker-compose down -v`, `docker system prune`, `git push --force`, `git reset --hard`.
Denied: `rm -rf /`, `rm -rf ~`, `rm -rf .`.
