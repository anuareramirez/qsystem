# Codebase Analysis Report — State Machine Deep Dive
**Generated**: 2026-03-16
**Analyst**: codebase-analyzer
**Request**: Comprehensive state machine analysis: CursoAgendado, CotizacionAbierta, CotizacionCerrada, FichaDeInscripcion, Factura — all model fields, signals, cascade behaviors, and edge cases.

---

<!-- ============================================================ -->
<!-- SECTION: STATE MACHINE ANALYSIS (added 2026-03-16)          -->
<!-- ============================================================ -->

## Executive Summary — State Machine Analysis

This project implements a multi-entity state machine across five core domain objects: `CursoAgendado`, `CotizacionAbierta`, `CotizacionCerrada`, `FichaDeInscripcion`, and `Factura`. Each entity has its own lifecycle, but their state machines are deeply coupled through Django signals, explicit cascade methods, and view-layer orchestration logic. The coupling is predominantly unidirectional — cotizaciones drive curso states, and the curso drives ficha states — but there are several bidirectional feedback loops that create subtle race conditions and edge cases.

The system distinguishes between two course tracks: "open" courses (`tipo_curso="abierto"`) marketed to the public via `CotizacionAbierta`, and "closed" courses (`tipo_curso="cerrado"`) created exclusively when a `CotizacionCerrada` is accepted. `Factura` is downstream of both quotation types and has no signals that drive upstream state changes; it is purely a billing record. The most complex logic is concentrated in `CursoAgendado.cambiar_estado()`, `_cancelar_relacionados()`, `_completar_fichas()`, and the signal files in `ventas/signals.py`, `logistica/signals.py`, and `core/signals.py`.

---

## Entity State Machines

---

### 1. CursoAgendado

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py`

#### States

| State | Meaning |
|---|---|
| `AGENDADO` | Scheduled but no quotations exist |
| `PROSPECTADO` | At least one active quotation (not rejected/expired) |
| `CONFIRMADO` | Quotation accepted (cerrada) OR minimum participants reached |
| `EN_PROCESO` | Start date has arrived |
| `FINALIZADO` | Course completed |
| `CANCELADO` | Definitively cancelled |
| `VENCIDO` | Start date passed without confirmation |

#### Valid Manual Transitions (from `cambiar_estado()`)

```
AGENDADO     → PROSPECTADO, CANCELADO, VENCIDO
PROSPECTADO  → CONFIRMADO, CANCELADO, VENCIDO, AGENDADO
CONFIRMADO   → EN_PROCESO, CANCELADO, PROSPECTADO, AGENDADO
EN_PROCESO   → FINALIZADO, CANCELADO
FINALIZADO   → (none — terminal)
CANCELADO    → AGENDADO
VENCIDO      → CONFIRMADO, AGENDADO, CANCELADO
```

#### Valid Automatic Transitions (from `core/signals.py` pre_save)

Only fires when `fechai` or `fechaf` changes via `FieldTracker`:

```
AGENDADO    → VENCIDO     (if today > fechaf)
PROSPECTADO → VENCIDO     (if today > fechaf)
CONFIRMADO  → EN_PROCESO  (if today >= fechai)
CONFIRMADO  → FINALIZADO  (if today > fechaf)
EN_PROCESO  → FINALIZADO  (if today > fechaf)
```

#### Transition Triggers

| Transition | Triggered By | Source |
|---|---|---|
| AGENDADO → PROSPECTADO | New CotizacionAbierta created pointing to this curso | `ventas/signals.py: actualizar_estado_curso_por_cotizacion_abierta` (created=True) |
| AGENDADO → PROSPECTADO | CotizacionCerrada M2M add (curso added to cotizacion) | `ventas/signals.py: actualizar_estado_cursos_por_m2m_cerrada` (post_add) |
| AGENDADO → PROSPECTADO | New CotizacionCerrada post_save with created=True | `ventas/signals.py: actualizar_estado_curso_por_cotizacion_cerrada` |
| PROSPECTADO → AGENDADO | Last active CotizacionAbierta rejected | `ventas/signals.py: actualizar_estado_curso_por_cotizacion_abierta` |
| PROSPECTADO → AGENDADO | CotizacionAbierta hard-deleted | `ventas/signals.py: verificar_estado_curso_al_eliminar_cotizacion` |
| PROSPECTADO → CONFIRMADO | Participant added to ficha, minimum reached | `logistica/signals.py: verificar_confirmacion_curso_al_agregar_participante` |
| PROSPECTADO → CONFIRMADO | Ficha confirmed, minimum reached | `logistica/signals.py: verificar_confirmacion_curso_al_confirmar_ficha` |
| PROSPECTADO → VENCIDO | Ficha confirmed, start date already passed | `logistica/signals.py: verificar_confirmacion_curso_al_confirmar_ficha` |
| ANY → VENCIDO | fechai/fechaf changes on curso, auto-calc fires | `core/signals.py: actualizar_estado_curso_automatico` (pre_save) |
| CONFIRMADO → EN_PROCESO | fechai changes, today >= fechai | `core/signals.py` (pre_save) |
| CONFIRMADO → EN_PROCESO | CotizacionCerrada accepted + start date passed | `ventas/signals.py: actualizar_estado_curso_por_cotizacion_cerrada` |
| CONFIRMADO → EN_PROCESO | CotizacionCerrada.cambiar_estado("aceptada") view action | `ventas/views.py: CotizacionCerradaViewSet.cambiar_estado` |
| CONFIRMADO → PROSPECTADO | Ficha cancelled/reverted, drops below minimum | `logistica/signals.py: verificar_confirmacion_curso_al_confirmar_ficha` |
| ANY → CANCELADO | Manual call via `cambiar_estado("CANCELADO")` | `CursoAgendado.cambiar_estado()` → `_cancelar_relacionados()` |
| EN_PROCESO → FINALIZADO | Manual or auto (fechaf) | `cambiar_estado()` → `_completar_fichas()` |
| PROSPECTADO → CANCELADO | CotizacionCerrada rejected, no other active cotizaciones | `ventas/signals.py: actualizar_estado_curso_por_cotizacion_cerrada` |
| VENCIDO → (any) | Cotizaciones vencidas expired by core/signals when curso → VENCIDO | `core/signals.py: vencer_cotizaciones_por_curso_vencido` |

#### Cascade Side Effects of CANCELADO

When `cambiar_estado("CANCELADO")` is called, `_cancelar_relacionados()` fires atomically:

1. All `CotizacionAbierta` linked to this curso (non-rejected) → set to `"rechazada"`
2. All `FichaDeInscripcion` linked to those cotizaciones abiertas (non-cancelled) → set to `"cancelada"` with `_skip_signal=True`
3. All child recotizaciones of those cotizaciones abiertas → set to `"rechazada"`, their fichas → `"cancelada"`
4. All `CotizacionCerrada` in `cursos_agendados` (non-rejected) → set to `"rechazada"`
5. All `FichaDeInscripcion` linked to those cotizaciones cerradas (non-cancelled) → `"cancelada"` with `_skip_signal=True`
6. All child recotizaciones of those cotizaciones cerradas → `"rechazada"`, their fichas → `"cancelada"`
7. All `FichaDeInscripcion` in `fichas_directas` (reagendamiento case) → `"cancelada"` with `_skip_signal=True`

**Critical note**: `_skip_signal=True` is set on fichas before saving to prevent the `verificar_confirmacion_curso_al_confirmar_ficha` signal from triggering a PROSPECTADO downgrade loop.

#### Cascade Side Effects of FINALIZADO

When `cambiar_estado("FINALIZADO")` is called, `_completar_fichas()` fires atomically:

1. All fichas in state `"confirmada"` or `"en_proceso"` (via cotizaciones abiertas, cerradas, and `fichas_directas`) → `"completada"` with `_skip_signal=True`
2. All fichas in state `"pendiente"` → `"cancelada"` with `_skip_signal=True`

#### Cascade Side Effects of VENCIDO (core/signals.py)

When CursoAgendado transitions to VENCIDO (via `post_save` signal `vencer_cotizaciones_por_curso_vencido`):

1. All `CotizacionAbierta` in states `["borrador", "realizada", "enviada"]` for this curso → set `estado_previo_vencimiento = current_estado`, then `estado = "vencida"` (saved with `update_fields`)
2. All `CotizacionCerrada` in states `["borrador", "realizada", "enviada"]` with this curso in `cursos_agendados` → same treatment

**Note**: Fichas are NOT touched when a curso goes VENCIDO. Only cotizaciones are expired.

#### Date Limit Update on Reagendamiento (core/signals.py)

When `fechai` changes on CursoAgendado (post_save, FieldTracker detects change):

- All `FichaDeInscripcion` linked via `CotizacionCerrada` that are NOT in `["confirmada", "completada"]` → `fecha_limite_inscripcion` updated to earliest `fechai` across all cursos in that cotizacion
- All `FichaDeInscripcion` with `curso_asociado=this_curso` that are NOT in `["confirmada", "completada"]` → `fecha_limite_inscripcion = nueva_fechai`

---

### 2. CotizacionAbierta

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/models.py`

