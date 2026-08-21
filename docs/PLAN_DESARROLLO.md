# Plan de desarrollo de ParkControl

## Propósito

Convertir ParkControl en una plataforma SaaS para la gestión de estacionamientos.

Cada estacionamiento tendrá datos aislados, su propio administrador y cajeros. La operación diaria debe cubrir el ciclo completo: entrada, estadía, salida, cobro, boleta, historial y reportes. ParkControl tendrá un SuperAdmin que podrá administrar clientes y el estado de sus suscripciones.

## Principios de trabajo

1. **La operación no se rompe.** Entradas, salidas, vehículos dentro, historial, boletas PDF, contabilidad, usuarios, tarifa, modificar y auditoría se conservan durante toda la evolución.
2. **Cambios pequeños y comprobables.** Cada bloque se prueba antes de iniciar el siguiente.
3. **Primero el núcleo.** No se agregan funciones comerciales si existen problemas críticos en autenticación, API, datos o cálculo de cobros.
4. **Datos protegidos.** La base `backend/parkcontrol.db` nunca se borra ni se recrea. Toda transición de esquema será mediante migraciones compatibles y respaldos verificados.
5. **Estados de movimientos.** Los únicos estados operativos actuales son `dentro`, `salio` y `eliminado`. Eliminar un movimiento siempre significa marcarlo como `eliminado`, nunca borrarlo físicamente.

## Punto de partida confirmado

### Ya disponible

- Aplicación Flutter con pantallas para administrador y cajero.
- API Node.js/Express con SQLite y generación de boletas PDF.
- Registro de entradas y salidas, tarifas, vehículos dentro, historial, boletas, contabilidad, usuarios y auditoría.
- Persistencia existente en `backend/parkcontrol.db`.

### Operación validada por ParkControl

El dashboard del cajero está confirmado como operativo en uso real. Registra entradas, salidas y modificaciones; emite boletas; muestra ingresos, salidas y vehículos dentro con datos reales; y el historial refleja las operaciones realizadas.

Estas funciones constituyen una línea base protegida: cualquier cambio posterior debe conservarlas y comprobar que siguen funcionando.

### Seguridad implementada — 18 de agosto de 2026

- Las contraseñas se almacenan con un hash seguro basado en `scrypt`.
- Al iniciar el servidor se protegen automáticamente las contraseñas antiguas sin borrar usuarios ni cambiar sus credenciales.
- El login entrega una sesión firmada que vence en 12 horas.
- Todas las rutas de `/api`, salvo el login, requieren una sesión válida.
- El servidor aplica los permisos actuales: solo un administrador modifica tarifas o usuarios; las entradas y salidas requieren el permiso correspondiente; la contabilidad requiere permiso de reportes.
- Las modificaciones y eliminaciones lógicas se registran en auditoría con el usuario autenticado por el servidor, no con datos enviados por la pantalla.
- Cerrar sesión invalida el token en el servidor y lo elimina del dispositivo.
- Las boletas PDF se abren con una URL temporal vinculada a la sesión actual.
- El servidor oculta su tecnología, agrega encabezados defensivos, limita el tamaño de las solicitudes JSON y no expone detalles internos de los errores.
- Los intentos fallidos de inicio de sesión se limitan por dirección y correo. El límite predeterminado es de 5 intentos durante 15 minutos.
- En producción, los orígenes web deben declararse expresamente mediante `PARKCONTROL_ALLOWED_ORIGINS`; Flutter móvil y las comunicaciones servidor-a-servidor continúan funcionando sin encabezado `Origin`.
- El arranque en modo producción exige `PARKCONTROL_AUTH_SECRET` con al menos 32 caracteres.

La migración compatible agrega `usuarios.sesionVersion` y la tabla `seguridad_configuracion`. No elimina, recrea ni modifica los movimientos existentes de `backend/parkcontrol.db`.

**Pendiente para una etapa posterior:** recuperación de contraseña por correo, almacenamiento seguro específico de cada dispositivo, HTTPS y monitoreo. Los roles SuperAdmin y el aislamiento multi-estacionamiento ya están incorporados en el backend local.

### Panel del administrador del estacionamiento — 18 de agosto de 2026

- El dashboard muestra recaudación, entradas, salidas y vehículos dentro desde el resumen real de la API.
- Incluye actividad reciente y accesos a vehículos dentro, historial, boletas, contabilidad y corrección de operaciones.
- Los accesos de administración incluyen usuarios, tarifas, reportes y auditoría.
- La pantalla de tarifas ahora consulta y actualiza la tarifa real del servidor; ya no guarda un valor aislado en el dispositivo.
- La auditoría tiene una pantalla propia con filtros para modificaciones y eliminaciones lógicas.
- Los botones de navegación y de cierre de sesión tienen acciones reales; no se mantienen opciones de configuración o alertas sin implementar.

### SuperAdministrador y multi-estacionamiento — 18 de agosto de 2026

