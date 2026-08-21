const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const Database = require('better-sqlite3');

const PUERTO_PRUEBA = 31818;
const URL_BASE = `http://127.0.0.1:${PUERTO_PRUEBA}`;
const DIRECTORIO_TEMPORAL = fs.mkdtempSync(
  path.join(os.tmpdir(), 'parkcontrol-superadmin-')
);
const RUTA_DB_PRUEBA = path.join(
  DIRECTORIO_TEMPORAL,
  'parkcontrol-prueba.db'
);
const SECRETO_WEBHOOK_PRUEBA = 'secreto-webhook-mercadopago-prueba-2026';

let servidor;
let salidaServidor = '';

function iniciarServidor() {
  salidaServidor = '';
  servidor = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      NODE_ENV: 'test',
      PORT: String(PUERTO_PRUEBA),
      PARKCONTROL_DB_PATH: RUTA_DB_PRUEBA,
      PARKCONTROL_ALLOW_SETUP: 'true',
      PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
      PARKCONTROL_ALLOWED_ORIGINS: 'http://localhost:8080',
      PARKCONTROL_LOGIN_MAX_ATTEMPTS: '3',
      PARKCONTROL_LOGIN_WINDOW_MS: '60000',
      PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET: SECRETO_WEBHOOK_PRUEBA,
      PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN: '',
      PARKCONTROL_PUBLIC_URL: '',
      PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado',
      PARKCONTROL_RESEND_API_KEY: '',
      PARKCONTROL_EMAIL_FROM: '',
      PARKCONTROL_EMAIL_REPLY_TO: ''
    },
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe']
  });

  servidor.stdout.on('data', dato => {
    salidaServidor += dato.toString();
  });
  servidor.stderr.on('data', dato => {
    salidaServidor += dato.toString();
  });
}

async function detenerServidor() {
  if (!servidor || servidor.exitCode != null) {
    return;
  }

  const salida = await new Promise(resolve => {
    const temporizador = setTimeout(() => {
      servidor.kill('SIGKILL');
    }, 3000);
    servidor.once('exit', (codigo, senal) => {
      clearTimeout(temporizador);
      resolve({ codigo, senal });
    });
    servidor.kill();
  });

  // Windows traduce child.kill('SIGTERM') a una terminación directa del
  // proceso hijo, sin entregar el evento a Node. En Linux (entorno del VPS)
  // exigimos el código 0 del cierre ordenado; en Windows se acepta SIGTERM
  // para no confundir esa diferencia de plataforma con una falla de la API.
  if (process.platform === 'win32') {
    assert.ok(salida.codigo === 0 || salida.senal === 'SIGTERM');
    return;
  }

  assert.equal(
    salida.codigo,
    0,
    `El servidor no se cerró de forma ordenada (${salida.senal || 'sin señal'})`
  );
}

async function esperarServidor() {
  const limite = Date.now() + 10000;

  while (Date.now() < limite) {
    if (servidor.exitCode != null) {
      throw new Error(`El servidor terminó antes de iniciar:\n${salidaServidor}`);
    }

    try {
      const respuesta = await fetch(`${URL_BASE}/api/setup/estado`);
      if (respuesta.status === 200) {
        return;
      }
    } catch (_) {
      // El proceso todavía está abriendo la base temporal.
    }

    await new Promise(resolve => setTimeout(resolve, 100));
  }

  throw new Error(`El servidor de prueba no respondió:\n${salidaServidor}`);
}

async function api(
  metodo,
  ruta,
  { datos, token, claveIdempotencia } = {}
) {
  const respuesta = await fetch(`${URL_BASE}${ruta}`, {
    method: metodo,
    headers: {
      ...(datos == null ? {} : { 'Content-Type': 'application/json' }),
      ...(token == null ? {} : { Authorization: `Bearer ${token}` }),
      ...(claveIdempotencia == null
        ? {}
        : { 'Idempotency-Key': claveIdempotencia })
    },
    body: datos == null ? undefined : JSON.stringify(datos)
  });

  const texto = await respuesta.text();
  let cuerpo = null;

  try {
    cuerpo = texto ? JSON.parse(texto) : null;
  } catch (_) {
    cuerpo = texto;
  }

  return {
    estado: respuesta.status,
    cuerpo,
    tipo: respuesta.headers.get('content-type') || '',
    idempotenciaReutilizada:
      respuesta.headers.get('idempotency-replayed') === 'true'
  };
}

function firmaWebhookMercadoPago({ dataId, requestId, ts }) {
  const manifiesto = `id:${dataId};request-id:${requestId};ts:${ts};`;

  return crypto
    .createHmac('sha256', SECRETO_WEBHOOK_PRUEBA)
    .update(manifiesto)
    .digest('hex');
}

async function login(email, password) {
  return api('POST', '/api/login', {
    datos: { email, password }
  });
}

function datosCliente({
  nombre,
  rut,
  email,
  vencimiento,
  plan = 'LITE'
}) {
  return {
    nombre,
    razonSocial: `${nombre} SpA`,
    rut,
    emailContacto: email,
    plan,
    fechaInicio: '2026-08-01',
    fechaVencimiento: vencimiento,
    tarifaPorMinuto: 10,
    administrador: {
      nombre: `Administrador ${nombre}`,
      email,
      password: 'ClienteSeguro2026'
    }
  };
}

function abrirBasePrueba() {
  return new Database(RUTA_DB_PRUEBA, { readonly: true });
}

function limpiarTemporal() {
  const temporalRaiz = path.resolve(os.tmpdir());
  const objetivo = path.resolve(DIRECTORIO_TEMPORAL);
  const nombre = path.basename(objetivo);

  if (!objetivo.startsWith(`${temporalRaiz}${path.sep}`) ||
      !nombre.startsWith('parkcontrol-superadmin-')) {
    throw new Error('Se rechazó limpiar una ruta temporal inesperada.');
  }

  fs.rmSync(objetivo, { recursive: true, force: true });
}

