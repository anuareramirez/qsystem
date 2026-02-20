# Post-Toast Implementation Analysis Report

**Fecha**: 2026-02-19
**Scope**: 301 archivos JSX/JS en `qsystem-frontend/src/`

---

## Resumen Ejecutivo

Se encontraron **3 catch blocks completamente vacios** en flujos criticos, **10+ catch blocks con solo console.error** sin feedback al usuario, **2 botones submit sin disabled**, **1 URL hardcodeada localhost:8003** que falla en cualquier entorno no-local, **~30+ console.log de debug** contaminando produccion, y el **ErrorBoundary** cubre solo el layout top-level con un fallback sin estilos.

---

## Prioridad P1 (Critico - Arreglar esta semana)

### 1. Empty catches en InvoiceManagementModal (lineas 80-91)
**Archivo**: `components/modals/InvoiceManagementModal.jsx`
- `loadFactura` y `loadPagos` tienen catch blocks completamente vacios
- Es un modal financiero — fallas silenciosas son criticas
- **Fix**: `showApiError(error, 'Error al cargar datos de la factura')`

### 2. URL hardcodeada localhost:8003 en EntregablesTab (lineas 122-130)
**Archivo**: `components/modals/CursoDetalle/tabs/EntregablesTab/index.jsx`
```jsx
const debugBackendData = async () => {
  const response = await fetch(`http://localhost:8003/api/logistica/diplomas/debug-fichas/?curso_agendado_id=${curso.id}`, {
    credentials: 'include'
  });
};
```
- Se llama incondicionalmente en `loadDocumentos` (linea ~161)
- Falla con CORS en cualquier entorno no-local
- El catch vacio silencia el error
- **Fix**: Eliminar `debugBackendData` y su llamada

### 3. ComisionVendedorDetalle - 11+ console.logs exponiendo datos
**Archivo**: `components/modals/CursoDetalle/tabs/CostosTab/CostoDetalles/ComisionVendedorDetalle.jsx`
- Lineas 160, 167, 189-224: dump completo de vendedores y cotizaciones en consola
- Cualquier usuario con DevTools abierto ve estos datos
- **Fix**: Eliminar todos los console.log

### 4. ParticipantRegistrationModal - empty catch (linea 596)
**Archivo**: `components/ui/ParticipantRegistrationModal.jsx`
- `actualizarDatosEmpresa` falla silenciosamente, pero ejecucion continua a `onSuccess()`
- **Fix**: `console.warn('No se pudo actualizar empresa:', companyError)`

---

## Prioridad P2 (Alta - Arreglar este sprint)

### 5. SalesStateContext - debug logs en cada navegacion
**Archivo**: `contexts/SalesStateContext.jsx` (lineas 35, 58, 63, 77)
- Cada cambio de pagina logea el estado completo
- Los hermanos `AccountingStateContext` y `LogisticsStateContext` ya estan limpios
- **Fix**: Eliminar console.logs (mantener console.warn linea 116)

### 6. AvailabilityForm - botones submit sin disabled
**Archivo**: `components/forms/AvailabilityForm.jsx` (lineas 737 y 997)
- Tiene guard `if (isLoading) return` pero los botones NO tienen `disabled={isLoading}`
- Unico formulario inconsistente tras los 19 fixes anteriores
- **Fix**: Agregar `disabled={isLoading}` y texto "Guardando..."

### 7. CostosTab - falta success toast al guardar
**Archivo**: `components/modals/CursoDetalle/tabs/CostosTab/index.jsx` (linea 621)
- Al guardar un costo, cierra el form y recarga pero no muestra confirmacion
- **Fix**: `showSuccess(editingCosto ? 'Costo actualizado' : 'Costo registrado')`

### 8. CostosTab - loadInstructores catch vacio (linea 119)
- Dropdown de instructores queda vacio sin feedback
- **Fix**: `showApiError(error, 'Error al cargar instructores')`

### 9. Sales.jsx - ~17 console.logs de navegacion
**Archivo**: `pages/modules/Sales.jsx` (lineas 518-775)
- Cada accion de navegacion URL dispara 1-3 console.logs
- **Fix**: Eliminar todos

### 10. ClosedQuotationForm - empty catch en loadLocations (linea 94)
- Dropdown de ubicaciones queda vacio sin feedback
- **Fix**: `showApiError(error, 'Error al cargar ubicaciones')`

### 11. OpenQuotationForm - empty catch en calcularPrecio (linea 115)
- Si falla, boton submit queda permanentemente deshabilitado sin explicacion
- **Fix**: `showError('Error al calcular precio')` + reset estado

### 12. ClosedQuotationForm - empty catch en calcularPrecio (linea 155)
- Mismo problema que OpenQuotationForm
- **Fix**: Mismo patron

### 13. ScheduledCourseForm - .catch((error) => {}) en linea 1174
- Calculo de precio fire-and-forget
- **Fix**: `.catch((error) => { console.warn('Error al calcular precio:', error) })`

### 14. SessionExpirationNotification - sin feedback al fallar extension
**Archivo**: `components/ui/SessionExpirationNotification.jsx` (lineas 65-67)
- Usuario clickea "Extender" y nada pasa si falla
- **Fix**: `showError('No se pudo extender la sesion')`

### 15. ErrorBoundary - fallback sin estilos
**Archivo**: `components/layout/ErrorBoundary.jsx`
- Solo muestra `<h1>Something went wrong.</h1>` sin boton ni estilos
- El de `datetime/components/ErrorBoundary.jsx` es mejor referencia
- **Fix**: UI estilizada con boton "Recargar pagina"

### 16. GeneralTab - loadEstadosDisponibles sin error toast (linea 51-58)
- Solo tiene console.error, sin feedback al usuario
- **Fix**: Agregar `showError('Error al cargar estados disponibles')`

---

## Prioridad P3 (Nice-to-have - Proximo sprint)

### 17. CourseDetailsForm - patron viejo setSuccess + setTimeout
- Migrar a `showSuccess()` del nuevo sistema toast

### 18. AvailabilityForm - patron viejo setSuccessMessage + setTimeout (3 lugares)
- Migrar a `showSuccess()` del nuevo sistema toast

### 19. GraphConfigForm - catch vacio en loadExistingConfig (linea 52)
- **Fix**: `setError('Error al cargar configuracion')`

### 20. FichaDetailView - catches con solo comentario (lineas 175, 187)
- `// Error loading departments` no es manejo de error
- **Fix**: `console.warn` minimo

