# Codebase Analysis Report
**Generated**: 2026-02-23
**Analyst**: codebase-analyzer
**Request**: Thorough analysis of all management tabs — section by section, entity type, data classification (CATALOG / OPERATIONAL / SYSTEM CONFIG), and logical module ownership.

---

## Executive Summary

The Management area (`/management/*`) is a two-level tabbed admin interface. The top level has six tabs: Dashboard, General, Ventas, Logistica, Contabilidad, and Variables. Each tab renders a second-level grid of sub-sections. All sub-sections except the Variables key-value config pages are built on a shared `SectionBase` component (paginated table + modal form + trash mode).

There are exactly **35 distinct management sections** in total. They fall into three categories:
- **CATALOG** — reference data that rarely changes and is used as dropdown/lookup values across the system (e.g., Cursos Catálogo, Plazas, Tipos de Material).
- **OPERATIONAL** — records created and modified daily as business transactions occur (e.g., Cursos Agendados, Cotizaciones, Facturas).
- **SYSTEM CONFIG** — key-value pairs stored in `ConfiguracionSistema` that control business rule parameters (discount percentages, pricing factors) plus infrastructure settings (email/Graph API credentials, import jobs, catalog lookup tables for classification/department/area).

A routing mismatch is worth noting: the `VariablesTab` navigation tile for "Clasificaciones", "Departamentos", and "Áreas Temáticas" points to paths under `/management/variables/*`, but the section components for those three entities live physically in `src/pages/management/sections/general/` and use the shared `CatalogosTable`/`CatalogoForm`. This means they are catalog/reference data accidentally housed under the Variables tab.

---

## Project Architecture (relevant scope)

### Technology Stack
- **Frontend**: React 18, Vite, React Router v6, Tailwind CSS, React Bootstrap, react-toastify
- **State**: React Context (AuthContext, TrashModeContext, ThemeContext, QuotationContext)
- **API Layer**: Axios with interceptors (`src/api/axios.jsx`), per-module API files
- **Backend**: Django REST Framework, PostgreSQL, JWT auth (HttpOnly cookies)

### Directory Structure (management-relevant)
```
qsystem-frontend/src/
├── pages/management/
│   ├── ManagementLayout.jsx          # Top-level shell with tab nav
│   ├── tabs/
│   │   ├── GeneralTab.jsx            # 9 sub-sections
│   │   ├── VentasTab.jsx             # 2 sub-sections
│   │   ├── LogisticaTab.jsx          # 10 sub-sections
│   │   ├── ContabilidadTab.jsx       # 4 sub-sections
│   │   └── VariablesTab.jsx          # 8 sub-sections
│   └── sections/
│       ├── SectionBase.jsx           # Shared table+form+pagination wrapper
│       ├── general/                  # 12 section files (9 in nav + 3 misrouted from Variables)
│       ├── ventas/                   # 2 section files
│       ├── logistica/                # 10 section files
│       ├── contabilidad/             # 4 section files
│       └── variables/                # 5 section files
├── components/
│   └── ui/VariablesManager.jsx       # Key-value config editor (used by 3 Variables sub-sections)
└── api/
    ├── configuration.jsx             # /core/configuracion/ CRUD + por-modulo endpoint
    ├── courseClassifications.jsx     # /core/clasificaciones-curso/
    ├── departments.jsx               # /core/departamentos/
    ├── areasThematic.jsx             # /core/areas-tematicas/
    ├── logistics.jsx                 # fichas, tipos material, ocupaciones, diplomas, formatos, costos, materiales
    ├── accounting.jsx                # facturas, pagos, notas credito, comprobantes gasto
    ├── quotations.jsx                # cotizaciones abiertas + cerradas
    ├── imports.jsx                   # import jobs
    └── mailings.jsx                  # email config, test, history

qsystem-backend/src/apps/core/
├── models.py                         # ConfiguracionSistema (key-value store)
├── views/configuracion.py            # ViewSet with por-modulo, actualizar-multiple, inicializar-variables-ventas
└── management/commands/initialize_sales_variables.py  # Seeds 23 sales variables
```

---

## Complete Section Map

### TAB: General (9 visible sub-sections in nav)

| # | Section UI Label | Entity (Spanish) | Entity (English) | Data Type | Logical Module | File |
|---|---|---|---|---|---|---|
| 1 | Cursos Agendados | CursoAgendado | Scheduled Course | OPERATIONAL | General/Core | `sections/general/CursosAgendadosSection.jsx` |
| 2 | Cursos Catálogo | CursoCatalogo | Catalog Course | CATALOG | General/Core | `sections/general/CursosCatalogoSection.jsx` |
| 3 | Clientes | Cliente | Client (individual person) | CATALOG | General/Core | `sections/general/ClientesSection.jsx` |
| 4 | Empresas | Empresa | Company/Organization | CATALOG | General/Core | `sections/general/EmpresasSection.jsx` |
| 5 | Plazas | Plaza | Sales Territory/Region | CATALOG | General/Core | `sections/general/PlazasSection.jsx` |
| 6 | Lugares | Lugar | Physical Location/Venue | CATALOG | General/Core | `sections/general/LugaresSection.jsx` |
| 7 | Instructores | Instructor | Instructor (User subtype) | CATALOG | General/Core | `sections/general/InstructoresSection.jsx` |
| 8 | Vendedores | Vendedor | Seller (User subtype) | CATALOG | General/Core | `sections/general/VendedoresSection.jsx` |
| 9 | Administradores | Administrador | Admin (User subtype) | CATALOG | General/Core | `sections/general/AdministradoresSection.jsx` |

**Detail per General section:**

#### Cursos Agendados
- Entity: `CursoAgendado` — a specific scheduled instance of a catalog course, with dates, instructor(s), location, modality.
- Type: OPERATIONAL — new scheduled courses are created for every training session sold or planned.
- API function: `getScheduledCourses` from `@/api/scheduledCourses`
- Components: `ScheduledCoursesTable` + `ScheduledCourseForm`

#### Cursos Catálogo
- Entity: `CursoCatalogo` — the master course definition (name, duration, base price, classification, area tematica).
- Type: CATALOG — grows slowly; used as a dropdown/reference in Scheduled Courses and Quotations.
- API function: `getCatalogCourses` from `@/api/catalogCourses`
- Components: `CatalogCoursesTable` + `CatalogCourseForm`
- Note: The form references Clasificaciones, Departamentos, Áreas Temáticas as dropdowns, making those true catalog dependencies.

#### Clientes
- Entity: `Cliente` — an individual person (contact) who may belong to an `Empresa`.
- Type: CATALOG — grows as new contacts are added; used in Quotations, Fichas de Inscripción.
- API function: `getClients` from `@/api/clients`
- Components: `ClientsTable` + `ClientForm`

#### Empresas
- Entity: `Empresa` — a company/organization that contracts training.
- Type: CATALOG — grows as new client organizations are added.
- API function: `getCompanies` from `@/api/companies`
- Components: `CompaniesTable` + `CompanyForm`

#### Plazas
- Entity: `Plaza` — a geographic sales territory or region (e.g. "Monterrey", "CDMX").
- Type: CATALOG — rarely changes; used to categorize Cursos Agendados and Cotizaciones.
- API function: `getSalesTerritories` from `@/api/salesTerritories`
- Components: `SalesTerritoriesTable` + `SalesTerritoryForm`

