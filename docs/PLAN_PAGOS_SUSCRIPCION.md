# Plan de pagos de suscripción de ParkControl

## Alcance

Esta pasarela cobrará la suscripción SaaS que cada estacionamiento paga a ParkControl. No corresponde al cobro que el estacionamiento realiza a los conductores.

La funcionalidad se incorporará dentro de los ajustes del administrador principal del estacionamiento con el nombre **Suscripción y método de pago**. Los demás cajeros y administradores no podrán cambiar el método de pago salvo autorización explícita del propietario de la cuenta.

La planificación se documenta ahora, pero su implementación se realizará únicamente cuando el responsable de ParkControl la autorice.

## Política comercial vigente

Los valores siguientes son mensuales, están expresados en pesos chilenos (CLP)
y corresponden a la suscripción de la plataforma ParkControl, no al cobro que
cobra el estacionamiento a sus propios conductores.

| Plan | Mensual estándar | Contrato de 6 meses | Contrato de 12 meses |
| --- | ---: | ---: | ---: |
| Lite | $69.990 | $59.990 mensuales | $49.990 mensuales |
| Pro | $119.990 | $109.990 mensuales | $99.990 mensuales |

Las condiciones de 6 y 12 meses son una oferta comercial destinada a los
primeros clientes durante el primer año comercial de ParkControl. Hasta que
exista el contrato definitivo, el SuperAdministrador aplicará la oferta y el
periodo contratado manualmente; una pasarela no debe inferir ni aplicar el
descuento por sí sola.

Totales de referencia del compromiso contratado:

| Plan | 6 meses | 12 meses |
| --- | ---: | ---: |
| Lite | $359.940 | $599.880 |
| Pro | $659.940 | $1.199.880 |

Antes de activar cobros automáticos se debe definir por escrito si estos valores
incluyen IVA, la fecha límite de la oferta, renovación posterior, salida
anticipada, reembolsos y cualquier ajuste de precio. No se modificarán pagos
históricos cuando esa decisión se formalice.

## Decisión de seguridad

ParkControl nunca almacenará:

- número completo de tarjeta;
- fecha de vencimiento completa;
- código CVV;
- PIN o claves bancarias.

El cliente será redirigido al formulario seguro de la pasarela. ParkControl guardará solamente identificadores externos, marca de tarjeta si el proveedor la entrega, últimos cuatro dígitos, estado de autorización y fechas de cobro.

El resultado visible en el navegador no confirmará por sí solo un pago. El backend verificará la notificación firmada de la pasarela y consultará el pago mediante su API antes de activar o extender una suscripción.

## Opciones evaluadas en Chile — 19 de agosto de 2026

### 1. Mercado Pago Suscripciones — recomendación inicial

Ventajas:

- disponible oficialmente en Chile;
- planes de suscripción sin programación para una prueba inicial;
- API para suscripciones integradas;
- cobros automáticos con frecuencia configurable;
- tarjetas de crédito y débito, además de medios de la cuenta Mercado Pago;
- reintentos automáticos cuando un cobro es rechazado;
- checkout alojado para no manejar tarjetas en ParkControl;
- sin costo fijo informado para Link de Pago; la comisión publicada es 3,19% + IVA con disponibilidad inmediata o 2,89% + IVA con disponibilidad en 10 días.

Consideraciones:

- la tarifa exacta de Suscripciones debe confirmarse dentro de la cuenta comercial antes de contratar;
- ParkControl dependerá de sus webhooks y estados externos;
- se debe validar en producción qué tarjetas de débito admiten recurrencia automática.

Fuentes oficiales:

- <https://www.mercadopago.cl/developers/es/docs/subscriptions/overview>
- <https://www.mercadopago.cl/developers/es/docs/subscription-plans/overview>
- <https://www.mercadopago.cl/herramientas-para-vender/link-de-pago>

### 2. Flow — alternativa chilena competitiva

Ventajas:

- empresa orientada al mercado chileno;
- suscripciones mediante panel o API REST;
- Cargo Automático para tarjetas inscritas;
- tarjetas de débito, crédito y prepago en su oferta general;
- desde 2,89% + IVA con abono al tercer día hábil y sin costo fijo;
- 3,19% + IVA para abono al día hábil siguiente;
- transferencias desde 0,99% + IVA más $100 CLP + IVA;
- sin inscripción ni mantención según su información pública.

Consideraciones:

- una suscripción sin Cargo Automático envía un enlace al cliente, pero no realiza necesariamente el débito automático;
- debe confirmarse con Flow qué tarjetas y marcas pueden utilizar Cargo Automático bajo el contrato de ParkControl;
- el servicio exige publicar precios y condiciones de la suscripción.

Fuentes oficiales:

- <https://web.flow.cl/es-cl/tarifas/>
- <https://www.flow.cl/oneclick.php>
- <https://web.flow.cl/es-cl/ayuda/>

