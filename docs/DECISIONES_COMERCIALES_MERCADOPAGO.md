# Decisiones necesarias antes de activar Mercado Pago

## Por qué este documento existe

ParkControl ya tiene una base segura para pasarela: credenciales sólo en el
backend, tabla separada de suscripciones, bandeja de webhook firmada e
idempotente, y pantalla que no pide ni almacena tarjeta o CVV. Pero no es
seguro inventar precio, periodo de gracia o reglas de reactivación: esas reglas
afectan directamente la suspensión de los estacionamientos.

La activación real queda bloqueada hasta completar las decisiones de este
documento y realizar una prueba sandbox controlada.

## Decisiones comerciales del propietario

Completar y aprobar por escrito:

| Decisión | Lite | Pro | Decisión final |
| --- | ---: | ---: | --- |
| Precio mensual estándar en CLP | $69.990 | $119.990 | Aprobado por propietario |
| Oferta contrato 6 meses, mensual | $59.990 | $109.990 | Primer año comercial y primeros clientes |
| Oferta contrato 12 meses, mensual | $49.990 | $99.990 | Primer año comercial y primeros clientes |
| Precio incluye IVA | Neto + IVA | Neto + IVA | Requiere emisión de factura mensual SaaS |
| Día de cobro mensual | Día aniversario de registro | Día aniversario de registro | Frecuencia mensual automática en pasarela |
| Días de gracia tras rechazo | 3 días | 3 días | Con avisos diarios en dashboard al administrador |
| Fecha desde la que se suspende | Día 4 tras vencimiento sin regularizar | Día 4 tras vencimiento sin regularizar | Suspensión automática controlada por backend |
| Reglas de descuento/anualidad | 6 meses: $359.940 total; 12 meses: $599.880 total | 6 meses: $659.940 total; 12 meses: $1.199.880 total | Opciones para contratos semestrales/anuales |
| Reembolso y contracargo | Gestión manual por SuperAdmin | Gestión manual por SuperAdmin | Suspende cuenta si hay contracargo no aclarado |
| Medio manual alternativo | Transferencia / Efectivo | Transferencia / Efectivo | Activación exclusiva por SuperAdministrador |

La oferta se registra como política comercial inicial para los primeros clientes
del primer año de ParkControl. Al crear planes en Mercado Pago se deben crear
identificadores distintos por combinación de plan y duración o, si la pasarela
no representa el compromiso completo, usar cobro manual autorizado. Nunca se
debe cambiar el importe de una suscripción ya autorizada sin la aceptación del
cliente.

Reglas que deben mantenerse incluso después de decidir lo anterior:

1. transferencia y efectivo sólo activan un cliente cuando el
   SuperAdministrador confirma el abono;
2. una suspensión por seguridad o soporte nunca se reactiva automáticamente;
3. un webhook, una URL de retorno o una captura de checkout no son prueba
   suficiente de pago; el backend consulta el recurso de Mercado Pago;
4. un evento repetido no puede extender dos veces el mismo periodo;
5. tarjetas, CVV, PAN y claves bancarias nunca pasan por Flutter ni SQLite.

## Configuración externa requerida

1. Crear la cuenta comercial de ParkControl en Mercado Pago Chile.
2. Crear credenciales de prueba y una aplicación de integración.
3. Publicar la API bajo HTTPS en un VPS, usando el despliegue de
   `docs/DESPLIEGUE_VPS.md`.
4. Crear dos planes de suscripción de prueba (Lite y Pro) en CLP, con importe,
   frecuencia mensual y URL de retorno aprobados. Mercado Pago expone
   `POST /preapproval_plan` para planes y `POST /preapproval` para asociar una
   suscripción a un cliente.
5. Configurar las notificaciones de suscripción y pagos que correspondan al
   flujo elegido. Para suscripciones sin plan asociado, Mercado Pago indica
   los tópicos `subscription_preapproval`,
   `subscription_authorized_payment` y `payments`; conservar la firma secreta
   sólo en el gestor de secretos.
6. Guardar exclusivamente en el VPS:

```ini
PARKCONTROL_PUBLIC_URL=https://api.tu-dominio.cl
PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN=TEST_O_PRODUCCION_SOLO_EN_SERVIDOR
PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET=SECRETO_DE_FIRMA
```

No configurar credenciales de producción hasta que el flujo de prueba haya
terminado completo.

## Prueba sandbox obligatoria

El piloto debe demostrar, en este orden:

1. apertura del checkout alojado desde el administrador de un estacionamiento
   de prueba;
2. autorización de una tarjeta de prueba sin que ParkControl reciba sus datos;
3. retorno al sitio sin cambiar por sí solo el estado comercial;
4. webhook firmado recibido y deduplicado;
5. consulta servidor-a-servidor del recurso de Mercado Pago;
6. un pago aprobado que extienda exactamente un periodo;
7. repetición del mismo webhook sin duplicar pago ni vencimiento;
8. pago rechazado, reintentos y periodo de gracia según la política aprobada;
9. cancelación, reembolso y contracargo sin reactivar una cuenta por error;
10. pago manual simultáneo y cambio Lite/Pro sin duplicar periodos.

El simulador de notificaciones de Mercado Pago puede ayudar a ensayar la
recepción, pero no reemplaza una prueba completa con las credenciales sandbox.

## Fuentes oficiales consultadas

- [Resumen de la API de Suscripciones](https://www.mercadopago.cl/developers/es/reference/online-payments/subscriptions/overview)
- [Crear plan de suscripción](https://www.mercadopago.cl/developers/es/reference/online-payments/subscriptions/create-preapproval-plan/post)
- [Crear suscripción](https://www.mercadopago.cl/developers/es/reference/online-payments/subscriptions/create-preapproval/post)
- [Obtener suscripción desde el backend](https://www.mercadopago.cl/developers/es/reference/online-payments/subscriptions/get-preapproval/get)
- [Webhooks y validación de firma](https://www.mercadopago.cl/developers/es/docs/your-integrations/notifications/webhooks)
- [Tópicos para Suscripciones](https://www.mercadopago.cl/developers/es/docs/your-integrations/notifications/additional-info)

## Siguiente cambio de código autorizado

Cuando estén aprobados los precios y existan credenciales sandbox, el siguiente
bloque será conectar el checkout alojado a los identificadores de plan creados
en Mercado Pago y procesar cada pago validado en una transacción backend. No se
habilitará una tarjeta ni una renovación automática antes de esa prueba.