#### Lugares
- Entity: `Lugar` — a physical venue or address where courses take place.
- Type: CATALOG — grows as new venues are added; referenced in Cursos Agendados.
- API function: `getLocations` from `@/api/locations`
- Components: `LocationsTable` + `LocationForm`

#### Instructores
- Entity: `Instructor` — a user account with the instructor role, including availability schedules.
- Type: CATALOG — grows as staff is hired; assigned to Cursos Agendados.
- API function: `getInstructors` from `@/api/instructors`
- Components: `InstructorsTable` + `InstructorForm`

#### Vendedores
- Entity: `Vendedor` — a user account with the seller role.
- Type: CATALOG — grows as sales staff is hired; linked to Cotizaciones.
- API function: `getSellers` from `@/api/sellers`
- Components: `SellersTable` + `SellerForm`

#### Administradores
- Entity: `Administrador` — a user account with the admin role (`role=admin`).
- Type: CATALOG — system administrators.
- API function: `getUsers({role: "admin"})` from `@/api/users`
- Components: `AdminsTable` + `AdminForm`

---

### TAB: Ventas (2 sub-sections)

| # | Section UI Label | Entity | Data Type | Logical Module | File |
|---|---|---|---|---|---|
| 1 | Cotizaciones Abiertas | CotizacionAbierta | OPERATIONAL | Ventas | `sections/ventas/CotizacionesAbiertasSection.jsx` |
| 2 | Cotizaciones Cerradas | CotizacionCerrada | OPERATIONAL | Ventas | `sections/ventas/CotizacionesCerradasSection.jsx` |

**Detail:**

#### Cotizaciones Abiertas
- Entity: Open-format quotations (flexible, not yet accepted/rejected). A distinct model from "Cerradas".
- Type: OPERATIONAL — created daily by sellers when prospecting clients.
- API function: `getCotizacionesAbiertas` from `@/api/quotations`
- Components: `OpenQuotationsTable` + `OpenQuotationForm`

#### Cotizaciones Cerradas
- Entity: `CotizacionCerrada` — finalized quotations with status lifecycle (borrador → enviada → aceptada/rechazada/vencida). These are the main quotation model with `PartidaCotizacion` line items.
- Type: OPERATIONAL — created when a quotation is confirmed/closed.
- API function: `getCotizacionesCerradas` from `@/api/quotations`
- Components: `ClosedQuotationsTable` + `ClosedQuotationForm`

---

### TAB: Logistica (10 sub-sections)

| # | Section UI Label | Entity | Data Type | Logical Module | File |
|---|---|---|---|---|---|
| 1 | Fichas de Cotizaciones Abiertas | FichaInscripcionAbierta | OPERATIONAL | Logistica | `sections/logistica/FichasAbiertasSection.jsx` |
| 2 | Fichas de Cotizaciones Cerradas | FichaInscripcionCerrada | OPERATIONAL | Logistica | `sections/logistica/FichasCerradasSection.jsx` |
| 3 | Costos | Costo | OPERATIONAL | Logistica | `sections/logistica/CostosSection.jsx` |
| 4 | Participantes | Participante | OPERATIONAL | Logistica | `sections/logistica/ParticipantesSection.jsx` |
| 5 | Diplomas y Constancias | Diploma | OPERATIONAL | Logistica | `sections/logistica/DiplomasSection.jsx` |
| 6 | Formatos de Asistencia | FormatoAsistencia | OPERATIONAL | Logistica | `sections/logistica/FormatosAsistenciaSection.jsx` |
| 7 | Tipos de Material | TipoMaterial | CATALOG | Logistica | `sections/logistica/TiposMaterialSection.jsx` |
| 8 | Ocupaciones Específicas | OcupacionEspecifica | CATALOG | Logistica | `sections/logistica/OcupacionesEspecificasSection.jsx` |
| 9 | Recesos | Receso | CATALOG/OPERATIONAL | Logistica | `sections/logistica/RecesosSection.jsx` |
| 10 | Materiales Entregados | MaterialEntregado | OPERATIONAL | Logistica | `sections/logistica/MaterialesEntregadosSection.jsx` |

**Detail:**

#### Fichas de Cotizaciones Abiertas
- Entity: `FichaInscripcionAbierta` — a registration/enrollment form linked to an open quotation. Tracks participants, logistics, status.
- Type: OPERATIONAL — created as part of the sales-to-delivery pipeline for open courses.
- API function: `getFichasInscripcionAbiertas` from `@/api/logistics`
- Components: `FichasInscripcionAbiertasTable` + `FichaInscripcionForm`

#### Fichas de Cotizaciones Cerradas
- Entity: `FichaInscripcionCerrada` — same structure but linked to a closed/confirmed quotation. Main logistics record for a confirmed training engagement.
- Type: OPERATIONAL — status lifecycle: pendiente → en_proceso → confirmada → completada → cancelada.
- API function: `getFichasInscripcionCerradas` from `@/api/logistics`
- Components: `FichasInscripcionCerradasTable` + `FichaInscripcionForm`

#### Costos
- Entity: `Costo` — an individual cost line item associated with a `CursoAgendado`. Has `tipo` (type of cost) and `estado` filters.
- Type: OPERATIONAL — recorded per course execution (instructor fees, venue, materials, food, etc.).
- Special: Custom implementation (not SectionBase) with tipo/estado/curso filters. Uses `COSTO_TIPOS` and `COSTO_ESTADOS` from `src/components/modals/CursoDetalle/constants/costoTypes`.
- API function: `getCostos` from `@/api/logistics`
- Components: `CostosTable` + `CostoForm`

#### Participantes
- Entity: `Participante` — an attendee enrolled in a specific `FichaInscripcion`.
- Type: OPERATIONAL — entered per course per client.
- Special: Requires selecting a `FichaInscripcion` first (two-level lookup). Custom implementation, not SectionBase.
- API functions: `getFichasInscripcion` (ficha dropdown) + `getParticipantesFicha(fichaId)` from `@/api/logistics`
- Components: `ParticipantesTable` + `ParticipanteForm`

#### Diplomas y Constancias
- Entity: `Diploma` — a diploma or certificate issued to a participant after course completion.
- Type: OPERATIONAL — generated individually or in bulk ("Generar Masivo" button via `DiplomaGenerarMasivoModal`).
- API function: `getDiplomas` from `@/api/logistics`
- Components: `DiplomasTable` + `DiplomaForm` + `DiplomaGenerarMasivoModal`

#### Formatos de Asistencia
- Entity: `FormatoAsistencia` — an attendance record for a course session.
- Type: OPERATIONAL — created per course session; tracks who attended.
- API function: `getFormatosAsistencia` from `@/api/logistics`
- Components: `FormatosAsistenciaTable` + `FormatoAsistenciaForm`

#### Tipos de Material
- Entity: `TipoMaterial` — a reference category for materials (e.g., "Manual", "USB", "Cuaderno").
- Type: CATALOG — small, rarely-changing list; used as a dropdown in material records.
- API function: `getTiposMaterial` from `@/api/logistics`
- Components: `TiposMaterialTable` + `TipoMaterialForm`