### 3. Transbank Oneclick o PatPass — opción para una etapa de escala

Ventajas:

- proveedor ampliamente reconocido en Chile;
- sin mensualidad fija publicada para Oneclick y PatPass;
- cobro por transacción;
- Webpay publica para comercios nuevos 2,35% en crédito y 1,75% en débito/prepago, más IVA y sujeto a mínimos;
- inscripción de tarjeta realizada en infraestructura Transbank.

Consideraciones:

- PatPass y la documentación consultada para Oneclick se orientan principalmente a tarjetas de crédito;
- su contratación e integración pueden requerir más gestión comercial y técnica;
- las tarifas específicas del producto recurrente deben ser cotizadas y confirmadas antes de decidir.

Fuentes oficiales:

- <https://publico.transbank.cl/productos-y-servicios/soluciones-para-ventas-internet/webpay-patpass>
- <https://publico.transbank.cl/productos-y-servicios/soluciones-para-ventas-internet/webpay-oneclick>
- <https://ayuda.transbank.cl/tarifas-vender-webpay>

### Opción descartada inicialmente: Stripe

Chile no aparece actualmente en la lista oficial de países admitidos para crear una cuenta local de Stripe Payments. No se recomienda constituir una empresa extranjera únicamente para resolver el primer cobro de ParkControl.

Fuente oficial: <https://stripe.com/global>

## Recomendación

### Primera implementación

Usar **Mercado Pago Suscripciones con checkout alojado** como primera integración técnica debido a su flujo de suscripciones, reintentos automáticos, documentación y disponibilidad en Chile.

### Preparación ya implementada

- La configuración de Mercado Pago vive únicamente en variables del servidor: `PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN`, `PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET` y `PARKCONTROL_PUBLIC_URL`.
- Se añadieron tablas separadas para la suscripción, eventos recibidos y cobros de pasarela. Los pagos manuales existentes no se modifican ni se atribuyen falsamente a un usuario.
- El endpoint de webhook valida HMAC antes de aceptar un aviso, lo deduplica y guarda sólo una huella segura; no almacena el payload crudo, PAN, CVV ni token de tarjeta.
- Ningún webhook ni URL de retorno activa aún una cuenta. Falta consultar el recurso contra Mercado Pago y ejecutar la regla comercial de manera atómica.
- Mientras falten credenciales o la prueba controlada, la ruta de checkout responde un error explícito y la pantalla mantiene transferencia y efectivo.

Antes de contratar se solicitará una confirmación comercial escrita de:

1. comisión aplicable específicamente a Suscripciones;
2. tarjetas de débito admitidas para recurrencia;
3. plazo de abono;
4. política de contracargos y reembolsos;
5. límites por operación;
6. disponibilidad y retención de eventos webhook.

### Alternativa

Solicitar en paralelo una cotización de Flow. Si confirma Cargo Automático con los medios requeridos y una comisión total inferior, el diseño por adaptador permitirá seleccionarlo sin reescribir la lógica comercial.

No se integrarán dos pasarelas en el primer piloto. Se elegirá una y se mantendrán transferencia y efectivo como alternativas manuales.

## Pantalla del administrador principal

Ruta propuesta: **Ajustes → Suscripción y método de pago**.

Mostrará:

- plan actual;
- precio y frecuencia;
- estado de la suscripción;
- próxima fecha de cobro;
- método: automático, transferencia o efectivo;
- tarjeta enmascarada, por ejemplo `Visa terminada en 1234`;
- último pago y su estado;
- pagos pendientes o rechazados;
- botón **Agregar o cambiar tarjeta**;
- botón **Cancelar renovación automática**;
- instrucciones para transferencia;
- aviso de que el efectivo requiere confirmación manual de ParkControl;
- acceso al historial de pagos de la suscripción.

No se presentarán campos propios para escribir el número o CVV. El botón abrirá la página segura de la pasarela.

## Métodos de pago

### Tarjeta automática

- el cliente autoriza la recurrencia en la pasarela;
- la pasarela realiza el cobro en la fecha definida;
- el backend recibe y verifica el evento;
- un pago confirmado extiende el vencimiento y registra el comprobante;
- un rechazo inicia reintentos y periodo de gracia;
- ParkControl nunca recibe los datos sensibles de la tarjeta.

### Transferencia manual

- se mostrarán los datos bancarios y una referencia única del cliente;
- el cliente informará la transferencia;
- inicialmente el SuperAdministrador confirmará manualmente el abono;
- la confirmación extenderá el vencimiento usando el flujo actual de pagos manuales;
- un comprobante adjunto nunca será suficiente por sí solo para activar la cuenta.

### Efectivo

- quedará permitido solamente según el contrato comercial;
- el SuperAdministrador registrará la recepción;
- se guardarán fecha, monto, periodo, observación y responsable;
- no existirá activación automática por parte del administrador del cliente.

## Reglas de cobro propuestas