#### States

| State | Meaning |
|---|---|
| `borrador` | Initial state, PDF not yet generated |
| `realizada` | PDF uploaded (borrador → realizada via `upload_pdf` action) |
| `enviada` | Sent by email to client (realizada/enviada → enviada via `send_email`) |
| `aceptada` | Client accepted |
| `rechazada` | Client rejected or cancelled by system |
| `recotizada` | Superseded by a new re-quote |
| `vencida` | Expired (either date passed, or curso went VENCIDO) |

#### Valid Transitions (`TRANSICIONES_VALIDAS`)

```
borrador   → realizada
realizada  → enviada, rechazada, recotizada
enviada    → aceptada, rechazada, recotizada
rechazada  → recotizada
recotizada → (none — terminal)
aceptada   → rechazada
vencida    → realizada
```

#### Transition Triggers and Side Effects

| Transition | Trigger | Side Effect |
|---|---|---|
| borrador → realizada | `upload_pdf` view action (file upload) | PDF stored, estado set directly (bypasses TRANSICIONES_VALIDAS check in view) |
| realizada → enviada | `send_email` view action (success) | Email sent to client |
| enviada → aceptada | Manual `cambiar_estado` view action | `post_save` signal fires → curso PROSPECTADO (if AGENDADO) |
| aceptada → rechazada | Manual `cambiar_estado` | All non-cancelled fichas linked to this cotizacion → `"cancelada"` (in view, NOT via model cascade) |
| any → recotizada | `duplicar` view action with `es_recotizacion=True` | Original cotizacion → `"recotizada"`, all its fichas → `"cancelada"`, new cotizacion created in `"realizada"` |
| any → vencida | `vencer_cotizaciones_por_curso_vencido` signal (when curso goes VENCIDO) | `estado_previo_vencimiento` saved for potential reactivation |
| vencida → realizada | Via `transfer_relationships()` during reagendamiento | `estado_previo_vencimiento` cleared, `fecha_vencimiento` set to new `fechai` |

#### Effect on CursoAgendado

- **Created** (new cotizacion with `curso` set): If curso is AGENDADO → PROSPECTADO
- **Rejected**: If no remaining active cotizaciones → curso AGENDADO (from PROSPECTADO/CONFIRMADO)
- **Hard-deleted** (`post_delete` signal): Same check as rejection
- **Accepted** (estado="aceptada"): If curso is AGENDADO → PROSPECTADO (cotizaciones abiertas do NOT push to CONFIRMADO; only cerradas do)

**Key asymmetry**: A `CotizacionAbierta` acceptance only drives a curso to PROSPECTADO, never to CONFIRMADO. CONFIRMADO for open courses requires participant minimum to be reached.

#### `vencida` State Behavior

- `estado_previo_vencimiento` stores the state before vencimiento
- The `vencida → realizada` transition in `TRANSICIONES_VALIDAS` enables reactivation
- During `transfer_relationships()`, vencida cotizaciones are reactivated to their `estado_previo_vencimiento` (or `"realizada"` as default)

---

### 3. CotizacionCerrada

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/models.py`

#### States

Identical choices to CotizacionAbierta:
`borrador`, `realizada`, `enviada`, `aceptada`, `rechazada`, `recotizada`, `vencida`

#### Valid Transitions (`TRANSICIONES_VALIDAS`)

Identical to CotizacionAbierta.

#### Key Structural Differences from CotizacionAbierta

1. **M2M relationship** to CursoAgendado via `cursos_agendados` (one cotizacion can cover multiple cursos and groups)
2. **Items** (`ItemCotizacionCerrada`) define the line-item details (curso de catálogo, participantes, grupos, price)
3. **CursoAgendado instances are CREATED at acceptance time** — they do not pre-exist
4. `curso_agendado_original` FK for tracking after desvinculacion

#### Unique Constraint on M2M

The `m2m_changed` signal (`actualizar_estado_cursos_por_m2m_cerrada`) enforces:
- A CursoAgendado cannot belong to more than one active `CotizacionCerrada` (`pre_add` raises `ValidationError`)
- The CursoAgendado's `curso` FK must match a `CursoCatalogo` present in the cotizacion's items

#### Transition Triggers and Side Effects

| Transition | Trigger | Side Effect |
|---|---|---|
| borrador → realizada | `upload_pdf` view action | PDF stored |
| realizada → enviada | `send_email` action (success) | Email sent |
| any → aceptada | `cambiar_estado` view action | **CursoAgendado instances CREATED** (one per group per item), added to `cursos_agendados` M2M, each starts at `CONFIRMADO`; if `fechai` already passed → immediately advanced to `EN_PROCESO` |
| aceptada → rechazada | `cambiar_estado` view action | All non-cancelled fichas → `"cancelada"` (in view) |
| any → recotizada | `duplicar` with `es_recotizacion=True` | Original → `"recotizada"`, fichas → `"cancelada"`, new cotizacion starts at `"realizada"` |
| any → vencida | `vencer_cotizaciones_por_curso_vencido` signal | `estado_previo_vencimiento` saved |

#### Effect on CursoAgendado (post_save signal)

- **estado="aceptada"**: If curso is AGENDADO → PROSPECTADO → CONFIRMADO (two sequential calls within the same signal iteration). Then if `fechai` passed → EN_PROCESO
- **estado="rechazada"**: If no other active cotizaciones → curso CANCELADO (IMPORTANT: cerradas cancel the curso, abiertas only revert to AGENDADO)
- **created=True**: If curso is AGENDADO → PROSPECTADO

**Critical asymmetry vs. CotizacionAbierta**: Rejection of a CotizacionCerrada leads to CANCELADO for the linked cursos, not just AGENDADO. This makes sense because closed-course cursos are created specifically for this cotizacion.

#### INTERESADOS Category

CotizacionCerradas without any `cursos_agendados` attached (`cursos_agendados__isnull=True`) are treated as "interesados" in the frontend and excluded from normal list views. This represents closed-course leads that haven't been assigned to scheduled courses yet.

---

### 4. FichaDeInscripcion

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/models.py`

#### States

| State | Meaning |
|---|---|
| `pendiente` | Created, awaiting participant data |
| `confirmada` | All participants registered and confirmed |
| `en_proceso` | Course is running |
| `completada` | Course finished, participants completed |
| `cancelada` | Cancelled (by system cascade or manual) |

#### Secondary State: `estado_inscripcion`

Separate from `estado`, tracks data completeness:
`sin_iniciar`, `parcial`, `completa`

#### Key Structural Points

- **Polymorphic FK**: Has either `cotizacion_abierta` OR `cotizacion_cerrada`, enforced by both a `CheckConstraint` at DB level and `clean()` validation
- **curso_asociado**: Optional direct FK to CursoAgendado for reagendamiento cases where the ficha is migrated to a new curso
- **ficha_origen**: Self-referential FK for tracking reagendamiento lineage
- **Constraint**: `logistica_ficha_una_sola_cotizacion` ensures only one of the two FKs is set

#### Transition Triggers

| Transition | Trigger | Source |
|---|---|---|
| pendiente → confirmada | Manual action by logistica staff | View or API call |
| confirmada → (course state changes) | FichaDeInscripcion post_save signal | `logistica/signals.py: verificar_confirmacion_curso_al_confirmar_ficha` |
| any → cancelada | `_cancelar_relacionados()` on curso | `CursoAgendado._cancelar_relacionados()` with `_skip_signal=True` |
| any → cancelada | Cotizacion `aceptada → rechazada` transition | `ventas/views.py` cambiar_estado handlers |
| any → cancelada | Cotizacion `duplicar` with `es_recotizacion=True` | `ventas/views.py` duplicar handlers |
| confirmada/en_proceso → completada | `_completar_fichas()` on curso FINALIZADO | `CursoAgendado._completar_fichas()` with `_skip_signal=True` |
| pendiente → cancelada | `_completar_fichas()` on curso FINALIZADO | Same — pending fichas cancelled when course finalizes |

#### Effect on CursoAgendado (via logistica/signals.py)

**When Participante added** (post_save, created=True):
- Finds associated cursos via cotizacion_abierta, cotizacion_cerrada, or curso_asociado
- If curso is PROSPECTADO and `alcanzo_minimo_participantes` → CONFIRMADO

**When FichaDeInscripcion saved** (post_save, not created):
- If `estado == "confirmada"`:
  - For each associated curso in PROSPECTADO: if minimum reached → CONFIRMADO; if start date passed → VENCIDO
  - For each curso in CONFIRMADO: if start date reached → EN_PROCESO
- If `estado in ("en_proceso", "cancelada")`:
  - For each associated curso in CONFIRMADO: if below minimum → PROSPECTADO

**When Participante deleted** (post_delete):
- Only logs a warning — does NOT automatically degrade curso state
- Degradation only happens through explicit ficha state changes (cancelada/en_proceso)

#### `_skip_signal` Flag

When `_cancelar_relacionados()` or `_completar_fichas()` cascade-cancels or completes fichas, they set `instance._skip_signal = True` before saving. The `verificar_confirmacion_curso_al_confirmar_ficha` signal checks `getattr(instance, "_skip_signal", False)` at the start and returns early if set. This prevents feedback loops.