#### Ocupaciones Específicas
- Entity: `OcupacionEspecifica` — a specific job title/occupation for participants (e.g., "Operador de Montacargas").
- Type: CATALOG — reference list used in participant registration.
- API function: `getOcupacionesEspecificas` from `@/api/logistics`
- Components: `OcupacionesEspecificasTable` + `OcupacionEspecificaForm`

#### Recesos
- Entity: `Receso` (UI title: "Recesos de Curso") — a scheduled break period within a course session (lunch, coffee break, etc.).
- Type: CATALOG/OPERATIONAL — ambiguous. The dedicated `@/api/recesos` module (separate from logistics) and Logistica tab placement suggest it is per-course-instance. Could be templates or actual records.
- API function: `getRecesos` from `@/api/recesos`
- Components: `RecesosTable` + `RecesoForm`

#### Materiales Entregados
- Entity: `MaterialEntregado` — a record of a specific material item delivered to a participant or course.
- Type: OPERATIONAL — recorded per course delivery to track what was handed out.
- API function: `getMaterialesEntregados` from `@/api/logistics`
- Components: `MaterialesEntregadosTable` + `MaterialEntregadoForm`

---

### TAB: Contabilidad (4 sub-sections)

| # | Section UI Label | Entity | Data Type | Logical Module | File |
|---|---|---|---|---|---|
| 1 | Facturas | Factura | OPERATIONAL | Contabilidad | `sections/contabilidad/FacturasSection.jsx` |
| 2 | Pagos | Pago | OPERATIONAL | Contabilidad | `sections/contabilidad/PagosSection.jsx` |
| 3 | Notas de Credito | NotaCredito | OPERATIONAL | Contabilidad | `sections/contabilidad/NotasCreditoSection.jsx` |
| 4 | Comprobantes de Gasto | ComprobanteGasto | OPERATIONAL | Contabilidad | `sections/contabilidad/ComprobantesGastoSection.jsx` |

**Detail:**

#### Facturas
- Entity: `Factura` — an invoice issued to a client, likely linked to a `CotizacionCerrada`.
- Type: OPERATIONAL — created per billing cycle; financial document.
- API function: `getFacturas` from `@/api/accounting`
- Components: `FacturasTable` + `FacturaForm`

#### Pagos
- Entity: `Pago` — a payment record against a factura or cotizacion.
- Type: OPERATIONAL — registered as money is received.
- API function: `getPagos` from `@/api/accounting`
- Components: `PagosTable` + `PagoForm`

#### Notas de Credito
- Entity: `NotaCredito` — a credit note issued as adjustment against a factura.
- Type: OPERATIONAL — created when a refund or billing adjustment occurs.
- API function: `getNotasCredito` from `@/api/accounting`
- Components: `NotasCreditoTable` + `NotaCreditoForm`

#### Comprobantes de Gasto
- Entity: `ComprobanteGasto` — an expense voucher/receipt (cost side, e.g. reimbursements or vendor invoices).
- Type: OPERATIONAL — recorded per expense event.
- API function: `getComprobantesGasto` from `@/api/accounting`
- Components: `ComprobantesGastoTable` + `ComprobanteGastoForm`

---

### TAB: Variables (8 sub-sections)

| # | Section UI Label | Entity | Data Type | Logical Module | File |
|---|---|---|---|---|---|
| 1 | Ventas | ConfiguracionSistema (modulo=ventas) | SYSTEM CONFIG | Ventas | `sections/variables/VentasVariablesSection.jsx` |
| 2 | Logística | ConfiguracionSistema (modulo=logistica) | SYSTEM CONFIG | Logistica | `sections/variables/LogisticaVariablesSection.jsx` |
| 3 | Contabilidad | ConfiguracionSistema (modulo=contabilidad) | SYSTEM CONFIG | Contabilidad | `sections/variables/ContabilidadVariablesSection.jsx` |
| 4 | Email | TenantGraphConfig + UserEmailPreferences + EmailLog | SYSTEM CONFIG | Infrastructure | `sections/variables/EmailConfigSection.jsx` |
| 5 | Importaciones | ImportJob | OPERATIONAL | Infrastructure | `sections/variables/ImportacionesSection.jsx` |
| 6 | Clasificaciones | ClasificacionCurso | CATALOG | General/Core | `sections/general/ClasificacionesSection.jsx` (routed under /management/variables/) |
| 7 | Departamentos | Departamento | CATALOG | General/Core | `sections/general/DepartamentosSection.jsx` (routed under /management/variables/) |
| 8 | Áreas Temáticas | AreaTematica | CATALOG | General/Core | `sections/general/AreasTematicasSection.jsx` (routed under /management/variables/) |

**Detail:**

#### Variables - Ventas
- Entity: `ConfiguracionSistema` records where `modulo = 'ventas'`
- Type: SYSTEM CONFIG — key-value pairs controlling pricing rules. Currently two sections are seeded:
  - **Factores de Ajuste de Precio** (9 variables): `factor_1_porcentaje` through `factor_9_cantidad` — percentages and monetary amounts controlling how course prices are calculated (extra participants, foraneo markup, hour adjustments, food prices).
  - **Descuentos por Número de Participantes** (14 variables): `descuento_6_menos_local`, `descuento_7_9_local`, etc. — volume-based discount percentages for local/virtual and foraneo modalities.
- UI: `VariablesManager` renders an inline editable table grouped by section. Supports batch save (`actualizar-multiple` API), discard, and one-click initialize (for first-time setup via `inicializar-variables-ventas`).
- Backend: `ConfiguracionSistemaViewSet` at `/core/configuracion/`, `por-modulo/ventas/` endpoint.
- Seed: `initialize_sales_variables` management command seeds all 23 variables.

#### Variables - Logística
- Entity: `ConfiguracionSistema` records where `modulo = 'logistica'`
- Type: SYSTEM CONFIG — parameters controlling logistics module behavior.
- Note: No seed command exists. Empty state shows "No hay variables configuradas" until manually populated.
- UI: Same `VariablesManager` component.

#### Variables - Contabilidad
- Entity: `ConfiguracionSistema` records where `modulo = 'contabilidad'`
- Type: SYSTEM CONFIG — parameters controlling accounting module behavior.
- Note: Same as Logística — no seed command exists.

#### Variables - Email
- Entity: Microsoft Graph API credentials (`TenantGraphConfigForm`) + per-user email preferences (`UserEmailPreferencesForm`) + email send history log.
- Type: SYSTEM CONFIG — infrastructure configuration for the email system (Azure tenant ID, client ID, client secret).
- Custom implementation (not using `VariablesManager`) — renders 4 cards: status/test buttons, graph config form, preferences form, history table.
- API functions: `getEmailConfigStatus`, `testConnection`, `sendTestEmail`, `getEmailHistory` from `@/api/mailings`

#### Variables - Importaciones
- Entity: `ImportJob` — a CSV/Excel bulk import job tracking file, status, rows processed, errors.
- Type: OPERATIONAL (admin-initiated) — jobs are queued and processed asynchronously via `process_imports` management command. Status: pendiente → procesando → completado → error.
- Uses standard `SectionBase` pattern.
- API function: `getImportJobs` from `@/api/imports`
- Components: `ImportJobsTable` + `ImportJobForm`

