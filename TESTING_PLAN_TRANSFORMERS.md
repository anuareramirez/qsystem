# Plan de Testing - DateTimeTransformers

## 🎯 Objetivo
Verificar que el sistema de transformers funciona correctamente en ambos componentes (ScheduledCourseForm y ConfigureCourseView) y que la validación del backend previene datos inconsistentes.

---

## Frontend Testing

### Test 1: ScheduledCourseForm - Crear curso custom
**Objetivo**: Verificar que se pueden crear cursos con horarios personalizados

**Pasos**:
1. Navegar a crear curso agendado
2. Seleccionar modo "Personalizado"
3. Agregar 3 fechas:
   - 2025-01-15: 09:00-12:00
   - 2025-01-16: 14:00-18:00
   - 2025-01-17: 08:00-13:00
4. Llenar resto del formulario
5. Guardar

**Resultado esperado**:
- ✅ Curso se crea exitosamente
- ✅ En backend, `horarios_detallados` contiene 3 sesiones con horarios correctos
- ✅ `nombre_dia` tiene formato "mié. ene. 15"
- ✅ Campo `activo: true` en todas las sesiones

---

### Test 2: ScheduledCourseForm - Editar curso custom
**Objetivo**: Verificar que se cargan correctamente los horarios al editar

**Pasos**:
1. Editar el curso creado en Test 1
2. Verificar que aparecen las 3 fechas con sus horarios correctos
3. Modificar horario de fecha 2: cambiar a 15:00-19:00
4. Guardar

**Resultado esperado**:
- ✅ Al abrir edición, se muestran las 3 fechas con horarios individuales
- ✅ Fecha 2 aparece con fondo verde (tiene horario individual)
- ✅ Al guardar, el cambio se refleja en backend
- ✅ Las otras 2 fechas mantienen sus horarios originales

---

### Test 3: ConfigureCourseView - Modificar curso custom
**Objetivo**: Verificar transformación en modal de detalles

**Pasos**:
1. Abrir curso del Test 1 en vista de detalles
2. Ir a pestaña "General"
3. Click en "Modificar Detalles"
4. Verificar que se cargan las 3 fechas
5. Cambiar instructor
6. Guardar

**Resultado esperado**:
- ✅ Modal carga correctamente las 3 fechas con horarios individuales
- ✅ Instructor cambia
- ✅ Horarios personalizados se mantienen sin cambios

---

### Test 4: ConfigureCourseView - Reagendar curso custom
**Objetivo**: Verificar transformación en modo reagendamiento

**Pasos**:
1. Desde vista de detalles del curso
2. Click en "Reagendar Curso"
3. Verificar que se cargan las 3 fechas
4. Agregar una 4ta fecha: 2025-01-18: 10:00-14:00
5. Ingresar motivo de reagendamiento
6. Guardar

**Resultado esperado**:
- ✅ Se carga el curso con las 3 fechas originales
- ✅ Se puede agregar la 4ta fecha
- ✅ Al guardar, el nuevo curso tiene 4 sesiones
- ✅ El curso original queda con estado "REAGENDADO"

---

### Test 5: Validación Frontend - Horarios inválidos
**Objetivo**: Verificar que validación bloquea datos incorrectos

**Pasos**:
1. Crear curso en modo custom
2. Agregar fecha: 2025-01-15
3. Configurar horario individual: 18:00-09:00 (fin < inicio)
4. Intentar guardar

**Resultado esperado**:
- ✅ Aparece mensaje de error: "Horario inválido para 2025-01-15: inicio debe ser anterior a fin"
- ✅ No se envía request al backend
- ✅ Usuario puede corregir el error

---

### Test 6: Validación Frontend - Sin fechas
**Objetivo**: Verificar validación de fechas vacías

**Pasos**:
1. Crear curso en modo custom
2. No seleccionar ninguna fecha
3. Intentar guardar

**Resultado esperado**:
- ✅ Aparece error: "Debe seleccionar al menos una fecha"
- ✅ No se envía request al backend

---

### Test 7: Edge Case - Sesión inactiva en backend
**Objetivo**: Verificar filtrado de sesiones inactivas

**Pasos**:
1. Crear curso con 3 fechas
2. En Django admin, editar `horarios_detallados`
3. Marcar sesión del medio como `"activo": false`
4. Editar curso desde frontend

**Resultado esperado**:
- ✅ Solo aparecen 2 fechas (se filtró la inactiva)
- ✅ Console muestra warning: "Sesión inactiva filtrada"
- ✅ Al guardar, se mantienen solo las 2 sesiones activas

---

### Test 8: Edge Case - Datos corruptos en backend
**Objetivo**: Verificar fallback cuando JSON está mal formado

**Pasos**:
1. En Django admin, editar un curso
2. Modificar `horarios_detallados` a JSON inválido:
   ```json
   {
     "modo": "personalizado",
     "sesiones": "esto_no_es_un_array"
   }
   ```
3. Intentar editar desde frontend

**Resultado esperado**:
- ✅ Console muestra warning sobre datos corruptos
- ✅ Componente hace fallback a modo "range"
- ✅ Se puede editar el curso normalmente
- ✅ Al guardar, se sobreescribe el JSON corrupto con uno válido

---

## Backend Testing (Django Admin)

### Test 9: Admin - Guardar horarios válidos
**Objetivo**: Verificar que validación permite datos correctos