#### Confirming a Ficha (save() override)

When a ficha transitions to `"confirmada"`, the `save()` override:
1. Detects the transition using `select_for_update()` on the old instance
2. After the save, bulk-updates all active `Participante` records: `confirmado=True, fecha_confirmacion=timezone.now()`
3. All within the same `transaction.atomic()` block

---

### 5. Factura

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/models.py`

#### States

| State | Meaning |
|---|---|
| `borrador` | Draft |
| `emitida` | Issued |
| `timbrada` | Digitally stamped (SAT/CFDI) |
| `cancelada` | Cancelled |
| `pagada` | Fully paid |

#### Key Structural Points

- **Mutually exclusive FKs**: Either `cotizacion_abierta` OR `cotizacion_cerrada` (validated in `clean()` and `FacturaCreateUpdateSerializer.validate()`)
- Serializer blocks Factura creation when cotizacion is in `"rechazada"` or `"recotizada"` states
- `pagada` state is set automatically by `actualizar_saldo_pendiente()` when `saldo_pendiente <= 0`
- No signals connect Factura back to CursoAgendado or cotizacion state changes — billing is downstream only
- `notas_desvinculacion` + `cotizacion_original_ref` fields provide audit trail after cotizacion deletion

#### Pago Model

- `estado`: `pendiente`, `confirmado`, `rechazado`, `cancelado`
- Confirmed pagos reduce `saldo_pendiente` on the Factura
- When `saldo_pendiente` reaches zero, `actualizar_saldo_pendiente()` sets Factura to `"pagada"`
- Serializer validates `monto <= factura.saldo_pendiente`

---

## Cross-Entity Cascade Matrix

| Trigger | Entity Affected | Condition |
|---|---|---|
| CursoAgendado → CANCELADO | CotizacionAbierta → "rechazada" | All non-rejected cotizaciones |
| CursoAgendado → CANCELADO | CotizacionCerrada → "rechazada" | All non-rejected cotizaciones |
| CursoAgendado → CANCELADO | FichaDeInscripcion → "cancelada" | All non-cancelled fichas via cots + directas, `_skip_signal=True` |
| CursoAgendado → CANCELADO | Child recotizaciones → "rechazada" | One level deep only |
| CursoAgendado → FINALIZADO | FichaDeInscripcion → "completada" | fichas in "confirmada"/"en_proceso", `_skip_signal=True` |
| CursoAgendado → FINALIZADO | FichaDeInscripcion → "cancelada" | fichas in "pendiente", `_skip_signal=True` |
| CursoAgendado → VENCIDO | CotizacionAbierta → "vencida" | Cotizaciones in "borrador","realizada","enviada" |
| CursoAgendado → VENCIDO | CotizacionCerrada → "vencida" | Same |
| CursoAgendado.fechai changes | FichaDeInscripcion.fecha_limite_inscripcion | Non-confirmed/completed fichas only |
| CotizacionAbierta created | CursoAgendado → PROSPECTADO | If curso was AGENDADO |
| CotizacionAbierta → "rechazada" | CursoAgendado → AGENDADO | If no other active cotizaciones remain |
| CotizacionAbierta deleted | CursoAgendado → AGENDADO | If no remaining cotizaciones (from PROSPECTADO only) |
| CotizacionAbierta → "aceptada" | CursoAgendado → PROSPECTADO | If curso was AGENDADO (NOT CONFIRMADO) |
| CotizacionAbierta → "aceptada" → "rechazada" | FichaDeInscripcion → "cancelada" | All non-cancelled fichas (view, no signal) |
| CotizacionAbierta → "recotizada" | CotizacionAbierta (child) created; fichas → "cancelada" | |
| CotizacionCerrada added to M2M | CursoAgendado → PROSPECTADO | If curso was AGENDADO |
| CotizacionCerrada → "aceptada" | CursoAgendado CREATED at CONFIRMADO | One per group per item |
| CotizacionCerrada → "aceptada" | CursoAgendado → EN_PROCESO | If fechai already passed |
| CotizacionCerrada → "rechazada" | CursoAgendado → CANCELADO | If no other active cotizaciones |
| CotizacionCerrada → "aceptada" → "rechazada" | FichaDeInscripcion → "cancelada" | All non-cancelled fichas (view) |
| Participante created | CursoAgendado → CONFIRMADO | If PROSPECTADO and minimum reached |
| FichaDeInscripcion → "confirmada" | CursoAgendado → CONFIRMADO | If PROSPECTADO and minimum reached |
| FichaDeInscripcion → "confirmada" | CursoAgendado → VENCIDO | If PROSPECTADO and fechai already passed |
| FichaDeInscripcion → "confirmada" | CursoAgendado → EN_PROCESO | If CONFIRMADO and fechai passed |
| FichaDeInscripcion → "cancelada"/"en_proceso" | CursoAgendado → PROSPECTADO | If CONFIRMADO and below minimum |
| Pago confirmed | Factura → "pagada" | When saldo_pendiente <= 0 |

---

## Critical Signal Execution Order

### When CotizacionCerrada is accepted (view action)

1. View validates transition using `TRANSICIONES_VALIDAS`
2. View creates `CursoAgendado` instances with `estado="CONFIRMADO"` directly (bypass AGENDADO→PROSPECTADO)
3. View adds cursos to `cotizacion.cursos_agendados` M2M
4. M2M `post_add` signal fires: tries AGENDADO→PROSPECTADO (no-op since cursos already CONFIRMADO)
5. View sets `cotizacion.estado = "aceptada"` and saves
6. CotizacionCerrada `post_save` signal fires: checks for EN_PROCESO advancement if fechai passed

**Race condition**: Steps 2-3 and 5-6 are NOT inside a single `transaction.atomic()` at the view level. CursoAgendado instances survive even if `cotizacion.save()` fails.

### Alternative path via send_inscription_form

The `CotizacionCerradaViewSet.send_inscription_form` action contains a **duplicate** CursoAgendado creation path with differences:
- Uses `item.curso.instructor.first()` as default instructor (with fallback)
- `num_grupos` calculated as `math.ceil(total_participantes / 20)` (hardcoded 20 max)
- NOT wrapped in `transaction.atomic()`
- Creates `FichaDeInscripcion` immediately after acceptance

This is a second mechanism for accepting a CotizacionCerrada with subtly different behavior.

---

## Identified Edge Cases and Issues

### Issue 1: VENCIDO via pre_save bypasses `cambiar_estado()`

`actualizar_estado_curso_automatico` (pre_save) sets `instance.estado = "VENCIDO"` directly without calling `cambiar_estado()`. Result: `_cancelar_relacionados()` is NOT called. The `vencer_cotizaciones_por_curso_vencido` post_save signal handles cotizacion expiration, but fichas are not touched.

### Issue 2: Recotizacion chain only one level deep

`_cancelar_relacionados()` iterates `cotizacion.recotizaciones` but does not recurse. A three-level chain A → B → C leaves C's fichas active when cancelling A.

### Issue 3: Two acceptance paths for CotizacionCerrada

`cambiar_estado("aceptada")` and `send_inscription_form` both create CursoAgendado instances. Calling both on the same cotizacion produces duplicate CursoAgendado records. `send_inscription_form` checks for existing fichas but not for existing cursos.

### Issue 4: CONFIRMADO → AGENDADO on last CotizacionAbierta rejection

When the last active CotizacionAbierta is rejected, the signal reverts the curso from PROSPECTADO or CONFIRMADO to AGENDADO. However, if the curso reached CONFIRMADO via participant minimum (not via cotizacion acceptance), reverting to AGENDADO discards that participant-driven confirmation.

### Issue 5: No automatic FichaDeInscripcion creation on CotizacionAbierta acceptance

The standard `CotizacionAbierta.cambiar_estado("aceptada")` does NOT create a ficha. Only `send_inscription_form` (a CotizacionCerrada action) creates fichas automatically. Open course ficha creation is a separate workflow step.

### Issue 6: Race condition on participant minimum check

`alcanzo_minimo_participantes` uses a live DB aggregate. Two concurrent participant additions may both see count below minimum, causing neither to trigger CONFIRMADO. No `select_for_update()` in `verificar_confirmacion_curso_al_agregar_participante`.

### Issue 7: `upload_pdf` implicit transition not in `TRANSICIONES_VALIDAS`

Both cotizacion types allow `borrador → realizada` only via the `upload_pdf` action. The view validates `estado == "borrador"` before proceeding. This works but the transition is not encoded in the model's `TRANSICIONES_VALIDAS` constant.

---

## Key File Reference

| File | Content |
|---|---|
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py` | CursoAgendado (states, `cambiar_estado`, `_cancelar_relacionados`, `_completar_fichas`, `actualizar_estado_automatico`) |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/signals.py` | Auto-state transitions on date change; VENCIDO → cotizacion expiration; fecha_limite update on reagendamiento |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/models.py` | CotizacionAbierta, CotizacionCerrada, ItemCotizacionCerrada, AutorizacionDescuento |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/signals.py` | Cotizacion post_save, post_delete, M2M signals → CursoAgendado state changes |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/views.py` | `cambiar_estado` actions (CursoAgendado creation on cerrada acceptance), `duplicar`, `send_inscription_form` |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/models.py` | FichaDeInscripcion (states, constraints, save override, prellenar, fecha_limite) |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/signals.py` | Participante/Ficha signals → CursoAgendado state changes |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/models.py` | Factura, Pago, NotaCredito, ComprobanteGasto |
| `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/serializers.py` | Factura validation (blocks rechazada/recotizada cotizaciones); FacturaCursoSerializer auto-link |

<!-- ============================================================ -->
<!-- END: STATE MACHINE ANALYSIS                                  -->
<!-- ============================================================ -->

---

## Previous Analysis Content Below

---

## Part 2: Focused Deep-Dive Analysis

### Topics: Multi-seller scenarios, Factura relationships, FichaDeInscripcion lifecycle, Reagendamiento

---

### 1. Multi-Seller Scenarios

#### CotizacionAbierta (open / public courses)

A `CotizacionAbierta` has a direct FK to a single `CursoAgendado` (`curso`). Multiple sellers can create separate `CotizacionAbierta` records all pointing to the same `CursoAgendado`. There is NO database-level or application-level uniqueness constraint preventing this.

**Key signal**: `actualizar_estado_curso_por_cotizacion_abierta`
File: `qsystem-backend/src/apps/ventas/signals.py` (lines 10-85)

**When one seller's quotation is accepted** (signal lines 33-61):
- `AGENDADO` → `PROSPECTADO` (if not already there)
- `PROSPECTADO` → `CONFIRMADO`
- `CONFIRMADO` + date already passed → `EN_PROCESO`

The acceptance of ANY single CotizacionAbierta drives the course to CONFIRMADO regardless of other sellers' quotations still being pending.

**When one seller's quotation is rejected** (signal lines 63-80 — the "last rejection" logic):
```python
otras_cotizaciones = (
    CotizacionAbierta.objects.filter(
        curso=curso, deleted_date__isnull=True
    )
    .exclude(id=instance.id)
    .exclude(estado__in=["rechazada", "vencida"])
    .exists()
)
if not otras_cotizaciones:
    if curso.estado in ["PROSPECTADO", "CONFIRMADO"]:
        curso.cambiar_estado("AGENDADO", "Sin cotizaciones activas")
