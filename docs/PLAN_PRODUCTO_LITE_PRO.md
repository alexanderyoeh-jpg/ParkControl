# Plan de desarrollo de planes Lite y Pro

## Objetivo

Aplicar una separación comercial clara entre Lite y Pro sin debilitar la seguridad, romper la operación actual ni confiar en botones ocultos de Flutter. El backend seguirá siendo la fuente de verdad para roles, límites de usuarios y funciones disponibles.

La implementación ya comenzó de forma controlada. Las capacidades existentes y las cuotas de usuarios se validan en el backend; las funciones Pro aún no construidas continúan planificadas en sus fases correspondientes.

La automatización de la suscripción de ParkControl, junto con transferencia y efectivo, se especifica por separado en `docs/PLAN_PAGOS_SUSCRIPCION.md`.

## Decisiones de producto

### Cajero

El cajero es un trabajador operativo. No tendrá ajustes de perfil, temas visuales, configuración de cuenta, tarifas, usuarios, suscripción, contabilidad ni herramientas globales.

Podrá:

- registrar entradas y salidas;
- consultar vehículos dentro;
- corregir datos de un vehículo activo;
- consultar el historial operativo permitido por su plan;
- ver conteos diarios de entradas, salidas y vehículos dentro;
- cerrar sesión.

Las correcciones permanecerán auditadas. El cajero no podrá alterar cobros cerrados ni eliminar silenciosamente movimientos históricos.

### Administrador del estacionamiento

El administrador controla únicamente su establecimiento. Podrá gestionar usuarios dentro del límite del plan, restablecer sus contraseñas, configurar la tarifa y consultar la información administrativa habilitada.

No podrá cambiar el plan, vencimiento, suscripción, límites ni estado comercial. Esas acciones pertenecen al SuperAdministrador.

### SuperAdministrador

Mantendrá el control de clientes, planes, pagos manuales, vencimientos, activación y suspensión. Un cambio de plan surtirá efecto en el backend, no solamente en la interfaz.

## Matriz funcional

| Función | Lite | Pro |
| --- | --- | --- |
| Administradores activos | 1 | Hasta 2 |
| Cajeros activos | 1 | Hasta 3 |
| Entrada, salida y vehículo dentro | Sí | Sí |
| Corrección de vehículo activo | Sí, auditada | Sí, auditada |
| Conteo operativo diario | Sí | Sí |
| Historial de vehículos | Sí | Sí |
| Reporte diario en pantalla | Sí | Sí |
| Auditoría básica | Sí | Sí |
| Tarifa del estacionamiento | Sí | Sí |
| Comprobante PDF ParkControl | No | Sí |
| Historial descargable de comprobantes | No | Sí |
| Contabilidad avanzada | No | Sí |
| Gráficos comparativos | No | Sí |
| Exportación PDF, Excel y CSV | No | Sí |
| Informes por correo | No | Sí |
| Informes programados | No | Sí |
| Cierre de caja y conciliación | No | Sí |
| Alertas administrativas avanzadas | No | Sí |

La auditoría básica no se considera una función prémium: es un control de seguridad necesario para ambos planes.

## Definición contable y documental

### Comprobante ParkControl

El PDF actual se presentará como **Comprobante de estacionamiento ParkControl** o **Comprobante no tributario**. No se anunciará como boleta electrónica válida ante el SII mientras no exista una integración certificada.

Las rutas actuales pueden conservarse temporalmente por compatibilidad, aunque el texto visible y los documentos deben indicar claramente su naturaleza.

### Información de IVA

La primera versión Pro mostrará:

- ingreso bruto;
- venta neta estimada;
- IVA débito estimado;
- periodo y datos utilizados;
- advertencia de que no sustituye al contador ni determina el impuesto final.

No se usará el texto “impuesto exacto a pagar”. El impuesto final puede depender de crédito fiscal, compras y situación tributaria del cliente.

## Fases de implementación

### Fase 0 — Congelar contrato y pruebas actuales

**Objetivo:** conservar la línea base antes de bloquear funciones.

1. Registrar pruebas de cajero, administrador y SuperAdministrador.
2. Confirmar entradas, salidas, modificación, historial, tarifa, contabilidad, comprobantes y auditoría.
3. Añadir casos Lite y Pro a la prueba multi-estacionamiento.
4. Confirmar que `parkcontrol.db` no se usa en las pruebas y nunca se recrea.

**Criterio de término:** las funciones actuales pasan antes de aplicar restricciones.

### Fase 1 — Capacidades y límites en el backend

**Objetivo:** hacer que Node.js decida lo permitido por cada plan.

1. Definir un catálogo central de capacidades, evitando comprobaciones dispersas de `plan == PRO`.
2. Incorporar capacidades mínimas como:
   - `operacion_basica`;
   - `historial_vehiculos`;
   - `reporte_diario`;
   - `comprobante_pdf`;
   - `contabilidad_avanzada`;
   - `analitica_avanzada`;
   - `exportaciones`;
   - `informes_email`;
   - `cierre_caja`.
