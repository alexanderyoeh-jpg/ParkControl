# Arquitectura de producción de ParkControl

## Decisión principal

La fuente de verdad será siempre el backend. Flutter presenta información y solicita acciones, pero no decide permisos, roles, estado de suscripción ni acceso a otro estacionamiento.

La arquitectura objetivo es:

```text
Flutter Android, iOS y web/PWA online/offline
        |
        v
API Node.js detrás de Nginx y HTTPS
        |
        v
PostgreSQL autoritativo + respaldos verificados
```

SQLite sigue siendo la base autoritativa durante la estabilización local. `backend/parkcontrol.db` no se borra, no se recrea y todavía no se migra. Más adelante SQLite también podrá existir dentro de Flutter como almacenamiento offline, pero esa copia nunca reemplazará la autoridad del servidor.

## Estado confirmado

- Roles `superadmin`, administrador de estacionamiento y cajero validados por la API.
- Estacionamientos aislados mediante `estacionamiento_id` en las entidades operativas.
- Suspensión y reactivación aplicadas por el backend incluso a sesiones ya abiertas.
- Movimientos conservados con estados `dentro`, `salio` y `eliminado`; no hay eliminación física de movimientos.
- Prueba automática con base temporal para aislamiento, entradas, salidas, boletas, usuarios, pagos, auditoría y suspensión.
- Las guardas de arranque de producción rechazan cuentas demo, configuración inicial HTTP y rutas de base inexistentes antes de exponer la API.
- El VPS puede supervisar `GET /healthz` (proceso vivo) y `GET /readyz` (lectura SQLite disponible); no revelan información interna.
- `SIGTERM` y `SIGINT` cierran primero HTTP y después SQLite con un checkpoint WAL pasivo, para que systemd, PM2 o Docker puedan reiniciar de forma ordenada.
- URL de API configurable desde Flutter.
- El token Bearer sólo permanece en memoria durante la sesión. No se añade a
  URLs, preferencias locales ni almacenamiento web; una nueva apertura exige
  autenticación antes de sincronizar operaciones pendientes.
- Un único código Flutter preparado para Android, iOS y web/PWA. Las tres
  plataformas consumen la misma API HTTPS y conservan las reglas de negocio
  en el backend; la configuración y los pasos de publicación están en
  `docs/PUBLICACION_ANDROID_IOS_WEB.md`.
- Control de orígenes, límite de solicitudes, encabezados defensivos, errores públicos seguros y limitación de intentos de login.
- Entradas, salidas, modificaciones y eliminaciones lógicas idempotentes mediante `Idempotency-Key`, con persistencia por estacionamiento incluso después de reiniciar el servidor.
- Snapshot autenticado de tarifa y movimientos activos para alimentar la caché local sin aceptar un `estacionamiento_id` elegido por Flutter.
- Versionado optimista de movimientos y validación opcional de la tarifa esperada para detectar conflictos de sincronización.
- Informes Pro por correo generados por el backend, con cola persistente,
  idempotencia del proveedor, reintentos y destinatario limitado a un
  administrador activo del mismo estacionamiento. El transporte permanece
  apagado hasta configurar un dominio/remitente verificado en el VPS.

Esto todavía no significa que el sistema esté listo para Internet. Faltan HTTPS,
almacenamiento seguro del token en el dispositivo, observabilidad y el ensayo
operativo en un VPS. Ya existen scripts y pruebas para respaldo/restauración,
pero falta decidir el destino remoto, automatizarlo y comprobar la recuperación
con una copia real. La cola offline, su coordinador y la materialización local
ya existen; su validación final requiere un turno real sin Internet en un
dispositivo físico.

## Orden de estabilización

### 1. Contrato operativo e idempotencia

Antes del modo offline, cada acción que pueda repetirse debe aceptar un identificador único generado por el dispositivo. Si la API recibe dos veces el mismo identificador, debe devolver el resultado original y no crear otra entrada, salida o cobro.