```
The course returns to AGENDADO **only when ALL remaining active quotations are also rejected/vencida**. If Seller A is rejected but Seller B still has an active quotation, the course stays at its current state unchanged.

**Can two sellers both have "aceptada" CotizacionAbierta for the same course?**
Yes — nothing prevents it. `TRANSICIONES_VALIDAS` for CotizacionAbierta (models.py line 418) allows `enviada → aceptada`. There is no uniqueness constraint on `(curso, estado='aceptada')`. The signal on second acceptance is idempotent (tries to move course to CONFIRMADO but it is already there). **This is a data integrity gap** — two sellers could both invoice the same course.

#### CotizacionCerrada (closed / private courses)

CotizacionCerrada uses a ManyToMany relationship to CursoAgendado via `cursos_agendados`.

**The critical `pre_add` exclusivity guard** (`qsystem-backend/src/apps/ventas/signals.py` lines 209-238):
```python
conflictos = (
    CotizacionCerrada.objects.filter(
        cursos_agendados__pk__in=pk_set,
        deleted_date__isnull=True,
    )
    .exclude(pk=instance.pk)
    .distinct()
)
if conflictos.exists():
    raise ValidationError(
        f"Los cursos ya pertenecen a otra(s) cotización(es) cerrada(s) activa(s): {ids_conflicto}"
    )
```
A `CursoAgendado` can belong to exactly one active `CotizacionCerrada`. Adding the same course to a second quotation raises a `ValidationError`. **This is a hard exclusive constraint** — unlike open quotations.

**When a CotizacionCerrada is rejected — "last rejection" logic** (signal lines 141-159):
```python
otras = (
    CotizacionCerrada.objects.filter(
        cursos_agendados=curso, deleted_date__isnull=True
    )
    .exclude(id=instance.id)
    .exclude(estado__in=["rechazada", "vencida", "recotizada"])
    .exists()
)
if not otras and curso.estado not in ["CANCELADO", "FINALIZADO"]:
    curso.cambiar_estado("CANCELADO", ...)
```
Unlike open quotations, rejecting the last CotizacionCerrada sends the course to **CANCELADO** — not AGENDADO. This is the most important asymmetry between the two types.

**Summary: Asymmetric rejection behavior**

| Quotation Type | On last rejection | Course destination |
|---|---|---|
| CotizacionAbierta | All others rejected/vencida | → AGENDADO |
| CotizacionCerrada | All others rejected/vencida/recotizada | → CANCELADO |

---

### 2. Invoice (Factura) Relationships

#### There is NO FacturaPartida model

The term `FacturaPartida` does not exist anywhere in the codebase. Searching confirmed zero matches. Invoice line items are called `ItemFactura` (contabilidad/models.py line 279). There is no per-quotation-line-item invoice linking.

#### Factura links to quotations

File: `qsystem-backend/src/apps/contabilidad/models.py`

```python
cotizacion_abierta = ForeignKey("ventas.CotizacionAbierta", on_delete=SET_NULL, null=True)
cotizacion_cerrada = ForeignKey("ventas.CotizacionCerrada", on_delete=SET_NULL, null=True)
```

`clean()` enforces mutual exclusivity. Multiple Factura records can reference the same quotation (no uniqueness constraint) — partial invoicing is supported by design.

#### What happens to invoices when a quotation is cancelled/rejected?

**Nothing automatic.** The `on_delete=SET_NULL` means:
- If the CotizacionAbierta/CotizacionCerrada is **hard deleted**, the Factura's FK becomes NULL (desvinculada)
- If the quotation is only **soft-deleted** or set to `estado="rechazada"` (the common case), the FK continues pointing to the rejected quotation — Factura stays in whatever state it had

No signal or view logic auto-cancels a Factura when its quotation is rejected. The `_cancelar_relacionados` method in CursoAgendado (core/models.py line 896) only touches cotizaciones and fichas — invoices are completely excluded from the cascade.

Desvinculadas invoices are identifiable via:
```python
Factura.objects.filter(
    cotizacion_abierta__isnull=True,
    cotizacion_cerrada__isnull=True,
    notas_desvinculacion__isnull=False,
)
```
(contabilidad/views.py lines 99-105)

#### What happens to invoices when a course is CANCELLED?

Nothing automatic to invoices. The cancellation cascade is:
`CursoAgendado → cotizaciones (estado="rechazada") → fichas (estado="cancelada")`
Invoices survive unchanged.

#### Can you have multiple invoices for the same quotation?

Yes. No unique constraint exists. This is intentional for installment/partial billing scenarios.

---

### 3. FichaDeInscripcion Deep Dive

#### Model location
`qsystem-backend/src/apps/logistica/models.py` line 103

#### Linking structure (polymorphic FK)

The ficha holds exactly one of two FKs (enforced by `CheckConstraint` named `logistica_ficha_una_sola_cotizacion` and `clean()` validation):
```python
cotizacion_abierta = ForeignKey(CotizacionAbierta, on_delete=CASCADE, null=True)
cotizacion_cerrada = ForeignKey(CotizacionCerrada, on_delete=CASCADE, null=True)
```
Both use `on_delete=CASCADE` — if a quotation is hard-deleted, all its fichas are hard-deleted too.

#### Reaching CursoAgendado from a ficha

- Via abierta: `ficha.cotizacion_abierta.curso` (single course, direct FK)
- Via cerrada: `ficha.cotizacion_cerrada.cursos_agendados.all()` (can be multiple courses)
- Via reagendamiento: `ficha.curso_asociado` (a third path for rescheduled fichas, `on_delete=SET_NULL`)

The convenience property `ficha.curso_agendado` (logistica/models.py line 634) only returns `cursos_agendados.first()` for cerrada fichas — this is a potential issue for multi-course quotations.

#### Participante relationship

`Participante → FichaDeInscripcion` FK with `on_delete=CASCADE` (logistica/models.py line 659).

When a ficha is confirmed, `save()` atomically bulk-updates all active participants to `confirmado=True`:
```python
if is_confirming:
    self.participantes.filter(state=True).update(
        confirmado=True, fecha_confirmacion=timezone.now()
    )
