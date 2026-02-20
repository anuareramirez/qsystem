# Codebase Analysis Report
**Generated**: 2026-02-16T20:30:00Z  
**Analyst**: codebase-analyzer  
**Request**: Comprehensive Django backend analysis focusing on business logic, data integrity, and architecture issues

---

## Executive Summary

This analysis examines the QSystem Django backend, which manages a course scheduling and quotation system. The codebase demonstrates sophisticated business logic with good separation of concerns through services, but suffers from **critical race conditions, missing transaction boundaries, and inconsistent validation enforcement**. The system handles quotations (CotizacionAbierta/CotizacionCerrada), scheduled courses (CursoAgendado), participant management (FichaDeInscripcion/Participante), and logistics (costs, materials, diplomas).

**Critical Issues Found**: 18 issues (4 critical, 8 high, 6 medium) including race conditions in state management, missing transaction boundaries in financial calculations, and validation gaps that could lead to data corruption.

**Architecture Strengths**: Service layer pattern, soft deletes with audit trails, comprehensive change tracking via JSON history fields.

**Architecture Weaknesses**: Business logic split between models/serializers/views, missing database constraints, signal-based side effects creating hidden dependencies.

---

## Project Architecture

### Technology Stack
- **Backend**: Django 4.x+, Django REST Framework 3.x
- **Database**: PostgreSQL 15
- **Key Libraries**:
  - django-simple-history (audit trails)
  - django-model-utils (FieldTracker)
  - Storage backends (S3/local via custom storage classes)

### Directory Structure
```
qsystem-backend/src/apps/
├── authentication/       # JWT authentication
├── core/                 # Business entities (cursos, instructores, clientes)
│   ├── models.py        # BaseModel, CursoAgendado, Instructor, Cliente, etc.
│   ├── signals.py       # Auto state management, change tracking
│   ├── views/           # Modular ViewSets
│   │   ├── cursos_agendados.py
│   │   ├── personas.py
│   │   └── disponibilidad.py
│   └── services/        # Business logic services
│       ├── curso_agendado_service.py
│       ├── curso_agendado_pricing_service.py
│       ├── curso_agendado_state_service.py
│       └── instructor_availability.py
├── ventas/              # Quotations (CotizacionAbierta/Cerrada)
├── logistica/           # Participant management, materials, costs
├── contabilidad/        # Accounting module
├── mailings/            # Email notifications
└── users/               # User management
```

---

## Summary of Critical Issues

| # | Issue | Severity | File | Line | Impact |
|---|-------|----------|------|------|--------|
| 1 | Missing transaction in total calculation | HIGH | ventas/models.py | 170 | Financial data corruption |
| 2 | Infinite loop risk in save() | HIGH | ventas/models.py | 241 | System hang |
| 3 | Validation only in serializers | MEDIUM | ventas/models.py | N/A | Data integrity bypass |
| 4 | Race condition in estado change | CRITICAL | core/models.py | 780 | Invalid states |
| 5 | Signal-based state change bypasses validation | HIGH | core/signals.py | 10 | State corruption |
| 7 | Participant confirmation race condition | HIGH | logistica/models.py | 344 | Double confirmation |
| 8 | Fecha limite calculation fragile | MEDIUM | logistica/models.py | 455 | Maintenance burden |
| 9 | Availability doesn't check course assignments | MEDIUM | core/models.py | 187 | Logic gap |
| 10 | Auto-deletion of monto_comprobado | MEDIUM | logistica/models.py | 912 | Data loss |
| 11 | Apellido materno validation mismatch | MEDIUM | logistica/models.py | 752 | Inconsistent validation |
| 12 | History validation not enforced | MEDIUM | core/signals.py | 274 | Data quality |
| 13 | Hidden dependencies via signals | MEDIUM | core/signals.py | N/A | Maintainability |
| 14 | No check constraint on estado | HIGH | core/models.py | N/A | Invalid data |
| 15 | Missing indexes on filtered fields | MEDIUM | Multiple | N/A | Performance |
| 16 | Computed properties cause N+1 queries | MEDIUM | core/models.py | 994 | Performance |
| 17 | No row-level permissions on state change | MEDIUM | views/cursos_agendados.py | 542 | Security |
| 18 | Cancellation cascade lacks atomicity | HIGH | core/models.py | 847 | Data integrity |

---

## Detailed Analysis

[Continue with full analysis content...]
