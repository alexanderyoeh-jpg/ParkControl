# Despliegue inicial en VPS

Esta guía prepara el primer entorno productivo de ParkControl: Flutter se comunica por HTTPS con Nginx, Nginx reenvía sólo a Node en loopback y SQLite sigue siendo la fuente de verdad. No ejecuta una migración a PostgreSQL, no publica el puerto `3000` y no autoriza copiar una base activa como un archivo normal.

> Antes del piloto, se debe ensayar este procedimiento en un VPS de staging con datos de prueba. Cada comando es una acción de operador; no se ejecuta automáticamente desde el repositorio.

## Alcance y decisión de arquitectura

```text
Aplicación Flutter
       |
       | HTTPS
       v
Nginx (80/443 público) ──> Node/Express (127.0.0.1:3000)
                                      |
                                      v
                         SQLite + WAL (/var/lib/parkcontrol)
```

- La API es la fuente de verdad de roles, planes, suspensión y `estacionamiento_id`.
- `backend/parkcontrol.db` del entorno de desarrollo no se borra ni se recrea.
- En producción `PARKCONTROL_DB_PATH` debe ser una ruta absoluta de un archivo ya existente. Si es incorrecta, ParkControl se detiene para impedir crear una base vacía.
- La migración a PostgreSQL está prohibida en este despliegue; consultar [PLAN_MIGRACION_POSTGRESQL.md](PLAN_MIGRACION_POSTGRESQL.md).

## Requisitos previos

- Un VPS Linux actualizado, con IP pública, acceso SSH mediante llave y un dominio como `api.tu-dominio.cl`.
- Firewall: permitir únicamente SSH administrativo, `80/tcp` y `443/tcp`. El puerto `3000` no se expone a Internet.
- Node.js LTS compatible con el `package-lock.json`, Nginx y un emisor de certificados TLS instalado según la distribución.
- Un usuario de sistema no interactivo `parkcontrol`, propietario de `/var/lib/parkcontrol` y sin privilegios de administrador.
- Un directorio de código de solo lectura para el servicio, por ejemplo `/opt/parkcontrol`, con `backend/node_modules` instalado mediante `npm ci --omit=dev` desde el artefacto revisado.
- Un destino de respaldo independiente del disco principal y una prueba de restauración satisfactoria antes de aceptar datos de clientes. Ver [RESPALDOS_Y_RESTAURACION.md](RESPALDOS_Y_RESTAURACION.md).

No copies credenciales, archivos `.env` ni `parkcontrol.db` al repositorio Git. El futuro repositorio privado contendrá código y plantillas, nunca datos operativos ni secretos.

## 1. Preparar el código y el usuario de servicio

1. Crear el usuario y grupo `parkcontrol` sin acceso de inicio de sesión.
2. Instalar una versión LTS de Node y confirmar su ruta con `command -v node`. Actualizar `ExecStart` de la plantilla systemd si no coincide con `/usr/bin/node`.
3. Desplegar el artefacto revisado bajo `/opt/parkcontrol`. El usuario del servicio necesita lectura del código, no escritura sobre él.
4. Dentro de `/opt/parkcontrol/backend`, instalar exactamente las dependencias bloqueadas con `npm ci --omit=dev` y ejecutar `npm test` antes de publicar la unidad.
5. Crear `/var/lib/parkcontrol` con dueño `parkcontrol:parkcontrol` y permisos restrictivos. Este directorio albergará el archivo SQLite, `-wal` y `-shm`.

No apuntes `PARKCONTROL_DB_PATH` a una ruta de `/tmp`, a un directorio del código ni a una unidad de red sin confirmar compatibilidad con bloqueos SQLite y WAL.

## 2. Transferir la base de datos de forma consistente

SQLite trabaja en modo WAL. Por ello, no se debe transferir únicamente `parkcontrol.db` mientras la API de origen esté activa: puede faltar información que aún vive en el archivo WAL.

Procedimiento seguro:

1. Crear una instantánea consistente mediante `backend/scripts/respaldo_sqlite.js` en el entorno de origen, con una ruta absoluta de destino nueva. El script usa la API de respaldo de SQLite y no sobrescribe destinos existentes.
2. Validar esa instantánea mediante `backend/scripts/verificar_restauracion_sqlite.js`, incluyendo el SHA-256 entregado por el respaldo.
3. Transferir el archivo validado al VPS por un canal cifrado, verificar nuevamente su hash y dejarlo como `/var/lib/parkcontrol/parkcontrol.db` con dueño `parkcontrol:parkcontrol` y permisos restrictivos.
4. Conservar la copia de origen intacta y conservar evidencia del hash y de la fecha. No usar la transferencia como una sustitución de respaldo.

Los comandos exactos, retención y ensayo de restauración están documentados en [RESPALDOS_Y_RESTAURACION.md](RESPALDOS_Y_RESTAURACION.md). No se automatiza aún un temporizador hasta que el destino remoto y la prueba de recuperación estén aprobados.

## 3. Crear el archivo de entorno seguro

Crear `/etc/parkcontrol/parkcontrol.env`, propiedad de `root`, con permisos `0600`. Puede partir de [`backend/.env.example`](../backend/.env.example), reemplazando todos los marcadores mediante el gestor de secretos del VPS.

Valores que deben estar definidos en producción:

```dotenv
NODE_ENV=production
PORT=3000
PARKCONTROL_HOST=127.0.0.1
PARKCONTROL_DB_PATH=/var/lib/parkcontrol/parkcontrol.db
PARKCONTROL_AUTH_SECRET=<secreto-aleatorio-de-al-menos-32-caracteres>
PARKCONTROL_ALLOWED_ORIGINS=https://app.tu-dominio.cl
PARKCONTROL_TRUST_PROXY=true
PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS=5000
```

Para la primera instalación, definir temporalmente `PARKCONTROL_SUPERADMIN_EMAIL` y `PARKCONTROL_SUPERADMIN_PASSWORD` (mínimo 12 caracteres) sólo dentro del gestor de secretos. Si se restaura una base con un SuperAdministrador activo, no es necesario dejarlas presentes. Nunca habilitar:

```dotenv
PARKCONTROL_ALLOW_SETUP=true
PARKCONTROL_CREAR_USUARIOS_DEMO=true
```

Ambas opciones hacen que el backend rechace el arranque en producción. Mercado Pago permanece deshabilitado hasta que se disponga de cuenta, HTTPS, credenciales de servidor y webhook validados; si se habilita, sus tres variables deben configurarse juntas y nunca se entregan a Flutter.

## 4. Instalar y comprobar systemd

1. Copiar [`infra/systemd/parkcontrol.service.example`](../infra/systemd/parkcontrol.service.example) como `/etc/systemd/system/parkcontrol.service`.
2. Revisar rutas, usuario, grupo y versión de Node; no modificar `PARKCONTROL_HOST=127.0.0.1`.
3. Recargar systemd, habilitar la unidad y arrancarla bajo supervisión.
4. Revisar `systemctl status parkcontrol` y los registros de `journalctl -u parkcontrol`. Un fallo por ruta de base, integridad, secreto corto o falta de SuperAdministrador es intencional y debe corregirse antes de reintentar.
5. Desde el VPS, confirmar que `http://127.0.0.1:3000/healthz` y `http://127.0.0.1:3000/readyz` responden `200`.

`/healthz` indica que el proceso HTTP responde. `/readyz` también ejecuta una lectura SQLite. Ninguno revela datos comerciales. systemd envía `SIGTERM` al detener la API; ParkControl cierra HTTP y SQLite ordenadamente, incluida una solicitud de checkpoint WAL pasivo.

## 5. Instalar Nginx y TLS

1. Crear el registro DNS `A`/`AAAA` de `api.tu-dominio.cl` hacia el VPS y esperar propagación.
2. Copiar [`infra/nginx/parkcontrol-api.conf.example`](../infra/nginx/parkcontrol-api.conf.example) a la ubicación de sitios de Nginx de la distribución; reemplazar el dominio y las rutas de certificado.
3. Emitir el certificado TLS y validar la configuración con `nginx -t` antes de recargar Nginx.
4. Confirmar desde Internet `https://api.tu-dominio.cl/healthz` y desde el VPS `https://api.tu-dominio.cl/readyz`. La plantilla limita `/readyz` a loopback; agregar una IP de monitor explícita sólo si es necesaria.
5. Verificar que `http://api.tu-dominio.cl` redirige a HTTPS y que `http://IP_DEL_VPS:3000` no responde desde fuera.