Ya está aplicado a entradas, salidas, modificaciones y eliminaciones lógicas. Una repetición idéntica devuelve la respuesta original y el encabezado `Idempotency-Replayed: true`. Usar la misma clave con datos diferentes devuelve `409`, y la misma clave puede existir en estacionamientos distintos sin compartir resultados.

La aplicación conserva la clave mientras una solicitud no recibe respuesta, de modo que un reintento tras una desconexión no crea otra operación.

Solo se extenderá a operaciones administrativas si posteriormente se decide que también deben funcionar sin conexión. No se agregarán claves idempotentes a consultas de solo lectura.

Los registros idempotentes se guardan en `operaciones_idempotentes`. No se eliminan automáticamente en esta etapa; antes del piloto se definirá una retención que sea mayor que el tiempo máximo durante el cual un dispositivo pueda permanecer sin conexión.

### 2. Separación del acceso a datos

El servidor actual concentra rutas, reglas y SQL en `backend/server.js`. Se extraerán módulos pequeños por dominio y repositorios de datos, manteniendo las mismas respuestas de API. Esta separación permitirá probar reglas sin iniciar el servidor y cambiar posteriormente el adaptador SQLite por PostgreSQL.

No se hará una reescritura completa. Cada extracción debe conservar la prueba automática y la operación actual.

### 3. Modo offline

Flutter tendrá una base SQLite local con dos responsabilidades:

- cachear la información necesaria para operar temporalmente;
- guardar una cola de acciones pendientes, conocida como `outbox`.

Cada elemento de la cola deberá incluir como mínimo:

- identificador UUID de operación;
- estacionamiento, usuario y dispositivo;
- tipo de acción y versión de su formato;
- datos necesarios para reproducirla;
- fecha local y fecha de creación de cola;
- número de intentos, estado y último error.

La sincronización será ordenada por estacionamiento. Una acción solo se marca completada cuando el servidor confirma su resultado. Los reintentos usarán el mismo UUID.

Las reglas de conflicto deben definirse antes de programar la cola. Como mínimo: patente ya activa, salida sin entrada válida, tarifa modificada mientras el equipo estuvo desconectado, usuario desactivado y estacionamiento suspendido. Ninguno de esos conflictos debe resolverse confiando solamente en Flutter.

Las capas base ya están incorporadas con Drift: cola SQLite persistente, caché local de movimientos activos y tarifa, y coordinador de envío secuencial. Incluyen aislamiento por estacionamiento, reserva atómica, reintentos crecientes, recuperación de envíos interrumpidos, detención estricta ante conflictos y migración de esquema sin perder la cola anterior. El contrato detallado está en `docs/CONTRATO_SINCRONIZACION_OFFLINE.md`.

La caché se reconcilia desde un snapshot versionado del backend. Conserva operaciones locales pendientes o en conflicto y solo retira proyecciones confirmadas que ya no aparecen activas en el servidor. Las pantallas operativas ya materializan dichas operaciones, muestran su estado de sincronización y permiten resolver conflictos de manera auditada.

## Migración futura a PostgreSQL

La migración se realizará solo después de estabilizar contratos y repositorios:

1. crear migraciones PostgreSQL versionadas;
2. probarlas con una base desechable;
3. construir una importación SQLite → PostgreSQL repetible;
4. comparar conteos, relaciones, estados y totales monetarios;
5. ensayar respaldo, restauración y reversión;
6. realizar el corte con una ventana controlada y validación final.

No se usará escritura doble entre SQLite y PostgreSQL como paso inicial, porque aumenta el riesgo de divergencia silenciosa.

### Representación monetaria pendiente

SQLite conserva actualmente tarifas y montos como `REAL`. Antes de migrar datos financieros a PostgreSQL se definirá una representación exacta: centavos enteros o columnas `NUMERIC` con escala fija. Esta corrección requiere una migración controlada y conciliación de totales; no debe aplicarse como una conversión silenciosa sobre los cobros históricos.