#### Variables - Clasificaciones
- Entity: `ClasificacionCurso` — a course classification label (e.g., "Seguridad Industrial", "Calidad").
- Type: CATALOG — small reference list used as dropdown in `CatalogCourseForm`.
- Backend: `/core/clasificaciones-curso/`
- Physical file: `sections/general/ClasificacionesSection.jsx` (misrouted under Variables tab)
- UI: Shared `CatalogosTable` + `CatalogoForm` with `entityType="clasificacion"`.

#### Variables - Departamentos
- Entity: `Departamento` — a department within a company (e.g., "Recursos Humanos", "Producción").
- Type: CATALOG — used in participant registration or client profiles.
- Backend: `/core/departamentos/`
- Physical file: `sections/general/DepartamentosSection.jsx` (misrouted under Variables tab)
- UI: Shared `CatalogosTable` + `CatalogoForm` with `entityType="departamento"`.

#### Variables - Áreas Temáticas
- Entity: `AreaTematica` — a thematic area grouping for courses (e.g., "Tecnología", "Habilidades Directivas").
- Type: CATALOG — used as dropdown in `CatalogCourseForm` to categorize courses by subject matter.
- Backend: `/core/areas-tematicas/`
- Physical file: `sections/general/AreasTematicasSection.jsx` (misrouted under Variables tab)
- UI: Shared `CatalogosTable` + `CatalogoForm` with `entityType="area_tematica"`.

---

## Consolidated Classification Summary

### CATALOG data (reference/lookup, rarely changes)

| Section | Entity | Tab Location | Backend Endpoint |
|---|---|---|---|
| Cursos Catálogo | CursoCatalogo | General | `/core/cursos-catalogo/` |
| Clientes | Cliente | General | `/core/clientes/` |
| Empresas | Empresa | General | `/core/empresas/` |
| Plazas | Plaza | General | `/core/plazas/` |
| Lugares | Lugar | General | `/core/lugares/` |
| Instructores | Instructor | General | `/core/instructores/` |
| Vendedores | Vendedor | General | `/core/vendedores/` |
| Administradores | Administrador (User) | General | `/core/users/?role=admin` |
| Tipos de Material | TipoMaterial | Logistica | `/logistica/tipos-material/` |
| Ocupaciones Específicas | OcupacionEspecifica | Logistica | `/logistica/ocupaciones-especificas/` |
| Clasificaciones | ClasificacionCurso | Variables (misplaced) | `/core/clasificaciones-curso/` |
| Departamentos | Departamento | Variables (misplaced) | `/core/departamentos/` |
| Áreas Temáticas | AreaTematica | Variables (misplaced) | `/core/areas-tematicas/` |

### OPERATIONAL data (created daily as business occurs)

| Section | Entity | Tab Location | Frequency |
|---|---|---|---|
| Cursos Agendados | CursoAgendado | General | Per training session scheduled |
| Cotizaciones Abiertas | CotizacionAbierta | Ventas | Per sales prospect |
| Cotizaciones Cerradas | CotizacionCerrada | Ventas | Per confirmed quotation |
| Fichas de Cot. Abiertas | FichaInscripcionAbierta | Logistica | Per open-course enrollment |
| Fichas de Cot. Cerradas | FichaInscripcionCerrada | Logistica | Per closed-course enrollment |
| Costos | Costo | Logistica | Per cost incurred per course |
| Participantes | Participante | Logistica | Per attendee per course |
| Diplomas y Constancias | Diploma | Logistica | Per completion per participant |
| Formatos de Asistencia | FormatoAsistencia | Logistica | Per session |
| Materiales Entregados | MaterialEntregado | Logistica | Per material delivery |
| Facturas | Factura | Contabilidad | Per billing event |
| Pagos | Pago | Contabilidad | Per payment received |
| Notas de Credito | NotaCredito | Contabilidad | Per billing adjustment |
| Comprobantes de Gasto | ComprobanteGasto | Contabilidad | Per expense recorded |
| Importaciones | ImportJob | Variables | Per CSV/Excel bulk import |

### SYSTEM CONFIG (key-value settings, changed by admins only)

| Section | What It Configures | Tab Location |
|---|---|---|
| Variables - Ventas | Pricing factors (factor_1..9) + volume discount %s (14 keys) | Variables |
| Variables - Logística | Logistics module parameters (currently empty, no seed) | Variables |
| Variables - Contabilidad | Accounting module parameters (currently empty, no seed) | Variables |
| Variables - Email | Microsoft Graph API credentials + email preferences | Variables |

### AMBIGUOUS / HYBRID

| Section | Entity | Notes |
|---|---|---|
| Recesos | Receso | Could be catalog break templates or per-course-instance entries. Own API file (`@/api/recesos`) rather than logistics. Placed in Logistica tab. |

---

## Structural Issues Identified

### Issue 1: Routing Mismatch — Catalog Entities Under Variables Tab

**Problem**: Three pure CATALOG entities (Clasificaciones, Departamentos, Áreas Temáticas) are:
- Counted in `VariablesTab.jsx` nav tiles (`getCourseClassifications`, `getDepartments`, `getAreasThematic`)
- Routed under `/management/variables/clasificaciones`, `/management/variables/departamentos`, `/management/variables/areas-tematicas`
- But their section component files physically live in `src/pages/management/sections/general/`

**Impact**: Logical inconsistency. These are dropdown reference tables that users of the courses module need to find, but they are buried under a "Variables" tab that users associate with system configuration. An admin trying to add a new "Clasificacion" to use in a new Catalog Course must navigate to Variables instead of General.

**Recommended fix**: Move these three sections under the General tab navigation (counts + NavLinks in `GeneralTab.jsx`) and reroute from `/management/variables/*` to `/management/general/*`. The section component files are already in `sections/general/` so no file moves are needed — only router and tab nav changes.

### Issue 2: Missing Seed Commands for Logistica and Contabilidad Variables

**Problem**: `initialize_sales_variables` command seeds 23 ventas config variables, but no equivalent command exists for `modulo='logistica'` or `modulo='contabilidad'`.

**Impact**: VariablesManager shows "No hay variables configuradas" empty state for those two modules. The "Inicializar" button in VariablesManager only appears for the Ventas module (`module === MODULES.VENTAS && variables.total < 10`), so Logistica/Contabilidad variables have no bootstrapping path.

### Issue 3: Recesos API Isolation

**Problem**: `Recesos` uses its own API module (`@/api/recesos`) separate from `@/api/logistics`, unlike all other logistics sections.

**Impact**: Minor inconsistency in API organization. Could be intentional if Recesos has a distinct backend app, but worth confirming.

---

## References