```

#### What happens to fichas when course state changes?

**CANCELADO** — `CursoAgendado._cancelar_relacionados()` (core/models.py line 896):
1. Each CotizacionAbierta → estado = "rechazada" → all non-cancelled fichas → "cancelada"
2. Each CotizacionCerrada → estado = "rechazada" → all non-cancelled fichas → "cancelada"
3. Each ficha in `fichas_directas` (curso_asociado=this course) → "cancelada"
4. Recursively follows `cotizacion.recotizaciones` children
All ficha saves use `_skip_signal=True` to prevent re-entrant signal loops.

**FINALIZADO** — `CursoAgendado._completar_fichas()` (core/models.py line 968):
- Fichas in `confirmada` or `en_proceso` → "completada"
- Fichas in `pendiente` or `cancelada` are NOT touched (left as-is)

**CONFIRMADO degradation** (logistica/signals.py line 163-181):
When a ficha transitions to `cancelada` or `en_proceso` (reversal), if the course is CONFIRMADO and no longer meets minimum participants, the course degrades to PROSPECTADO.

#### Ficha validation logic (confirmation requirements)

`FichaInscripcionService.confirmar_ficha` (ficha_inscripcion_service.py line 22):
1. `ficha.estado != "confirmada"` — not already confirmed
2. `ficha.numero_participantes_actuales > 0` — at least one participant
3. Zero incomplete participants: all must have `nombre`, `apellido_paterno`, `curp`, `puesto`, `genero` — no empty strings, no CURPs starting with "XXXX" or "TEMP"

Only on passing all three is the ficha marked `confirmada`.

---

### 4. Rescheduling (Reagendamiento)

#### What rescheduling is in this codebase

There is NO REAGENDADO course state (it was removed — mentioned in CLAUDE.md). Rescheduling is implemented as a **date mutation** on the existing CursoAgendado via PATCH. The dedicated `/reagendar` endpoint was deprecated.

Comment in `qsystem-backend/src/apps/logistica/views/cursos_logistica.py` (lines 193-195):
```
# [DEPRECATED] El endpoint /reagendar ha sido eliminado.
# Use PATCH /core/cursos-agendados/{id}/ para actualizar fechas del curso existente.
# El historial de reagendamiento se registra automáticamente.
```

#### Ficha deadline cascade on date change

Signal: `actualizar_fecha_limite_fichas_al_reagendar` (`qsystem-backend/src/apps/core/signals.py` line 157)

Triggers on `post_save` when `tracker.has_changed("fechai")`:
1. For each `CotizacionCerrada` linked to this course: find earliest `fechai` among all courses in that cotización, then update `fecha_limite_inscripcion` on all non-confirmed/non-completed fichas
2. For all `fichas_directas` (curso_asociado=this course) that are not confirmed/completed: set `fecha_limite_inscripcion = nueva_fechai`

#### ficha_origen / curso_asociado pattern for rescheduled fichas

When a participant confirms for a rescheduled course, a **new** FichaDeInscripcion is created:
- `ficha_origen` = FK to the original ficha (self-referential, `on_delete=SET_NULL`)
- `curso_asociado` = FK to the new CursoAgendado

`FichaInscripcionService.confirmar_reagendamiento` validates both fields must be set before proceeding. After confirmation the service optionally changes the course from AGENDADO to PROSPECTADO if at least one ficha is confirmed.

#### What changes when a course is rescheduled (date changed)?

| Entity | Effect |
|---|---|
| FichaDeInscripcion | `fecha_limite_inscripcion` updated via signal (non-confirmed/completed only) |
| Participantes | No effect |
| Facturas | No effect — FK and estado preserved |
| Cotizaciones | No effect — unless new dates push the course past thresholds triggering VENCIDO |
| Course estado | May change automatically (CONFIRMADO → EN_PROCESO if fechai passed, or AGENDADO → VENCIDO if fechaf passed) |

---

### Critical Issues Found

#### 1. Dual "aceptada" CotizacionAbierta — no guard
**File**: `qsystem-backend/src/apps/ventas/models.py` (no uniqueness constraint)
Two sellers can both have `estado="aceptada"` for quotations on the same CursoAgendado. The system would allow both to proceed to invoice generation.

#### 2. Asymmetric course cancellation on rejection
CotizacionCerrada rejection → CANCELADO (irreversible terminal state)
CotizacionAbierta rejection → AGENDADO (recoverable)
Operators must understand this asymmetry — mistakenly rejecting a cerrada quotation cannot be undone without admin intervention.

#### 3. Invoices survive quotation rejection with no automatic action
No cascade from quotation rejection to Factura estado. Invoices in "emitida" or "timbrada" remain active even after the underlying commercial transaction is cancelled. Requires manual intervention.

#### 4. `ficha.curso_agendado` property returns only first course for cerrada fichas
`logistica/models.py` line 642: `return self.cotizacion_cerrada.cursos_agendados.first()`
Any logic using this property for multi-course quotations silently ignores courses after the first.

#### 5. Participant deletion does NOT degrade course state
`post_delete` on Participante only logs a warning — no automatic CONFIRMADO → PROSPECTADO degradation when participant count drops below minimum after a deletion.

---

## References

### Key Files for This Analysis
- `qsystem-backend/src/apps/ventas/signals.py` — lines 10-85 (open rejection "last rejection" logic), lines 141-159 (closed rejection → CANCELADO), lines 209-238 (pre_add exclusivity guard)
- `qsystem-backend/src/apps/ventas/views.py` — lines 825-838 (ficha cancel on cerrada rejection), lines 1865-1878 (ficha cancel on abierta rejection)
- `qsystem-backend/src/apps/ventas/models.py` — lines 134 and 418 (TRANSICIONES_VALIDAS for both types)
- `qsystem-backend/src/apps/logistica/models.py` — lines 103-648 (FichaDeInscripcion model, constraints, properties)
- `qsystem-backend/src/apps/logistica/services/ficha_inscripcion_service.py` — full file (all ficha state transitions and reagendamiento confirmation)
- `qsystem-backend/src/apps/contabilidad/models.py` — lines 10-277 (Factura, ItemFactura — no FacturaPartida)
- `qsystem-backend/src/apps/core/models.py` — lines 815-1000 (cambiar_estado, _cancelar_relacionados, _completar_fichas)
- `qsystem-backend/src/apps/core/signals.py` — lines 157-235 (fecha_limite cascade on reagendamiento)
- `qsystem-backend/src/apps/core/tests/test_cascading_cancellation.py` — full file (test coverage for cascade)

---

**Next Steps**:
1. Decide whether dual-accepted open quotations need a DB-level partial unique index or application-level guard in `cambiar_estado`.
2. Clarify with accounting team: should rejecting a quotation automatically void associated unpaid invoices?
3. Evaluate adding a `cursos_agendados` M2M to FichaDeInscripcion to replace the fragile `.first()` property for cerrada fichas.

---

## Part 1: Original Analysis (preserved below)


---

## Executive Summary

The QSystem backend implements a tightly coupled, event-driven state machine across four interdependent modules: `core` (CursoAgendado), `ventas` (CotizacionCerrada / CotizacionAbierta / ItemCotizacionCerrada), `logistica` (FichaDeInscripcion / Participante), and `contabilidad` (Factura / ItemFactura). State changes in one entity cascade to multiple others through a combination of Django signals, model methods, and service-layer logic.

The central orchestrator is `CursoAgendado`: its state drives downstream changes to quotations, enrollment forms, and ultimately invoices. Quotation acceptance (both open and closed types) triggers automated creation of CursoAgendado records and links them to FichaDeInscripcion records. The FichaDeInscripcion model implements a secondary enrollment lifecycle that reflects and influences the course state through participant counts. The Factura model sits at the terminus of this flow, referencing cotizaciones directly and remaining structurally independent from state cascades once created.

A critical design note: the system has two parallel quotation types — CotizacionAbierta (for open/catalog courses, direct FK to CursoAgendado) and CotizacionCerrada (for closed/private courses, M2M to CursoAgendado). Both share identical ESTADO_CHOICES and TRANSICIONES_VALIDAS logic, but their cascade behaviors differ in important ways documented below.

---

## Project Architecture

### Technology Stack
- **Backend**: Django + Django REST Framework, PostgreSQL 15
- **Key Libraries**: simple-history (audit trail on CursoAgendado), model-utils FieldTracker (CursoAgendado), django-filter, django.db.transaction with select_for_update throughout
- **Infrastructure**: Docker, docker-compose

### Directory Structure
```
qsystem-backend/src/apps/
├── core/
│   ├── models.py             # CursoAgendado, CursoCatalogo, BaseModel, ConfiguracionSistema
│   ├── signals.py            # CursoAgendado pre/post_save, m2m_changed (plazas, materiales)
│   ├── services/
│   │   └── curso_agendado_service.py   # reagendar_simple, transfer_relationships, etc.
│   └── views/cursos_agendados.py       # CursoAgendadoViewSet
├── ventas/
│   ├── models.py             # CotizacionCerrada, ItemCotizacionCerrada, CotizacionAbierta
│   ├── signals.py            # post_save/post_delete on both cotizacion types, m2m_changed
│   └── views.py              # CotizacionCerradaViewSet, CotizacionAbiertaViewSet
├── logistica/
│   ├── models.py             # FichaDeInscripcion, Participante, Costo, ServicioReceso
│   ├── signals.py            # post_save on Participante and FichaDeInscripcion
│   ├── services/
│   │   └── ficha_inscripcion_service.py
│   └── views/fichas_inscripcion.py
└── contabilidad/
    ├── models.py             # Factura, ItemFactura, Pago, NotaCredito, ComprobanteGasto
    └── views.py              # FacturaViewSet
