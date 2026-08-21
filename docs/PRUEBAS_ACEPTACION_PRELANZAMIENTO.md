# Pruebas de aceptación pre-lanzamiento

Lista manual de aprobación para el piloto de ParkControl. Se ejecuta en **staging** o con una copia de datos de prueba: nunca sobre `backend/parkcontrol.db` ni sobre una base productiva. Una prueba crítica fallida bloquea el lanzamiento hasta que exista corrección, nueva prueba y evidencia registrada.

## Preparación común

- [ ] Registrar fecha, versión de Flutter/API, dispositivo, navegador y responsable de la prueba.
- [ ] Preparar dos estacionamientos de prueba aislados: **A (Lite)** y **B (Pro)**, con tarifas y patentes de prueba conocidas.
- [ ] Preparar sesiones de SuperAdministrador, administrador y cajero para cada estacionamiento. En Pro, crear dos administradores y tres cajeros; en Lite, uno de cada rol.
- [ ] Usar una base de staging que pueda descartarse y guardar capturas o respuestas de API de cada resultado relevante.
- [ ] Definir una hoja de resultados con: caso, ejecutor, esperado, obtenido, evidencia, fecha y decisión (`aprobado` / `bloqueado`).

## 1. Aislamiento multi-estacionamiento e IDOR

- [ ] Con una sesión de A, confirmar que dashboard, vehículos, historial, tarifa, usuarios, turnos, alertas y reportes muestran únicamente datos de A; repetir con B.
- [ ] Obtener un identificador válido de B (movimiento, usuario, turno, reporte o comprobante) e intentar abrirlo, modificarlo o eliminarlo lógicamente desde una sesión de A mediante navegación directa o una solicitud controlada a la API.
- [ ] **Esperado:** el backend rechaza el acceso o la mutación (`403`/`404` según la ruta), no aparece información de B y ningún dato de B cambia.
- [ ] Repetir al menos una prueba de lectura y una de escritura con un cajero; no basta con que el botón esté oculto en Flutter.

## 2. Suspensión con sesión existente

- [ ] Mantener una sesión activa de administrador y otra de cajero del estacionamiento A.
- [ ] Desde SuperAdministrador, suspender A sin cerrar esas sesiones.
- [ ] En las sesiones ya abiertas, actualizar el dashboard e intentar registrar entrada, salida o modificación.
- [ ] **Esperado:** la API bloquea la operación y no se crea ni se altera un movimiento mientras el estacionamiento esté suspendido.
- [ ] Reactivar A y confirmar que la operación vuelve a estar disponible sólo con la cuenta/estacionamiento activos; registrar en auditoría la suspensión y reactivación.

## 3. Roles, Lite y Pro

- [ ] En Lite, validar operación básica: entrada, salida, vehículos dentro, modificación auditada, historial y conteo/reporte diario.
- [ ] En Lite, intentar crear un segundo administrador y un segundo cajero. **Esperado:** el backend rechaza el exceso de cuota (`409 LIMITE_USUARIOS_PLAN`).
- [ ] En Lite, comprobar que no se habilitan comprobante PDF, historial descargable de comprobantes, contabilidad/analítica avanzada, exportaciones ni cierre de caja; probar una ruta Pro directamente. **Esperado:** rechazo `403 FUNCION_NO_DISPONIBLE_PLAN`.
- [ ] En Pro, validar que se permiten hasta dos administradores y tres cajeros; intentar un tercero administrador y cuarto cajero. **Esperado:** rechazo por límite, sin crear usuarios adicionales.
- [ ] En Pro, comprobar acceso de administrador a comprobantes, contabilidad, analítica, exportaciones, cierre de caja y alertas. El cajero conserva sólo atribuciones operativas de su rol.
- [ ] Cambiar un Pro con usuarios excedentes a Lite. **Esperado:** el backend rechaza el cambio sin borrar usuarios; tras reducir explícitamente los activos al límite, el cambio es posible y las funciones Pro quedan bloqueadas.