### Key Files Analyzed
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/management/ManagementLayout.jsx`: Top-level shell with 6-tab navigation
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/management/tabs/GeneralTab.jsx`: 9 sub-sections, counts fetched in parallel
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/management/tabs/VentasTab.jsx`: 2 sub-sections
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/management/tabs/LogisticaTab.jsx`: 10 sub-sections
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/management/tabs/ContabilidadTab.jsx`: 4 sub-sections
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/management/tabs/VariablesTab.jsx`: 8 sub-sections (incl. 3 catalog misplacements)
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/ui/VariablesManager.jsx`: Shared key-value config editor for Ventas/Logistica/Contabilidad variables
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/api/configuration.jsx`: Full API for ConfiguracionSistema CRUD, por-modulo, batch update, initialize
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py`: ConfiguracionSistema model (fields: modulo, seccion, clave, nombre, valor, tipo, unidad)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/configuracion.py`: ViewSet with por-modulo, actualizar-multiple, inicializar-variables-ventas endpoints
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/management/commands/initialize_sales_variables.py`: Seeds 23 ventas config variables in 2 sections

---

**Next Steps**:
1. Decide whether to move Clasificaciones, Departamentos, and Áreas Temáticas from Variables tab to General tab (router + nav change only).
2. Create seed commands/data for logistica and contabilidad variables if those modules need configurable parameters.
3. Clarify whether Recesos are per-course-instance records or reusable templates, and consider merging `@/api/recesos` into `@/api/logistics`.

---
---

# Codebase Analysis Report — New User Roles Impact
**Generated**: 2026-03-04
**Analyst**: codebase-analyzer
**Request**: Understand the full impact of adding two new user roles ("capturista" and "administrativo") to the Django+React system. Currently three roles exist: admin, seller, customer. Analyze backend role definitions, frontend routing, plaza assignment, contabilidad section, and custom permission classes. Provide file paths and line numbers for all findings.

---

## Executive Summary

Adding "capturista" and "administrativo" to this system is a significant cross-cutting change that touches the database layer, all four backend apps, all major frontend modules, the TypeScript type system, and at least six permission classes. The analysis identified one blocking database constraint, four data-security regressions that would occur without explicit handling, a frontend login loop for any unknown role, and two duplicate permission class definitions that must both be updated.

The most critical finding is a hard database constraint: `role = models.CharField(max_length=10, ...)` in `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/models.py` line 83. The value "administrativo" is 14 characters and will be silently truncated or rejected by PostgreSQL without a migration to widen the column. "capturista" is exactly 10 characters and would fit today, but widening the column for both roles in a single migration is strongly recommended.

The second critical finding is in the ventas and organizacion ViewSets: `get_queryset()` uses `if role == "customer" ... elif role == "seller" ... else` (implicit admin) patterns. Any role not explicitly matched falls into the admin branch and receives unfiltered, all-record access. Both "capturista" and "administrativo" users would silently see every quotation and every empresa in the system without additional guards.

On the frontend, both `RootRedirect` and `LoginRedirect` in the router fall to `default: return <Navigate to="/login">`, which sends any unrecognized role back to the login page in an infinite loop. Every `RoleRoute` gate that currently lists `["admin", "seller"]` would deny access to the new roles, and the Navbar `getNavigationLinks()` function returns an empty array for unknown roles — leaving users with no navigation links even if they somehow reach a protected page.

---

## Analysis Area 1: Backend Role Definitions and Role Checks

### 1.1 The Role Field — Database Constraint

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/models.py`

**Lines 74–83**:
```python
ROLE_CHOICES = [
    ("admin", "Administrador"),
    ("seller", "Vendedor"),
    ("customer", "Cliente"),
]
role = models.CharField(max_length=10, choices=ROLE_CHOICES, default="customer")
```

**Impact**:
- "capturista" = 10 characters — fits within `max_length=10` today.
- "administrativo" = 14 characters — **exceeds `max_length=10` and will fail at the database level**. PostgreSQL raises `value too long for type character varying(10)`. Django's `choices` validation only fires at the form/serializer layer; the model `save()` will pass the value to the database unvalidated if called directly.
- Both new roles are absent from `ROLE_CHOICES`. Django will not raise a validation error for missing choices at the ORM level, but `UserCreateSerializer` (line 70) uses `serializers.ChoiceField(choices=User.ROLE_CHOICES)` which will reject any value not in that list with a 400 error.

**Required changes**:
1. Add both new roles to `ROLE_CHOICES`.
2. Increase `max_length` to at least 14 (to accommodate "administrativo").
3. Generate and apply a migration (`makemigrations users`, `migrate`).

**Line 51–52** — `create_user()` sets `is_staff` and `is_superuser` only for `role == "admin"`. New roles correctly receive `is_staff=False, is_superuser=False` with no code changes needed here.

**Line 126–132** — `set_as_customer()` hardcodes `role = "customer"`. This method is only called when converting an existing user to a passwordless customer; it does not affect the new roles.

### 1.2 UserCreateSerializer — Validation Branching

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/serializers.py`

**Line 70**:
```python
role = serializers.ChoiceField(choices=User.ROLE_CHOICES)
```
This is the first gate. Until `ROLE_CHOICES` includes the new roles, any API attempt to create a "capturista" or "administrativo" user returns `{"role": ["\"capturista\" is not a valid choice."]}`.

**Lines 101–143** — `validate()` contains four explicit branches:
- Lines 101–112: `if role in ("admin", "seller")` — requires username, name, last_name, and password (on create).
- Lines 115–122: `if role == "admin"` — forbids vendedor_data and cliente_data.
- Lines 126–133: `elif role == "seller"` — forbids cliente_data, requires vendedor_data on create.
- Lines 136–142: `elif role == "customer"` — forbids vendedor_data, requires cliente_data.

**Gap**: Neither "capturista" nor "administrativo" matches any of those branches. A user created with either new role would:
- Not be required to provide username/name/last_name/password (they fall outside the `if role in ("admin", "seller")` block).
- Not be prevented from sending arbitrary nested data.
- Not be required to send any nested profile data.
- Successfully pass validation with just `email` and `role`.

**Lines 166–228** — `create()` only creates business profiles for `role == "seller"` (Vendedor) and `role == "customer"` (Cliente). New roles would get a bare User record with no profile — which is likely correct for "capturista" and may be correct for "administrativo", but the password/username requirement bypass is a problem.

**Recommended change**: Add a third branch to the `if role in (...)` check:
```python
if role in ("admin", "seller", "capturista", "administrativo"):
    # require username, name, last_name, password on create
```
And add explicit validation that those roles reject nested profile data:
```python
if role in ("capturista", "administrativo"):
    if data.get("vendedor_data") is not None:
        errors["vendedor_data"] = "No se aceptan datos de vendedor para este rol."
    if data.get("cliente_data") is not None:
        errors["cliente_data"] = "No se aceptan datos de cliente para este rol."
```

### 1.3 UserViewSet — Role-Specific Actions

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/views.py`

**Line 15–25** — `IsAdmin` permission class:
```python
class IsAdmin(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user and request.user.is_authenticated
            and request.user.role == "admin"
        )
```
The entire `UserViewSet` is protected by `IsAdmin` (line 34). Only role=="admin" can create/list/update users. New roles have no special access here — this is correct behavior.

**Lines 297, 306** — `reactivate()` action:
```python
if user.role == "seller" and hasattr(user, "vendedor"):
    # reactivate Vendedor profile
if user.role == "customer" and hasattr(user, "cliente"):
    # reactivate Cliente profile
```
New roles fall through both branches silently. Their User record is reactivated but no associated profile is touched — which is correct since they have no profile model.

**Lines 453, 553, 600** — `create_client` and `update_client` actions check `if user.role == "seller"` for plaza restriction enforcement. An "administrativo" user calling these endpoints would bypass the plaza filter and be treated like an admin (no plaza restriction). Whether that is desired depends on the intended access level of "administrativo".

**Lines 681–683, 700–701** — `set_pin` and `set_pin_for_user`:
```python
admins_con_pin = User.objects.filter(role="admin", is_active=True, pin_hash__isnull=False)
# and
if target_user.role != "admin":
    return Response({"error": "Solo se puede configurar PIN para administradores."}, ...)
```
PIN system is explicitly restricted to `role="admin"`. New roles cannot set or receive PINs. Correct.

