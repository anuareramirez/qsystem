# /commit - Smart Commit para QSystem Monorepo

Eres un asistente de commits para un monorepo con Git Submodules (frontend y backend). Tu trabajo es analizar los cambios, generar un buen mensaje de commit, y ejecutar el proceso completo.

## Argumento opcional

El usuario puede pasar un mensaje de commit como argumento: `/commit fix: corregir bug en login`
Si no pasa argumento, genera el mensaje analizando los cambios.

Argumento recibido: $ARGUMENTS

## Proceso

### Paso 1: Detectar cambios

Ejecuta estos comandos en paralelo para entender el estado actual:

```bash
# Estado del frontend
cd /Users/anuareramirez/DEV/qsys/qsystem-frontend && git status --short
```

```bash
# Estado del backend
cd /Users/anuareramirez/DEV/qsys/qsystem-backend && git status --short
```

```bash
# Estado del monorepo raiz
cd /Users/anuareramirez/DEV/qsys && git status --short
```

### Paso 2: Determinar el target

Basado en los cambios detectados:
- Si solo hay cambios en `qsystem-frontend/` -> target = `frontend`
- Si solo hay cambios en `qsystem-backend/` -> target = `backend`
- Si hay cambios en ambos -> target = `both`
- Si no hay cambios en ningun submodule -> informar al usuario y terminar

### Paso 3: Analizar los cambios en detalle

Para cada submodule con cambios, ejecuta `git diff` (staged y unstaged) para entender QUE cambio.

```bash
# Diff del frontend (si tiene cambios)
cd /Users/anuareramirez/DEV/qsys/qsystem-frontend && git diff && git diff --cached
```

```bash
# Diff del backend (si tiene cambios)
cd /Users/anuareramirez/DEV/qsys/qsystem-backend && git diff && git diff --cached
```

### Paso 4: Generar mensaje de commit

Si el usuario NO proporciono un mensaje ($ARGUMENTS esta vacio):
- Analiza los diffs del paso 3
- Genera un mensaje siguiendo conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `style:`, `test:`
- El mensaje debe ser conciso (1 linea principal, max 72 chars)
- Si los cambios son complejos, agrega un cuerpo descriptivo
- Muestra el mensaje propuesto al usuario y pide confirmacion

Si el usuario SI proporciono un mensaje:
- Usa ese mensaje directamente

### Paso 5: Ejecutar commit-helper.sh

Una vez confirmado el mensaje, ejecuta:

```bash
cd /Users/anuareramirez/DEV/qsys && ./commit-helper.sh {target} "{mensaje}"
```

Donde `{target}` es `frontend`, `backend`, o `both` segun el Paso 2.

### Paso 6: Confirmar resultado

Muestra un resumen:
- Target: frontend/backend/both
- Mensaje de commit usado
- Estado del push (exito o error)

## Reglas importantes

- NUNCA hagas commit sin mostrar al usuario que cambios se van a incluir
- Si el diff es muy grande, muestra un resumen en vez del diff completo
- Si hay archivos sensibles (.env, credentials, secrets), ADVIERTE al usuario
- Si hay archivos no rastreados nuevos, mencionalos explicitamente
- El script `commit-helper.sh` hace `git add -A` internamente, asi que TODOS los cambios se incluyen
- El script tambien hace push automaticamente a todos los repos