```

---

## Detailed Analysis

---

### 1. CursoAgendado

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py` line 516

**State Choices (ESTADO_CHOICES)**:
```
AGENDADO      -> Course exists but has no quotations
PROSPECTADO   -> Has at least one active quotation
CONFIRMADO    -> Has accepted quotations or reached min participants
EN_PROCESO    -> Currently executing (fechai reached)
FINALIZADO    -> Completed (terminal)
CANCELADO     -> Cancelled definitively (terminal)
VENCIDO       -> fechai passed without confirmation
```

**Valid State Transitions (inside cambiar_estado() method)**:
```
AGENDADO     -> [PROSPECTADO, CANCELADO, VENCIDO]
PROSPECTADO  -> [CONFIRMADO, CANCELADO, VENCIDO, AGENDADO]
CONFIRMADO   -> [EN_PROCESO, CANCELADO, PROSPECTADO, AGENDADO]
EN_PROCESO   -> [FINALIZADO, CANCELADO]
FINALIZADO   -> []   (terminal)
CANCELADO    -> []   (terminal)
VENCIDO      -> [CONFIRMADO, AGENDADO, CANCELADO]
```

**Key Fields**:
- tipo_curso: "abierto" | "cerrado" determines which cotizacion relationship to follow
- historial_cambios_estado (JSONField): full audit log with fecha, usuario, estado_anterior, estado_nuevo, motivo, tipo
- historial_reagendamientos, historial_cambios_instructor, historial_cambios_ubicacion, historial_cambios_plaza, historial_cambios_materiales: separate JSON audit fields
- veces_reagendado, ultima_fecha_reagendamiento: rescheduling counters
- min_participantes_confirmacion (default 5): threshold for auto-confirmation via participants
- tracker = FieldTracker(fields=["fechai", "fechaf", "instructor"]): used in pre_save signal

**Foreign Key Relationships (outgoing)**:
- curso -> CursoCatalogo (CASCADE)
- instructor -> Instructor (CASCADE, nullable)
- lugar_curso -> LugarCurso (CASCADE, nullable)
- plaza -> M2M to Plaza
- usuario_cambio_estado -> User (SET_NULL)
- usuario_ultimo_reagendamiento -> User (SET_NULL)
- usuario_eliminacion -> User (SET_NULL)
- materiales_seleccionados -> M2M to logistica.MaterialCursoCatalogo

**Reverse Relationships (incoming)**:
- cotizaciones_abiertas <- CotizacionAbierta.curso (SET_NULL)
- cotizaciones_cerradas <- CotizacionCerrada.cursos_agendados (M2M)
- fichas_directas <- FichaDeInscripcion.curso_asociado (SET_NULL)
- comprobantes_gasto <- ComprobanteGasto.curso_agendado

**cambiar_estado(nuevo_estado, motivo, usuario)**:
- Acquires select_for_update() lock, re-reads current state from DB before validating
- Appends to historial_cambios_estado JSON array
- On CANCELADO: calls _cancelar_relacionados()
- On FINALIZADO: calls _completar_fichas()

**_cancelar_relacionados()**:
- Sets all CotizacionAbierta linked to this course -> estado="rechazada" (unless already rechazada)
- Sets all FichaDeInscripcion on those cotizaciones -> estado="cancelada" (_skip_signal=True)
- Follows cotizacion.recotizaciones chain recursively, cancelling children too
- Same logic for CotizacionCerrada (via M2M)
- Also cancels fichas_directas (rescheduled fichas linked directly to this course)

**_completar_fichas()**:
- Fichas in "confirmada" or "en_proceso" -> "completada" (_skip_signal=True)
- Covers fichas via CotizacionAbierta, CotizacionCerrada, and fichas_directas

**actualizar_estado_automatico()**:
- Programmatic method (called explicitly, not via signal)
- VENCIDO if past fechaf and in AGENDADO/PROSPECTADO
- FINALIZADO if past fechaf and in CONFIRMADO/EN_PROCESO
- CONFIRMADO if PROSPECTADO and has accepted cotizacion
- EN_PROCESO if CONFIRMADO and fechai reached

**verificar_vencimiento()**:
- Called on every list and retrieve API call
- Transitions AGENDADO/PROSPECTADO -> VENCIDO if fechai < today

**transfer_relationships(nuevo_curso, opciones)**:
- For "abierto": bulk-updates CotizacionAbierta.curso FK to new course; reactivates "vencida" quotations
- For "cerrado": M2M adds existing CotizacionCerrada to new course
- Fichas are NOT transferred; they remain with their cotizaciones (which now point to new course)
- Optionally copies "autorizado" Costo records (deep clone)

**Visibility Properties**:
- visible_en_logistica: True unless CANCELADO or FINALIZADO
- visible_en_contabilidad: True only if (CONFIRMADO|EN_PROCESO|FINALIZADO) AND tiene_compromisos_economicos

---

### 2. CotizacionCerrada / ItemCotizacionCerrada

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/models.py` line 87

**State Choices (ESTADOS)**:
```
borrador    -> Initial draft state
realizada   -> PDF uploaded; formally issued
enviada     -> Sent to client via email
aceptada    -> Client accepted
rechazada   -> Rejected or cancelled
recotizada  -> Superseded by a new quotation (terminal)
vencida     -> Expired
```

**Valid State Transitions (TRANSICIONES_VALIDAS)**:
```
borrador    -> [realizada]
realizada   -> [enviada, rechazada, recotizada]
enviada     -> [aceptada, rechazada, recotizada]
rechazada   -> [recotizada]
recotizada  -> []   (terminal)
aceptada    -> [rechazada]
vencida     -> [realizada]   (reactivation after rescheduling)
```

**Foreign Key Relationships**:
- cliente -> core.Cliente (CASCADE)
- recotizada_de -> self (SET_NULL): recotizacion chain
- cursos_agendados -> M2M to core.CursoAgendado (related_name="cotizaciones_cerradas")
- curso_agendado_original -> core.CursoAgendado (SET_NULL): desvinculacion audit reference
- items <- ItemCotizacionCerrada.cotizacion (CASCADE, related_name="items")
- fichas_inscripcion <- FichaDeInscripcion.cotizacion_cerrada (CASCADE)
- facturas <- Factura.cotizacion_cerrada (SET_NULL)
- autorizaciones_descuento <- AutorizacionDescuento.cotizacion_cerrada

**ItemCotizacionCerrada Key Fields**:
- cotizacion -> CotizacionCerrada (CASCADE)
- curso -> CursoCatalogo (CASCADE)
- precio_unitario, num_participantes, num_grupos, descuento_porcentaje, descuento_monto, precio_subtotal
- fecha_propuesta_inicio, fecha_propuesta_fin, duracion, lugar, modalidad
- incluye_desayuno, incluye_comida, incluye_coffee, incluye_material, incluye_diploma
- save() triggers cotizacion.calcular_totales() atomically with select_for_update()

**State Transition Logic via API Actions**:

upload_pdf action:
- Only valid when estado="borrador"
- Saves PDF file and transitions borrador -> realizada

send_email action:
- Only valid when estado in ["realizada", "enviada"]
- On email success: transitions to "enviada"

cambiar_estado action - transitioning to "aceptada":
- Creates one CursoAgendado per ItemCotizacionCerrada per num_grupos
- Created courses: tipo_curso="cerrado", estado="CONFIRMADO"
- If fechai already passed: immediately transitions created course to EN_PROCESO
- Links all created courses via cotizacion.cursos_agendados.add()

cambiar_estado action - "aceptada" -> "rechazada":
- Soft-deletes all FichaDeInscripcion on this cotizacion
- Sets ficha.estado="cancelada"

cambiar_estado action - any state -> "realizada" (reactivation path):
- If soft-deleted fichas exist: restores them
- Sets ficha.estado to "en_proceso" (if has participants) or "pendiente"
- IMPORTANT: overrides nuevo_estado to "aceptada" if fichas were restored

duplicar action (es_recotizacion=True):
- Marks original cotizacion as "recotizada"
- Soft-deletes all fichas on original
- Creates new CotizacionCerrada with recotizada_de reference, estado="realizada"
- Duplicates all items

**M2M Signal Constraints (ventas/signals.py)**:
- pre_add: validates no course already belongs to another active CotizacionCerrada
- pre_add: validates courses match a CursoCatalogo in the cotizacion's items
- post_add: advances AGENDADO courses -> PROSPECTADO

---

### 3. CotizacionAbierta

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/models.py` line 372

**State Choices and Transitions**: Identical to CotizacionCerrada.

**Key Differences from CotizacionCerrada**:
- Single curso FK (not M2M) -> CursoAgendado (SET_NULL)
- precio_total calculated inline in save() using num_participantes and descuento_porcentaje
- Group discount applied automatically when num_participantes >= 2 (Factor 1 from ConfiguracionSistema)
- fecha_vencimiento defaults to curso.fechai if available
- clean() prevents reassigning to a CursoAgendado of a different CursoCatalogo
- Multiple CotizacionAbierta can reference the same CursoAgendado (multi-seller model)