## 4. Operación diaria, historial y comprobantes

- [ ] Con tarifa conocida, registrar una entrada Pro y comprobar patente, hora, vehículo dentro y conteo diario.
- [ ] Modificar un vehículo activo y comprobar que la corrección y su responsable quedan en auditoría.
- [ ] Eliminar lógicamente un movimiento de prueba cuando el flujo lo permita. **Esperado:** se conserva en historial/auditoría con estado `eliminado`; no se borra físicamente.
- [ ] Registrar una salida, verificar duración y monto contra el cálculo esperado, y comprobar que deja de figurar dentro.
- [ ] En Pro, abrir/descargar el PDF generado tras la salida. **Esperado:** datos coherentes y texto de comprobante ParkControl/no tributario, no una boleta electrónica certificada ante SII.
- [ ] En Lite, confirmar que la misma operación no entrega comprobante PDF ni historial descargable de comprobantes.

## 5. Cierre de caja, auditoría y alertas Pro

- [ ] Con un cajero Pro, abrir turno con monto inicial conocido; registrar cobros de prueba y cerrar declarando el monto esperado.
- [ ] **Esperado:** el cierre conserva cajero, montos esperados/declarados, diferencia, movimientos e incidencias del turno; no puede cambiarse silenciosamente después.
- [ ] Intentar cobrar sin turno, desde un administrador y después de cerrar el turno. **Esperado:** el backend rechaza la salida; cada cobro Pro exitoso queda vinculado al turno abierto de su cajero y no puede trasladarse a otro turno.
- [ ] Enviar una salida con una hora local retroactiva de prueba. **Esperado:** la hora oficial, el monto y el turno corresponden a la recepción del servidor; la hora informada sólo queda como trazabilidad y no altera contabilidad.
- [ ] Repetir con un monto declarado distinto. **Esperado:** aparece una alerta Pro de diferencia de cierre aislada al estacionamiento, inicialmente `pendiente`.
- [ ] Un administrador Pro revisa el turno primero como observado y luego, en un cierre de prueba distinto, como revisado. **Esperado:** alerta y auditoría reflejan `revisada` o `resuelta`, responsable, fecha y observación cuando corresponda.
- [ ] Confirmar que Lite no puede abrir/cerrar turnos ni consultar las rutas Pro de cierre/alertas.

## 6. Offline y reconexión en dispositivo real

- [ ] Usar un teléfono o equipo físico con sesión de cajero, abrir la aplicación con conexión y luego desactivar realmente Wi-Fi/datos.
- [ ] Registrar una entrada offline, reiniciar la aplicación, volver a iniciar
  sesión con el mismo cajero y confirmar que la operación pendiente y el
  vehículo local se conservan. El token no debe sobrevivir al cierre completo
  de la app.
- [ ] En Lite, completar una salida offline de prueba; restaurar conexión y comprobar que queda un solo movimiento/una sola salida/cobro, sin filas duplicadas.
- [ ] En Pro, intentar una salida sin conexión. **Esperado:** la aplicación la rechaza antes de cobrar; una cola heredada de salida Pro queda en conflicto administrativo y nunca se asigna al siguiente turno. Las entradas Pro sí pueden conservarse localmente y se oficializan al sincronizar.
- [ ] Forzar un reintento o reconexión repetida. **Esperado:** la idempotencia evita duplicados y el indicador de sincronización informa pendiente, envío, conflicto o bloqueo de forma comprensible.
- [ ] Suspender el estacionamiento o modificar el dato involucrado mientras una acción permanece pendiente; restaurar conexión. **Esperado:** se detiene como conflicto/bloqueo visible, sin que Flutter lo resuelva por sí solo ni afecte otro cajero.

## 7. Respaldo y restauración en copia aislada