3. Crear validadores de capacidad y cuota para las rutas protegidas.
4. Validar en el backend el máximo de administradores y cajeros activos.
5. Entregar al iniciar sesión las capacidades efectivas para que Flutter construya su navegación.
6. Registrar en auditoría cambios de plan y rechazos por límite.

**Implementado:** una función no incluida devuelve `403` con `FUNCION_NO_DISPONIBLE_PLAN`; una cuota superada devuelve `409` con `LIMITE_USUARIOS_PLAN`.

**Criterio de término:** llamar directamente a una ruta Pro con una sesión Lite debe ser rechazado por el servidor.

### Fase 2 — Cambios de plan y exceso de usuarios

**Objetivo:** permitir Lite ↔ Pro sin pérdida de información.

1. Subir de Lite a Pro habilitará funciones inmediatamente.
2. Bajar de Pro a Lite nunca borrará usuarios, movimientos ni documentos.
3. Si existen más usuarios activos que el límite Lite, el cambio se rechaza con el detalle de los límites y usuarios activos.
4. La reducción se realiza previamente y de forma explícita por el administrador autorizado; ParkControl no desactiva personas de forma automática.
5. Se conserva al menos un administrador activo.

**Criterio de término:** el cambio es reversible y no elimina físicamente información.

### Fase 3 — Simplificación de dashboards

**Objetivo:** que cada rol vea solamente herramientas pertinentes.

#### Dashboard del cajero

1. Retirar ajustes de perfil, temas, diseño y administración de cuenta.
2. Retirar acceso a usuarios, tarifa, contabilidad y configuración.
3. Mostrar operación, conteo diario, vehículos dentro, historial permitido y cierre de sesión.
4. En Lite no mostrar comprobantes ni exportaciones.

#### Dashboard del administrador

1. Mantener usuarios, tarifa y datos administrativos del local.
2. Construir accesos según las capacidades recibidas del backend.
3. Lite mostrará resumen y reporte diario en pantalla.
4. Pro mostrará contabilidad, comprobantes, exportaciones, gráficos, correo y cierre de caja.

**Criterio de término:** no quedan botones sin permiso, pero la seguridad continúa funcionando aunque alguien intente llamar manualmente a la API.

### Fase 4 — Contabilidad y analítica Pro

**Objetivo:** entregar información útil para dirigir el estacionamiento.

1. Definir periodos diarios, semanales, mensuales, semestrales y anuales usando la zona horaria del cliente.
2. Calcular ingresos brutos, neto estimado e IVA débito estimado.
3. Agregar gráficos de ingresos, cantidad de vehículos, ocupación, permanencia promedio y rotación.
4. Incorporar comparación contra el periodo anterior.
5. Crear análisis de días y horarios fuertes o lentos.
6. Validar que todos los cálculos estén aislados por `estacionamiento_id`.

**Implementado adicionalmente:** el administrador Pro dispone de una
comparativa de demanda de 30, 90 o 365 días. El backend agrupa entradas y
salidas persistidas por día de la semana y hora local, usando exclusivamente
la zona horaria IANA del estacionamiento. Los tramos sin actividad no se
presentan como fuertes ni lentos, y cada consulta permanece filtrada por
`estacionamiento_id`.

**Criterio de término:** los totales de cada gráfico coinciden con consultas de control y con la contabilidad del mismo periodo.

### Fase 5 — Cierre de caja y turnos Pro

**Objetivo:** detectar descuadres y responsabilizar cada turno.

1. Crear apertura de turno con cajero, fecha y efectivo inicial.
2. Asociar cobros y formas de pago al turno.
3. Calcular efectivo, transferencia, tarjeta y total esperado.
4. Registrar monto declarado por el cajero y diferencia.
5. Mostrar vehículos que permanecen dentro al cierre.
6. Incluir modificaciones, anulaciones e incidencias del turno.
7. Permitir revisión y confirmación por un administrador.
8. Mantener el cierre inmutable; cualquier corrección posterior será un ajuste auditado.

**Implementado en la conciliación v2:** cada salida Pro se vincula en la misma
transacción al único turno abierto del cajero. No se permiten cobros sin turno,
por un administrador ni sobre un turno ajeno o cerrado. Las salidas offline Pro
v1 se dejan en conflicto administrativo para no asignarlas de manera ambigua a
un turno posterior; una futura versión podrá habilitarlas mediante un protocolo
de sincronización con lease verificable. Las horas que informa el dispositivo
se conservan sólo para trazabilidad: los montos, reportes y cierres usan la
hora oficial recibida por el servidor.

**Criterio de término:** cada cobro pertenece como máximo a un turno y un cierre nunca puede cambiarse silenciosamente.

### Fase 6 — Comprobantes, exportaciones y correo Pro

