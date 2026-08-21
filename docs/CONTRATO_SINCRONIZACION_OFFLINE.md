# Contrato de sincronización offline de ParkControl

## Estado actual

Las capas base offline están implementadas y probadas: una base SQLite local multiplataforma contiene una cola persistente de operaciones, una caché operativa de tarifa y movimientos activos, un coordinador de envío y una capa de materialización local para entradas, salidas, modificaciones y eliminaciones lógicas. Funciona en Windows mediante SQLite nativo y está preparada para navegador mediante SQLite WebAssembly.

Las pantallas de entrada, salida y modificación ya usan esta base como respaldo cuando no hay conexión. La API sigue siendo la ruta principal; si falla la red, la operación se guarda localmente y queda pendiente de sincronización.

Los dashboards de cajero y administrador muestran un indicador central cuando existen operaciones pendientes, enviándose, bloqueadas o en conflicto. Ese indicador permite forzar un reintento manual, abre un detalle de sincronización y también activa un reintento silencioso periódico desde el dashboard.

El detalle de sincronización ya lista operaciones pendientes, bloqueadas y en conflicto sin borrar ni saltarse registros. Los conflictos pueden descartarse localmente sólo después de auditar la decisión en el backend mediante `POST /api/sincronizacion/conflictos/resolver`; esa acción no modifica movimientos del servidor y queda registrada en auditoría.

Ya existen pruebas automatizadas para reinicio con operaciones pendientes y para un turno corto sin internet con sincronización posterior en orden entrada → salida. Cuando una salida offline queda confirmada por el servidor, Flutter guarda un comprobante local pendiente de revisión con el folio, patente, horas, minutos, tarifa y monto; el dashboard muestra el aviso y el detalle de sincronización permite ver el comprobante y marcarlo como visto. La boleta PDF final queda disponible en el módulo de boletas/historial porque se genera desde el servidor.

Todavía falta repetir el escenario offline manualmente en un dispositivo real antes de anunciarlo como disponible en producción.

La caché se llena desde `GET /api/sincronizacion/estado`. El servidor obtiene el estacionamiento desde la sesión autenticada y devuelve `versionFormato`, fecha del servidor, tarifa activa y movimientos con estado `dentro`. Flutter no puede pedir por parámetro los datos de otro estacionamiento.

Cuando una entrada offline se confirma, Flutter enlaza su clave local con el `id` y la versión entregados por el backend antes de reconciliar el snapshot. De esta forma no aparecen dos filas locales para el mismo vehículo. Un snapshot tampoco sobrescribe una modificación, salida o eliminación lógica todavía pendiente: la proyección local se conserva hasta que el servidor confirme esa misma operación.

## Información guardada

Cada operación contiene:

- clave idempotente;
- `estacionamiento_id` y usuario que la originó;
- tipo: entrada, salida, modificación o eliminación lógica;
- método y ruta relativa de API;
- cuerpo JSON y versión de formato;
- estado, intentos, último error y próximo intento;
- fechas de creación y actualización.

La base local no guarda contraseñas ni copia el token dentro de cada operación. Al sincronizar se utilizará la sesión vigente y el backend volverá a validar usuario, permisos, estacionamiento y estado de la suscripción.

La caché operativa guarda por `estacionamiento_id`:

- identificador y valor de la tarifa confirmada por el servidor;
- identificador, patente, datos, hora de entrada y versión de cada movimiento activo;
- estado local de sincronización de cada movimiento;
- fechas de actualización del snapshot.

Una reconciliación retira solamente proyecciones ya confirmadas que dejaron de estar activas en el servidor. Nunca borra un movimiento del backend ni elimina una entrada local pendiente o en conflicto.

## Estados

| Estado | Significado | Acción |
| --- | --- | --- |
| `pendiente` | Lista para enviar o esperando su próximo intento | Se procesa al llegar su turno |
| `enviando` | La solicitud salió pero aún no fue confirmada | Al reiniciar vuelve a `pendiente` con la misma clave |
| `completada` | El backend confirmó el resultado | No vuelve a enviarse |
| `conflicto` | El servidor rechazó una condición operativa | Requiere resolución visible y auditada |
| `bloqueada` | La sesión, permiso o suscripción impide sincronizar | Requiere autenticación o intervención administrativa |

## Orden y aislamiento