- Existe una cuenta propietaria única, creada con un código de configuración de un solo uso y sin credenciales comerciales predeterminadas.
- El panel global crea y edita clientes, asigna planes Lite o Pro, administra sus vencimientos y permite suspender o reactivar el servicio.
- Los pagos del piloto se registran manualmente como transferencia o efectivo. Una anulación conserva el pago para auditoría y deja de sumarlo en los ingresos.
- Usuarios, tarifas, fichas de vehículos, movimientos, historial, boletas, contabilidad y auditoría están segmentados por estacionamiento.
- Las sesiones de un cliente suspendido quedan bloqueadas de inmediato y sus datos permanecen guardados.
- Se agregó una prueba automática del servidor que valida configuración inicial, aislamiento, permisos, pagos, suspensión, boletas cruzadas y eliminación lógica.
- Entradas, salidas, modificaciones y eliminaciones lógicas aceptan una clave idempotente persistente: un reintento por pérdida de conexión no duplica movimientos, cobros ni registros de auditoría, incluso después de reiniciar el servidor.
- Los movimientos tienen una versión compatible con instalaciones existentes. Las operaciones offline podrán detectar si otro equipo cambió el movimiento o la tarifa antes de confirmar una salida.
- La API ofrece un snapshot autenticado de tarifa y vehículos activos por estacionamiento; Flutter ya cuenta con caché local Drift, reconciliación aislada y migración desde la cola anterior sin pérdida.
- La arquitectura oficial y la regla para el futuro modo de soporte están documentadas en `docs/ARQUITECTURA_SUPERADMIN.md`.

### Antes de producción

- Configurar la URL centralizada de la API para el dominio definitivo y no para `localhost`.
- Migrar la fuente autoritativa desde SQLite local a PostgreSQL administrado.
- Configurar Nginx, HTTPS, los orígenes autorizados, secretos de producción y monitoreo.
- Implementar y probar respaldos automáticos y restauraciones.
- Diseñar el modo soporte temporal y auditado antes de permitir que el propietario entre a la operación de un cliente.
- Ejecutar las pruebas de aceptación desde Flutter en los dispositivos del primer piloto.
- Validar el modo offline en Windows y navegador con cache operativo, cola, conflictos y recuperación después de reinicios.

## Alcance del primer piloto

El piloto se considera listo cuando un estacionamiento real puede operar un turno completo:

1. Un cajero autorizado registra una entrada.
2. El sistema evita dos sesiones activas para la misma patente en el mismo estacionamiento.
3. El cajero registra la salida y el importe se calcula con la tarifa configurada.
4. La operación queda en historial y puede generar una boleta PDF.
5. El administrador ve vehículos, ingresos, usuarios y reportes de su propio estacionamiento.
6. Un SuperAdmin puede activar, suspender o reactivar el estacionamiento según la confirmación manual de su pago.

Las suscripciones del primer piloto seguirán siendo de control manual: el cliente paga por transferencia bancaria o efectivo y el SuperAdmin registra la confirmación. Las pasarelas de pago y cobros recurrentes quedan planificadas como un bloque posterior, documentado en `docs/PLAN_PAGOS_SUSCRIPCION.md`, para no mezclar riesgo comercial con la primera validación operativa.

## Hitos de desarrollo

| Hito | Resultado verificable | Prioridad |
| --- | --- | --- |
| H0 | Auditoría del proyecto y pruebas manuales de las funciones existentes | Crítica |
| H1 | API configurable, manejo uniforme de errores y migraciones seguras | Crítica |
| H2 | Inicio de sesión seguro, sesión y permisos validados por el servidor | Crítica |
| H3 | Estacionamientos y aislamiento de datos por cliente | Crítica |
| H4 | Operación completa: entrada, salida, tarifa, cobro, historial y boleta | Crítica |
| H5 | Administración de usuarios, reportes y auditoría por estacionamiento | Alta |
| H6 | SuperAdmin para activar, suspender, reactivar y administrar estacionamientos | Alta |
| H7 | Despliegue, HTTPS, respaldos, monitoreo y pruebas de aceptación | Crítica |
| H8 | Piloto en un estacionamiento real | Crítica |
| H9 | Suscripciones automatizadas, facturación y mejoras de escala | Posterior al piloto |

## Fases

### Fase 0 — Auditoría y línea base

**Objetivo:** saber exactamente qué funciona antes de modificar la arquitectura.

- Ejecutar y probar los flujos actuales contra una copia de respaldo de la base local.
- Crear una lista de pruebas manuales para entradas, salidas, tarifa, edición, anulación lógica, boletas, reportes y usuarios.
- Documentar errores encontrados y acordar criterios de aceptación.

**Salida:** lista priorizada de correcciones y línea base funcional.

### Fase 1 — Base técnica estable

**Objetivo:** hacer predecible la comunicación entre Flutter, API y datos.

- Centralizar la configuración de URL de API en Flutter.
- Incorporar configuración por ambiente (desarrollo, prueba y producción).
- Estandarizar respuestas y errores del servidor.
- Ordenar migraciones sin borrar `parkcontrol.db`.
- Añadir registros técnicos y pruebas mínimas de API.