- [ ] Crear una instantánea con `backend/scripts/respaldo_sqlite.js`; no copiar físicamente una base activa ni sólo su archivo `.db` en WAL.
- [ ] Verificarla con `backend/scripts/verificar_restauracion_sqlite.js` y registrar SHA-256, tamaño, `quick_check`, claves foráneas y conteos.
- [ ] Restaurar/arrancar exclusivamente sobre una ruta o VPS de ensayo, nunca sobre la base operativa.
- [ ] En la copia, validar login autorizado, movimientos, auditoría, usuarios, tarifas y aislamiento de A/B; comparar conteos y montos con la evidencia del respaldo.
- [ ] Registrar duración de respaldo/restauración y confirmar que la copia externa cifrada y la retención están disponibles según [RESPALDOS_Y_RESTAURACION.md](RESPALDOS_Y_RESTAURACION.md).

## 8. Despliegue y supervisión

- [ ] En producción/staging, confirmar `NODE_ENV=production`, `PARKCONTROL_HOST=127.0.0.1`, ruta SQLite absoluta existente y ausencia de usuarios demo/configuración HTTP inicial.
- [ ] Confirmar localmente `http://127.0.0.1:3000/healthz` y `/readyz` con respuesta `200`.
- [ ] Confirmar públicamente HTTPS mediante Nginx y `https://api.tu-dominio.cl/healthz`; `/readyz` debe respetar la restricción de acceso definida para el monitor.
- [ ] Confirmar que el puerto `3000` no es accesible desde Internet, que systemd reinicia la API de forma controlada y que los registros no contienen secretos.
- [ ] Revisar [DESPLIEGUE_VPS.md](DESPLIEGUE_VPS.md) y aprobar su checklist antes de habilitar clientes reales.

## 9. Android, iOS, web/PWA y sesiones

- [ ] Generar Android/Web con
  `PARKCONTROL_API_URL=https://api.tu-dominio.cl`; una compilación
  profile/release sin URL o con HTTP debe detenerse antes de operar.
- [ ] En Android de prueba, validar red, entrada/salida, PDF autenticado,
  impresión/guardado, offline, retorno de red y cierre de sesión. Repetir en
  un iPhone/iPad real mediante TestFlight antes de enviar a App Store.
- [ ] En `https://app.tu-dominio.cl`, probar Chrome, Edge, Firefox y Safari:
  login CORS, recarga de una ruta interna, PDF, Excel, cola offline e
  instalación PWA cuando aplique.
- [ ] Solicitar una ruta protegida y una ruta PDF usando
  `?access_token=<token>` en lugar del header Authorization.
  **Esperado:** `401`; el token nunca aparece en URL, historial ni log de
  proxy. La descarga PDF autenticada sigue funcionando desde la aplicación.
- [ ] Cerrar por completo la app móvil y recargar la web.
  **Esperado:** se pide autenticación de nuevo; no existe `auth_token` en
  SharedPreferences/localStorage. Tras login del usuario correcto, una cola
  offline existente puede sincronizarse.
- [ ] Abrir dos pestañas web con cajeros de estacionamientos distintos, generar una entrada offline en cada una y restaurar conexión. **Esperado:** cada pestaña conserva su propia identidad de sesión y sólo procesa su cola; no se cruzan datos ni comprobantes.
- [ ] Confirmar que cada cajero usa un dispositivo/perfil de navegador
  individual, con bloqueo de pantalla y cifrado del sistema. La cola offline
  puede contener datos operativos mientras está pendiente; no se usa en equipos
  públicos ni se borra antes de sincronizar/resolver sus operaciones.
- [ ] Validar que las fichas Google Data Safety y Apple App Privacy describen
  exactamente la versión enviada, incluidas cuentas, patentes, movimientos y
  datos de cobro que efectivamente trate el producto.

## Cierre de aceptación

- [ ] No existen casos críticos bloqueados.
- [ ] Cada caso tiene evidencia y responsable de aprobación.
- [ ] Se anotaron limitaciones conocidas y un plan de corrección para las no críticas.
- [ ] SuperAdministrador y responsable operativo autorizan por escrito el piloto, fecha de inicio y procedimiento de reversión.