1. Cobro mensual en una fecha informada claramente.
2. Sin prorrateo en el primer piloto, salvo decisión comercial posterior.
3. Periodo de gracia propuesto de cinco días después del primer rechazo.
4. Reintentos administrados por la pasarela dentro de ese periodo.
5. Avisos de pago rechazado y próximo vencimiento por correo.
6. Suspensión únicamente después de agotar reintentos y periodo de gracia.
7. Un pago automático solo levantará una suspensión cuyo motivo sea falta de pago.
8. Una suspensión por seguridad, soporte o decisión manual nunca se levantará automáticamente.
9. Cancelar la renovación evita cobros futuros, pero mantiene el servicio hasta terminar el periodo ya pagado.
10. Cada evento será idempotente para impedir dos renovaciones por una notificación repetida.

## Arquitectura

Se creará una interfaz interna de proveedor de pagos para evitar acoplar el negocio a una marca:

- crear suscripción;
- abrir portal o checkout;
- consultar estado;
- cancelar renovación;
- verificar firma de webhook;
- consultar pago;
- solicitar reembolso cuando corresponda.

Tablas propuestas:

### `suscripciones_pago`

- `estacionamiento_id`;
- proveedor;
- identificador externo de suscripción;
- estado;
- renovación automática;
- marca y últimos cuatro dígitos si están disponibles;
- próxima fecha de cobro;
- fechas de creación y actualización.

### `eventos_pasarela`

- proveedor;
- identificador único del evento;
- tipo;
- fecha recibida;
- estado de verificación y procesamiento;
- error público seguro;
- referencia al pago resultante.

La tabla existente `pagos_suscripcion` se ampliará mediante migración compatible para guardar proveedor, identificador externo, comisión, monto neto y origen automático/manual. No se borrarán pagos anteriores.

## Fases de desarrollo

### Fase 1 — Contrato comercial

Definir precios Lite/Pro, fecha de cobro, autorización de recurrencia, periodo de gracia, cancelación, reembolsos, transferencia, efectivo, mora, suspensión y tratamiento de contracargos.

### Fase 2 — Prueba sin código y selección

1. Crear cuentas comerciales de prueba en Mercado Pago y Flow.
2. Confirmar tarifas y medios recurrentes por escrito.
3. Ejecutar una suscripción real de monto mínimo y un reembolso.
4. Elegir un único proveedor para el piloto.

### Fase 3 — Modelo y backend

1. Agregar migraciones compatibles.
2. Crear adaptador del proveedor.
3. Crear endpoints protegidos para administrar la suscripción.
4. Implementar webhook con verificación de firma y consulta posterior.
5. Aplicar idempotencia y auditoría.
6. Conectar pago confirmado con vencimiento, activación y plan.

### Fase 4 — Ajustes del administrador

1. Crear la pantalla **Suscripción y método de pago**.
2. Restringirla al administrador principal.
3. Abrir checkout alojado.
4. Mostrar tarjeta enmascarada y estados.
5. Incorporar transferencia y efectivo como opciones manuales.

### Fase 5 — Recuperación de cobros

1. Avisar antes del vencimiento.
2. Mostrar rechazo sin revelar información bancaria.
3. Aplicar periodo de gracia.
4. Suspender después del fallo definitivo.
5. Reactivar solamente por pago confirmado y causa compatible.

### Fase 6 — Pruebas

Casos obligatorios:

- evento webhook repetido;
- redirección falsa sin pago real;
- cobro aprobado, pendiente y rechazado;
- tarjeta reemplazada o vencida;
- cancelación;
- contracargo y reembolso;
- cambio Lite ↔ Pro;
- pago manual simultáneo con intento automático;
- cliente suspendido por seguridad;
- aislamiento entre estacionamientos;
- caída del servidor durante el webhook.

## Estimación

| Bloque | Horas |
| --- | ---: |
| Contrato, cotización y prueba de proveedor | 8–14 |
| Modelo, migraciones y adaptador | 18–28 |
| Webhooks, idempotencia y reglas comerciales | 18–28 |
| Pantalla de ajustes y checkout | 12–20 |
| Avisos, gracia y suspensión | 10–16 |
| Pruebas y piloto | 16–24 |
| **Total estimado** | **82–130** |

La estimación no incluye certificación tributaria, emisión de boleta electrónica ni desarrollo de una bóveda propia de tarjetas.

## Criterio de terminado

La pasarela estará terminada cuando:

1. ParkControl no manipule datos sensibles de tarjetas;
2. el backend verifique cada pago con el proveedor;
3. las notificaciones repetidas no dupliquen periodos ni ingresos;
4. un pago rechazado respete reintentos y gracia;
5. transferencia y efectivo mantengan confirmación manual;
6. las suspensiones de seguridad no se reactiven por error;
7. todos los cambios queden auditados;
8. exista una prueba controlada de cobro, cancelación y reembolso.