**Pasos**:
1. En Django admin, editar un curso
2. Agregar `horarios_detallados`:
   ```json
   {
     "modo": "personalizado",
     "sesiones": [
       {"fecha": "2025-01-20", "inicio": "09:00", "fin": "12:00", "activo": true}
     ]
   }
   ```
3. Guardar

**Resultado esperado**:
- ✅ Se guarda exitosamente
- ✅ Sin errores de validación

---

### Test 10: Admin - Bloquear hora inicio > hora fin
**Objetivo**: Verificar validación de lógica de horarios

**Pasos**:
1. En Django admin, editar un curso
2. Agregar `horarios_detallados`:
   ```json
   {
     "modo": "personalizado",
     "sesiones": [
       {"fecha": "2025-01-20", "inicio": "18:00", "fin": "09:00", "activo": true}
     ]
   }
   ```
3. Intentar guardar

**Resultado esperado**:
- ✅ Aparece error de validación
- ✅ Mensaje: "Sesión 1 (2025-01-20): hora de inicio (18:00) debe ser anterior a hora de fin (09:00)"
- ✅ No se guarda el curso

---

### Test 11: Admin - Bloquear formato de hora inválido
**Objetivo**: Verificar validación de formato

**Pasos**:
1. En Django admin, editar un curso
2. Agregar sesión con hora mal formada:
   ```json
   {"fecha": "2025-01-20", "inicio": "9:00", "fin": "12:00"}
   ```
3. Intentar guardar

**Resultado esperado**:
- ✅ Error: "Sesión 1: formato de hora inválido. Debe ser HH:MM (ej: 09:00)"
- ✅ No se guarda

---

### Test 12: Admin - Bloquear campos faltantes
**Objetivo**: Verificar campos requeridos

**Pasos**:
1. En Django admin, editar un curso
2. Agregar sesión sin campo `inicio`:
   ```json
   {"fecha": "2025-01-20", "fin": "12:00"}
   ```
3. Intentar guardar

**Resultado esperado**:
- ✅ Error: "Sesión 1: faltan campos requeridos: inicio"
- ✅ No se guarda

---

### Test 13: Admin - Bloquear sesiones vacías
**Objetivo**: Verificar que modo personalizado requiere sesiones

**Pasos**:
1. En Django admin, editar un curso
2. Agregar:
   ```json
   {"modo": "personalizado", "sesiones": []}
   ```
3. Intentar guardar

**Resultado esperado**:
- ✅ Error: "El modo personalizado requiere al menos una sesión"
- ✅ No se guarda

---

## Integration Testing

### Test 14: Flujo completo - Crear, editar, reagendar
**Objetivo**: Verificar flujo end-to-end

**Pasos**:
1. **Crear** curso con 2 fechas con horarios diferentes
2. **Editar** el curso y agregar una 3ra fecha
3. **Modificar** instructor desde ConfigureCourseView
4. **Reagendar** el curso
5. **Verificar** en Django admin que todos los JSONs sean válidos

**Resultado esperado**:
- ✅ Todos los pasos se completan sin errores
- ✅ Cada modificación se refleja correctamente en backend
- ✅ Los JSONs están bien formados en todos los momentos
- ✅ El transformer mantiene consistencia en todas las operaciones

---

## Performance Testing

### Test 15: Muchas sesiones
**Objetivo**: Verificar rendimiento con muchas fechas

**Pasos**:
1. Crear curso en modo custom
2. Usar botón "4 semanas" varias veces para llegar a ~50 fechas
3. Configurar horarios individuales para varias fechas
4. Guardar

**Resultado esperado**:
- ✅ El componente no se congela
- ✅ Se guarda en tiempo razonable (<2 segundos)
- ✅ JSON generado es válido y completo

---

## Checklist Final

Después de ejecutar todos los tests, verificar:

- [ ] ✅ ScheduledCourseForm carga horarios individuales correctamente
- [ ] ✅ ScheduledCourseForm guarda horarios individuales correctamente
- [ ] ✅ ConfigureCourseView carga horarios individuales correctamente
- [ ] ✅ ConfigureCourseView guarda horarios individuales correctamente
- [ ] ✅ Validación frontend bloquea datos inválidos
- [ ] ✅ Validación backend bloquea datos inválidos desde admin
- [ ] ✅ Sesiones inactivas se filtran automáticamente
- [ ] ✅ Datos corruptos no crashean el frontend (fallback funciona)
- [ ] ✅ Formato `nombre_dia` es consistente ("mié. ene. 15")
- [ ] ✅ Console warnings son informativos (no errores)
- [ ] ✅ Rendimiento es aceptable con muchas fechas
- [ ] ✅ No hay breaking changes en otros componentes del sistema

---

## 🚨 Si encuentras errores

**Registra**:
1. Test que falló
2. Pasos exactos para reproducir
3. Error exacto (mensaje, stack trace)
4. Navegador y versión
5. Datos en `horarios_detallados` en ese momento

**Debugging**:
- Revisar console.log para warnings del transformer
- Verificar Network tab para ver request/response exactos
- Revisar Django logs para errores de validación
- Verificar que transformer y modelo tengan misma lógica de validación

---

## ✅ Criterio de Aprobación

El sistema pasa si:
- **100%** de tests 1-14 pasan
- **90%+** de checklist final está completo
- **0** errores críticos que rompan funcionalidad existente
- **<5** warnings en console durante uso normal

---

**Fecha de creación**: 2025-01-07
**Versión**: Opción B - Arquitectura Profesional con Transformers
**Branch**: `datetime-transformers-architecture`