La opción `PARKCONTROL_TRUST_PROXY=true` es correcta solamente detrás de este proxy controlado. Si se coloca otro proxy delante de Nginx, revisar la cadena de IPs confiables antes de modificarla.

## 6. Publicar la plataforma web

La aplicación web Flutter no se sirve desde Node. Se compila una vez con la
URL HTTPS de la API y Nginx entrega sus archivos estáticos en un subdominio
separado, por ejemplo `app.tu-dominio.cl`:

```bash
flutter build web --release \
  --dart-define=PARKCONTROL_API_URL=https://api.tu-dominio.cl
```

Copiar únicamente el contenido de `build/web` al directorio web del VPS, por
ejemplo `/var/www/parkcontrol-web`, con usuario de lectura para Nginx. Usar la
plantilla [`infra/nginx/parkcontrol-web.conf.example`](../infra/nginx/parkcontrol-web.conf.example)
después de reemplazar el dominio y las rutas TLS. Agregar exactamente
`https://app.tu-dominio.cl` a `PARKCONTROL_ALLOWED_ORIGINS` en el entorno de
Node y reiniciar el servicio de manera controlada.

No colocar `build/web`, la API, respaldos, `.env` ni SQLite bajo el mismo
directorio público. Probar login, recarga de una ruta interna, PDF autenticado,
reconexión offline y cierre de sesión antes de anunciar la URL.

## 7. Lista de aceptación antes de abrir a usuarios

- [ ] `NODE_ENV=production` y `PARKCONTROL_HOST=127.0.0.1` están activos.
- [ ] `PARKCONTROL_DB_PATH` es absoluto, existe, pertenece al usuario de servicio y pasó `quick_check` y `foreign_key_check` al arrancar.
- [ ] Existe un SuperAdministrador activo sin usar credenciales demo.
- [ ] No hay secretos, respaldo ni base de datos dentro del repositorio ni del directorio público de Nginx.
- [ ] Sólo Nginx escucha tráfico público; el puerto 3000 no figura en el firewall.
- [ ] HTTPS, redirección HTTP, `/healthz` y `/readyz` funcionan según la política de acceso.
- [ ] Se ejecutó una restauración de ensayo desde un respaldo reciente y se registró su resultado.
- [ ] Login, entrada, salida, modificación lógica, comprobante Pro, cierre de caja, suspensión y aislamiento entre dos estacionamientos se probaron en staging.
- [ ] Se definió una persona responsable de incidentes, respaldos y rotación de secretos.
- [ ] La web se compiló con `PARKCONTROL_API_URL` HTTPS, el dominio final está
  incluido en `PARKCONTROL_ALLOWED_ORIGINS` y la recarga de rutas internas
  funciona detrás de Nginx.
- [ ] Android/iOS se compilaron con la misma URL HTTPS y se probaron en equipos
  físicos antes de enviar a las tiendas.

## Rollback del despliegue

Si la nueva versión falla antes de aceptar operaciones:

1. Poner Nginx en mantenimiento o retirar temporalmente el upstream para detener nuevas escrituras.
2. Detener ParkControl mediante systemd y conservar los registros del incidente.
3. Volver al artefacto de código previamente validado y a su `node_modules` correspondiente; no modificar ni borrar la base como parte del rollback de código.
4. Arrancar la versión anterior y comprobar `/healthz`, `/readyz` y un login de prueba autorizado.
5. Si se sospecha daño de datos, no continuar escribiendo. Seguir el procedimiento de restauración aislada en [RESPALDOS_Y_RESTAURACION.md](RESPALDOS_Y_RESTAURACION.md) y documentar la hora de corte.

El rollback de código y la restauración de datos son decisiones separadas. Nunca se restaura un respaldo sólo para revertir una pantalla o una versión de API.