### 1.4 Authentication Views — Login Flow and PIN Gate

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/authentication/views.py`

**Lines 437–450** — `CheckUserTypeView`:
```python
user_type = "standard"  # admin o seller
if user.role == "customer":
    user_type = "customer"
```
Any role that is not "customer" is classified as "standard". Both new roles would correctly receive `user_type = "standard"` — meaning they use password login, not PIN. No change needed here.

**Lines 479–483** — `EmailPINRequestView`:
```python
if user.role != "customer":
    return Response({"error": "Este método de acceso es solo para clientes"}, ...)
```
Non-customers (including new roles) are correctly blocked from PIN login. No change needed.

### 1.5 Core Permission Classes

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/base.py`

Six permission-related classes are defined or enforced here:

| Class | Line | Logic | Impact on New Roles |
|---|---|---|---|
| `IsAdminOrSeller` | 14–20 | `role in ('admin', 'seller')` | New roles are denied all endpoints using this class |
| `IsAuthenticatedReadOnly` | 23–35 | Read: any auth; Write: `role in ('admin', 'seller')` | New roles can read but cannot create/update/delete |
| `IsAdminOrSellerWithPlazaFilter` | 38–74 | `role in ('admin', 'seller')` for access | New roles are denied entirely |
| `SoftDeleteModelViewSet.get_queryset` | 95 | `role != 'admin'` denies inactive records | New roles cannot see soft-deleted records (correct) |
| `SoftDeleteModelViewSet.reactivate` | 211 | `role != 'admin'` denies reactivation | New roles cannot reactivate records (correct) |
| `SoftDeleteModelViewSet.permanent_delete` | 253 | `role != 'admin'` denies permanent delete | New roles cannot permanently delete (correct) |

**Critical**: Every ViewSet that uses `IsAdminOrSeller` or `IsAdminOrSellerWithPlazaFilter` as its `permission_classes` will return HTTP 403 for any "capturista" or "administrativo" user. This affects the entire `core`, `contabilidad`, and `ventas` apps.