- La cola se procesa por `estacionamiento_id` **y** `usuario_id`.
- Dentro de cada cajero y estacionamiento se respeta estrictamente el orden de creación.
- Una operación `enviando`, `conflicto` o `bloqueada` detiene las siguientes del mismo cajero, no las de otro cajero.
- Un cajero sólo puede ver, reintentar, reanudar o enviar las operaciones que originó; una sesión nueva no puede atribuirse la cola pendiente de otra persona.
- Una operación de otro estacionamiento nunca se devuelve desde la consulta del cliente actual.
- Repetir la misma clave con los mismos datos no crea otra fila.
- Repetir la misma clave con otros datos se considera un error y se rechaza.

Esta regla impide que una salida se sincronice antes de la entrada de la cual depende.

## Política de reintentos

Después de cada intento fallido se usa una espera creciente de 5, 10, 20, 40, 80, 160 y como máximo 320 segundos. La aplicación no debe realizar ciclos continuos sin espera.

Resultado aplicado por el coordinador de red:

- respuesta `2xx`: `completada`;
- pérdida de red, timeout, `5xx`, `408`, `425` o `429`: vuelve a `pendiente` con espera creciente;
- `409` operativo: `conflicto`;
- `401`: pausa y solicita iniciar sesión;
- `403` por suspensión o permisos: `bloqueada`;
- datos inválidos no recuperables: `conflicto`, mostrando el mensaje del servidor.

Antes de marcar una respuesta `2xx` como completada, el dispositivo actualiza su proyección local. Si esa proyección falla, conserva la misma clave idempotente y reintenta de forma segura: el backend devuelve el resultado original y no crea un segundo movimiento ni cobro.

La reserva de la siguiente operación es atómica: dos activaciones concurrentes del coordinador local no pueden enviar la misma fila. Si la aplicación se cierra durante un envío, al reiniciar se devuelve la fila a `pendiente` y se conserva su clave idempotente. Después de una nueva autenticación o reactivación se pueden reanudar solamente las filas `bloqueada` del estacionamiento actual; los conflictos nunca se liberan automáticamente.

## Conflictos que deben resolverse en el backend

1. Patente ya activa al sincronizar una entrada.
2. Salida cuya entrada fue eliminada, cerrada o no existe.
3. Modificación de un movimiento que cambió mientras el dispositivo estuvo offline.
4. Usuario desactivado o permiso retirado.
5. Estacionamiento suspendido.
6. Cambio de tarifa durante el periodo sin conexión.

Las modificaciones y eliminaciones pueden enviar `versionEsperada`. Las salidas también pueden enviar `movimientoId`, `versionEsperada` y `tarifaIdEsperada`. Si el estado cambió, el backend responde `409` con `MOVIMIENTO_DESACTUALIZADO` o `TARIFA_DESACTUALIZADA`; los campos siguen siendo opcionales para conservar compatibilidad con las pantallas online actuales.

Las entradas offline pueden enviar `horaEntradaCliente` y las salidas offline pueden enviar `horaSalidaCliente`. El backend valida esas fechas y las usa para conservar la hora real de operación cuando el dispositivo se reconecta más tarde. Si no se envían, la operación online conserva el comportamiento actual y usa la hora del servidor.

Flutter puede mostrar y solicitar una decisión, pero nunca debe forzar la aceptación del conflicto sin una ruta específica y validada por el backend. La resolución disponible en el MVP es conservadora: descartar la operación local, registrar motivo y permitir que la cola continúe; aplicar un conflicto sobre datos reales requerirá rutas específicas por tipo de conflicto.

## Compatibilidad de plataformas

La implementación usa Drift sobre SQLite:

- Android, iOS, Windows, Linux y macOS utilizan una base en los documentos de la aplicación.
- Web utiliza `web/sqlite3.wasm` y `web/drift_worker.js` del mismo lanzamiento que Drift `2.34.3`.
- El servidor web de producción deberá entregar `sqlite3.wasm` con `Content-Type: application/wasm`.
- Los encabezados COOP/COEP podrán mejorar el almacenamiento web, pero se probarán antes porque pueden interferir con ventanas emergentes de otros paquetes.

## Próximo bloque

1. Probar reinicio de app y turno offline en dispositivo real.
2. Activar offline primero en un entorno de prueba y después en el piloto.

No se anunciará “modo offline disponible” hasta que entrada, salida, cálculo, reinicio, conflicto y reconciliación hayan sido probados de extremo a extremo.
