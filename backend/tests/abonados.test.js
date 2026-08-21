const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const PUERTO_PRUEBA = 31920;
const URL_BASE = `http://127.0.0.1:${PUERTO_PRUEBA}`;
const DIRECTORIO_TEMPORAL = fs.mkdtempSync(
  path.join(os.tmpdir(), 'parkcontrol-abonados-')
);
const RUTA_DB_PRUEBA = path.join(
  DIRECTORIO_TEMPORAL,
  'parkcontrol-abonados.db'
);

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
      PARKCONTROL_ALLOW_SETUP: 'false',
      PARKCONTROL_CREAR_USUARIOS_DEMO: 'true',
      PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado'
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

async function esperarServidor() {
  const limite = Date.now() + 10000;

  while (Date.now() < limite) {
    if (servidor.exitCode != null) {
      throw new Error(`El servidor terminó antes de iniciar:\n${salidaServidor}`);
    }

    try {
      const respuesta = await fetch(`${URL_BASE}/api/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'test@ping.com', password: '123' })
      });
      if (respuesta.status === 401) {
        return;
      }
    } catch (_) {
      // esperando inicialización
    }

    await new Promise(resolve => setTimeout(resolve, 100));
  }

  throw new Error(`El servidor de prueba no respondió:\n${salidaServidor}`);
}

async function detenerServidor() {
  if (servidor && !servidor.killed) {
    servidor.kill();
  }
  try {
    fs.rmSync(DIRECTORIO_TEMPORAL, { recursive: true, force: true });
  } catch (_) {}
}

async function solicitud(ruta, opciones = {}) {
  const respuesta = await fetch(`${URL_BASE}${ruta}`, {
    ...opciones,
    headers: {
      'Content-Type': 'application/json',
      ...(opciones.headers || {})
    }
  });

  const texto = await respuesta.text();
  let json = null;
  try {
    json = JSON.parse(texto);
  } catch (_) {}

  return {
    status: respuesta.status,
    body: json || texto
  };
}

async function ejecutarPruebas() {
  try {
    iniciarServidor();
    await esperarServidor();

    // 1. Login con admin demo inicial
    const resLogin = await solicitud('/api/login', {
      method: 'POST',
      body: JSON.stringify({
        email: 'admin@parkcontrol.cl',
        password: '123456'
      })
    });
    assert.strictEqual(resLogin.status, 200, 'Login demo debe ser 200');
    const token = resLogin.body.token;
    const authHeaders = { Authorization: `Bearer ${token}` };

    // 2. Crear/Actualizar tarifa por minuto
    const resTarifa = await solicitud('/api/tarifa', {
      method: 'PUT',
      headers: authHeaders,
      body: JSON.stringify({ tarifaPorMinuto: 30 })
    });
    assert.strictEqual(resTarifa.status, 200);

    // 3. Listar abonados vacío
    const resListarVacio = await solicitud('/api/abonados', {
      headers: authHeaders
    });
    assert.strictEqual(resListarVacio.status, 200);
    assert.deepStrictEqual(resListarVacio.body.abonados, []);

    // 4. Crear abonado mensual vigente
    const hoy = new Date();
    const inicio = hoy.toISOString().slice(0, 10);
    const unMes = new Date(hoy.getTime() + 30 * 24 * 3600 * 1000).toISOString().slice(0, 10);

    const resCrear = await solicitud('/api/abonados', {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        nombreTitular: 'Constructora Los Andes SpA',
        rut: '76.123.456-7',
        telefono: '+56912345678',
        email: 'contacto@losandes.cl',
        patente: 'CCDD-11',
        tipoVehiculo: 'Camioneta',
        montoMensual: 60000,
        fechaInicio: inicio,
        fechaVencimiento: unMes,
        observacion: 'Espacio reservado n° 5'
      })
    });
    assert.strictEqual(resCrear.status, 201, 'Crear abonado debe retornar 201');
    const abonadoId = resCrear.body.abonado.id;
    assert.strictEqual(resCrear.body.abonado.patente, 'CCDD-11');

    // 5. Verificar patente
    const resVerif = await solicitud('/api/abonados/verificar/CCDD-11', {
      headers: authHeaders
    });
    assert.strictEqual(resVerif.status, 200);
    assert.strictEqual(resVerif.body.esAbonado, true);
    assert.strictEqual(resVerif.body.vigente, true);

    // 6. Registrar entrada de abonado
    const resEntrada = await solicitud('/api/entradas', {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        patente: 'CCDD-11',
        tipo: 'Camioneta',
        color: 'Blanco'
      })
    });
    assert.strictEqual(resEntrada.status, 201);
    assert.strictEqual(resEntrada.body.esAbonado, true);
    assert.strictEqual(resEntrada.body.movimiento.esAbonado, true);

    // 7. Registrar salida de abonado -> Cobro debe ser $0 CLP
    const resSalida = await solicitud('/api/salidas', {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        patente: 'CCDD-11',
        metodoPago: 'efectivo'
      })
    });
    assert.strictEqual(resSalida.status, 200);
    assert.strictEqual(resSalida.body.esAbonado, true);
    assert.strictEqual(resSalida.body.salida.monto, 0, 'El cobro a un abonado vigente debe ser $0 CLP');
    assert.strictEqual(resSalida.body.salida.metodoPago, 'abonado');

    // 8. Actualizar abonado (renovar vencimiento)
    const dosMeses = new Date(hoy.getTime() + 60 * 24 * 3600 * 1000).toISOString().slice(0, 10);
    const resUpdate = await solicitud(`/api/abonados/${abonadoId}`, {
      method: 'PUT',
      headers: authHeaders,
      body: JSON.stringify({
        fechaVencimiento: dosMeses
      })
    });
    assert.strictEqual(resUpdate.status, 200);
    assert.strictEqual(resUpdate.body.abonado.fechaVencimiento, dosMeses);

    // 9. Listar con filtro y búsqueda
    const resListar = await solicitud('/api/abonados?buscar=Constructora', {
      headers: authHeaders
    });
    assert.strictEqual(resListar.status, 200);
    assert.strictEqual(resListar.body.abonados.length, 1);
    assert.strictEqual(resListar.body.abonados[0].estadoComercial, 'al_dia');

    // 10. Eliminar abonado
    const resDelete = await solicitud(`/api/abonados/${abonadoId}`, {
      method: 'DELETE',
      headers: authHeaders
    });
    assert.strictEqual(resDelete.status, 200);

    console.log('Todas las pruebas del módulo de Abonados y Convenios pasaron exitosamente.');
  } finally {
    await detenerServidor();
  }
}

ejecutarPruebas().catch(async error => {
  console.error('ERROR EN PRUEBAS DE ABONADOS:', error);
  await detenerServidor();
  process.exit(1);
});
