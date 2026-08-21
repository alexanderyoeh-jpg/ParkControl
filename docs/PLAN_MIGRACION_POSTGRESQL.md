# Plan de migración futura: SQLite a PostgreSQL

## Estado actual y decisión

**No migrar todavía.** SQLite sigue siendo la base de datos autoritativa de ParkControl durante la estabilización funcional, la validación offline y el primer piloto. PostgreSQL es el destino de arquitectura, no una tarea que se deba ejecutar junto con cambios de dashboards o funcionalidades.

La dirección objetivo sigue siendo:

```text
Flutter ──> API Node.js ──> PostgreSQL administrado o privado ──> respaldos verificados
```

El backend mantiene la fuente de verdad: Flutter nunca elegirá un `estacionamiento_id`, plan o permiso por cuenta propia. La migración no cambia los roles `superadmin`, administrador ni cajero, ni los estados de movimientos `dentro`, `salio` y `eliminado`.

## Por qué no se debe migrar ahora

- La API y las reglas de negocio todavía se están consolidando alrededor de SQLite.
- La cola offline requiere pruebas reales en dispositivos y un contrato estable antes de cambiar el adaptador de datos.
- Montos históricos se guardan actualmente como `REAL`. Su representación exacta en PostgreSQL debe decidirse antes de copiar datos financieros.
- Una migración simultánea con nuevas funciones, doble escritura o cambios de interfaz dificultaría identificar la causa de una diferencia de datos.

No se implementará doble escritura SQLite/PostgreSQL como paso inicial. Dos fuentes que aceptan escrituras pueden divergir silenciosamente y complican auditoría, cierres de caja y recuperación.

## Criterios de entrada

La migración sólo puede comenzar después de aprobar todos los puntos siguientes:

- [ ] Las rutas críticas (login, entradas, salidas, modificaciones, eliminación lógica, boletas, tarifas, usuarios, auditoría, cierres y suspensión) tienen pruebas de integración repetibles.
- [ ] Los contratos de API y las migraciones SQLite vigentes están documentados y estables durante un periodo de piloto acordado.
- [ ] Multi-tenancy está revisado: cada entidad comercial y operativa relevante posee y valida `estacionamiento_id` en backend.
- [ ] El respaldo y la restauración SQLite fueron ensayados con éxito en un entorno aislado.
- [ ] Se definió un RPO/RTO comercial y un periodo de mantenimiento aceptable para el corte.
- [ ] Se aprobó la política de montos: unidades enteras (por ejemplo, pesos) o `NUMERIC(p,s)` con escala explícita. No se convertirá `REAL` histórico de forma silenciosa.
- [ ] Existe una instancia PostgreSQL de staging aislada, con TLS, respaldo, acceso mínimo y monitorización.
- [ ] Un responsable técnico y un responsable comercial aprobaron el plan de corte y rollback.

## Diseño de destino propuesto

La capa de transporte Node/Express debe conservar respuestas de API y autorización. La evolución previa es extraer reglas y acceso a datos desde `backend/server.js` hacia módulos de dominio y repositorios, evitando una reescritura completa.

PostgreSQL deberá incorporar explícitamente:

- claves primarias, foráneas, restricciones `NOT NULL`, `CHECK` e índices equivalentes a los actuales;
- índices compuestos por `estacionamiento_id` en todas las consultas de aislamiento multi-tenant;
- transacciones para entrada/salida, cierres de caja, pagos y auditoría;
- una restricción para que el ciclo de vida de movimientos admita únicamente `dentro`, `salio` y `eliminado`;
- `NUMERIC` o una unidad monetaria entera decidida y documentada antes de importar totales;
- fechas UTC con conversión de zona horaria sólo en presentación/reportes;
- secretos fuera de la cadena de conexión, TLS y un usuario de base con privilegios mínimos;
- respaldos, pruebas de restauración y monitorización propios de PostgreSQL.

No asumir que las tablas SQLite se pueden copiar con una herramienta genérica sin revisar tipos, restricciones, secuencias e índices. Las migraciones PostgreSQL deben ser versionadas, revisadas y aplicadas primero en una base desechable.

## Fases de ejecución futura

### Fase 0: inventario y congelamiento

