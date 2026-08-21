# Roadmap de ejecucion desde el 25 de agosto de 2026

## Objetivo

Este roadmap ordena las tareas que quedaron planificadas antes de seguir programando. La idea es retomar el desarrollo con una ruta clara, sin mezclar cambios de operacion, planes comerciales, dashboards y pagos en una misma tanda.

## Regla principal

Primero se protege el backend, despues se ajusta Flutter.

Ocultar botones ayuda a que la aplicacion sea mas clara, pero no es seguridad. Cada permiso, limite y funcion por plan debe estar validado en Node.js antes de mostrarse o retirarse en los dashboards.

## Orden de ejecucion

### Bloque 1 - Cerrar modo offline operativo

**Estado actual:** base local, cola, cache, sincronizador, coordinador, materializacion local, conexion inicial con pantallas de entrada/salida/modificacion, indicador de sincronizacion en dashboards, detalle de operaciones offline, descarte auditado de conflictos, comprobante local de salida offline confirmada, prueba automatizada de reinicio y prueba automatizada de turno offline ya existen. La cola ya se aísla por estacionamiento y cajero, la entrada confirmada se enlaza con su proyección local para no duplicarse y los snapshots no revierten cambios pendientes.

**Pendiente:**

1. Probar en dispositivo real reinicio, entrada y modificación sin Internet.
2. Diseñar un lease verificable para salidas Pro offline antes de habilitarlas.

**Regla vigente:** las salidas Pro requieren conexión. No se encolan ni se
asignan al turno siguiente de forma ambigua; una cola heredada queda en
conflicto para revisión administrativa. Las entradas se pueden conservar
localmente y reciben hora oficial al sincronizar.

**Criterio de termino:** la operación offline habilitada conserva orden e
idempotencia sin duplicar movimientos. Un futuro turno Pro offline sólo se
habilita con un contrato de lease validado por backend.

**No hacer en este bloque:** redisenar dashboards, cambiar planes Lite/Pro o integrar pagos.

### Bloque 2 - Capacidades Lite/Pro en backend

**Estado actual:** implementado para las capacidades que ya existen en el producto.

1. Catálogo central en backend: Lite (1 administrador, 1 cajero) y Pro (2 administradores, 3 cajeros).
2. Cuotas validadas al crear usuarios, cambiar su rol y agregar administradores desde SuperAdmin.
3. Boletas PDF y contabilidad avanzada protegidas por rol administrador y capacidad Pro.
4. Las capacidades se entregan al iniciar sesión y en `GET /api/cuenta/capacidades`, para reflejar cambios de plan sin reiniciar sesión.
5. Las pruebas de integración verifican el rechazo directo de Lite y los máximos de Lite/Pro.

**También implementado posteriormente:** rutas de gráficos y cierre de caja Pro protegidas por capacidad en el backend.

**Criterio de termino:** Lite y Pro quedan definidos por reglas del servidor, no por botones de Flutter.

### Bloque 3 - Ajustar dashboards por rol y plan

**Estado actual:** avanzado. El cajero ya no ve perfil, ajustes, facturación ni PDF; conserva operación, conteos diarios, historial, vehículos, reporte diario y cierre de sesión. El administrador consulta las capacidades al cargar su tablero y sólo ve boletas y contabilidad cuando tiene Pro.

**Cajero:**

1. Retirar ajustes de perfil, diseno, cuenta y configuracion.
2. Mantener entradas, salidas, modificacion, vehiculos dentro, historial permitido, reporte diario y cierre de sesion.
3. Mostrar solo conteos simples de operacion diaria.

**Administrador Lite:**

1. Mantener gestion basica del local.
2. Mantener usuarios dentro de cuota, tarifa, operacion, historial y reporte diario.
3. Retirar comprobantes PDF, exportaciones, contabilidad avanzada y graficos.

**Administrador Pro:**

1. Mantener todo lo operativo.
2. Agregar contabilidad avanzada, graficos, exportaciones, comprobantes, informes y cierre de caja.
3. Agregar acceso a suscripcion y metodo de pago cuando el bloque de pagos este listo.

**Criterio de termino:** cada usuario ve solo lo que le compete y los rechazos del backend se muestran con mensajes claros.

### Bloque 4 - Cierre de caja Pro

**Estado actual:** primera versión operativa implementada y cubierta por prueba de integración.