**Signal Behavior (ventas/signals.py)**:
- Created + AGENDADO -> PROSPECTADO
- estado="aceptada" -> chain AGENDADO -> PROSPECTADO -> CONFIRMADO
- estado="rechazada" + no other active cotizaciones -> AGENDADO (downgrade, NOT CANCELADO)
- post_delete: last cotizacion deleted -> PROSPECTADO reverts to AGENDADO

---

### 4. FichaDeInscripcion

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/models.py` line 103

**State Choices (ESTADO_CHOICES)**:
```
pendiente    -> Created, no participants yet
en_proceso   -> Participants being added
confirmada   -> All required data complete; confirmed
completada   -> Course finished (terminal, set by _completar_fichas)
cancelada    -> Cancelled (reversible unless cotizacion also cancelled)
```

**ESTADO_INSCRIPCION_CHOICES** (tracks data completeness separately from workflow state):
```
sin_iniciar  -> No participant data entered
parcial      -> Some participants have data
completa     -> All expected participants have full required data
```

**Foreign Key Relationships**:
- cotizacion_abierta -> ventas.CotizacionAbierta (CASCADE, nullable)
- cotizacion_cerrada -> ventas.CotizacionCerrada (CASCADE, nullable)
- ficha_origen -> self (SET_NULL): rescheduling chain, original ficha
- curso_asociado -> core.CursoAgendado (SET_NULL): direct link for rescheduled fichas
- participantes <- Participante.ficha_inscripcion (CASCADE)

**DB Constraint**: logistica_ficha_una_sola_cotizacion - exactly ONE of cotizacion_abierta or cotizacion_cerrada must be non-null (enforced at DB CheckConstraint level AND model.clean()).

**Computed Properties**:
- cotizacion: returns whichever FK is set
- tipo: "abierto" | "cerrado"
- curso_agendado: for abiertas -> cotizacion_abierta.curso; for cerradas -> cotizacion_cerrada.cursos_agendados.first()
- numero_participantes_actuales: count of active Participantes
- numero_participantes_con_datos: count with all required fields (nombre, apellido, CURP, puesto, genero); excludes CURP starting with "XXXX" or "TEMP"
- esta_completa: numero_participantes_actuales >= num_participantes_esperados

**FichaInscripcionService State Transitions**:

confirmar_ficha:
- Requires: estado != "confirmada", numero_participantes_actuales > 0, zero incomplete participants
- Transition: any -> "confirmada"
- Sets fecha_confirmacion = now()
- Atomically sets all active Participante.confirmado = True

revertir_confirmacion:
- Requires: estado == "confirmada"
- Transition: "confirmada" -> "en_proceso"
- Sets fecha_confirmacion = None
- Resets all Participante.confirmado = False

cancelar_ficha:
- Requires: estado not in ["cancelada", "completada"]
- Transition: any -> "cancelada"

reactivar_ficha:
- Requires: estado == "cancelada"
- Restores soft-delete if deleted_date is set
- Transition: "cancelada" -> "en_proceso" (if has participants) or "pendiente"

confirmar_reagendamiento:
- Requires: ficha.curso_asociado is set AND ficha.ficha_origen is set
- Confirms attendance at rescheduled course

**model save() behavior**:
- When transitioning to "confirmada": bulk-confirms all active participants
- On new ficha creation: calls _prellenar_datos_temporales() (copies empresa/contacto from cotizacion)
- _calcular_fecha_limite() priority order: CursoAgendado.fechai -> cotizacion.fecha_vencimiento -> item.fecha_propuesta_inicio

---

### 5. Factura / ItemFactura

**Location**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/models.py` line 10

**State Choices (ESTADO_CHOICES)**:
```
borrador   -> Draft invoice
emitida    -> Issued, ready for SAT stamping
timbrada   -> Stamped with PAC (UUID assigned, folio fiscal)
cancelada  -> Cancelled (only from "timbrada")
pagada     -> Fully paid
```

**State Transitions (enforced per-action in views, NO central TRANSICIONES_VALIDAS)**:
- timbrar action: "emitida" -> "timbrada" (assigns UUID, fecha_timbrado)
- cancelar action: "timbrada" -> "cancelada" (optionally creates NotaCredito)
- marcar_pagada action: any non-pagada -> "pagada"
- actualizar_saldo_pendiente() method: if saldo_pendiente <= 0 -> auto-sets "pagada"

**Foreign Key Relationships**:
- cliente -> core.Cliente (PROTECT: cannot delete client with invoices)
- cotizacion_abierta -> ventas.CotizacionAbierta (SET_NULL, nullable)
- cotizacion_cerrada -> ventas.CotizacionCerrada (SET_NULL, nullable)
- items <- ItemFactura.factura (CASCADE)
- pagos <- Pago.factura (PROTECT)
- notas_credito <- NotaCredito.factura_origen (PROTECT)

**DB Constraint** (model.clean()): Cannot have both cotizacion_abierta AND cotizacion_cerrada simultaneously.

**ItemFactura**:
- importe = (cantidad * precio_unitario) - descuento (calculated in save())
- save() calls factura.calcular_totales() then factura.save() (cascade recalculation)

**Factura.calcular_totales()**:
- subtotal = sum of item importes
- iva = (subtotal - descuento) * 0.16
- total = subtotal - descuento + iva - retencion_iva - retencion_isr

**Pago Model**:
- estado: pendiente -> confirmado | rechazado | cancelado
- Confirmed payments summed for saldo_pendiente on Factura
- actualizar_saldo_pendiente() auto-marks Factura as "pagada" when fully settled

**Orphaned Invoice Detection**:
- notas_desvinculacion field populated when cotizacion is cascade-deleted
- Filter: ?desvinculadas=true returns invoices with both cotizacion FKs null but notas_desvinculacion set

---

## Complete State Machine Cascade Map

```
CursoAgendado.cambiar_estado("CANCELADO")
  -> _cancelar_relacionados()
       -> CotizacionAbierta(s) linked to course: estado="rechazada" (if not already)
            -> FichaDeInscripcion(s) on those cotizaciones: estado="cancelada" (_skip_signal=True)
            -> cotizacion.recotizaciones children: estado="rechazada"
                 -> their fichas: estado="cancelada" (_skip_signal=True)
       -> CotizacionCerrada(s) linked via M2M: estado="rechazada" (if not already)
            -> FichaDeInscripcion(s): estado="cancelada" (_skip_signal=True)
            -> cotizacion.recotizaciones children: same cascade
       -> fichas_directas (curso_asociado=this course): estado="cancelada" (_skip_signal=True)

CursoAgendado.cambiar_estado("FINALIZADO")
  -> _completar_fichas()
       -> FichaDeInscripcion in ["confirmada","en_proceso"] via CotizacionAbierta -> "completada"
       -> FichaDeInscripcion in ["confirmada","en_proceso"] via CotizacionCerrada -> "completada"
       -> fichas_directas in ["confirmada","en_proceso"] -> "completada"

CursoAgendado state -> "VENCIDO" [post_save signal: vencer_cotizaciones_por_curso_vencido]
  -> CotizacionAbierta(borrador|realizada|enviada) for this course:
       estado="vencida", estado_previo_vencimiento saved
  -> CotizacionCerrada(borrador|realizada|enviada) linked to this course:
       estado="vencida", estado_previo_vencimiento saved

CotizacionAbierta created [post_save signal: actualizar_estado_curso_por_cotizacion_abierta]
  -> If curso AGENDADO: cambiar_estado("PROSPECTADO")

CotizacionAbierta.estado="aceptada" [post_save signal]
  -> If curso AGENDADO: PROSPECTADO then CONFIRMADO (two sequential cambiar_estado calls)
  -> If curso PROSPECTADO: cambiar_estado("CONFIRMADO")
  -> If fechai passed: cambiar_estado("EN_PROCESO")

CotizacionAbierta.estado="rechazada" [post_save signal]
  -> Check for other active cotizaciones on same course
  -> If none: cambiar_estado("AGENDADO")  [NOTE: downgrade, NOT CANCELADO]

CotizacionAbierta deleted [post_delete signal]
  -> If was last active cotizacion: PROSPECTADO -> AGENDADO

CotizacionCerrada.estado="aceptada" [post_save signal]
  -> For each linked CursoAgendado:
       AGENDADO -> PROSPECTADO -> CONFIRMADO
       CONFIRMADO + fechai passed -> EN_PROCESO

CotizacionCerrada created [post_save signal]
  -> For each linked CursoAgendado AGENDADO: -> PROSPECTADO

CotizacionCerrada.estado="rechazada" [post_save signal]
  -> For each linked CursoAgendado: if no other active cerradas -> CANCELADO
  [NOTE: CANCELADO, not AGENDADO - asymmetry with abierta rejection]

CotizacionCerrada M2M post_add [m2m signal]
  -> For each newly added CursoAgendado AGENDADO: -> PROSPECTADO

CotizacionCerrada.cambiar_estado("aceptada") [API action - ventas/views.py]
  -> Creates CursoAgendado per item x num_grupos
       tipo_curso="cerrado", estado="CONFIRMADO"
       If fechai passed: -> EN_PROCESO
  -> cotizacion.cursos_agendados.add(*cursos_creados)

CotizacionCerrada.cambiar_estado("aceptada"->"rechazada") [API action]
  -> FichaDeInscripcion(s): estado="cancelada" + soft-delete

CotizacionCerrada.duplicar(es_recotizacion=True) [API action]
  -> Original: estado="recotizada"
  -> Original fichas: estado="cancelada" + soft-delete
  -> New CotizacionCerrada: estado="realizada", recotizada_de=original

Participante created [post_save signal: verificar_confirmacion_curso_al_agregar_participante]
  -> For each curso linked via ficha:
       If PROSPECTADO + alcanzo_minimo_participantes: -> CONFIRMADO

FichaDeInscripcion.estado="confirmada" [post_save signal, not _skip_signal]
  -> For each linked curso:
       If PROSPECTADO + min alcanzado: -> CONFIRMADO
       If PROSPECTADO + fechai passed + min not reached: -> VENCIDO
       If CONFIRMADO + fechai passed: -> EN_PROCESO

FichaDeInscripcion.estado in ["en_proceso","cancelada"] [post_save signal]
  -> For each linked curso CONFIRMADO + below min: -> PROSPECTADO

CursoAgendado.fechai changed [post_save signal via FieldTracker]
  -> FichaDeInscripcion(via CotizacionCerrada, not confirmada/completada): update fecha_limite_inscripcion
  -> FichaDeInscripcion(fichas_directas, not confirmada/completada): update fecha_limite_inscripcion
```

