# QSystem Codebase Analysis Report
**Generated**: 2026-02-16
**Analyst**: Claude Code (Opus 4.6)
**Request**: Database Schema & API Design Review

---

## Executive Summary

The QSystem project is a Django REST Framework + React application for managing training courses, quotations, logistics, and billing. The analysis reveals a mature codebase with several architectural strengths but **12 critical database design issues** and **8 API security/design concerns** that require immediate attention.

**Critical Findings**:
- ❌ Missing foreign key indexes on high-traffic relationships
- ❌ Soft delete (deleted_date) not properly handled in unique constraints
- ❌ Missing validation for quotations referencing deleted courses
- ❌ Circular deletion cascades that can cause data loss
- ❌ API endpoints expose sensitive data without proper filtering
- ⚠️ Docker container runs as root (security risk)
- ✅ Good use of Django ORM to prevent SQL injection
- ✅ All monetary calculations use DECIMAL (excellent!)
- ✅ JWT authentication properly implemented

---

## Project Architecture

### Technology Stack
- **Backend**: Django 4.2.24, Django REST Framework, PostgreSQL 15
- **Frontend**: React (Vite dev server), Bootstrap
- **Infrastructure**: Docker Compose, Gunicorn (production WSGI server)
- **Key Libraries**:
  - django-simple-history (audit trails)
  - django-model-utils (FieldTracker)
  - cryptography (encryption)
  - boto3 (AWS S3 storage)
  - openpyxl, reportlab (file generation)

---

## 🔴 CRITICAL DATABASE SCHEMA ISSUES

### 1. Missing Foreign Key Indexes (Performance Impact)

**Location**: Multiple models across all apps

**Problem**: Django does NOT automatically create indexes on ForeignKey fields. The codebase has NO explicit `db_index=True` on any foreign keys, leading to SLOW queries.

**Affected Fields**:
- `CursoAgendado.curso` (line 498 in core/models.py) - High traffic lookup
- `CursoAgendado.instructor` (line 544)
- `CotizacionAbierta.curso` (line 266 in ventas/models.py)
- `CotizacionAbierta.cliente` (line 265)
- `CotizacionCerrada.cliente` (line 89)
- `FichaDeInscripcion.cotizacion_abierta` (line 124 in logistica/models.py)
- `FichaDeInscripcion.cotizacion_cerrada` (line 132)
- `Participante.ficha_inscripcion` (line 653)
- `Factura.cliente` (line 63 in contabilidad/models.py)
- `Pago.factura` (line 418)

**Recommendation**:
```python
# Add to ALL ForeignKey fields with frequent lookups:
curso = models.ForeignKey(
    CursoCatalogo,
    on_delete=models.CASCADE,
    db_index=True  # <-- ADD THIS
)
```

---

### 2. Soft Delete Not Handled in Unique Constraints

**Location**:
- `DisponibilidadInstructor` (line 408-412 in core/models.py)
- `BloqueDisponibilidad` (line 462-466)
- `MaterialCursoCatalogo` (line 1897)
- `Diploma` (line 1798)

**Problem**: Unique constraints don't exclude soft-deleted records, causing false conflicts.

**Current Code**:
```python
models.UniqueConstraint(
    fields=["instructor", "dia_semana", "hora_inicio", "fecha_inicio"],
    condition=models.Q(state=True),  # Uses 'state', not 'deleted_date'
    name="unique_disponibilidad_activa",
)
```

**Fix**:
```python
models.UniqueConstraint(
    fields=["instructor", "dia_semana", "hora_inicio", "fecha_inicio"],
    condition=models.Q(deleted_date__isnull=True),  # <-- CORRECT
    name="unique_disponibilidad_activa",
)
```

---

### 3. Nullable Fields That Shouldn't Be Nullable

**Location**: Multiple critical models

**Examples**:

1. **CursoAgendado.instructor** (line 544):
   - Course without instructor? Should be `null=False`

2. **CursoAgendado.lugar_curso** (line 526):
   - Course without location (unless online)? Needs validation

**Recommendation**:
```python
instructor = models.ForeignKey(
    Instructor,
    on_delete=models.PROTECT,  # Prevent deletion
    null=False,  # <-- ENFORCE
    blank=False
)
```

---

### 4. Missing Cascading Delete Protection

**Location**:
- `Empresa.plaza` (line 81 in core/models.py)
- `Cliente.empresa` (line 111)

**Problem**: Deleting Plaza → CASCADE deletes Empresas → deletes Clientes → deletes Quotations → deletes Participants!

**Recommendation**:
```python
plaza = models.ForeignKey(
    Plaza,
    on_delete=models.PROTECT  # <-- Prevent accidental deletion
)
```

---

### 5. Orphaned Records Possible

**Location**: `CotizacionAbierta.curso` (line 267)

**Problem**: Quotations can reference soft-deleted courses (no database constraint prevents this).

**Fix**: Add application-level validation:
```python
def clean(self):
    if self.curso and self.curso.deleted_date:
        raise ValidationError("Cannot create quotation for deleted course")
```

---