## Configuración HTTP incorporada

Variables relevantes del backend:

- `NODE_ENV=production`: activa las restricciones de producción.
- `PARKCONTROL_AUTH_SECRET`: obligatorio en producción, con al menos 32 caracteres.
- `PARKCONTROL_ALLOWED_ORIGINS`: lista separada por comas de sitios web autorizados.
- `PARKCONTROL_JSON_LIMIT`: tamaño máximo del JSON; predeterminado `256kb`.
- `PARKCONTROL_LOGIN_MAX_ATTEMPTS`: intentos fallidos permitidos; predeterminado `5`.
- `PARKCONTROL_LOGIN_WINDOW_MS`: ventana del bloqueo; predeterminado `900000`.
- `PARKCONTROL_TRUST_PROXY=true`: se usará detrás de Nginx para reconocer correctamente la IP del cliente.
- `PARKCONTROL_HOST`: en producción sólo acepta loopback; Nginx es quien expone HTTPS al exterior.
- `PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS`: espera corta y validada ante escrituras concurrentes; SQLite se inicia en modo WAL.
- `PARKCONTROL_DB_PATH`: ubicación explícita de SQLite mientras siga siendo la base activa. En producción debe ser absoluta y referirse a un archivo ya existente; un error de ruta detiene el inicio en vez de crear una base vacía.
- `PARKCONTROL_ALLOW_SETUP`: nunca se habilita en producción. La primera cuenta propietaria debe crearse antes de publicar la API mediante `PARKCONTROL_SUPERADMIN_EMAIL`, `PARKCONTROL_SUPERADMIN_PASSWORD` (mínimo 12 caracteres) y, opcionalmente, `PARKCONTROL_SUPERADMIN_NOMBRE`, o restaurando una base que ya la contenga. Sin un SuperAdministrador activo la API no inicia.
- `PARKCONTROL_CREAR_USUARIOS_DEMO`: sólo sirve para desarrollo y pruebas; en producción detiene el inicio para impedir credenciales conocidas.
- `PARKCONTROL_EMAIL_*`: configuración opcional y exclusiva del servidor para
  informes Pro. Sólo se activa con proveedor, API key y remitente válidos;
  consultar `docs/CONTRATO_INFORMES_CORREO_PRO.md`.

Las compilaciones Flutter de publicación requieren
`--dart-define=PARKCONTROL_API_URL=https://api.tu-dominio.cl`. No se permite
una URL HTTP ni el valor local predeterminado en modo release. El sitio web
publicado debe estar incluido exactamente en `PARKCONTROL_ALLOWED_ORIGINS`,
por ejemplo `https://app.tu-dominio.cl`.

En desarrollo, si no se declara una lista de orígenes, se conserva el acceso abierto para no interrumpir Flutter local. En producción, un navegador no listado recibe `403`; las aplicaciones móviles y llamadas servidor-a-servidor sin `Origin` siguen permitidas y deben autenticarse normalmente.

Para supervisión de infraestructura, Nginx o el gestor de contenedores puede consultar `GET /healthz`; un `200` confirma que el proceso responde. `GET /readyz` además comprueba una lectura SQLite y devuelve `503` si la base no está disponible. Ninguno requiere token ni entrega nombres, rutas, usuarios o métricas comerciales.

Al respaldar SQLite en modo WAL, no se debe copiar únicamente el archivo `.db` mientras la API está abierta: se debe usar una copia consistente (por ejemplo, un respaldo SQLite controlado o una detención ordenada) que contemple el estado WAL. La restauración se prueba antes de declarar válido un respaldo.

## Criterio para avanzar

Cada bloque debe conservar las funciones actuales, pasar las pruebas automáticas, verificar la integridad de la base usada en la prueba y documentar cualquier cambio de contrato. Los ajustes visuales de dashboards se atenderán en bloques separados para que un cambio de interfaz no oculte una regresión del servidor.
