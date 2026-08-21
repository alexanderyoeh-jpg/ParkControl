# Respaldos y restauración de SQLite

SQLite es actualmente la base de datos autoritativa de ParkControl. Este procedimiento protege sus datos mientras el servidor usa modo WAL. No borra, recrea ni reemplaza `backend/parkcontrol.db` de desarrollo, y ninguna restauración se ejecuta automáticamente.

## Riesgo que se evita

Con WAL, copiar solamente el archivo `.db` de una API activa puede omitir cambios que todavía están en `.db-wal`. Tampoco se debe copiar `.db`, `.db-wal` y `.db-shm` a mano como política de respaldo: el conjunto puede cambiar durante la copia.

ParkControl contiene dos utilidades para una instantánea consistente y su validación:

- [`backend/scripts/respaldo_sqlite.js`](../backend/scripts/respaldo_sqlite.js): usa la API de respaldo de SQLite, exige rutas absolutas, no sobrescribe un destino y devuelve SHA-256.
- [`backend/scripts/verificar_restauracion_sqlite.js`](../backend/scripts/verificar_restauracion_sqlite.js): crea una restauración temporal aislada, comprueba hash, `quick_check`, claves foráneas y conteos esenciales. No abre el archivo como base operativa.

Antes de automatizarlas, deben probarse en staging con el mismo usuario, versión de Node, permisos y destino remoto que se usarán en producción.

## Política mínima recomendada

- Crear una instantánea diaria y mantener, como punto inicial, 7 diarias, 4 semanales y 12 mensuales. Ajustar según contratos, volumen y obligaciones tributarias aplicables.
- Mantener al menos una copia fuera del VPS y fuera del mismo proveedor de almacenamiento cuando sea posible.
- Cifrar las copias en reposo y durante el transporte; limitar acceso al responsable de operación.
- Guardar junto al respaldo: nombre del archivo, fecha UTC, SHA-256, tamaño, versión de aplicación y resultado de verificación.
- Probar una restauración completa al menos mensualmente y después de cualquier cambio de versión, esquema o infraestructura.
- Definir RPO/RTO antes del piloto. Como referencia inicial, una copia diaria implica que podrían perderse hasta 24 horas de datos si no existen copias más frecuentes; no declarar este valor como compromiso comercial sin validarlo.

El directorio de trabajo de respaldos y su destino remoto deben ser distintos de `/var/lib/parkcontrol`. Ninguna credencial de almacenamiento se guarda en Git ni se imprime en registros.

## Crear una instantánea consistente

Ejemplo para un VPS donde la API usa `/var/lib/parkcontrol/parkcontrol.db`:

```bash
node /opt/parkcontrol/backend/scripts/respaldo_sqlite.js \
  --origen /var/lib/parkcontrol/parkcontrol.db \
  --destino /var/backups/parkcontrol/parkcontrol-AAAA-MM-DDTHH-mm-ssZ.sqlite
```

Condiciones previas:

1. Confirmar que el origen es el valor exacto de `PARKCONTROL_DB_PATH`, existe y no es un enlace inesperado.
2. Crear `/var/backups/parkcontrol` con permisos restrictivos y confirmar espacio disponible. El archivo de destino debe ser nuevo: la utilidad rechaza sobrescribir uno existente.
3. Ejecutar como un usuario autorizado que pueda leer la base y escribir únicamente en el directorio de respaldos.
4. Registrar la salida JSON, especialmente `sha256`, `bytes` y `creadoEn`.

No uses `cp`, sincronización de carpetas ni una copia del `.db` vivo como sustituto. La utilidad usa la API online backup y es compatible con una base que está operando en WAL.

## Verificar cada respaldo

Usar el hash informado por el paso anterior:

```bash
node /opt/parkcontrol/backend/scripts/verificar_restauracion_sqlite.js \
  --respaldo /var/backups/parkcontrol/parkcontrol-AAAA-MM-DDTHH-mm-ssZ.sqlite \
  --sha256 HASH_SHA256_DEL_RESPALDO
```

La verificación debe terminar con:

- `integridad.quickCheck: "ok"`;
- `integridad.clavesForaneas: "ok"`;
- presencia de tablas esenciales (`estacionamientos`, `usuarios`, `movimientos`, `auditoria`);
- conteos razonables frente al último control conocido;
- movimientos sólo con los estados permitidos por la aplicación: `dentro`, `salio` o `eliminado`.

Un hash correcto no sustituye la restauración de ensayo. Si la validación falla, conservar el archivo y los registros para investigación, generar una nueva instantánea y escalar antes de afirmar que existe una copia recuperable.

## Copia externa y automatización futura

Después de verificar la instantánea, transferirla a un destino externo cifrado con control de acceso y retención definida. La transferencia debe volver a comprobar el SHA-256 una vez almacenada.

Por ahora, no se incluye un cron ni un temporizador systemd porque se debe elegir y probar el destino externo, sus credenciales, cifrado, alertas de fallo y política de retención. Cuando se incorpore, el trabajo automatizado debe:

1. generar un destino único;
2. verificar localmente el resultado;
3. enviar la copia cifrada;
4. verificar el hash remoto;
5. registrar éxito o fallo sin revelar secretos;
6. alertar a una persona responsable si falla o no se ejecuta.

## Restauración de ensayo (obligatoria)

La primera restauración debe realizarse en una ruta o VPS aislado, nunca sobre la API en producción:

1. Elegir un respaldo verificado y copiarlo a un entorno de ensayo protegido.
2. Confirmar SHA-256 y ejecutar `verificar_restauracion_sqlite.js`.
3. Configurar una instancia de ParkControl de staging con su propia ruta `PARKCONTROL_DB_PATH`; no reutilizar secretos ni URLs de producción.
4. Arrancar la instancia y revisar `healthz`, `readyz`, login autorizado, movimientos históricos, auditoría, tarifas, usuarios y aislamiento por estacionamiento.
5. Comparar conteos y montos con el registro del respaldo; documentar fecha, operador, duración y resultado.
6. Eliminar sólo la restauración de ensayo creada en el entorno aislado según la política local. No eliminar el respaldo fuente.

## Recuperación ante incidente en producción

Restaurar datos requiere autorización explícita del responsable del sistema porque puede descartar operaciones posteriores al punto de respaldo.

1. Declarar incidente, anotar hora UTC, síntomas y último respaldo confirmado. Detener nuevas escrituras mediante mantenimiento en Nginx.
2. Detener el servicio `parkcontrol` de manera ordenada. No matar el proceso ni borrar archivos `.db`, `-wal` o `-shm`.
3. Conservar como evidencia la base afectada y sus archivos asociados en una ubicación segura. Si el disco o la integridad están comprometidos, trabajar sobre una copia forense y no sobre el original.
4. Verificar el respaldo elegido en una ruta aislada y comparar sus conteos con el último registro conocido.
5. Restaurar primero en staging, arrancar con una ruta de datos independiente y aprobar las comprobaciones funcionales.
6. Sólo después de la aprobación, sustituir la ruta de datos de producción durante una ventana de mantenimiento, con el servicio detenido y una copia preservada de la base previa.
7. Arrancar ParkControl, comprobar `/healthz` y `/readyz`, validar SuperAdministrador, permisos, movimientos y auditoría. Mantener seguimiento reforzado durante el siguiente turno operativo.
8. Registrar la hora de recuperación, respaldo utilizado, SHA-256, datos potencialmente no recuperados y decisión de cierre del incidente.

Si la restauración falla antes de reabrir el servicio, volver a la base preservada y no aceptar operaciones hasta revisar el incidente. Si se sospecha corrupción, no intentar "arreglar" tablas manualmente en producción.

## Lista de verificación operativa

- [ ] El respaldo procede de una instantánea SQLite coherente, no de una copia física del `.db` vivo.
- [ ] Se registraron hash, fecha UTC, tamaño y resultado de verificación.
- [ ] Existe una copia externa cifrada y se comprobó su hash.
- [ ] Se probó restauración aislada durante el último mes.
- [ ] La persona responsable conoce RPO/RTO, retención y ruta de escalamiento.
- [ ] Ningún respaldo, hash con datos sensibles, secreto o base de producción se subió a Git.