1. Un cajero Pro abre una caja con fondo inicial y novedad de apertura.
2. Sólo puede existir una caja abierta por estacionamiento; así se preserva la entrega entre el cajero saliente y entrante.
3. Cada salida nueva conserva el usuario que la realizó y, en Pro, su medio de pago: efectivo, transferencia, tarjeta u otro. El monto esperado se calcula en el backend desde el efectivo real del turno, nunca desde Flutter; transferencia y tarjeta quedan separadas de la caja física.
4. El cierre guarda monto total, desglose por medio, efectivo esperado, declarado, diferencia y novedad para el relevo; es inmutable.
5. El siguiente cajero consulta el último cierre y su novedad antes de iniciar el turno.
6. Se fotografía la lista de vehículos que permanecían dentro al momento del cierre.
7. El administrador Pro ve turnos abiertos/cerrados, diferencias, medios de pago, vehículos abiertos y novedades; también un gráfico animado y métricas reales por cajero: cobros, recaudación, turnos, modificaciones y eliminaciones.
8. El administrador puede confirmar u observar cada cierre una sola vez. La revisión conserva responsable, fecha y comentario en la auditoría.
9. Cada cierre cerrado dispone de un PDF operativo descargable con desglose de medios, conciliación, revisión y vehículos que permanecían dentro.

**También implementado posteriormente:** Alertas administrativas Pro V1.
Un cierre con diferencia crea una alerta persistente y aislada por
estacionamiento; un administrador Pro puede verla en el centro de alertas y
la revisión del turno la deja revisada o resuelta con trazabilidad en auditoría.

**Integridad v2 incorporada:** los cobros Pro se enlazan en la transacción de
salida al único turno abierto del cajero. El backend rechaza salidas sin turno,
desde administrador, sobre turno ajeno o tras el cierre; el cierre totaliza
sólo esos vínculos inmutables. Las horas del dispositivo se conservan como
trazabilidad y no pueden retroceder ingresos, reportes o caja.

**Criterio de termino:** cada turno deja una foto auditada de dinero esperado, dinero declarado y diferencias.

### Bloque 5 - Contabilidad, graficos y reportes Pro

**Estado actual:** informes contables y analítica operativa implementados.

1. Totales diarios, semanales, mensuales, semestrales y anuales desde movimientos y auditoría reales.
2. Venta bruta, neto estimado e IVA débito estimado al 19% incluido, claramente marcado como referencial.
3. Gráfico animado que recorre sólo los puntos disponibles hasta la fecha u hora actual.
4. Indicadores de entradas, salidas, modificaciones y eliminaciones lógicas.
5. El Excel incluye el detalle de cobros, medio de pago y hojas consolidadas por día, semana, mes, semestre y año.
6. El administrador Pro puede generar y compartir un PDF contable profesional para el período filtrado.
7. La comparativa de demanda de 30, 90 o 365 días identifica días y horas
   con mayor o menor actividad registrada, sin inventar tramos sin datos.
   Los grupos se calculan en backend con la zona horaria del estacionamiento
   y se muestran mediante mini-gráficos animados en el dashboard Pro.

**Implementado adicionalmente:** informes programados Pro con PDF resumen y
CSV de detalle generados por el backend, cola persistente, reintentos y
trazabilidad aislada por estacionamiento. El destinatario se restringe al
correo de una cuenta administradora activa; no se aceptan correos arbitrarios
desde Flutter.

**Pendiente externo:** activar un dominio/remitente verificado y API key de
Resend en el gestor de secretos del VPS, luego ejecutar el envío controlado
indicado en `docs/CONTRATO_INFORMES_CORREO_PRO.md`. Hasta entonces la pantalla
permite preparar programaciones, pero no simula correos enviados.

**Criterio de termino:** los totales mostrados coinciden con consultas de control del backend.

### Bloque 6 - Suscripcion y metodo de pago

**Estado actual:** Mercado Pago es el proveedor elegido. La pantalla muestra el estado separado de la renovación automática y del último pago manual; no guarda números de tarjeta ni CVV. El backend ya tiene configuración por variables de entorno, tablas aisladas para suscripciones/eventos/cobros de pasarela y una bandeja webhook firmada e idempotente que aún no produce efectos comerciales.

**Pendiente:**