**Salida:** el sistema se ejecuta localmente de forma repetible y se puede apuntar a un servidor remoto sin editar cada pantalla.

### Fase 2 — Identidad, sesión y permisos

**Objetivo:** el servidor decide quién puede hacer cada acción.

- Reemplazar contraseñas en texto plano por hashes seguros.
- Implementar sesiones mediante tokens de duración limitada.
- Proteger rutas de la API según usuario, rol y permisos.
- Definir roles: `superadmin`, `admin_estacionamiento` y `cajero`.
- Evitar credenciales iniciales inseguras en producción.

**Salida:** un cajero no puede administrar tarifas, usuarios ni operaciones que no le corresponden.

### Fase 3 — Multi-estacionamiento

**Objetivo:** permitir muchos clientes sin mezclar sus datos.

- Crear la entidad estacionamiento.
- Asociar usuarios, tarifas, vehículos, movimientos, boletas y auditoría a un estacionamiento.
- Migrar con seguridad los datos existentes a un estacionamiento inicial.
- Aplicar el filtro de estacionamiento en cada consulta del servidor.

**Salida:** dos estacionamientos pueden operar simultáneamente con datos totalmente separados.

### Fase 4 — Operación y cobro

**Objetivo:** terminar y endurecer el ciclo diario de un estacionamiento.

- Validar entrada, vehículo activo, salida y cierre de movimiento.
- Formalizar la regla de cálculo de tarifa con ejemplos acordados.
- Registrar monto, forma de pago y responsable de cada salida.
- Mantener anulación lógica mediante `estado = 'eliminado'` y auditoría.
- Validar emisión y consulta de boletas PDF.

**Salida:** una jornada completa puede ejecutarse sin usar directamente la base de datos.

### Fase 5 — Administración y SuperAdmin

**Objetivo:** ofrecer control operativo a cada cliente y control comercial a ParkControl.

- Administración de cajeros y permisos por estacionamiento.
- Reportes, caja, historial y auditoría segmentados por estacionamiento.
- Panel SuperAdmin para crear, activar, suspender y reactivar estacionamientos.
- Estado de suscripción gestionado manualmente durante el piloto: plan, fecha de inicio, fecha de vencimiento, fecha de pago confirmada, referencia u observación y responsable que realizó el cambio.
- Bloqueo de operaciones del estacionamiento cuando su estado sea suspendido, manteniendo el acceso de SuperAdmin para reactivarlo.

**Salida:** ParkControl puede administrar clientes y un administrador ve solamente su negocio.

### Fase 6 — Producción y piloto

**Objetivo:** operar fuera del computador de desarrollo.

- Migrar la fuente de datos autoritativa a PostgreSQL administrado.
- Conservar SQLite solo para el modo local/offline que se defina después del piloto.
- Desplegar API con dominio, HTTPS, variables seguras, respaldo y monitoreo básico.
- Ejecutar pruebas de aceptación con escenarios reales.
- Capacitar al primer estacionamiento y acompañar su piloto.

**Salida:** primer estacionamiento operando con ParkControl en producción.

## Estimación realista

Con dos horas diarias de dedicación, el piloto no debe medirse solo por semanas de calendario. La estimación profesional es:

- **Piloto operativo:** 20 a 28 semanas (280 a 390 horas efectivas).
- **Producto comercial con suscripción automatizada:** 8 a 12 semanas adicionales después de un piloto estable; no forma parte de la primera versión.

La estimación inicial de 12 a 16 semanas es posible únicamente si se reduce el alcance: un solo estacionamiento piloto, suscripción manual, sin facturación automática y con infraestructura gestionada.

## Secuencia de trabajo inmediata

La hoja de ruta de ejecución desde el 25 de agosto de 2026 se mantiene en `docs/ROADMAP_EJECUCION_25_AGOSTO.md`. La definición funcional de Lite, Pro, cierres de caja, analítica y reportes se mantiene en `docs/PLAN_PRODUCTO_LITE_PRO.md`.

1. Separar progresivamente el acceso a datos de las rutas HTTP, sin migrar todavía la base real.
2. Materializar operaciones offline sobre la caché y sus resultados confirmados.
3. Añadir el indicador visible de sincronización y una resolución clara de conflictos.
4. Definir una retención segura para registros idempotentes según el máximo tiempo offline permitido.
5. Preparar PostgreSQL, despliegue HTTPS, monitoreo y política de respaldos para el piloto online.
6. Validar y ajustar los dashboards con el responsable de ParkControl, sin mezclar esos cambios con la estabilización del servidor.

## Criterio de avance

Un hito solo se marca como terminado cuando cumple las cuatro condiciones:

1. Implementación completada.
2. Prueba del flujo en Flutter y API.
3. Sin regresiones en las funciones actuales.
4. Resultado validado por el responsable de ParkControl.