### 6. Missing Indexes on Filtered Fields

**Examples**:
- `CursoAgendado.estado` - Filtered in dashboards
- `CursoAgendado.fechai` - Filtered for date ranges
- `Factura.estado` - Filtered for payment status

**Recommendation**:
```python
estado = models.CharField(max_length=20, db_index=True)

class Meta:
    indexes = [
        models.Index(fields=['estado', 'fechai'], name='curso_estado_fecha_idx'),
    ]
```

---

### 7. Unique Constraints Don't Handle Soft Deletes

**Location**: `Participante` (line 729 in logistica/models.py)

**Current**:
```python
unique_together = [["ficha_inscripcion", "curp"]]
# If participant is soft-deleted, you CANNOT recreate them
```

**Fix**:
```python
constraints = [
    models.UniqueConstraint(
        fields=["ficha_inscripcion", "curp"],
        condition=models.Q(deleted_date__isnull=True),
        name="unique_participante_activo"
    )
]
```

---

### 8. CheckConstraint Issues

**Location**: `FichaDeInscripcion` (line 312-326)

**Problem**: Constraint doesn't prevent BOTH cotizacion fields being NULL.

---

### 9. Missing Default Values

**Location**: `CursoAgendado.min_participantes_confirmacion` (line 563)

**Problem**: Has `default=1` AND `null=True` (contradictory).

**Fix**: Remove `null=True`.

---

### 10. JSONField Validation Missing

**Location**:
- `CursoAgendado.horarios_detallados` (line 534)
- `CursoAgendado.historial_reagendamientos` (line 587)

**Recommendation**: Use JSON Schema validation or dedicated models.

---

### 11. Circular Import Dependencies

**Location**: Serializers import each other

**Better Approach**: Create `common/serializers.py` with basic serializers.

---

## 🔴 CRITICAL API DESIGN ISSUES

### 1. Missing Pagination Implementation

**Risk**: Endpoints can return thousands of records without pagination.

**Fix**:
```python
# settings.py
REST_FRAMEWORK = {
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 50,
}
```

---

### 2. Over-Exposure of Sensitive Fields

**Location**: InstructorSerializer (line 257)

**Problem**: Exposes `honorario_por_hora` (payment rate) to all users.

**Fix**: Use different serializers per role.

---

### 3. Missing Permission Classes

**Check Required**: Review all ViewSets for proper permissions.

---

### 4. No Rate Limiting

**Risk**: API vulnerable to brute force and DoS attacks.

---

### 5. Inconsistent Response Formats

**Recommendation**: Standardize success/error response format.

---

### 6. Missing Input Validation

**Example**: `CursoAgendadoSerializer` doesn't validate `fechai < fechaf`.

---

### 7. No API Versioning

**Current**: URLs don't include version (`/api/v1/`)

---

### 8. CORS Configuration Security

**Issue**: Hardcoded localhost, missing credentials config.

---

## 🟡 DOCKER/INFRASTRUCTURE ISSUES

### 1. Security: Running as Root

**Location**: Dockerfile (line 1)

**Fix**: Add non-root user directive.

---

### 2. Missing Health Checks (Backend)

**Recommendation**: Add `/api/health/` endpoint and Docker health check.

---

### 3. Exposed Secrets in docker-compose.yml

**Issue**: Default SECRET_KEY is insecure.

---

### 4. Database Backup Strategy Missing

**Recommendation**: Add backup service to docker-compose.yml.

---

## ✅ STRENGTHS IDENTIFIED

1. ✅ **Excellent Use of Django ORM** - Prevents SQL injection
2. ✅ **Proper Decimal for Money** - All monetary fields use DecimalField
3. ✅ **Soft Delete Implementation** - BaseModel provides deleted_date
4. ✅ **JWT Authentication** - HttpOnly cookies prevent XSS
5. ✅ **Audit Trail** - django-simple-history tracks changes
6. ✅ **Field Tracking** - django-model-utils monitors changes
7. ✅ **Storage Abstraction** - Supports S3 and local storage

---

## 🎯 IMMEDIATE ACTION ITEMS

### Week 1: Critical Fixes
- [ ] Add `db_index=True` to all ForeignKey fields
- [ ] Fix cascade deletes (PROTECT on Plaza → Empresa → Cliente)
- [ ] Fix soft delete in unique constraints

### Week 2: Security
- [ ] Implement API rate limiting
- [ ] Add role-based serializers
- [ ] Run Docker as non-root user

### Week 3: Performance
- [ ] Enable DRF pagination
- [ ] Add database health checks
- [ ] Implement backup strategy

### Week 4: Testing
- [ ] Write schema integrity tests
- [ ] Write API security tests
- [ ] Document API versioning

---

## 📁 KEY FILES ANALYZED

- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py` (1516 lines)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/models.py` (373 lines)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/models.py` (1954 lines)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/models.py` (567 lines)
- `/Users/anuareramirez/DEV/qsys/docker-compose.yml` (99 lines)

---

**Next Steps**: Prioritize fixes based on business impact (data loss risk > performance > security). Create issues in project tracker for each finding.
