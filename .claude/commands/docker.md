# /docker - Control de servicios Docker para QSystem

Eres un asistente para manejar los servicios Docker del proyecto QSystem. Interpreta el subcomando del usuario y ejecuta la accion correspondiente.

## Argumento requerido

El usuario pasa un subcomando: `/docker <subcomando> [opciones]`

Argumento recibido: $ARGUMENTS

## Subcomandos disponibles

### `up` - Levantar servicios de desarrollo
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose --profile dev up -d
```
Despues verifica que todos los contenedores estan corriendo:
```bash
docker-compose ps
```

### `down` - Detener todos los servicios
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose down
```

### `restart [servicio]` - Reiniciar servicio(s)
Si se especifica un servicio (backend, frontend-dev, db):
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose restart {servicio}
```
Si no se especifica servicio, reinicia todo:
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose --profile dev down && docker-compose --profile dev up -d
```

### `logs [servicio]` - Ver logs
Si se especifica servicio:
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose logs --tail=80 {servicio}
```
Si no se especifica, muestra logs de backend y frontend-dev:
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose logs --tail=50 backend frontend-dev
```

### `migrate [nombre_migracion]` - Ejecutar migraciones Django
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose exec backend python manage.py migrate
```
Si se proporciona un nombre de app o migracion especifica:
```bash
docker-compose exec backend python manage.py migrate {nombre}
```

### `makemigrations [app]` - Crear migraciones
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose exec backend python manage.py makemigrations {app}
```

### `shell` - Abrir Django shell
Informa al usuario que ejecute manualmente:
```
! docker-compose exec backend python manage.py shell
```
(Los shells interactivos no se pueden ejecutar desde Claude, el usuario debe hacerlo con el prefijo `!`)

### `test [args]` - Ejecutar tests
Para backend:
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose exec backend python manage.py test {args}
```
Si el argumento menciona "frontend" o "front":
```bash
cd /Users/anuareramirez/DEV/qsys/qsystem-frontend && npm test
```

### `build [servicio]` - Reconstruir imagen(es)
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose build {servicio}
```
Si no se especifica servicio, reconstruye todo:
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose build
```

### `ps` o `status` - Estado de los contenedores
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose ps
```

### `clean` - Limpiar todo (pide confirmacion)
PRIMERO pregunta al usuario si esta seguro, ya que esto elimina volumenes.
Si confirma:
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose down -v && docker system prune -f
```

### `seed` - Poblar base de datos con datos de prueba
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose exec backend python manage.py poblar_produccion
```

### `resetdb` - Resetear base de datos (pide confirmacion)
PRIMERO pregunta al usuario si esta seguro.
Si confirma:
```bash
cd /Users/anuareramirez/DEV/qsys && docker-compose exec db psql -U postgres -c "DROP DATABASE qsystem;" && docker-compose exec db psql -U postgres -c "CREATE DATABASE qsystem;" && docker-compose exec backend python manage.py migrate
```

## Comportamiento cuando no hay argumento

Si $ARGUMENTS esta vacio, muestra la lista de subcomandos disponibles con una breve descripcion de cada uno.

## Reglas importantes

- Para `clean` y `resetdb`, SIEMPRE pide confirmacion antes de ejecutar
- Para `shell`, indica al usuario que use `!` para ejecutar interactivamente
- Despues de `up`, siempre verifica el estado con `docker-compose ps`
- Despues de `migrate`, muestra si hubo migraciones aplicadas o si estaba todo al dia
- Si un comando falla, muestra el error y sugiere una solucion
- El directorio base del proyecto es siempre `/Users/anuareramirez/DEV/qsys`