**Objetivo:** entregar información descargable sin bloquear la operación.

1. Renombrar visualmente los PDFs como comprobantes no tributarios.
2. Habilitar historial y descarga solo para Pro.
3. Exportar reportes a PDF, Excel y CSV desde datos generados por el backend.
4. Configurar un correo administrativo verificado por estacionamiento.
5. Crear una cola de envío en el servidor con reintentos y registro de resultado.
6. Permitir informes diarios, semanales o mensuales programados.
7. Evitar que Flutter almacene claves del proveedor de correo.

**Criterio de término:** una falla de correo no interrumpe entradas ni salidas, y queda visible para reintento.

**Implementado internamente:** la programación Pro, la cola persistente,
reservas recuperables, reintentos, trazabilidad y los adjuntos PDF/CSV se
generan en el backend y quedan aislados por `estacionamiento_id`. El
destinatario se limita a una cuenta administradora activa y se enmascara en la
API. Falta la activación externa del remitente/dominio y API key del proveedor;
hasta entonces el sistema muestra el estado real `CORREO_NO_CONFIGURADO` y no
finge un envío. El contrato operativo está en
`docs/CONTRATO_INFORMES_CORREO_PRO.md`.

### Fase 7 — Alertas administrativas Pro

**Objetivo:** destacar excepciones importantes sin crear ruido.

**Estado actual (V1):** implementada la alerta de mayor señal: un cierre de
caja con diferencia distinta de cero. Se crea dentro de la misma transacción
del cierre, queda aislada por `estacionamiento_id`, exige administrador Pro y
no puede depender de que Flutter permanezca abierto. El centro de alertas
muestra el estado y la diferencia; la revisión del turno la actualiza junto
con una entrada de auditoría.

Estados disponibles:

- `pendiente`: el cierre con diferencia aún requiere revisión;
- `revisada`: un administrador registró una observación;
- `resuelta`: un administrador confirmó el cierre como revisado.

Pendiente para una fase posterior, con reglas explícitas para no generar
ruido:

- modificación o eliminación lógica;
- vehículo abierto por un tiempo configurable;
- intento de acceso rechazado;
- operación pendiente o en conflicto de sincronización.

Las alertas conservan responsable, fecha y comentario de revisión. No se
eliminan al resolverlas.

### Fase 8 — Pruebas de aceptación

1. Probar Lite con un administrador y un cajero.
2. Verificar rechazo del segundo usuario por cada rol.
3. Probar Pro con dos administradores y tres cajeros.
4. Cambiar Pro → Lite y confirmar el tratamiento de usuarios excedentes.
5. Intentar rutas Pro usando una cuenta Lite directamente contra la API.
6. Comparar gráficos, exportaciones y cierres contra movimientos conocidos.
7. Validar funcionamiento en Windows y web.
8. Ejecutar un turno real controlado antes de anunciar las funciones.

## Orden recomendado desde el 25 de agosto

1. Fases 0 y 1: contrato y seguridad del plan.
2. Fase 2: cambio de plan y cuotas.
3. Fase 3: dashboards por rol y plan.
4. Fase 4: contabilidad y gráficos.
5. Fase 5: cierre de caja.
6. Fase 6: comprobantes, exportaciones y correo.
7. Fase 7: alertas.
8. Fase 8: aceptación y correcciones.

No se empezará por ocultar botones. Primero se protegerán capacidades y límites en el backend; después se adaptará Flutter al contrato validado.

## Estimación

Estimación inicial para este alcance, sin incluir la migración a PostgreSQL ni el despliegue definitivo:

| Bloque | Horas estimadas |
| --- | ---: |
| Contrato, capacidades y cuotas | 18–28 |
| Dashboards Lite/Pro | 16–24 |
| Contabilidad y analítica | 28–42 |
| Cierre de caja y turnos | 24–36 |
| Exportaciones y correo | 20–32 |
| Alertas y pruebas finales | 20–30 |
| **Total** | **126–192** |

Las correcciones visuales adicionales o una integración tributaria real aumentarían el plazo. La integración certificada con el SII no forma parte de este bloque.

## Fuera de alcance de esta etapa

- emisión certificada de boleta electrónica ante el SII;
- cálculo definitivo del impuesto a pagar;
- la pasarela de pagos, que se ejecutará como el bloque separado definido en `docs/PLAN_PAGOS_SUSCRIPCION.md`;
- contabilidad completa que sustituya al contador;
- migración inmediata de SQLite a PostgreSQL.

## Definición de terminado

Este bloque se considerará terminado cuando:

1. los permisos y cuotas se validen en el backend;
2. Lite y Pro muestren únicamente sus funciones;
3. no exista pérdida de datos al cambiar de plan;
4. todas las pruebas automáticas pasen;
5. `parkcontrol.db` permanezca conservada;
6. un turno piloto complete apertura, operación, cierre y reporte;
7. el responsable de ParkControl apruebe los dashboards resultantes.
