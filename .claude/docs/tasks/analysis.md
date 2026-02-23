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
