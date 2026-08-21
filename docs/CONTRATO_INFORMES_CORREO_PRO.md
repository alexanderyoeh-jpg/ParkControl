# Informes Pro por correo

## Propósito

Los administradores del plan Pro pueden programar un resumen contable para su
cuenta administradora. El informe se genera en el backend desde movimientos
reales del mismo estacionamiento y se entrega con un PDF operacional y un CSV
de detalle. No depende de que Flutter permanezca abierto.

No es una boleta tributaria ni sustituye al contador del estacionamiento.

## Límites de seguridad

- La API exige sesión activa, administrador, estacionamiento activo y la
  capacidad Pro `reportesPorCorreo`.
- El `estacionamiento_id` se obtiene exclusivamente del token. Flutter nunca
  puede elegir el cliente de un informe.
- El destinatario inicial es el correo de la cuenta administradora que crea o
  actualiza la programación. La API no acepta correos arbitrarios: evita que
  esta función se use para extraer información hacia terceros.
- Si esa persona deja de ser administrador activo, los envíos pendientes se
  cancelan; no se redirigen silenciosamente.
- La interfaz y las respuestas API muestran el correo enmascarado.
- No se guardan secretos, contenido de adjuntos, tarjeta, payloads del
  proveedor ni detalles crudos de errores en SQLite o logs.
- Los CSV neutralizan valores que podrían abrirse como fórmulas en una
  planilla.

## Periodos y programación

Cada estacionamiento puede tener una programación activa o pausada por cada
frecuencia:

- **Diaria:** entrega el día local ya cerrado.
- **Semanal:** cubre lunes a domingo anteriores.
- **Mensual:** cubre el mes anterior.

La hora y el periodo se calculan con la zona IANA del estacionamiento, no con
la zona del VPS. Si el proceso estuvo detenido el lunes o el día 1, al volver
en un día posterior prepara el último período semanal o mensual ya cerrado;
no genera una avalancha de informes antiguos. La clave de período impide que
ticks o reinicios repetidos dupliquen ese envío.

Un informe manual usa el mes local actual hasta el día de la solicitud. Exige
`Idempotency-Key` para que un doble toque o reintento de red no cree dos envíos.

## Cola y estados

Las tablas `informes_correo_programados`, `informes_correo_envios` e
`informes_correo_eventos` conservan programación, estado y trazabilidad. No se
borran los envíos ni sus eventos.

| Estado | Significado |
| --- | --- |
| `pendiente` | Espera ser tomada por el procesador. |
| `enviando` | Un proceso tiene una reserva temporal. |
| `reintento` | Falló de forma transitoria y quedó con nueva fecha. |
| `enviado` | El proveedor devolvió un identificador de envío. |
| `fallido` | Falló de manera definitiva o agotó seis intentos. |
| `cancelado` | Se desactivó la programación, el plan dejó de ser Pro, la cuenta se suspendió o el destinatario dejó de ser administrador. |

Las reservas vencidas se recuperan al siguiente ciclo. Los reintentos siguen
una espera creciente (1 min, 5 min, 30 min, 2 h, 8 h y 24 h). Cada solicitud a
Resend usa una clave idempotente estable por envío, reduciendo el riesgo de
duplicar un correo ante una caída entre la respuesta remota y la actualización
local. Resend documenta soporte de `Idempotency-Key` para `POST /emails`.

## Activación del transporte

En una instalación nueva el correo queda deliberadamente apagado. Es correcto
crear programaciones, pero no se fingirá que un informe fue enviado.

Antes de activarlo se necesita:

1. un dominio de ParkControl y una dirección remitente controlada;
2. verificar el dominio/remitente en Resend, incluyendo los registros que su
   panel solicite;
3. crear una API key con permiso sólo de envío;
4. guardar la clave únicamente en el gestor de secretos del VPS;
5. ejecutar un envío de prueba a una cuenta controlada y revisar entrega,
   adjuntos y spam.

Variables de entorno del servidor:

```ini
PARKCONTROL_EMAIL_PROVIDER=resend
PARKCONTROL_RESEND_API_KEY=re_SOLO_EN_EL_GESTOR_DE_SECRETOS
PARKCONTROL_EMAIL_FROM="ParkControl <informes@tu-dominio.cl>"
PARKCONTROL_EMAIL_REPLY_TO=soporte@tu-dominio.cl
PARKCONTROL_EMAIL_TIMEOUT_MS=15000
```

La configuración es rechazada si falta la clave o el remitente. No poner estas
variables en Flutter, Git, la base de datos ni capturas de pantalla. Al iniciar
con una configuración completa, el API procesa una pequeña cantidad de trabajos
cada minuto; una falla de correo no interrumpe entradas, salidas, cobros ni
cierres de caja.

El adaptador usa la API HTTPS de Resend y adjuntos en Base64. Las referencias
oficiales relevantes son [envío de correo](https://resend.com/docs/api-reference/emails/send-email),
[claves de idempotencia](https://resend.com/docs/dashboard/emails/idempotency-keys)
y [límites de adjuntos](https://resend.com/docs/dashboard/emails/attachments).

## Endpoints internos

Todos están limitados a administrador Pro del propio estacionamiento:

- `GET /api/pro/informes-correo`
- `POST /api/pro/informes-correo`
- `PATCH /api/pro/informes-correo/:id`
- `DELETE /api/pro/informes-correo/:id` (desactivación lógica)
- `POST /api/pro/informes-correo/:id/envio-prueba`
- `GET /api/pro/informes-correo/envios`
- `POST /api/pro/informes-correo/envios/:id/reintentar`

La pantalla **Informes por correo Pro** aparece sólo si el backend informa la
capacidad correspondiente. Las rutas siguen rechazando directamente una sesión
Lite aunque se intente llamar la API sin usar Flutter.

## Operación inicial en un VPS único

La primera versión está preparada para un único proceso Node detrás de Nginx.
No levantar dos procesos que apunten simultáneamente a la misma SQLite para
procesar correo. La migración futura a PostgreSQL deberá conservar la reserva
atómica de trabajos antes de escalar a varias réplicas.

Si se detecta un problema de entrega:

1. revisar el estado y el mensaje público en el panel Pro;
2. confirmar dominio/remitente y API key en el gestor de secretos, nunca en
   Flutter;
3. corregir la causa y usar **Reintentar** sólo sobre un envío fallido;
4. no cambiar manualmente estados en SQLite;
5. conservar los eventos para auditoría.