### 1.6 Logistica Duplicate Permission Classes

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/views/base.py`

**Lines 8–24** — Defines its own copies of `IsAdminOrSeller` and `IsAdminSellerOrCustomer`:
```python
class IsAdminOrSeller(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(user and user.is_authenticated and getattr(user, 'role', None) in ('admin', 'seller'))

class IsAdminSellerOrCustomer(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(user and user.is_authenticated and getattr(user, 'role', None) in ('admin', 'seller', 'customer'))
```

These are byte-for-byte duplicates of the core versions. When adding new roles, **both files must be updated**. If only `core/views/base.py` is updated, logistica endpoints will still block the new roles.

### 1.7 Ventas ViewSets — Data Exposure Risk

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/views.py`

**Lines 159–188** — `CotizacionCerradaViewSet.get_queryset()`:
```python
if self.request.user.role == "customer":
    queryset = queryset.filter(cliente__user=self.request.user)
elif self.request.user.role == "seller":
    # filter by plaza
    ...
# No else branch — implicit fallthrough gives all records to any other role
```

**Lines 1435–1468** — `CotizacionAbiertaViewSet.get_queryset()`:
```python
if self.request.user.role == "customer":
    queryset = queryset.filter(cliente__user=self.request.user)
elif self.request.user.role == "seller":
    # filter by plaza
    ...
# Same fallthrough
```

**Data exposure**: Any role not explicitly matched receives the full unfiltered queryset — identical to admin access. Both "capturista" and "administrativo" would see all quotations from all plazas until explicit branches are added.

The `permission_classes` on both ViewSets use `IsAdminOrSeller` (from core), which currently blocks the new roles at the access control layer. So the data exposure is **latent** — it only becomes active once permission classes are updated to allow the new roles. However, it must be addressed at that time.

### 1.8 Core Organizacion Views — Same Pattern

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/organizacion.py`

**Lines ~347–360** — `EmpresaViewSet.get_queryset()`:
```python
if user.role == "admin":
    return queryset  # all empresas
if user.role == "seller":
    # filter by vendedor plazas
    ...
# New roles fall through to the bottom of the method — behavior depends on what follows
```

Same fallthrough risk as ventas. Must add explicit handling for new roles before enabling their access.

---

## Analysis Area 2: Frontend Role-Based Routing and Access

### 2.1 RootRedirect and LoginRedirect — Login Loop

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/router/index.jsx`

**Lines 89–98** — `RootRedirect`:
```jsx
switch (user.role) {
  case "customer": return <Navigate to="/home" replace />;
  case "admin":    return <Navigate to="/management" replace />;
  case "seller":   return <Navigate to="/sales" replace />;
  default:         return <Navigate to="/login" replace />;
}
```

**Lines 110–119** — `LoginRedirect` (same switch):
```jsx
switch (user.role) {
  case "customer": return <Navigate to="/home" replace />;
  case "admin":    return <Navigate to="/management" replace />;
  case "seller":   return <Navigate to="/sales" replace />;
  default:         return <Navigate to="/login" replace />;
}
```

**Impact**: A "capturista" or "administrativo" user who successfully authenticates will be redirected to `/login`, which will then re-run `LoginRedirect`, which will redirect to `/login` again — infinite loop. The user can never reach any page.

**Required change**: Add cases for both new roles pointing to their respective landing pages (e.g., `/sales` or a new dedicated route).

### 2.2 RoleRoute — Access Gate

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/router/RoleRoute.jsx`

The component checks `allowed.includes(user.role)` and redirects to `/` if not included. Since all current `RoleRoute` gates specify only `["admin"]`, `["admin", "seller"]`, or `"customer"`, every protected route will redirect new roles to `/`, which triggers `RootRedirect`, which redirects to `/login` again.

**Route gates requiring updates** (from `index.jsx`):

| Route Path | Current Roles Allowed | Impact on New Roles |
|---|---|---|
| `/management` | `["admin"]` (line 174) | "administrativo" needs access if admin-like |
| `/sales` | `["admin", "seller"]` (line 325) | "capturista" or "administrativo" may need access |
| `/logistics` | `["admin", "seller"]` (line 406) | Same |
| `/accounting` | `["admin", "seller"]` (line 427) | Same |
| `/home` | `"customer"` (line 321) | New roles do not need this |

### 2.3 Navbar — Empty Navigation for Unknown Roles

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/layout/Navbar.jsx`

**Lines 67–94** — `getNavigationLinks()`:
```jsx
if (user.role === 'customer') { return [{to: "/home", label: "Inicio"}]; }
if (user.role === 'seller')   { return [Ventas, Logística, Contabilidad]; }
if (user.role === 'admin')    { return [Ventas, Logística, Contabilidad, Administración]; }
return [];  // line 94 — fallback for unknown roles
```

A user with a new role who somehow bypasses the router gate would see a completely empty navigation bar. No links, no way to navigate.

**Required change**: Add `if/else if` blocks for both new roles with the appropriate set of navigation links.

### 2.4 Inline Role Checks in Components

The `Sales.jsx` component alone contains over 30 inline `user?.role === "admin"` and `user?.role === "seller"` checks. These controls show or hide UI elements (buttons, form fields, view-all toggles). New roles that land on `/sales` would see a stripped-down view — no buttons that require seller or admin role, no form controls, read-only where controlled by `user?.role === "seller"`.

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/modules/Sales.jsx`

Notable checks:
- Line 2617: `user?.role === "admin"` — shows "Crear Curso Agendado" button.
- Lines 3287–3352: `user?.role === "seller"` — controls form read-only mode and delete button visibility.

Each of these would need to be updated to include new roles in the condition if those roles should have the same UI access as seller or admin.

### 2.5 TypeScript Type Definition

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/types/user.d.ts`

**Line 5**:
```typescript
role: "admin" | "seller" | "customer";
```

TypeScript will produce a type error anywhere `user.role` is compared against a new role string until this union is updated. While TypeScript errors do not prevent the app from running (Vite does not fail on type errors by default), they produce noise in the IDE and may block CI if a type-check step exists.

**Required change**: Extend the union to include new roles:
```typescript
role: "admin" | "seller" | "customer" | "capturista" | "administrativo";
```

### 2.6 AdminForm and SellerForm — Hardcoded Role Values

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/forms/AdminForm.jsx`

Lines 47, 74, 222: `role: "admin"` is hardcoded in form state and payload. This form can only create admin users. A new form would need to be created to create "capturista" or "administrativo" users via the management UI.

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/forms/SellerForm.jsx`

Lines 270, 293: `role: "seller"` is hardcoded. Same situation.

Neither form needs modification for the new roles, but corresponding new forms (`CapturistaForm.jsx`, `AdministrativoForm.jsx`) would need to be created and registered in the management sections if admins should be able to create users with those roles from the UI.

---

## Analysis Area 3: Plaza Assignment System

### 3.1 Data Model

**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py`

The plaza assignment is a simple one-to-many relationship:
- `Plaza` has a `ForeignKey` to `Vendedor` (nullable, blank=True) — one seller per plaza at any time.
- `Vendedor` has a `OneToOneField` to `User` with `related_name="vendedor"`.
- A seller can hold multiple plazas via the reverse relation: `user.vendedor.plaza_set.all()`.

The relationship direction means:
1. Each `Plaza` can be assigned to at most one `Vendedor`.
2. One `Vendedor` can have many `Plaza`s.
3. "Unassigned" plazas have `vendedor=None`.

### 3.2 How Plazas Filter Data

All plaza-based filtering works through the chain:
```
user → user.vendedor → vendedor.plaza_set.values_list('id', flat=True) → filter(plaza_id__in=plazas_ids)
```

This means:
- Only users with `role="seller"` have a `Vendedor` profile and thus a `plaza_set`.
- Accessing `user.vendedor` on a non-seller user raises `RelatedObjectDoesNotExist`.
- The ventas and core views always check `role == "seller"` before accessing `user.vendedor`.

### 3.3 Impact on New Roles

Neither "capturista" nor "administrativo" has a `Vendedor` profile in the current design. There are two options:

**Option A — No plaza association**: New roles have access similar to admin (all data) or are restricted in some other dimension. No plaza filtering code needs to change.

**Option B — Plaza-associated**: If "capturista" should be restricted to specific plazas (e.g., a data entry operator for one region), the plaza filtering chain would need to be refactored. Options include:
- Reusing the `Vendedor` model for capturistas (anti-pattern — semantically wrong).
- Adding a `ManyToManyField` from User to Plaza directly (clean but requires migration and new filtering code).
- Creating a separate profile model for capturistas with a plaza relationship.

This is an architectural decision to make before implementation.

---

## Analysis Area 4: Contabilidad Section

### 4.1 Backend

The contabilidad module is fully implemented.

**Models** (`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/models.py`):
- `Factura` — invoice linked to a cotizacion
- `ItemFactura` — line items on a factura
- `NotaCredito` — credit note against a factura
- `Pago` — payment record
- `ComprobanteGasto` — expense voucher/receipt

All extend `BaseModel` (soft delete, created_at, updated_at).

**Views** (`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/views.py`):
All viewsets use `permission_classes = [IsAuthenticated]` only — no role restriction at the permission class level. The only role check in the entire file is at approximately line 596: `if user.role == "seller"` to filter `cursos` by the seller's plazas. Any authenticated user (including new roles) can access contabilidad endpoints today.

**URLs** (`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/urls.py`):
Registers: `facturas/`, `items-factura/`, `pagos/`, `notas-credito/`, `comprobantes-gasto/`, `estadisticas/`, `cursos/` — all under `api/contabilidad/`.

### 4.2 Frontend

The accounting module is fully implemented on the frontend.

**Route** (`/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/router/index.jsx`, line 427):
```jsx
<Route element={<RoleRoute roles={["admin", "seller"]} />}>
  {/* accounting routes */}
</Route>
```
Currently blocked to admin and seller only. New roles require explicit addition to this `roles` array to gain access.

**Navbar**: The accounting link ("Contabilidad") appears in the navigation for both seller and admin roles. New roles would need to be added to the `getNavigationLinks()` function to receive this link.

---

## Analysis Area 5: Custom Permission Classes — Full Inventory

There are **six** distinct permission classes across the backend. Four are in core, two are duplicates in logistica.

### Core App (`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/base.py`)

| Class | Line | Allowlist | Notes |
|---|---|---|---|
| `IsAdminOrSeller` | 14 | `('admin', 'seller')` | Used by core, ventas, contabilidad ViewSets |
| `IsAuthenticatedReadOnly` | 23 | Read: any auth; Write: `('admin', 'seller')` | Write-gates for read-heavy resources |
| `IsAdminOrSellerWithPlazaFilter` | 38 | `('admin', 'seller')` | Has `has_object_permission` that additionally filters by plaza for sellers |

### Users App (`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/views.py`)

| Class | Line | Allowlist | Notes |
|---|---|---|---|
| `IsAdmin` | 15 | `role == "admin"` only | Protects `UserViewSet`, `set-pin`, `has-pin` |

### Logistica App (`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/views/base.py`)

| Class | Line | Allowlist | Notes |
|---|---|---|---|
| `IsAdminOrSeller` (duplicate) | 8 | `('admin', 'seller')` | Exact copy of core version; used by logistica ViewSets |
| `IsAdminSellerOrCustomer` | 17 | `('admin', 'seller', 'customer')` | Used for logistica routes that customers can read |

### Inline Role Checks in SoftDeleteModelViewSet (not a permission class, but acts as one)

| Method | File | Line | Check | Effect |
|---|---|---|---|---|
| `get_queryset` | `core/views/base.py` | 95 | `role != 'admin'` | Non-admins cannot see inactive records |
| `reactivate` | `core/views/base.py` | 211 | `role != 'admin'` | Non-admins cannot reactivate |
| `permanent_delete` | `core/views/base.py` | 253 | `role != 'admin'` | Non-admins cannot permanently delete |

---

## Implementation Plan

### Phase 1 — Backend Foundation (required before any frontend work)

#### 1. Database Migration
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/models.py`

Changes needed:
- Add `("capturista", "Capturista")` and `("administrativo", "Administrativo")` to `ROLE_CHOICES` (lines 74–78).
- Change `max_length=10` to `max_length=20` on the `role` field (line 83).

After model change:
```bash
docker-compose exec backend python manage.py makemigrations users
docker-compose exec backend python manage.py migrate
```

#### 2. Serializer Validation Update
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/serializers.py`

Changes needed at `validate()` (lines 101–143):
- Extend the base fields check: `if role in ("admin", "seller", "capturista", "administrativo"):` (line 101).
- Add a branch after the "customer" elif to handle new roles: reject vendedor_data and cliente_data, require no profile data.

#### 3. Permission Classes Update
Update all six permission classes:

**`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/base.py`** (lines 20, 35, 44):
Decide the new role levels and update the tuples. For example, if "administrativo" should have admin-level access and "capturista" should have seller-level access:
- `IsAdminOrSeller`: add whichever new roles should have write access.
- `IsAuthenticatedReadOnly`: update the write-allowlist accordingly.
- `IsAdminOrSellerWithPlazaFilter`: update allowlist; if new roles need plaza filtering, add additional branches in `has_object_permission`.

**`/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/views/base.py`** (lines 14, 23):
Mirror the same changes made to the core permission classes. These must be kept in sync.

Consider refactoring to import from core instead of duplicating:
```python
from src.apps.core.views.base import IsAdminOrSeller  # instead of redefining
```

#### 4. Ventas ViewSet get_queryset() Guards
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/views.py`

Add explicit branches for new roles in `CotizacionCerradaViewSet.get_queryset()` (lines 159–188) and `CotizacionAbiertaViewSet.get_queryset()` (lines 1435–1468):
```python
elif self.request.user.role == "capturista":
    # define what a capturista can see — e.g., same as seller but no plaza filter,
    # or all records, or empty queryset
elif self.request.user.role == "administrativo":
    # define what an administrativo can see — likely all records like admin
```

#### 5. Core Organizacion ViewSet Guards
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/organizacion.py`

Add explicit handling in `EmpresaViewSet.get_queryset()` for the new roles to prevent fallthrough admin access.

### Phase 2 — Frontend Foundation

#### 1. TypeScript Type Definition
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/types/user.d.ts` (line 5)

Change:
```typescript
role: "admin" | "seller" | "customer";
```
To:
```typescript
role: "admin" | "seller" | "customer" | "capturista" | "administrativo";
```

#### 2. Fix Login Loop — Router Redirect Functions
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/router/index.jsx` (lines 89–98, 110–119)

Add cases for new roles in both `RootRedirect` and `LoginRedirect` switch statements:
```jsx
case "capturista":    return <Navigate to="/sales" replace />;
case "administrativo": return <Navigate to="/management" replace />;
```
(Adjust destination routes based on intended access levels.)

#### 3. RoleRoute Gates
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/router/index.jsx` (lines 174, 325, 406, 427)

Update `roles` arrays for each `RoleRoute` based on access decisions:
- `/management`: add "administrativo" if it should have management access.
- `/sales`: add "capturista" and/or "administrativo" as needed.
- `/logistics`: same.
- `/accounting`: same.

#### 4. Navbar Navigation Links
**File**: `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/layout/Navbar.jsx` (lines 67–94)

Add `if/else if` blocks for new roles before the `return []` fallback:
```jsx
if (user.role === 'capturista') {
  return [{ to: "/sales", label: "Ventas" }];
}
if (user.role === 'administrativo') {
  return [
    { to: "/sales", label: "Ventas" },
    { to: "/logistics", label: "Logística" },
    { to: "/accounting", label: "Contabilidad" },
    { to: "/management", label: "Administración" }
  ];
}
```

### Phase 3 — Management UI (to create users with new roles)

If admins should be able to create "capturista" and "administrativo" users from the management UI:

1. Create `CapturistaForm.jsx` and `AdministrativoForm.jsx` in `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/forms/`. Model them on `AdminForm.jsx` but hardcode the appropriate role value.
2. Create corresponding management sections in `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/management/sections/general/` (e.g., `CapturistasSection.jsx`, `AdministrativosSection.jsx`).
3. Add the new sections as sub-routes under `/management/general` in `index.jsx`.
4. Add navigation tiles for the new sections in `GeneralTab.jsx`.

---

## Risk Summary

| Risk | Severity | Area | Description |
|---|---|---|---|
| "administrativo" exceeds max_length=10 | BLOCKING | DB / Backend | Will fail at database layer without migration |
| Unfiltered queryset fallthrough in ventas | HIGH | Backend | New roles see all quotations until explicit branch added |
| Unfiltered queryset fallthrough in organizacion | HIGH | Backend | New roles see all empresas until explicit branch added |
| Login loop for unknown roles | HIGH | Frontend | User cannot reach any page after login |
| Duplicate permission classes not updated | HIGH | Backend | Logistica endpoints remain blocked even after core is updated |
| TypeScript union not updated | MEDIUM | Frontend | Type errors in IDE; may block CI type-check |
| Navbar empty for unknown roles | MEDIUM | Frontend | No navigation links displayed |
| Sales.jsx inline role checks | MEDIUM | Frontend | UI elements hidden or shown incorrectly |
| Serializer validation bypass for new roles | LOW | Backend | New roles can be created with minimal data (no username required) |
| AdminForm/SellerForm hardcoded roles | LOW | Frontend | No UI path to create new-role users without new forms |

---

## References

### Key Files Analyzed
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/models.py`: ROLE_CHOICES, max_length=10, set_as_customer()
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/serializers.py`: ChoiceField gate, validate() branching, create() profile logic
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/users/views.py`: IsAdmin class, reactivate(), create_client(), set_pin() checks
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/authentication/views.py`: CheckUserTypeView (line 437), EmailPINRequestView (line 479)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/base.py`: All core permission classes and SoftDeleteModelViewSet inline checks
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/logistica/views/base.py`: Duplicate IsAdminOrSeller and IsAdminSellerOrCustomer classes
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/ventas/views.py`: Fallthrough get_queryset() in CotizacionCerrada (line 159) and CotizacionAbierta (line 1435)
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/views/organizacion.py`: EmpresaViewSet fallthrough get_queryset()
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/models.py`: Factura, Pago, NotaCredito, ComprobanteGasto
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/contabilidad/views.py`: IsAuthenticated-only permissions, seller plaza filter at line 596
- `/Users/anuareramirez/DEV/qsys/qsystem-backend/src/apps/core/models.py`: Plaza → Vendedor ForeignKey, Vendedor → User OneToOneField
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/router/index.jsx`: RootRedirect/LoginRedirect switch (lines 89–119), RoleRoute gates (lines 174, 325, 406, 427)
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/layout/Navbar.jsx`: getNavigationLinks() role branches (lines 67–94)
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/types/user.d.ts`: Role union type (line 5)
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/forms/AdminForm.jsx`: Hardcoded role="admin"
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/components/forms/SellerForm.jsx`: Hardcoded role="seller"
- `/Users/anuareramirez/DEV/qsys/qsystem-frontend/src/pages/modules/Sales.jsx`: 30+ inline role checks

---

**Next Steps**:
1. Decide the exact access level for each new role (what data they can see, what actions they can perform) before writing any code — the implementation plan above has placeholders that depend on these decisions.
2. Start with the database migration (widening max_length and adding ROLE_CHOICES entries) as it is a hard prerequisite for all other backend work.
3. Fix the frontend login loop immediately after the serializer/permission changes go in — otherwise new role users cannot log in at all.
4. Update both the core and logistica permission class files in the same commit to avoid a window where one app allows access but the other does not.