1. Capturar versión de aplicación, esquema SQLite, migraciones aplicadas, conteos y totales por estacionamiento.
2. Identificar todas las tablas, vistas, índices, claves y campos que dependen de `estacionamiento_id`.
3. Definir una ventana sin cambios de esquema y un conjunto de pruebas de regresión obligatorio.
4. Documentar decisiones de precisión monetaria y tratamiento de fechas antes de escribir el importador.

### Fase 1: esquema PostgreSQL y repositorios

1. Crear migraciones PostgreSQL idempotentes y una base de staging desechable.
2. Extraer gradualmente repositorios de datos sin alterar las rutas ni respuestas públicas del backend.
3. Implementar el adaptador PostgreSQL detrás de la misma interfaz de repositorio.
4. Ejecutar pruebas de integración contra SQLite y PostgreSQL por separado; no activar escritura doble.

### Fase 2: importación repetible de ensayo

1. Construir un importador de una sola dirección SQLite → PostgreSQL, con identificadores conservados o un mapa explícito y auditable.
2. Importar en orden de dependencias: estacionamientos, usuarios/roles, configuración y tarifas, movimientos, cobros/boletas, turnos, auditoría, suscripciones, idempotencia y demás tablas operativas.
3. Ejecutar la importación desde una instantánea SQLite verificada, nunca desde una copia física incierta de una base en WAL.
4. Repetirla desde cero en staging hasta obtener el mismo resultado para la misma instantánea.

### Fase 3: conciliación

La importación no se aprueba sólo porque termine sin error. Comparar, por cada estacionamiento:

- cantidad de registros de todas las tablas relevantes;
- movimientos por estado `dentro`, `salio` y `eliminado`;
- usuarios por rol, activos/suspendidos y asignación de estacionamiento;
- tarifas, ingresos, cierres de caja, boletas y pagos con la precisión monetaria acordada;
- eventos de auditoría y claves de idempotencia;
- relaciones sin claves foráneas huérfanas;
- resultados de los reportes operativos y Pro para una muestra representativa de fechas.

Las diferencias deben clasificarse, explicarse y aprobarse por escrito. No se compensa una diferencia modificando datos históricos a mano sin un registro auditable.

### Fase 4: ensayo de corte y rollback

1. Simular la ventana de mantenimiento en staging: poner API en modo de no escritura, crear última instantánea SQLite, importar, conciliar, iniciar API contra PostgreSQL y ejecutar pruebas críticas.
2. Medir duración real, pasos manuales, RPO/RTO y puntos de decisión.
3. Confirmar que el rollback devuelve la API a SQLite desde una base conservada sin borrar el origen.
4. Repetir el ensayo hasta que sea reproducible y aprobado.

### Fase 5: corte productivo controlado

1. Comunicar mantenimiento, congelar despliegues y detener nuevas operaciones de escritura.
2. Crear y verificar el último respaldo SQLite; conservarlo inmutable junto con hash y conteos.
3. Ejecutar importación, conciliación y pruebas de humo contra PostgreSQL.
4. Cambiar la configuración del backend para usar únicamente PostgreSQL, sin borrado de SQLite.
5. Monitorear errores, latencia, permisos, conteos, cierres y reportes durante la ventana reforzada definida.

El código, variables y herramienta exacta para apuntar a PostgreSQL se diseñarán cuando se complete la Fase 1. No crear una variable de conexión ni una migración parcial ahora.

## Rollback

El rollback debe ser posible mientras PostgreSQL no haya aceptado operaciones que no puedan reflejarse en SQLite:

1. Mantener la instantánea SQLite de corte, el artefacto anterior y su configuración sin modificar.
2. Si falla conciliación o prueba de humo antes de abrir escrituras, volver el backend a SQLite y cancelar el corte.
3. Si PostgreSQL ya aceptó operaciones, pausar el servicio y evaluar una reconciliación explícita; no alternar de vuelta automáticamente porque podría perder dichas operaciones.
4. No borrar SQLite hasta después del periodo de estabilización y de una decisión documentada de retención.

## Criterio de finalización

La migración se considera concluida sólo cuando PostgreSQL es la única fuente de escritura, los respaldos/restauraciones PostgreSQL están verificados, la conciliación está firmada, el monitoreo funciona y SQLite queda retenida como respaldo histórico según una política aprobada. Hasta entonces, este documento es un plan, no autorización de migración.
