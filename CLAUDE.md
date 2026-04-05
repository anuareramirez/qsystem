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
- **users** - User model with roles: admin, seller (vendedor), customer (cliente)
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

Role-based routing: admin → `/dashboard`, seller → `/cotizaciones`, customer → `/mis-cursos`

### Quotation Workflow

Status flow: borrador → enviada → aceptada/rechazada/vencida

### Instructor Availability

Two-level system: regular weekly schedule (DisponibilidadInstructor) + specific date blocks (BloqueDisponibilidad).

## Claude Code Hooks

Configured in `.claude/settings.json`:
- **PostToolUse** (Edit/Write): auto-formats files via `.claude/hooks/auto-format.sh`
- **Stop**: notification via `.claude/hooks/notify-complete.sh`