async function ejecutar() {
  iniciarServidor();
  await esperarServidor();

  let respuestaHttp = await fetch(`${URL_BASE}/healthz`);
  assert.equal(respuestaHttp.status, 200);
  assert.deepEqual(await respuestaHttp.json(), { estado: 'ok' });

  respuestaHttp = await fetch(`${URL_BASE}/readyz`);
  assert.equal(respuestaHttp.status, 200);
  assert.deepEqual(await respuestaHttp.json(), { estado: 'listo' });

  respuestaHttp = await fetch(`${URL_BASE}/api/setup/estado`, {
    headers: { Origin: 'https://sitio-no-autorizado.example' }
  });
  assert.equal(respuestaHttp.status, 403);
  assert.equal(respuestaHttp.headers.get('x-powered-by'), null);
  assert.equal(
    respuestaHttp.headers.get('x-content-type-options'),
    'nosniff'
  );

  respuestaHttp = await fetch(`${URL_BASE}/api/setup/estado`, {
    headers: { Origin: 'http://localhost:8080' }
  });
  assert.equal(respuestaHttp.status, 200);
  assert.equal(
    respuestaHttp.headers.get('access-control-allow-origin'),
    'http://localhost:8080'
  );

  respuestaHttp = await fetch(`${URL_BASE}/api/entradas`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'http://localhost:8080',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers':
        'authorization,content-type,idempotency-key'
    }
  });
  assert.equal(respuestaHttp.status, 204);
  assert.match(
    respuestaHttp.headers.get('access-control-allow-headers') || '',
    /Idempotency-Key/i
  );

  const dataIdWebhook = 'preapproval-prueba-001';
  const requestIdWebhook = 'solicitud-prueba-001';
  const timestampWebhook = '1760000000';
  const firmaWebhook = firmaWebhookMercadoPago({
    dataId: dataIdWebhook,
    requestId: requestIdWebhook,
    ts: timestampWebhook
  });
  const avisoWebhook = {
    id: 'evento-mercadopago-prueba-001',
    type: 'subscription_preapproval',
    action: 'subscription_preapproval.updated',
    data: { id: dataIdWebhook }
  };

  respuestaHttp = await fetch(
    `${URL_BASE}/api/webhooks/mercadopago?data.id=${dataIdWebhook}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-request-id': requestIdWebhook,
        'x-signature': `ts=${timestampWebhook},v1=${firmaWebhook}`
      },
      body: JSON.stringify(avisoWebhook)
    }
  );
  assert.equal(respuestaHttp.status, 202);
  let cuerpoWebhook = await respuestaHttp.json();
  assert.equal(cuerpoWebhook.recibido, true);
  assert.equal(cuerpoWebhook.duplicado, false);
  assert.equal(cuerpoWebhook.procesado, false);

  respuestaHttp = await fetch(
    `${URL_BASE}/api/webhooks/mercadopago?data.id=${dataIdWebhook}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-request-id': requestIdWebhook,
        'x-signature': `ts=${timestampWebhook},v1=${firmaWebhook}`
      },
      body: JSON.stringify(avisoWebhook)
    }
  );
  assert.equal(respuestaHttp.status, 200);
  cuerpoWebhook = await respuestaHttp.json();
  assert.equal(cuerpoWebhook.duplicado, true);

  respuestaHttp = await fetch(
    `${URL_BASE}/api/webhooks/mercadopago?data.id=${dataIdWebhook}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-request-id': requestIdWebhook,
        'x-signature': `ts=${timestampWebhook},v1=${'0'.repeat(64)}`
      },
      body: JSON.stringify({ ...avisoWebhook, id: 'evento-firma-invalida' })
    }
  );
  assert.equal(respuestaHttp.status, 401);

  let baseWebhook = abrirBasePrueba();
  const eventosWebhook = baseWebhook.prepare(`
    SELECT
      COUNT(*) AS total,
      MIN(firma_valida) AS firma_valida,
      MIN(estado_procesamiento) AS estado_procesamiento
    FROM eventos_pasarela
  `).get();
  assert.equal(eventosWebhook.total, 1);
  assert.equal(eventosWebhook.firma_valida, 1);
  assert.equal(eventosWebhook.estado_procesamiento, 'pendiente_verificacion');
  baseWebhook.close();

  respuestaHttp = await fetch(`${URL_BASE}/api/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{json-incompleto'
  });
  assert.equal(respuestaHttp.status, 400);
  let errorPublico = await respuestaHttp.json();
  assert.equal(errorPublico.detalle, undefined);

  respuestaHttp = await fetch(`${URL_BASE}/api/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ contenido: 'x'.repeat(300 * 1024) })
  });
  assert.equal(respuestaHttp.status, 413);
  errorPublico = await respuestaHttp.json();
  assert.equal(errorPublico.detalle, undefined);

  let intentoLogin = await login('intruso@prueba.cl', 'incorrecta');
  assert.equal(intentoLogin.estado, 401);
  intentoLogin = await login('intruso@prueba.cl', 'incorrecta');
  assert.equal(intentoLogin.estado, 401);
  intentoLogin = await login('intruso@prueba.cl', 'incorrecta');
  assert.equal(intentoLogin.estado, 429);
  assert.equal(
    intentoLogin.cuerpo.codigo,
    'DEMASIADOS_INTENTOS_LOGIN'
  );

  let respuesta = await api('GET', '/api/setup/estado');
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.requiereConfiguracion, true);
  assert.equal(respuesta.cuerpo.requiereCodigo, true);

  let base = abrirBasePrueba();
  const claveSetup = base.prepare(`
    SELECT valor
    FROM seguridad_configuracion
    WHERE clave = 'superadmin_setup_key'
  `).get().valor;
  assert.match(claveSetup, /^[A-F0-9]{12}$/);
  base.close();

  // El código debe seguir siendo el mismo aunque el servidor se reinicie
  // antes de terminar la configuración inicial.
  await detenerServidor();
  iniciarServidor();
  await esperarServidor();

  base = abrirBasePrueba();
  const claveTrasReinicio = base.prepare(`
    SELECT valor
    FROM seguridad_configuracion
    WHERE clave = 'superadmin_setup_key'
  `).get().valor;
  assert.equal(claveTrasReinicio, claveSetup);
  base.close();

  respuesta = await api('POST', '/api/setup/superadmin', {
    datos: {
      nombre: 'Propietario ParkControl',
      email: 'propietario@prueba.cl',
      password: 'PropietarioSeguro2026'
    }
  });
  assert.equal(respuesta.estado, 403);

  respuesta = await api('POST', '/api/setup/superadmin', {
    datos: {
      nombre: 'Propietario ParkControl',
      email: 'propietario@prueba.cl',
      password: 'PropietarioSeguro2026',
      claveConfiguracion: claveSetup
    }
  });
  assert.equal(respuesta.estado, 201);

  respuesta = await api('POST', '/api/setup/superadmin', {
    datos: {
      nombre: 'Segundo propietario',
      email: 'segundo@prueba.cl',
      password: 'OtroPropietario2026',
      claveConfiguracion: claveSetup
    }
  });
  assert.equal(respuesta.estado, 409);

  await detenerServidor();
  iniciarServidor();
  await esperarServidor();

  base = abrirBasePrueba();
  assert.equal(
    base.prepare(`SELECT COUNT(*) AS total FROM usuarios`).get().total,
    1
  );
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM usuarios
      WHERE email IN ('admin@parkcontrol.cl', 'cajero@parkcontrol.cl')
    `).get().total,
    0
  );
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM seguridad_configuracion
      WHERE clave = 'superadmin_setup_key'
    `).get().total,
    0
  );
  base.close();

  let sesionPropietario = await login(
    'propietario@prueba.cl',
    'PropietarioSeguro2026'
  );
  assert.equal(sesionPropietario.estado, 200);
  let tokenPropietario = sesionPropietario.cuerpo.token;

  respuesta = await api('GET', '/api/superadmin/resumen', {
    token: tokenPropietario
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.totalClientes, 0);

  respuesta = await api('POST', '/api/superadmin/clientes', {
    token: tokenPropietario,
    datos: {
      ...datosCliente({
        nombre: 'Parking Zona Inválida',
        rut: '76.000.000-1',
        email: 'admin.zona.invalida@prueba.cl',
        vencimiento: '2026-08-31'
      }),
      zonaHoraria: 'America/Zona_Inexistente'
    }
  });
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /identificador IANA válido/i);

  respuesta = await api('GET', '/api/superadmin/resumen', {
    token: tokenPropietario
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.totalClientes, 0);

  const clienteA = await api('POST', '/api/superadmin/clientes', {
    token: tokenPropietario,
    datos: datosCliente({
      nombre: 'Parking Norte',
      rut: '76.111.111-1',
      email: 'admin.norte@prueba.cl',
      vencimiento: '2026-08-31'
    })
  });
  assert.equal(clienteA.estado, 201);
  const clienteAId = clienteA.cuerpo.cliente.id;

  const clienteB = await api('POST', '/api/superadmin/clientes', {
    token: tokenPropietario,
    datos: datosCliente({
      nombre: 'Parking Sur',
      rut: '76.222.222-2',
      email: 'admin.sur@prueba.cl',
      vencimiento: '2026-09-30',
      plan: 'PRO'
    })
  });
  assert.equal(clienteB.estado, 201);
  const clienteBId = clienteB.cuerpo.cliente.id;

  const sesionA = await login('admin.norte@prueba.cl', 'ClienteSeguro2026');
  const sesionB = await login('admin.sur@prueba.cl', 'ClienteSeguro2026');
  assert.equal(sesionA.estado, 200);
  assert.equal(sesionB.estado, 200);
  const tokenA = sesionA.cuerpo.token;
  const tokenB = sesionB.cuerpo.token;

  // La autenticación no acepta tokens por query string en ninguna ruta de la
  // API, no sólo en documentos PDF.
  respuesta = await api(
    'GET',
    `/api/cuenta/capacidades?access_token=${encodeURIComponent(tokenA)}`
  );
  assert.equal(respuesta.estado, 401);

  // Las capacidades se determinan en el servidor. Un Lite no puede abrir
  // funciones Pro aun si alguien intenta invocar la ruta directamente.
  respuesta = await api('GET', '/api/cuenta/capacidades', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.plan, 'LITE');
  assert.equal(respuesta.cuerpo.capacidades.boletasPdf, false);
  assert.equal(respuesta.cuerpo.capacidades.contabilidadAvanzada, false);
  assert.equal(respuesta.cuerpo.limitesUsuarios.maxAdministradores, 1);
  assert.equal(respuesta.cuerpo.limitesUsuarios.maxCajeros, 1);

  respuesta = await api('GET', '/api/cuenta/suscripcion', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.plan, 'LITE');
  assert.equal(respuesta.cuerpo.pagoAutomaticoDisponible, false);
  assert.equal(respuesta.cuerpo.proveedor, 'mercadopago');
  assert.equal(respuesta.cuerpo.estadoPagoAutomatico, 'no_configurado');
  assert.equal(respuesta.cuerpo.tarjeta, null);
  assert.equal(respuesta.cuerpo.checkoutUrl, null);

  respuesta = await api('POST', '/api/cuenta/suscripcion/checkout', {
    token: tokenA,
    datos: {}
  });
  assert.equal(respuesta.estado, 503);
  assert.equal(respuesta.cuerpo.codigo, 'PASARELA_NO_CONFIGURADA');

  respuesta = await api('GET', '/api/boletas', { token: tokenA });
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'FUNCION_NO_DISPONIBLE_PLAN');

  respuesta = await api('GET', '/api/contabilidad', { token: tokenA });
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'FUNCION_NO_DISPONIBLE_PLAN');

  respuesta = await api('GET', '/api/pro/analitica?periodo=mes', {
    token: tokenA
  });
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'FUNCION_NO_DISPONIBLE_PLAN');

  respuesta = await api(
    'GET',
    '/api/pro/analitica/comparativa?dias=90',
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'FUNCION_NO_DISPONIBLE_PLAN');

  respuesta = await api('GET', '/api/pro/alertas', { token: tokenA });
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'FUNCION_NO_DISPONIBLE_PLAN');

  respuesta = await api('GET', '/api/pro/informes-correo', {
    token: tokenA
  });
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'FUNCION_NO_DISPONIBLE_PLAN');

  const cajeroLite = await api('POST', '/api/usuarios', {
    token: tokenA,
    datos: {
      nombre: 'Cajero Lite',
      email: 'cajero.lite@prueba.cl',
      password: 'CajeroLiteSeguro2026',
      rol: 'cajero',
      registrarEntradas: true,
      registrarSalidas: true,
      verReportes: true
    }
  });
  assert.equal(cajeroLite.estado, 201);

  const sesionCajeroLite = await login(
    'cajero.lite@prueba.cl',
    'CajeroLiteSeguro2026'
  );
  assert.equal(sesionCajeroLite.estado, 200);

  respuesta = await api('GET', '/api/turnos/actual', {
    token: sesionCajeroLite.cuerpo.token
  });
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'FUNCION_NO_DISPONIBLE_PLAN');

  respuesta = await api('POST', '/api/usuarios', {
    token: tokenA,
    datos: {
      nombre: 'Segundo cajero Lite',
      email: 'cajero.lite.2@prueba.cl',
      password: 'CajeroLiteSeguro2026',
      rol: 'cajero'
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'LIMITE_USUARIOS_PLAN');

  respuesta = await api('POST', '/api/usuarios', {
    token: tokenA,
    datos: {
      nombre: 'Segundo administrador Lite',
      email: 'admin.lite.2@prueba.cl',
      password: 'AdminLiteSeguro2026',
      rol: 'admin'
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'LIMITE_USUARIOS_PLAN');

  // La cuota no reemplaza la protección básica: el único administrador
  // activo tampoco puede degradarse a cajero.
  respuesta = await api('GET', '/api/usuarios', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  const administradorLite = respuesta.cuerpo[0];
  respuesta = await api('PUT', `/api/usuarios/${administradorLite.id}`, {
    token: tokenA,
    datos: {
      nombre: administradorLite.nombre,
      email: administradorLite.email,
      rol: 'cajero',
      registrarEntradas: true,
      registrarSalidas: true,
      verReportes: true
    }
  });
  assert.equal(respuesta.estado, 403);

  respuesta = await api('PUT', `/api/superadmin/clientes/${clienteAId}`, {
    token: tokenPropietario,
    datos: { plan: 'PRO' }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.cliente.plan, 'PRO');

  respuesta = await api('GET', '/api/cuenta/capacidades', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.plan, 'PRO');
  assert.equal(respuesta.cuerpo.capacidades.boletasPdf, true);
  assert.equal(respuesta.cuerpo.capacidades.contabilidadAvanzada, true);
  assert.equal(respuesta.cuerpo.limitesUsuarios.maxAdministradores, 2);
  assert.equal(respuesta.cuerpo.limitesUsuarios.maxCajeros, 3);

  // Los informes Pro quedan aislados por estacionamiento. En el entorno de
  // pruebas el transporte externo está apagado: se permite preparar una
  // programación, pero nunca se simula un correo que no se envió.
  respuesta = await api('GET', '/api/pro/informes-correo', {
    token: tokenA
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.transporte.disponible, false);
  assert.deepEqual(respuesta.cuerpo.programaciones, []);

  respuesta = await api('POST', '/api/pro/informes-correo', {
    token: tokenA,
    datos: {
      frecuencia: 'semanal',
      horaLocal: '08:30',
      activo: true
    }
  });
  assert.equal(respuesta.estado, 201);
  const programacionCorreoAId = respuesta.cuerpo.programacion.id;
  assert.equal(respuesta.cuerpo.programacion.frecuencia, 'semanal');
  assert.equal(respuesta.cuerpo.programacion.horaLocal, '08:30');
  assert.equal(respuesta.cuerpo.programacion.activo, true);
  assert.ok(respuesta.cuerpo.programacion.correoDestino.includes('*'));
  assert.equal(
    respuesta.cuerpo.programacion.correoDestino.includes('admin.norte'),
    false
  );

  respuesta = await api('GET', '/api/pro/informes-correo', {
    token: tokenB
  });
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.programaciones, []);
  assert.deepEqual(respuesta.cuerpo.envios, []);

  respuesta = await api(
    'PATCH',
    `/api/pro/informes-correo/${programacionCorreoAId}`,
    {
      token: tokenB,
      datos: { horaLocal: '09:00' }
    }
  );
  assert.equal(respuesta.estado, 404);

  respuesta = await api(
    'POST',
    `/api/pro/informes-correo/${programacionCorreoAId}/envio-prueba`,
    {
      token: tokenA,
      claveIdempotencia: 'informe-correo-prueba-0001',
      datos: { fechaInicio: '2026-08-01', fechaFin: '2026-08-01' }
    }
  );
  assert.equal(respuesta.estado, 503);
  assert.equal(respuesta.cuerpo.codigo, 'CORREO_NO_CONFIGURADO');

  respuesta = await api(
    'DELETE',
    `/api/pro/informes-correo/${programacionCorreoAId}`,
    { token: tokenB }
  );
  assert.equal(respuesta.estado, 404);

  respuesta = await api(
    'DELETE',
    `/api/pro/informes-correo/${programacionCorreoAId}`,
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 200);

  respuesta = await api('GET', '/api/pro/informes-correo', {
    token: tokenA
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.programaciones.length, 1);
  assert.equal(respuesta.cuerpo.programaciones[0].activo, false);

  respuesta = await api('GET', '/api/pro/analitica?periodo=mes', {
    token: tokenA
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.periodo, 'mes');
  assert.ok(respuesta.cuerpo.puntos.length >= 28);
  assert.equal(respuesta.cuerpo.resumen.tasaIva, 19);

  respuesta = await api(
    'POST',
    `/api/superadmin/clientes/${clienteAId}/administradores`,
    {
      token: tokenPropietario,
      datos: {
        nombre: 'Segundo administrador Pro',
        email: 'admin.pro.2@prueba.cl',
        password: 'AdministradorProSeguro2026'
      }
    }
  );
  assert.equal(respuesta.estado, 201);

  respuesta = await api(
    'POST',
    `/api/superadmin/clientes/${clienteAId}/administradores`,
    {
      token: tokenPropietario,
      datos: {
        nombre: 'Tercer administrador Pro',
        email: 'admin.pro.3@prueba.cl',
        password: 'AdministradorProSeguro2026'
      }
    }
  );
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'LIMITE_USUARIOS_PLAN');

  for (const numero of [2, 3]) {
    respuesta = await api('POST', '/api/usuarios', {
      token: tokenA,
      datos: {
        nombre: `Cajero Pro ${numero}`,
        email: `cajero.pro.${numero}@prueba.cl`,
        password: 'CajeroProSeguro2026',
        rol: 'cajero'
      }
    });
    assert.equal(respuesta.estado, 201);
  }

  respuesta = await api('POST', '/api/usuarios', {
    token: tokenA,
    datos: {
      nombre: 'Cuarto cajero Pro',
      email: 'cajero.pro.4@prueba.cl',
      password: 'CajeroProSeguro2026',
      rol: 'cajero'
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'LIMITE_USUARIOS_PLAN');

  respuesta = await api('PUT', `/api/superadmin/clientes/${clienteAId}`, {
    token: tokenPropietario,
    datos: { plan: 'LITE' }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'LIMITE_USUARIOS_PLAN');

  // Turnos de caja: sólo Pro, una caja activa por estacionamiento y cierre
  // calculado desde las salidas persistidas por el propio cajero.
  const sesionCajeroPro = await login(
    'cajero.pro.2@prueba.cl',
    'CajeroProSeguro2026'
  );
  assert.equal(sesionCajeroPro.estado, 200);
  const tokenCajeroPro = sesionCajeroPro.cuerpo.token;

  respuesta = await api('GET', '/api/turnos/actual', {
    token: tokenCajeroPro
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno, null);

  respuesta = await api('POST', '/api/turnos/iniciar', {
    token: tokenCajeroPro,
    datos: {
      montoInicial: 1000,
      novedad: 'Fondo recibido desde el turno anterior'
    }
  });
  assert.equal(respuesta.estado, 201);
  const turnoProId = respuesta.cuerpo.turno.id;
  assert.equal(respuesta.cuerpo.turno.montoInicial, 1000);

  const sesionSegundoCajeroPro = await login(
    'cajero.pro.3@prueba.cl',
    'CajeroProSeguro2026'
  );
  assert.equal(sesionSegundoCajeroPro.estado, 200);
  respuesta = await api('POST', '/api/turnos/iniciar', {
    token: sesionSegundoCajeroPro.cuerpo.token,
    datos: { montoInicial: 0 }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'TURNO_ESTACIONAMIENTO_ABIERTO');

  respuesta = await api('POST', '/api/entradas', {
    token: tokenCajeroPro,
    claveIdempotencia: 'entrada-turno-pro-0001',
    datos: {
      patente: 'TURN001',
      tipo: 'Auto',
      color: 'Gris'
    }
  });
  assert.equal(respuesta.estado, 201);
  const movimientoTurnoId = respuesta.cuerpo.movimiento.id;

  respuesta = await api('GET', '/api/tarifa', { token: tokenCajeroPro });
  assert.equal(respuesta.estado, 200);
  const tarifaTurnoProId = respuesta.cuerpo.tarifaId;

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    claveIdempotencia: 'salida-turno-pro-0001',
    datos: {
      patente: 'TURN001',
      movimientoId: movimientoTurnoId,
      versionEsperada: 1,
      tarifaIdEsperada: tarifaTurnoProId
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.salida.monto, 10);
  assert.equal(respuesta.cuerpo.salida.metodoPago, 'efectivo');
  assert.equal(respuesta.cuerpo.salida.turnoCajaId, turnoProId);

  respuesta = await api('POST', '/api/entradas', {
    token: tokenCajeroPro,
    claveIdempotencia: 'entrada-turno-pro-0002',
    datos: {
      patente: 'TURN002',
      tipo: 'Moto',
      color: 'Azul'
    }
  });
  assert.equal(respuesta.estado, 201);
  const movimientoTransferenciaId = respuesta.cuerpo.movimiento.id;

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    claveIdempotencia: 'salida-turno-pro-0002',
    datos: {
      patente: 'TURN002',
      movimientoId: movimientoTransferenciaId,
      versionEsperada: 1,
      tarifaIdEsperada: tarifaTurnoProId,
      metodoPago: 'transferencia'
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.salida.metodoPago, 'transferencia');

  respuesta = await api('GET', '/api/turnos/actual', {
    token: tokenCajeroPro
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.id, turnoProId);
  assert.equal(respuesta.cuerpo.turno.salidas, 2);
  assert.equal(respuesta.cuerpo.turno.montoEsperado, 1010);
  assert.equal(respuesta.cuerpo.turno.montoRecaudado, 20);
  assert.equal(respuesta.cuerpo.turno.montoTransferencia, 10);

  respuesta = await api('POST', `/api/turnos/${turnoProId}/cerrar`, {
    token: tokenCajeroPro,
    datos: {
      montoDeclarado: 1010,
      novedad: 'Caja cuadrada; sin incidencias.'
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.diferencia, 0);
  assert.equal(respuesta.cuerpo.turno.estado, 'cerrado');

  respuesta = await api('GET', '/api/turnos/actual', {
    token: tokenCajeroPro
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno, null);
  assert.equal(respuesta.cuerpo.entregaAnterior.id, turnoProId);
  assert.equal(
    respuesta.cuerpo.entregaAnterior.novedadCierre,
    'Caja cuadrada; sin incidencias.'
  );

  respuesta = await api('GET', '/api/pro/turnos', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turnos[0].id, turnoProId);
  assert.equal(respuesta.cuerpo.turnos[0].montoEsperado, 1010);
  assert.equal(respuesta.cuerpo.turnos[0].montoTransferencia, 10);

  respuesta = await api(
    'GET',
    `/api/pro/turnos/${turnoProId}/vehiculos-abiertos`,
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.vehiculos, []);

  respuesta = await api(
    'GET',
    `/api/pro/turnos/${turnoProId}/vehiculos-abiertos`,
    { token: tokenB }
  );
  assert.equal(respuesta.estado, 404);

  respuesta = await api(
    'POST',
    `/api/pro/turnos/${turnoProId}/revision`,
    {
      token: tokenA,
      datos: {
        estadoRevision: 'revisado',
        observacion: 'Cierre revisado contra el resumen de caja.'
      }
    }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.estadoRevision, 'revisado');

  respuesta = await api(
    'POST',
    `/api/pro/turnos/${turnoProId}/revision`,
    {
      token: tokenA,
      datos: { estadoRevision: 'observado', observacion: 'No corresponde.' }
    }
  );
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'CIERRE_YA_REVISADO');

  respuesta = await api('GET', `/api/pro/turnos/${turnoProId}/pdf`, {
    token: tokenA
  });
  assert.equal(respuesta.estado, 200);
  assert.match(respuesta.tipo, /application\/pdf/);

  // Los PDF siguen usando el header Authorization; un token en la URL no se
  // acepta porque podría quedar expuesto en logs, historiales o referers.
  respuesta = await api(
    'GET',
    `/api/pro/turnos/${turnoProId}/pdf?access_token=${encodeURIComponent(tokenA)}`
  );
  assert.equal(respuesta.estado, 401);

  respuesta = await api('GET', `/api/pro/turnos/${turnoProId}/pdf`, {
    token: tokenB
  });
  assert.equal(respuesta.estado, 404);

  respuesta = await api(
    'GET',
    '/api/pro/auditoria-cajeros?periodo=mes',
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.resumen.turnosCerrados, 1);
  assert.equal(respuesta.cuerpo.resumen.recaudado, 20);
  assert.equal(
    respuesta.cuerpo.cajeros.find(
      cajero => cajero.email === 'cajero.pro.2@prueba.cl'
    ).cobros,
    2
  );

  // La comparativa Pro se calcula desde movimientos persistidos y no mezcla
  // información entre estacionamientos. En este punto A tiene dos entradas
  // y dos salidas; B todavía no registra actividad.
  respuesta = await api(
    'GET',
    '/api/pro/analitica/comparativa?dias=90',
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 200);
  const comparativaA = respuesta.cuerpo;
  assert.equal(comparativaA.dias, 90);
  assert.equal(comparativaA.diasSemana.length, 7);
  assert.equal(comparativaA.horas.length, 24);
  assert.deepEqual(
    comparativaA.diasSemana.map(grupo => grupo.diaSemana),
    Array.from({ length: 7 }, (_, indice) => indice)
  );
  assert.deepEqual(
    comparativaA.horas.map(grupo => grupo.hora),
    Array.from({ length: 24 }, (_, indice) => indice)
  );
  assert.deepEqual(comparativaA.resumen, {
    entradas: 2,
    salidas: 2,
    ingresos: 20,
    actividad: 4
  });
  assert.deepEqual(
    comparativaA.diasSemana.reduce((acumulado, grupo) => ({
      entradas: acumulado.entradas + grupo.entradas,
      salidas: acumulado.salidas + grupo.salidas,
      ingresos: acumulado.ingresos + grupo.ingresos,
      actividad: acumulado.actividad + grupo.actividad
    }), { entradas: 0, salidas: 0, ingresos: 0, actividad: 0 }),
    comparativaA.resumen
  );
  assert.deepEqual(
    comparativaA.horas.reduce((acumulado, grupo) => ({
      entradas: acumulado.entradas + grupo.entradas,
      salidas: acumulado.salidas + grupo.salidas,
      ingresos: acumulado.ingresos + grupo.ingresos,
      actividad: acumulado.actividad + grupo.actividad
    }), { entradas: 0, salidas: 0, ingresos: 0, actividad: 0 }),
    comparativaA.resumen
  );
  for (const destacado of Object.values(comparativaA.destacados)) {
    assert.ok(destacado);
    assert.ok(destacado.actividad > 0);
  }

  for (const dias of [30, 365]) {
    respuesta = await api(
      'GET',
      `/api/pro/analitica/comparativa?dias=${dias}`,
      { token: tokenA }
    );
    assert.equal(respuesta.estado, 200);
    assert.equal(respuesta.cuerpo.dias, dias);
    assert.equal(respuesta.cuerpo.resumen.salidas, 2);
  }

  for (const diasInvalidos of ['7', '90.0']) {
    respuesta = await api(
      'GET',
      `/api/pro/analitica/comparativa?dias=${diasInvalidos}`,
      { token: tokenA }
    );
    assert.equal(respuesta.estado, 400);
    assert.equal(respuesta.cuerpo.codigo, 'DIAS_COMPARATIVA_INVALIDO');
  }

  respuesta = await api(
    'GET',
    '/api/pro/analitica/comparativa?dias=90',
    { token: tokenB }
  );
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.resumen, {
    entradas: 0,
    salidas: 0,
    ingresos: 0,
    actividad: 0
  });
  assert.ok(respuesta.cuerpo.diasSemana.every(grupo =>
    grupo.entradas === 0 &&
    grupo.salidas === 0 &&
    grupo.ingresos === 0 &&
    grupo.actividad === 0
  ));
  assert.ok(respuesta.cuerpo.horas.every(grupo =>
    grupo.entradas === 0 &&
    grupo.salidas === 0 &&
    grupo.ingresos === 0 &&
    grupo.actividad === 0
  ));
  assert.ok(
    Object.values(respuesta.cuerpo.destacados).every(
      destacado => destacado === null
    )
  );

  // Los filtros contables son días civiles del estacionamiento, no del huso
  // horario del VPS. Pacific/Kiritimati está 14 horas adelantado a UTC: el
  // cierre UTC del 1 de agosto corresponde al 2 de agosto para este cliente.
  respuesta = await api('PUT', `/api/superadmin/clientes/${clienteAId}`, {
    token: tokenPropietario,
    datos: { zonaHoraria: 'Pacific/Kiritimati' }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.cliente.zonaHoraria, 'Pacific/Kiritimati');

  const baseContabilidadZona = new Database(RUTA_DB_PRUEBA, {
    timeout: 5000
  });
  baseContabilidadZona.prepare(`
    INSERT INTO movimientos
    (
      estacionamiento_id,
      patente,
      tipo,
      color,
      observacion,
      hora_entrada,
      hora_salida,
      minutos,
      tarifa_por_minuto,
      monto,
      metodo_pago,
      estado,
      version
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'salio', ?)
  `).run(
    clienteAId,
    'ZONA01',
    'Auto',
    'Blanco',
    'Prueba de día local',
    '2026-08-01T10:30:00.000Z',
    '2026-08-01T12:30:00.000Z',
    120,
    10,
    99,
    'efectivo',
    1
  );
  baseContabilidadZona.close();

  respuesta = await api(
    'GET',
    '/api/contabilidad?fechaInicio=2026-08-02&fechaFin=2026-08-02',
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.zonaHoraria, 'Pacific/Kiritimati');
  assert.ok(respuesta.cuerpo.registros.some(
    registro => registro.patente === 'ZONA01'
  ));

  respuesta = await api(
    'GET',
    '/api/contabilidad?fechaInicio=2026-08-01&fechaFin=2026-08-01',
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.registros.some(
    registro => registro.patente === 'ZONA01'
  ), false);

  respuesta = await api(
    'GET',
    '/api/contabilidad?fechaInicio=2026-08-02&fechaFin=2026-08-02',
    { token: tokenB }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.registros.some(
    registro => registro.patente === 'ZONA01'
  ), false);

  respuesta = await api(
    'GET',
    '/api/contabilidad?fechaInicio=2026-02-30',
    { token: tokenA }
  );
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /fecha válida/);

  // Las alertas administrativas Pro nacen desde un cierre con diferencia,
  // permanecen aisladas por estacionamiento y registran su revisión.
  respuesta = await api('POST', '/api/turnos/iniciar', {
    token: tokenCajeroPro,
    datos: { montoInicial: 100 }
  });
  assert.equal(respuesta.estado, 201);
  const turnoConFaltanteId = respuesta.cuerpo.turno.id;

  respuesta = await api('POST', `/api/turnos/${turnoConFaltanteId}/cerrar`, {
    token: tokenCajeroPro,
    datos: {
      montoDeclarado: 90,
      novedad: 'Faltante detectado al entregar el turno.'
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.diferencia, -10);

  respuesta = await api('GET', '/api/pro/alertas', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.resumen, {
    pendientes: 1,
    criticas: 1,
    revisadas: 0,
    resueltas: 0
  });
  const alertaFaltante = respuesta.cuerpo.alertas.find(
    alerta => alerta.entidadId === turnoConFaltanteId
  );
  assert.ok(alertaFaltante);
  assert.equal(alertaFaltante.tipo, 'CIERRE_CON_DIFERENCIA');
  assert.equal(alertaFaltante.severidad, 'alta');
  assert.equal(alertaFaltante.estado, 'pendiente');
  assert.equal(alertaFaltante.montoDiferencia, -10);

  respuesta = await api('GET', '/api/pro/alertas', { token: tokenB });
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.resumen, {
    pendientes: 0,
    criticas: 0,
    revisadas: 0,
    resueltas: 0
  });
  assert.deepEqual(respuesta.cuerpo.alertas, []);

  respuesta = await api(
    'POST',
    `/api/pro/turnos/${turnoConFaltanteId}/revision`,
    {
      token: tokenA,
      datos: {
        estadoRevision: 'observado',
        observacion: 'Debe verificarse el faltante con el cajero.'
      }
    }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.estadoRevision, 'observado');

  respuesta = await api('GET', '/api/pro/alertas', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.resumen, {
    pendientes: 0,
    criticas: 0,
    revisadas: 1,
    resueltas: 0
  });
  const alertaRevisada = respuesta.cuerpo.alertas.find(
    alerta => alerta.id === alertaFaltante.id
  );
  assert.equal(alertaRevisada.estado, 'revisada');
  assert.equal(
    alertaRevisada.observacionRevision,
    'Debe verificarse el faltante con el cajero.'
  );
  assert.ok(alertaRevisada.revisadaEn);
  assert.ok(alertaRevisada.revisadaPorUsuarioId);
  assert.equal(alertaRevisada.resueltaEn, null);

  respuesta = await api('POST', '/api/turnos/iniciar', {
    token: tokenCajeroPro,
    datos: { montoInicial: 100 }
  });
  assert.equal(respuesta.estado, 201);
  const turnoConSobranteId = respuesta.cuerpo.turno.id;

  respuesta = await api('POST', `/api/turnos/${turnoConSobranteId}/cerrar`, {
    token: tokenCajeroPro,
    datos: {
      montoDeclarado: 110,
      novedad: 'Sobrante detectado al entregar el turno.'
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.diferencia, 10);

  respuesta = await api(
    'POST',
    `/api/pro/turnos/${turnoConSobranteId}/revision`,
    {
      token: tokenA,
      datos: {
        estadoRevision: 'revisado',
        observacion: 'Sobrante conciliado con el cierre de caja.'
      }
    }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.estadoRevision, 'revisado');

  respuesta = await api('GET', '/api/pro/alertas', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.resumen, {
    pendientes: 0,
    criticas: 0,
    revisadas: 1,
    resueltas: 1
  });
  const alertaResuelta = respuesta.cuerpo.alertas.find(
    alerta => alerta.entidadId === turnoConSobranteId
  );
  assert.ok(alertaResuelta);
  assert.equal(alertaResuelta.estado, 'resuelta');
  assert.equal(alertaResuelta.montoDiferencia, 10);
  assert.equal(
    alertaResuelta.observacionRevision,
    'Sobrante conciliado con el cierre de caja.'
  );
  assert.ok(alertaResuelta.revisadaEn);
  assert.ok(alertaResuelta.resueltaEn);
  assert.ok(alertaResuelta.resueltaPorUsuarioId);

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    claveIdempotencia: 'corta',
    datos: {
      patente: 'BADKEY',
      tipo: 'Auto',
      color: 'Negro'
    }
  });
  assert.equal(respuesta.estado, 400);
  assert.equal(
    respuesta.cuerpo.codigo,
    'CLAVE_IDEMPOTENCIA_INVALIDA'
  );

  respuesta = await api('GET', '/api/usuarios', { token: tokenA });
  assert.equal(respuesta.estado, 200);
  const adminA = respuesta.cuerpo[0];
  respuesta = await api('PUT', `/api/usuarios/${adminA.id}`, {
    token: tokenA,
    datos: {
      nombre: adminA.nombre,
      email: adminA.email,
      rol: 'cajero',
      registrarEntradas: true,
      registrarSalidas: true,
      verReportes: true
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'LIMITE_USUARIOS_PLAN');

  const claveEntradaCompartida = 'entrada-compartida-0001';

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    claveIdempotencia: claveEntradaCompartida,
    datos: {
      patente: 'SAME01',
      tipo: 'Auto',
      color: 'Rojo',
      observacion: 'Cliente norte'
    }
  });
  assert.equal(respuesta.estado, 201);
  const entradaAId = respuesta.cuerpo.movimiento.id;
  assert.equal(respuesta.idempotenciaReutilizada, false);

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    claveIdempotencia: claveEntradaCompartida,
    datos: {
      patente: 'SAME01',
      tipo: 'Auto',
      color: 'Rojo',
      observacion: 'Cliente norte'
    }
  });
  assert.equal(respuesta.estado, 201);
  assert.equal(respuesta.cuerpo.movimiento.id, entradaAId);
  assert.equal(respuesta.idempotenciaReutilizada, true);

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    claveIdempotencia: claveEntradaCompartida,
    datos: {
      patente: 'OTRA01',
      tipo: 'Auto',
      color: 'Negro',
      observacion: 'Reutilización inválida'
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(
    respuesta.cuerpo.codigo,
    'CLAVE_IDEMPOTENCIA_REUTILIZADA'
  );

  respuesta = await api('POST', '/api/entradas', {
    token: tokenB,
    claveIdempotencia: claveEntradaCompartida,
    datos: {
      patente: 'SAME01',
      tipo: 'Auto',
      color: 'Azul',
      observacion: 'Cliente sur'
    }
  });
  assert.equal(respuesta.estado, 201);

  let estadoSincronizacionA = await api(
    'GET',
    '/api/sincronizacion/estado',
    { token: tokenA }
  );
  let estadoSincronizacionB = await api(
    'GET',
    '/api/sincronizacion/estado',
    { token: tokenB }
  );
  assert.equal(estadoSincronizacionA.estado, 200);
  assert.equal(estadoSincronizacionB.estado, 200);
  assert.equal(
    estadoSincronizacionA.cuerpo.estacionamientoId,
    clienteAId
  );
  assert.equal(
    estadoSincronizacionB.cuerpo.estacionamientoId,
    clienteBId
  );
  assert.deepEqual(
    estadoSincronizacionA.cuerpo.movimientos.map(item => item.patente),
    ['SAME01']
  );
  assert.deepEqual(
    estadoSincronizacionB.cuerpo.movimientos.map(item => item.patente),
    ['SAME01']
  );
  assert.equal(estadoSincronizacionA.cuerpo.movimientos[0].version, 1);
  assert.notEqual(
    estadoSincronizacionA.cuerpo.tarifa.id,
    estadoSincronizacionB.cuerpo.tarifa.id
  );

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    claveIdempotencia: 'entrada-modificar-0001',
    datos: {
      patente: 'MOD001',
      tipo: 'Moto',
      color: 'Negro',
      observacion: 'Antes de modificar'
    }
  });
  assert.equal(respuesta.estado, 201);
  const movimientoModificableId = respuesta.cuerpo.movimiento.id;

  const datosModificacion = {
    patente: 'MOD002',
    tipo: 'Moto',
    color: 'Verde',
    observacion: 'Después de modificar'
  };
  respuesta = await api('PUT', '/api/modificar/MOD001', {
    token: tokenA,
    claveIdempotencia: 'modificacion-vehiculo-0001',
    datos: {
      ...datosModificacion,
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.registro.patente, 'MOD002');
  assert.equal(respuesta.cuerpo.registro.version, 2);
  assert.equal(respuesta.idempotenciaReutilizada, false);

  respuesta = await api('PUT', '/api/modificar/MOD001', {
    token: tokenA,
    claveIdempotencia: 'modificacion-vehiculo-0001',
    datos: {
      ...datosModificacion,
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.registro.patente, 'MOD002');
  assert.equal(respuesta.idempotenciaReutilizada, true);

  respuesta = await api('PUT', '/api/modificar/MOD001', {
    token: tokenA,
    claveIdempotencia: 'modificacion-vehiculo-0001',
    datos: {
      ...datosModificacion,
      color: 'Azul',
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(
    respuesta.cuerpo.codigo,
    'CLAVE_IDEMPOTENCIA_REUTILIZADA'
  );

  respuesta = await api('DELETE', '/api/modificar/MOD002', {
    token: tokenA,
    claveIdempotencia: 'eliminacion-desactualizada-0001',
    datos: { versionEsperada: 1 }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'MOVIMIENTO_DESACTUALIZADO');

  respuesta = await api('DELETE', '/api/modificar/MOD002', {
    token: tokenA,
    claveIdempotencia: 'eliminacion-vehiculo-0001',
    datos: { versionEsperada: 2 }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.idempotenciaReutilizada, false);

  respuesta = await api('DELETE', '/api/modificar/MOD002', {
    token: tokenA,
    claveIdempotencia: 'eliminacion-vehiculo-0001',
    datos: { versionEsperada: 2 }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.idempotenciaReutilizada, true);

  respuesta = await api('POST', '/api/sincronizacion/conflictos/resolver', {
    token: tokenCajeroPro,
    datos: {
      claveOperacion: 'salida-pro-revision-0001',
      accion: 'descartar_operacion_local',
      tipo: 'salida',
      estado: 'conflicto',
      metodo: 'POST',
      ruta: '/api/salidas',
      patente: 'SAME01',
      motivo: 'El cajero no puede descartar dinero por su cuenta'
    }
  });
  assert.equal(respuesta.estado, 403);
  assert.equal(
    respuesta.cuerpo.codigo,
    'REVISION_ADMINISTRATIVA_REQUERIDA'
  );

  base = abrirBasePrueba();
  assert.equal(
    base.prepare(`
      SELECT estado
      FROM movimientos
      WHERE id = ?
    `).get(movimientoModificableId).estado,
    'eliminado'
  );
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM auditoria
      WHERE movimiento_id = ?
        AND accion = 'MODIFICACION'
    `).get(movimientoModificableId).total,
    1
  );
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM auditoria
      WHERE movimiento_id = ?
        AND accion = 'ELIMINACION'
    `).get(movimientoModificableId).total,
    1
  );
  base.close();

  const dentroA = await api('GET', '/api/vehiculos-dentro', { token: tokenA });
  const dentroB = await api('GET', '/api/vehiculos-dentro', { token: tokenB });
  assert.equal(dentroA.cuerpo.length, 1);
  assert.equal(dentroB.cuerpo.length, 1);
  assert.equal(dentroA.cuerpo[0].color, 'Rojo');
  assert.equal(dentroB.cuerpo[0].color, 'Azul');

  // En Pro un cobro no puede quedar fuera de una caja. El administrador
  // tampoco puede usar silenciosamente el turno de un cajero distinto.
  respuesta = await api('POST', '/api/salidas', {
    token: tokenA,
    datos: {
      patente: 'SAME01',
      movimientoId: entradaAId,
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'TURNO_CAJA_REQUERIDO');

  respuesta = await api('POST', '/api/turnos/iniciar', {
    token: tokenCajeroPro,
    datos: { montoInicial: 0, novedad: 'Turno de pruebas de integridad.' }
  });
  assert.equal(respuesta.estado, 201);
  const turnoIntegridadId = respuesta.cuerpo.turno.id;
  assert.equal(respuesta.cuerpo.turno.versionConciliacion, 2);

  respuesta = await api('POST', '/api/salidas', {
    token: tokenA,
    datos: {
      patente: 'SAME01',
      movimientoId: entradaAId,
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 403);
  assert.equal(respuesta.cuerpo.codigo, 'TURNO_DE_OTRO_CAJERO');

  const tarifaAnteriorA = estadoSincronizacionA.cuerpo.tarifa;
  respuesta = await api('PUT', '/api/tarifa', {
    token: tokenA,
    datos: { tarifaPorMinuto: 11 }
  });
  assert.equal(respuesta.estado, 200);

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    claveIdempotencia: 'salida-tarifa-antigua-0001',
    datos: {
      patente: 'SAME01',
      movimientoId: entradaAId,
      versionEsperada: 1,
      tarifaIdEsperada: tarifaAnteriorA.id
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'TARIFA_DESACTUALIZADA');

  respuesta = await api('POST', '/api/sincronizacion/conflictos/resolver', {
    token: tokenA,
    claveIdempotencia: 'salida-tarifa-antigua-0001',
    datos: {
      claveOperacion: 'salida-tarifa-antigua-0001',
      accion: 'descartar_operacion_local',
      tipo: 'salida',
      estado: 'conflicto',
      metodo: 'POST',
      ruta: '/api/salidas',
      patente: 'SAME01',
      ultimoError: 'TARIFA_DESACTUALIZADA',
      motivo: 'Se descarta operación local para recalcular con tarifa vigente'
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.idempotenciaReutilizada, false);

  respuesta = await api('POST', '/api/sincronizacion/conflictos/resolver', {
    token: tokenA,
    claveIdempotencia: 'salida-tarifa-antigua-0001',
    datos: {
      claveOperacion: 'salida-tarifa-antigua-0001',
      accion: 'descartar_operacion_local',
      tipo: 'salida',
      estado: 'conflicto',
      metodo: 'POST',
      ruta: '/api/salidas',
      patente: 'SAME01',
      ultimoError: 'TARIFA_DESACTUALIZADA',
      motivo: 'Se descarta operación local para recalcular con tarifa vigente'
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.idempotenciaReutilizada, true);

  base = abrirBasePrueba();
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM auditoria
      WHERE estacionamiento_id = ?
        AND accion = 'CONFLICTO_OFFLINE_DESCARTADO'
        AND patente_anterior = 'SAME01'
    `).get(clienteAId).total,
    1
  );
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM auditoria_sistema
      WHERE accion = 'conflicto_offline_descartado'
        AND entidad = 'operacion_offline'
    `).get().total,
    0
  );
  base.close();

  respuesta = await api('POST', '/api/sincronizacion/conflictos/resolver', {
    token: tokenA,
    datos: {
      claveOperacion: 'operacion-pendiente-0001',
      accion: 'descartar_operacion_local',
      tipo: 'salida',
      estado: 'pendiente',
      metodo: 'POST',
      ruta: '/api/salidas',
      motivo: 'Intento inválido'
    }
  });
  assert.equal(respuesta.estado, 400);
  assert.equal(respuesta.cuerpo.codigo, 'ESTADO_CONFLICTO_REQUERIDO');

  estadoSincronizacionA = await api(
    'GET',
    '/api/sincronizacion/estado',
    { token: tokenA }
  );
  assert.equal(estadoSincronizacionA.cuerpo.movimientos.length, 1);
  assert.notEqual(
    estadoSincronizacionA.cuerpo.tarifa.id,
    tarifaAnteriorA.id
  );

  const claveSalidaA = 'salida-norte-0001';

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    claveIdempotencia: claveSalidaA,
    datos: {
      patente: 'SAME01',
      movimientoId: entradaAId,
      versionEsperada: 1,
      tarifaIdEsperada: estadoSincronizacionA.cuerpo.tarifa.id
    }
  });
  assert.equal(respuesta.estado, 200);
  const boletaAId = respuesta.cuerpo.salida.id;
  const salidaAOriginal = respuesta.cuerpo.salida;

  respuesta = await api('GET', `/api/boletas/${boletaAId}/pdf`, {
    token: tokenA
  });
  assert.equal(respuesta.estado, 200);
  assert.match(respuesta.tipo, /application\/pdf/);

  respuesta = await api(
    'GET',
    `/api/boletas/${boletaAId}/pdf?access_token=${encodeURIComponent(tokenA)}`
  );
  assert.equal(respuesta.estado, 401);

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    claveIdempotencia: claveSalidaA,
    datos: {
      patente: 'SAME01',
      movimientoId: entradaAId,
      versionEsperada: 1,
      tarifaIdEsperada: estadoSincronizacionA.cuerpo.tarifa.id
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.salida, salidaAOriginal);
  assert.equal(respuesta.idempotenciaReutilizada, true);

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    claveIdempotencia: claveSalidaA,
    datos: {
      patente: 'OTRA01',
      movimientoId: entradaAId,
      versionEsperada: 1,
      tarifaIdEsperada: estadoSincronizacionA.cuerpo.tarifa.id
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(
    respuesta.cuerpo.codigo,
    'CLAVE_IDEMPOTENCIA_REUTILIZADA'
  );

  await detenerServidor();
  iniciarServidor();
  await esperarServidor();

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    claveIdempotencia: claveSalidaA,
    datos: {
      patente: 'SAME01',
      movimientoId: entradaAId,
      versionEsperada: 1,
      tarifaIdEsperada: estadoSincronizacionA.cuerpo.tarifa.id
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.deepEqual(respuesta.cuerpo.salida, salidaAOriginal);
  assert.equal(respuesta.idempotenciaReutilizada, true);

  respuesta = await api('PUT', '/api/modificar/MOD001', {
    token: tokenA,
    claveIdempotencia: 'modificacion-vehiculo-0001',
    datos: {
      ...datosModificacion,
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.registro.patente, 'MOD002');
  assert.equal(respuesta.idempotenciaReutilizada, true);

  respuesta = await api('DELETE', '/api/modificar/MOD002', {
    token: tokenA,
    claveIdempotencia: 'eliminacion-vehiculo-0001',
    datos: { versionEsperada: 2 }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.idempotenciaReutilizada, true);

  respuesta = await api('GET', `/api/boletas/${boletaAId}`, { token: tokenB });
  assert.equal(respuesta.estado, 404);

  base = abrirBasePrueba();
  const filasAntes = base.prepare(`
    SELECT COUNT(*) AS total
    FROM movimientos
    WHERE estacionamiento_id = ?
  `).get(clienteBId).total;
  const operacionesIdempotentes = base.prepare(`
    SELECT estacionamiento_id, tipo, COUNT(*) AS total
    FROM operaciones_idempotentes
    GROUP BY estacionamiento_id, tipo
    ORDER BY estacionamiento_id, tipo
  `).all();
  base.close();
  assert.deepEqual(
    operacionesIdempotentes,
    [
      { estacionamiento_id: clienteAId, tipo: 'eliminacion', total: 1 },
      { estacionamiento_id: clienteAId, tipo: 'entrada', total: 4 },
      { estacionamiento_id: clienteAId, tipo: 'modificacion', total: 1 },
      {
        estacionamiento_id: clienteAId,
        tipo: 'resolucion_conflicto_offline',
        total: 1
      },
      { estacionamiento_id: clienteAId, tipo: 'salida', total: 3 },
      { estacionamiento_id: clienteBId, tipo: 'entrada', total: 1 }
    ]
  );

  // El reloj local queda sólo como trazabilidad; los cálculos oficiales y la
  // conciliación usan la recepción del servidor. Así una fecha manipulada no
  // puede cambiar ingresos, reportes ni el turno asignado.
  const fechaEntradaReportada =
    new Date(Date.now() - 20 * 24 * 60 * 60000);
  const horaEntradaReportada =
    fechaEntradaReportada.toISOString();
  const horaSalidaReportada =
    new Date(
      fechaEntradaReportada.getTime() + 30 * 60000
    ).toISOString();

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    datos: {
      patente: 'TIME01',
      tipo: 'Auto',
      color: 'Blanco',
      observacion: 'Prueba de hora reportada',
      horaEntradaCliente: horaEntradaReportada
    }
  });
  assert.equal(respuesta.estado, 201);
  const movimientoTiempoId = respuesta.cuerpo.movimiento.id;
  assert.notEqual(respuesta.cuerpo.movimiento.horaEntrada, horaEntradaReportada);
  assert.equal(
    respuesta.cuerpo.movimiento.horaEntradaReportada,
    horaEntradaReportada
  );
  assert.ok(respuesta.cuerpo.movimiento.entradaRecibidaEn);

  // Las salidas Pro offline v1 no se asignan de forma ambigua a un turno.
  // Quedan en conflicto hasta que exista el protocolo de lease v2.
  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    datos: {
      patente: 'TIME01',
      movimientoId: movimientoTiempoId,
      versionEsperada: 1,
      horaSalidaCliente: horaSalidaReportada,
      origenOperacion: 'offline_v1'
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(
    respuesta.cuerpo.codigo,
    'SALIDA_OFFLINE_PRO_REQUIERE_REVISION'
  );

  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    datos: {
      patente: 'TIME01',
      movimientoId: movimientoTiempoId,
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.salida.horaSalidaReportada, null);
  assert.equal(respuesta.cuerpo.salida.origenSalida, 'online');
  assert.equal(respuesta.cuerpo.salida.turnoCajaId, turnoIntegridadId);

  base = abrirBasePrueba();
  const salidaVinculada = base.prepare(`
    SELECT turno_caja_id, origen_salida, hora_salida_reportada
    FROM movimientos
    WHERE id = ? AND estacionamiento_id = ?
  `).get(movimientoTiempoId, clienteAId);
  base.close();
  assert.deepEqual(salidaVinculada, {
    turno_caja_id: turnoIntegridadId,
    origen_salida: 'online',
    hora_salida_reportada: null
  });

  respuesta = await api('POST', `/api/turnos/${turnoIntegridadId}/cerrar`, {
    token: tokenCajeroPro,
    datos: { montoDeclarado: 22, novedad: 'Cierre de prueba vinculado.' }
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.turno.montoRecaudado, 22);
  assert.equal(respuesta.cuerpo.turno.salidas, null);

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    datos: { patente: 'POSTTURN', tipo: 'Auto', color: 'Verde' }
  });
  assert.equal(respuesta.estado, 201);
  respuesta = await api('POST', '/api/salidas', {
    token: tokenCajeroPro,
    datos: {
      patente: 'POSTTURN',
      movimientoId: respuesta.cuerpo.movimiento.id,
      versionEsperada: 1
    }
  });
  assert.equal(respuesta.estado, 409);
  assert.equal(respuesta.cuerpo.codigo, 'TURNO_CAJA_REQUERIDO');

  respuesta = await api('POST', '/api/entradas', {
    token: tokenA,
    datos: {
      patente: 'FUTURE1',
      tipo: 'Auto',
      color: 'Blanco',
      horaEntradaCliente:
        new Date(Date.now() + 10 * 60000).toISOString()
    }
  });
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /futuro/);

  respuesta = await api('DELETE', '/api/modificar/SAME01', { token: tokenB });
  assert.equal(respuesta.estado, 200);

  base = abrirBasePrueba();
  const movimientoEliminado = base.prepare(`
    SELECT estado
    FROM movimientos
    WHERE estacionamiento_id = ? AND patente = 'SAME01'
    ORDER BY id DESC
    LIMIT 1
  `).get(clienteBId);
  const filasDespues = base.prepare(`
    SELECT COUNT(*) AS total
    FROM movimientos
    WHERE estacionamiento_id = ?
  `).get(clienteBId).total;
  base.close();
  assert.equal(filasDespues, filasAntes);
  assert.equal(movimientoEliminado.estado, 'eliminado');

  const pagoB1 = await api(
    'POST',
    `/api/superadmin/clientes/${clienteBId}/pagos`,
    {
      token: tokenPropietario,
      datos: {
        monto: 10000,
        metodo: 'efectivo',
        fechaPago: '2026-08-18',
        periodoDesde: '2026-09-30',
        periodoHasta: '2026-10-31',
        reactivar: false
      }
    }
  );
  assert.equal(pagoB1.estado, 201);

  const pagoB2 = await api(
    'POST',
    `/api/superadmin/clientes/${clienteBId}/pagos`,
    {
      token: tokenPropietario,
      datos: {
        monto: 12000,
        metodo: 'transferencia',
        fechaPago: '2026-08-18',
        periodoDesde: '2026-10-31',
        periodoHasta: '2026-11-30',
        reactivar: false
      }
    }
  );
  assert.equal(pagoB2.estado, 201);

  respuesta = await api(
    'POST',
    `/api/superadmin/clientes/${clienteBId}/pagos/${pagoB1.cuerpo.pago.id}/anular`,
    {
      token: tokenPropietario,
      datos: { motivo: 'Intento fuera de orden' }
    }
  );
  assert.equal(respuesta.estado, 409);

  respuesta = await api(
    'POST',
    `/api/superadmin/clientes/${clienteBId}/pagos/${pagoB2.cuerpo.pago.id}/anular`,
    {
      token: tokenPropietario,
      datos: { motivo: 'Deshacer pago más reciente' }
    }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.efectosComercialesRestaurados, true);
  assert.match(respuesta.cuerpo.cliente.fechaVencimiento, /^2026-10-31/);

  respuesta = await api(
    'POST',
    `/api/superadmin/clientes/${clienteBId}/pagos/${pagoB1.cuerpo.pago.id}/anular`,
    {
      token: tokenPropietario,
      datos: { motivo: 'Deshacer primer pago' }
    }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.efectosComercialesRestaurados, true);
  assert.match(respuesta.cuerpo.cliente.fechaVencimiento, /^2026-09-30/);

  respuesta = await api(
    'PATCH',
    `/api/superadmin/clientes/${clienteAId}/estado`,
    {
      token: tokenPropietario,
      datos: { estado: 'suspendido', motivo: 'Pago pendiente' }
    }
  );
  assert.equal(respuesta.estado, 200);

  respuesta = await api('GET', '/api/resumen', { token: tokenA });
  assert.equal(respuesta.estado, 403);

  const pago = await api(
    'POST',
    `/api/superadmin/clientes/${clienteAId}/pagos`,
    {
      token: tokenPropietario,
      datos: {
        monto: 35000,
        metodo: 'transferencia',
        referencia: 'TRX-PRUEBA-001',
        observacion: 'Mensualidad de prueba',
        fechaPago: '2026-08-18',
        periodoDesde: '2026-08-31',
        periodoHasta: '2026-09-30',
        reactivar: true
      }
    }
  );
  assert.equal(pago.estado, 201);
  assert.equal(pago.cuerpo.cliente.estado, 'activo');
  assert.match(pago.cuerpo.cliente.fechaVencimiento, /^2026-09-30/);

  const sesionAReactivada = await login(
    'admin.norte@prueba.cl',
    'ClienteSeguro2026'
  );
  assert.equal(sesionAReactivada.estado, 200);

  respuesta = await api(
    'POST',
    `/api/superadmin/clientes/${clienteAId}/pagos/${pago.cuerpo.pago.id}/anular`,
    {
      token: tokenPropietario,
      datos: { motivo: 'Comprobante ingresado por error' }
    }
  );
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.efectosComercialesRestaurados, true);
  assert.equal(respuesta.cuerpo.cliente.estado, 'suspendido');
  assert.match(respuesta.cuerpo.cliente.fechaVencimiento, /^2026-08-31/);

  respuesta = await api('GET', '/api/resumen', {
    token: sesionAReactivada.cuerpo.token
  });
  assert.equal(respuesta.estado, 403);

  respuesta = await api('GET', '/api/superadmin/resumen', {
    token: tokenPropietario
  });
  assert.equal(respuesta.estado, 200);
  assert.equal(respuesta.cuerpo.ingresosMes, 0);
  assert.equal(respuesta.cuerpo.totalClientes, 2);

  respuesta = await api('PATCH', '/api/cuenta/password', {
    token: tokenPropietario,
    datos: {
      passwordActual: 'PropietarioSeguro2026',
      passwordNueva: 'PropietarioNuevo2026'
    }
  });
  assert.equal(respuesta.estado, 200);

  respuesta = await api('GET', '/api/superadmin/resumen', {
    token: tokenPropietario
  });
  assert.equal(respuesta.estado, 401);
  sesionPropietario = await login(
    'propietario@prueba.cl',
    'PropietarioNuevo2026'
  );
  assert.equal(sesionPropietario.estado, 200);
  tokenPropietario = sesionPropietario.cuerpo.token;

  // Modo Soporte Delegado de SuperAdmin
  const motivoSoporte = 'Auditoría y soporte administrativo a estacionamiento B';
  respuesta = await api(
    'POST',
    `/api/superadmin/clientes/${clienteBId}/entrar-soporte`,
    {
      token: tokenPropietario,
      datos: { motivo: motivoSoporte }
    }
  );
  assert.equal(respuesta.estado, 200, 'Debe autorizar el acceso en modo soporte');
  assert.equal(respuesta.cuerpo.usuario.esSuperadminDelegado, true);
  const tokenSoporte = respuesta.cuerpo.token;

  // Acceder a endpoints operativos con el token de soporte
  const resumenSoporte = await api('GET', '/api/resumen', { token: tokenSoporte });
  assert.equal(resumenSoporte.estado, 200, 'Debe acceder a /api/resumen');

  const auditoriaSoporte = await api('GET', '/api/auditoria', { token: tokenSoporte });
  assert.equal(auditoriaSoporte.estado, 200, 'Debe acceder a /api/auditoria');

  respuesta = await api('GET', '/api/superadmin/auditoria', {
    token: tokenPropietario
  });
  assert.equal(respuesta.estado, 200);
  assert.ok(respuesta.cuerpo.auditoria.length >= 8);
  const eventoSoporte = respuesta.cuerpo.auditoria.find(
    a => a.accion === 'SOPORTE_ACCESO_ESTACIONAMIENTO' && a.entidadId === clienteBId
  );
  assert.ok(eventoSoporte, 'El acceso en modo soporte debe estar registrado en auditoría');
  assert.equal(eventoSoporte.motivo, motivoSoporte);

  base = abrirBasePrueba();
  assert.equal(base.pragma('quick_check', { simple: true }), 'ok');
  assert.deepEqual(base.pragma('foreign_key_check'), []);
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM movimientos
      WHERE estado NOT IN ('dentro', 'salio', 'eliminado')
    `).get().total,
    0
  );
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM movimientos
      WHERE patente = 'BADKEY'
    `).get().total,
    0
  );
  assert.equal(
    base.prepare(`
      SELECT COUNT(*) AS total
      FROM estacionamientos
      WHERE visible_superadmin = 1
    `).get().total,
    2
  );
  base.close();

  console.log('Prueba SuperAdministrador completada correctamente.');
}

(async () => {
  try {
    await ejecutar();
  } catch (error) {
    console.error(error);
    if (salidaServidor) {
      console.error('\nSalida del servidor de prueba:\n', salidaServidor);
    }
    process.exitCode = 1;
  } finally {
    await detenerServidor();
    limpiarTemporal();
  }
})();