1. Definir contrato comercial: precio Lite/Pro, fecha de cobro, mora, gracia, cancelación, efectivo y transferencia.
2. Crear cuenta comercial de prueba, URL HTTPS pública y credenciales sandbox de Mercado Pago.
3. Implementar checkout alojado y consulta servidor-a-servidor del recurso notificado.
4. Procesar el webhook firmado: pago aprobado, pendiente, rechazado, reembolso y contracargo.
5. Integrar pagos manuales y automáticos sin duplicar períodos.
6. Conectar la pantalla de ajustes al checkout alojado, tarjeta enmascarada, transferencia y efectivo.

**Criterio de termino:** un pago automatico confirmado extiende la suscripcion, una notificacion repetida no duplica nada, y una suspension por seguridad no se reactiva por error.

### Bloque 7 - Alertas administrativas Pro

**Estado actual:** versión inicial implementada para cierres de caja con
diferencia. La alerta se guarda en backend, se crea de forma idempotente con
el cierre, se consulta sólo dentro del estacionamiento correspondiente y se
actualiza junto con la revisión administrativa del turno.

**Pendiente:** definir umbrales y responsables antes de alertar vehículos
abiertos, conflictos offline, modificaciones/eliminaciones e intentos de
acceso. Esos eventos no se convertirán en alertas automáticas hasta tener una
política que evite ruido operativo.

**Criterio de termino:** los administradores Pro reciben excepciones reales,
no simples eventos normales de operación, y toda alerta conserva su origen y
trazabilidad.

## Dependencias

| Tarea | Depende de |
| --- | --- |
| Dashboards Lite/Pro | Capacidades y cuotas en backend |
| Contabilidad avanzada | Separacion clara de funciones Pro |
| Cierre de caja | Operacion y cobros consistentes |
| Pagos automaticos | Reglas de suspension y vencimiento estables |
| Exportaciones Pro | Reportes correctos en backend |
| GitHub privado | Revision de secretos y version estable |

## Riesgos a vigilar

1. **Activar offline incompleto:** puede crear estados distintos entre app y servidor.
2. **Bloquear funciones solo en Flutter:** cualquier usuario podria llamar la API manualmente.
3. **Llamar boleta tributaria a un PDF interno:** puede generar un problema legal o comercial.
4. **Calcular impuesto exacto a pagar:** el IVA final depende tambien de credito fiscal y situacion tributaria.
5. **Guardar datos de tarjeta:** ParkControl no debe almacenar numero completo ni CVV.
6. **Cambiar Pro a Lite borrando datos:** debe desactivar accesos, no eliminar informacion historica.

## Pruebas minimas por bloque

### Offline

- entrada sin internet;
- salida sin internet;
- modificacion sin internet;
- eliminacion logica sin internet;
- reinicio con operaciones pendientes;
- conflicto por version;
- conflicto por tarifa;
- sincronizacion exitosa.

### Lite/Pro

- Lite no puede crear segundo cajero;
- Lite no puede crear segundo administrador;
- Lite no accede a comprobantes ni contabilidad avanzada;
- Pro permite hasta 3 cajeros y 2 administradores;
- downgrade Pro a Lite conserva datos y se rechaza mientras existan usuarios activos que excedan el límite destino; nunca se desactivan personas automáticamente.

### Pagos

- pago aprobado;
- pago rechazado;
- webhook repetido;
- transferencia manual;
- efectivo manual;
- cancelacion de renovacion;
- periodo de gracia;
- suspension por mora;
- reactivacion por pago confirmado.

## Checklist del dia de reinicio

1. Revisar que no haya cambios pendientes ajenos al bloque.
2. Confirmar respaldo local de `backend/parkcontrol.db`.
3. Ejecutar pruebas actuales antes de tocar codigo.
4. Empezar por el Bloque 1: modo offline operativo.
5. Al terminar cada bloque, ejecutar pruebas y actualizar documentos.
6. No subir a GitHub hasta llegar a una version estable cercana al 90%.

## Documentos relacionados

- `docs/CONTRATO_SINCRONIZACION_OFFLINE.md`
- `docs/PLAN_PRODUCTO_LITE_PRO.md`
- `docs/PLAN_PAGOS_SUSCRIPCION.md`
- `docs/ARQUITECTURA_PRODUCCION.md`
- `docs/ARQUITECTURA_SUPERADMIN.md`