### 21. Per-module ErrorBoundaries en router
- Agregar ErrorBoundary por modulo (Sales, Logistics, Accounting) para que un crash en uno no afecte los demas

---

## Tabla Resumen

| # | Categoria | Archivo | Prioridad | Accion |
|---|-----------|---------|-----------|--------|
| 1 | Empty catch | InvoiceManagementModal.jsx:80-91 | P1 | showApiError |
| 2 | Hardcoded URL | EntregablesTab/index.jsx:122-130 | P1 | Eliminar funcion |
| 3 | Debug logs | ComisionVendedorDetalle.jsx:160-224 | P1 | Eliminar console.logs |
| 4 | Empty catch | ParticipantRegistrationModal.jsx:596 | P1 | console.warn |
| 5 | Debug logs | SalesStateContext.jsx:35-77 | P2 | Eliminar console.logs |
| 6 | Missing disabled | AvailabilityForm.jsx:737,997 | P2 | disabled={isLoading} |
| 7 | Missing toast | CostosTab/index.jsx:621 | P2 | showSuccess |
| 8 | Empty catch | CostosTab/index.jsx:119 | P2 | showApiError |
| 9 | Debug logs | Sales.jsx:518-775 | P2 | Eliminar console.logs |
| 10 | Empty catch | ClosedQuotationForm.jsx:94 | P2 | showApiError |
| 11 | Empty catch | OpenQuotationForm.jsx:115 | P2 | showError + reset |
| 12 | Empty catch | ClosedQuotationForm.jsx:155 | P2 | showError + reset |
| 13 | Empty catch | ScheduledCourseForm.jsx:1174 | P2 | console.warn |
| 14 | No feedback | SessionExpirationNotification.jsx:65 | P2 | showError |
| 15 | UX | ErrorBoundary.jsx | P2 | Mejorar fallback UI |
| 16 | No feedback | GeneralTab/index.jsx:51-58 | P2 | showError |
| 17 | Old pattern | CourseDetailsForm.jsx | P3 | Migrar a showSuccess |
| 18 | Old pattern | AvailabilityForm.jsx | P3 | Migrar a showSuccess |
| 19 | Empty catch | GraphConfigForm.jsx:52 | P3 | setError |
| 20 | Comment catch | FichaDetailView.jsx:175,187 | P3 | console.warn |
| 21 | Architecture | Router | P3 | Per-module ErrorBoundaries |