---

## Multi-Seller / Multi-Cotizacion Scenarios

### Open Courses (CotizacionAbierta)
A single CursoAgendado of tipo_curso="abierto" can have MULTIPLE CotizacionAbierta records
pointing to it — one per interested client/seller combination.

- numero_interesados property: counts cotizaciones in [realizada, enviada, aceptada, rechazada],
  excludes "recotizada" to prevent duplicates
- AGENDADO downgrade: only triggered if ALL other cotizaciones are rechazada/vencida
- CONFIRMADO upgrade: triggered the moment ANY ONE cotizacion is accepted
- No exclusive ownership: multiple sellers can quote the same open course

### Closed Courses (CotizacionCerrada)
The M2M pre_add signal enforces that a CursoAgendado belongs to at most ONE active CotizacionCerrada.
This prevents two sellers from simultaneously quoting the same closed course session.

Critical asymmetry:
- CotizacionAbierta rejection -> course goes to AGENDADO (soft downgrade, recoverable)
- CotizacionCerrada rejection -> course goes to CANCELADO (hard termination)
  Rationale: closed courses are purpose-created for a specific client; rejection = no longer needed.
  Risk: if the course pre-existed and the cotizacion is the first and only one, the course is
  permanently terminated on first rejection.

---

## Transfer / Reagendamiento Logic

### Simple Reschedule (CursoAgendadoService.reagendar_simple)
- Updates fechai, fechaf, horai, horaf in-place on the SAME CursoAgendado
- Validates instructor conflicts via InstructorAvailabilityService
- Does NOT create a new CursoAgendado record
- Triggers post_save signal -> actualizar_fecha_limite_fichas_al_reagendar
  -> Updates fecha_limite_inscripcion on all non-confirmed/non-completed fichas
- Increments veces_reagendado counter
- Appends to historial_reagendamientos JSON

### Complex Transfer (CursoAgendado.transfer_relationships)
- Creates a NEW CursoAgendado as the rescheduled version
- For "abierto": bulk-updates CotizacionAbierta.curso FK to point to new course
  -> Reactivates "vencida" cotizaciones (restores estado_previo_vencimiento)
- For "cerrado": M2M adds existing cotizaciones to new course
  -> Reactivates "vencida" cotizaciones
- Fichas are NOT moved; they remain with their cotizaciones (which now reference new course)
- fichas_directas use curso_asociado FK + ficha_origen FK chain for tracking rescheduled fichas
- Returns summary dict: {cotizaciones_transferidas, costos_copiados, fichas_mantenidas}

---

## Cancellation Scenarios

### Scenario 1: Course Cancelled Before Any Quotation (AGENDADO -> CANCELADO)
- _cancelar_relacionados() finds nothing to cascade
- State: terminal, no downstream effects

### Scenario 2: Open Course Cancelled With Active Quotations
- All CotizacionAbierta -> "rechazada" (unless already rechazada)
- All FichaDeInscripcion on those cotizaciones -> "cancelada" (_skip_signal=True, NOT soft-deleted)
- Recotizacion chains followed and cancelled
- Factura records: SET_NULL on cotizacion_abierta FK, not deleted

### Scenario 3: Closed Course Cancelled With Accepted Cotizacion + Fichas
- CotizacionCerrada -> "rechazada"
- FichaDeInscripcion -> "cancelada" (_skip_signal=True, NOT soft-deleted here)
- Factura: SET_NULL on cotizacion_cerrada FK

### Scenario 4: Quotation Rejected (Abierta) — Course Has Other Active Quotations
- Signal: otras_cotizaciones = CotizacionAbierta.filter(curso=curso).exclude(id=instance.id).exclude(estado__in=["rechazada","vencida"]).exists()
- If True: NO course state change; course stays PROSPECTADO or CONFIRMADO
- The rejected cotizacion's fichas are NOT automatically cancelled in this scenario

### Scenario 5: Course Vencido
- Trigger: FieldTracker detects fechai/fechaf change (pre_save) OR verificar_vencimiento() on list/retrieve
- AGENDADO/PROSPECTADO -> VENCIDO
- post_save signal: all borrador/realizada/enviada cotizaciones -> "vencida" (saves estado_previo_vencimiento)
- Reactivation: VENCIDO -> CONFIRMADO, AGENDADO, or CANCELADO (manual)

---

## Critical Issues and Anti-Patterns

### Issue 1: Duplicate CursoAgendado Creation Paths
Two separate code paths in ventas/views.py create CursoAgendado for closed quotations:
1. CotizacionCerradaViewSet.cambiar_estado (lines 751-812): the primary correct path
2. CotizacionCerradaViewSet.send_inscription_form (lines 1284-1398): legacy path that also
   creates courses, transitions cotizacion to "aceptada", AND creates FichaDeInscripcion

These paths are not synchronized. If the primary path is updated, send_inscription_form is a
maintenance hazard.

### Issue 2: Asymmetric Rejection Behavior (Abierta vs Cerrada)
- Abierta rejection -> AGENDADO (recoverable)
- Cerrada rejection -> CANCELADO (terminal)
This is intentional per business logic but undocumented. If a closed course needs to be
re-offered after rejection, there is no recovery path — a new CursoAgendado must be created.

### Issue 3: FichaDeInscripcion.save() Calls full_clean()
Every save() on FichaDeInscripcion calls self.full_clean(), including cascade saves from
_cancelar_relacionados() and _completar_fichas(). The _skip_signal flag bypasses signal
re-triggering but NOT validation. If data is inconsistent, ValidationError could interrupt
the cancellation cascade.

### Issue 4: _skip_signal Pattern
The _skip_signal = True attribute set on instances before save is a non-standard pattern.
If a new signal handler is added to logistica/signals.py without checking _skip_signal,
cascade loops become possible. Current handlers do check: getattr(instance, "_skip_signal", False).

### Issue 5: Factura Has No TRANSICIONES_VALIDAS Map
Unlike cotizaciones, the Factura state machine has no central transition guard. Arbitrary
PATCH requests can set estado to any value. Only the specific action endpoints (timbrar,
cancelar, marcar_pagada) enforce transitions.

### Issue 6: cambiar_estado("realizada") Silent Override to "aceptada"
In ventas/views.py lines 841-860, transitioning a CotizacionCerrada to "realizada" can
silently result in the cotizacion ending at "aceptada" state if soft-deleted fichas are
restored. The API response reflects the final state but the intent mismatch could confuse
frontend code.

---

## References

### Key Files Analyzed
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py`: CursoAgendado (line 516)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/signals.py`: all 4 signal handlers
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/models.py`: CotizacionCerrada (line 87), CotizacionAbierta (line 372)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/signals.py`: all signal handlers
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/views.py`: cambiar_estado (line 673), duplicar (line 868), send_inscription_form (line 1173)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/models.py`: FichaDeInscripcion (line 103), Participante (line 650)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/signals.py`: all 3 signal handlers
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/services/ficha_inscripcion_service.py`: all state transitions
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/views/fichas_inscripcion.py`: all action endpoints
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/models.py`: Factura (line 10), ItemFactura (line 279), Pago (line 408)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/views.py`: FacturaViewSet actions
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/services/curso_agendado_service.py`: reagendar_simple

---

**Next Steps**:
1. Clarify Issue 1: determine if send_inscription_form should delegate to cambiar_estado("aceptada") or be deprecated
2. Decide on Issue 2: document the Cerrada-rejection-to-CANCELADO behavior as explicit business rule or align with Abierta behavior
3. Add TRANSICIONES_VALIDAS to Factura model for consistency
4. Consider extracting cotizacion cambiar_estado view logic into a service class
