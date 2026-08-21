const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const Database = require('better-sqlite3');

const DIRECTORIO_TEMPORAL = fs.mkdtempSync(
  path.join(os.tmpdir(), 'parkcontrol-configuracion-')
);
const RUTA_DB_VALIDA = path.join(DIRECTORIO_TEMPORAL, 'parkcontrol-valida.db');
const RUTA_DB_ARRANQUE_SANO = path.join(
  DIRECTORIO_TEMPORAL,
  'parkcontrol-arranque-sano.db'
);
const DIRECTORIO_BACKEND = path.join(__dirname, '..');
const SECRETO_PRUEBA = 'secreto-configuracion-prueba-de-32-caracteres';

function ejecutarConfiguracion(variables = {}) {
  return spawnSync(
    process.execPath,
    [
      '-e',
      [
        "const configuracion = require('./config');",
        'process.stdout.write(JSON.stringify({',
        '  esProduccion: configuracion.esProduccion,',
        '  rutaBaseDatos: configuracion.rutaBaseDatos,',
        '  host: configuracion.host,',
        '  sqliteBusyTimeoutMs: configuracion.sqliteBusyTimeoutMs,',
        '  passwordMinUsuario: configuracion.politicaPassword.longitudMinimaUsuario,',
        '  passwordMinSuperadmin: configuracion.politicaPassword.longitudMinimaSuperadmin,',
        '  correoModo: configuracion.correo.modo,',
        '  correoConfigurado: configuracion.correo.configuracionCompleta',
        '}));'
      ].join('\n')
    ],
    {
      cwd: DIRECTORIO_BACKEND,
      encoding: 'utf8',
      windowsHide: true,
      env: {
        ...process.env,
        NODE_ENV: 'production',
        PARKCONTROL_AUTH_SECRET: SECRETO_PRUEBA,
        PARKCONTROL_DB_PATH: RUTA_DB_VALIDA,
        PARKCONTROL_HOST: '',
        PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS: '',
        PARKCONTROL_ALLOW_SETUP: 'false',
        PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
        PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN: '',
        PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET: '',
        PARKCONTROL_PUBLIC_URL: '',
        PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado',
        PARKCONTROL_RESEND_API_KEY: '',
        PARKCONTROL_EMAIL_FROM: '',
        PARKCONTROL_EMAIL_REPLY_TO: '',
        ...variables
      }
    }
  );
}

function ejecutarServidorProduccion(variables = {}) {
  return spawnSync(process.execPath, ['server.js'], {
    cwd: DIRECTORIO_BACKEND,
    encoding: 'utf8',
    windowsHide: true,
    timeout: 10000,
    env: {
      ...process.env,
      NODE_ENV: 'production',
      PORT: '31919',
      PARKCONTROL_AUTH_SECRET: SECRETO_PRUEBA,
      PARKCONTROL_DB_PATH: RUTA_DB_VALIDA,
      PARKCONTROL_HOST: '',
      PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS: '',
      PARKCONTROL_ALLOW_SETUP: 'false',
      PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
      PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN: '',
      PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET: '',
      PARKCONTROL_PUBLIC_URL: '',
      PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado',
      PARKCONTROL_RESEND_API_KEY: '',
      PARKCONTROL_EMAIL_FROM: '',
      PARKCONTROL_EMAIL_REPLY_TO: '',
      ...variables
    }
  });
}

function ejecutarConfiguracionDesarrollo(variables = {}) {
  return spawnSync(
    process.execPath,
    [
      '-e',
      [
        "const configuracion = require('./config');",
        'process.stdout.write(JSON.stringify({',
        '  esProduccion: configuracion.esProduccion,',
        '  host: configuracion.host,',
        '  passwordMinUsuario: configuracion.politicaPassword.longitudMinimaUsuario,',
        '  passwordMinSuperadmin: configuracion.politicaPassword.longitudMinimaSuperadmin',
        '}));'
      ].join('\n')
    ],
    {
      cwd: DIRECTORIO_BACKEND,
      encoding: 'utf8',
      windowsHide: true,
      env: {
        ...process.env,
        NODE_ENV: 'development',
        PARKCONTROL_HOST: '',
        PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS: '',
        PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado',
        PARKCONTROL_RESEND_API_KEY: '',
        PARKCONTROL_EMAIL_FROM: '',
        PARKCONTROL_EMAIL_REPLY_TO: '',
        ...variables
      }
    }
  );
}

function obtenerPuertoDisponible() {
  return new Promise((resolve, reject) => {
    const servidor = net.createServer();

    servidor.once('error', reject);
    servidor.listen(0, '127.0.0.1', () => {
      const direccion = servidor.address();

      servidor.close(error => {
        if (error) {
          reject(error);
          return;
        }

        resolve(direccion.port);
      });
    });
  });
}

function solicitarEstado(puerto, ruta) {
  return new Promise((resolve, reject) => {
    const solicitud = http.get({
      host: '127.0.0.1',
      port: puerto,
      path: ruta,
      timeout: 1000
    }, respuesta => {
      let contenido = '';

      respuesta.setEncoding('utf8');
      respuesta.on('data', fragmento => {
        contenido += fragmento;
      });
      respuesta.on('end', () => {
        resolve({
          estado: respuesta.statusCode,
          contenido
        });
      });
    });

    solicitud.once('timeout', () => {
      solicitud.destroy(new Error('La consulta de salud agotó el tiempo'));
    });
    solicitud.once('error', reject);
  });
}

function solicitarJson(
  puerto,
  metodo,
  ruta,
  {
    datos,
    token
  } = {}
) {
  return new Promise((resolve, reject) => {
    const contenido = datos == null
      ? null
      : JSON.stringify(datos);
    const solicitud = http.request({
      host: '127.0.0.1',
      port: puerto,
      path: ruta,
      method: metodo,
      timeout: 4000,
      headers: {
        ...(contenido == null
          ? {}
          : {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(contenido)
            }),
        ...(token == null
          ? {}
          : { Authorization: `Bearer ${token}` })
      }
    }, respuesta => {
      let contenidoRespuesta = '';

      respuesta.setEncoding('utf8');
      respuesta.on('data', fragmento => {
        contenidoRespuesta += fragmento;
      });
      respuesta.on('end', () => {
        let cuerpo = null;

        try {
          cuerpo = contenidoRespuesta
            ? JSON.parse(contenidoRespuesta)
            : null;
        } catch (error) {
          reject(new Error(
            `La API devolvió una respuesta no JSON para ${metodo} ${ruta}: ${error.message}`
          ));
          return;
        }

        resolve({
          estado: respuesta.statusCode,
          cuerpo
        });
      });
    });

    solicitud.once('timeout', () => {
      solicitud.destroy(new Error(
        `La solicitud ${metodo} ${ruta} agotó el tiempo`
      ));
    });
    solicitud.once('error', reject);

    if (contenido != null) {
      solicitud.write(contenido);
    }

    solicitud.end();
  });
}

async function esperarServidorSaludable(proceso, puerto) {
  let salida = '';
  let errorSalida = '';

  proceso.stdout.on('data', dato => {
    salida += dato.toString();
  });
  proceso.stderr.on('data', dato => {
    errorSalida += dato.toString();
  });

  return new Promise((resolve, reject) => {
    let finalizado = false;
    let reintento;

    const terminar = error => {
      if (finalizado) return;
      finalizado = true;
      clearTimeout(reintento);
      clearTimeout(limite);
      proceso.removeListener('exit', alSalir);
      error ? reject(error) : resolve();
    };

    const alSalir = (codigo, senal) => {
      terminar(new Error(
        `El servidor de producción terminó antes de responder salud (código ${codigo}, señal ${senal}). ${errorSalida || salida}`
      ));
    };

    const comprobar = async () => {
      try {
        const respuesta = await solicitarEstado(puerto, '/readyz');

        if (respuesta.estado === 200 &&
            JSON.parse(respuesta.contenido).estado === 'listo') {
          terminar();
          return;
        }
      } catch (_) {
        // El proceso puede estar aplicando el esquema en el primer arranque.
      }

      if (!finalizado) {
        reintento = setTimeout(comprobar, 100);
      }
    };

    const limite = setTimeout(() => {
      terminar(new Error(
        `El servidor de producción no respondió /readyz. ${errorSalida || salida}`
      ));
    }, 10000);

    proceso.once('exit', alSalir);
    comprobar();
  });
}

function esperarSalida(proceso) {
  if (proceso.exitCode !== null || proceso.signalCode !== null) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const limite = setTimeout(() => {
      proceso.kill('SIGKILL');
      reject(new Error('El servidor sano no se detuvo a tiempo.'));
    }, 10000);

    proceso.once('exit', () => {
      clearTimeout(limite);
      resolve();
    });

    proceso.kill('SIGTERM');
  });
}

async function iniciarServidorProduccionSano() {
  const puerto = await obtenerPuertoDisponible();
  const proceso = spawn(process.execPath, ['server.js'], {
    cwd: DIRECTORIO_BACKEND,
    windowsHide: true,
    env: {
      ...process.env,
      NODE_ENV: 'production',
      PORT: String(puerto),
      PARKCONTROL_HOST: '',
      PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS: '',
      PARKCONTROL_AUTH_SECRET: SECRETO_PRUEBA,
      PARKCONTROL_DB_PATH: RUTA_DB_ARRANQUE_SANO,
      PARKCONTROL_ALLOW_SETUP: 'false',
      PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
      PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN: '',
      PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET: '',
      PARKCONTROL_PUBLIC_URL: '',
      PARKCONTROL_EMAIL_PROVIDER: 'deshabilitado',
      PARKCONTROL_RESEND_API_KEY: '',
      PARKCONTROL_EMAIL_FROM: '',
      PARKCONTROL_EMAIL_REPLY_TO: '',
      PARKCONTROL_SUPERADMIN_NOMBRE: 'Propietario temporal',
      PARKCONTROL_SUPERADMIN_EMAIL: 'propietario.temporal@prueba.cl',
      PARKCONTROL_SUPERADMIN_PASSWORD: 'SuperAdminSeguro2026'
    },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  servidorSano = proceso;
  puertoServidorSano = puerto;
  await esperarServidorSaludable(proceso, puerto);

  return proceso;
}

function debeFallar(variables, mensajeEsperado) {
  const resultado = ejecutarConfiguracion(variables);

  assert.notEqual(resultado.status, 0);
  assert.match(resultado.stderr, mensajeEsperado);
}

async function verificarPoliticaPasswordProduccion(puerto) {
  let respuesta = await solicitarJson(
    puerto,
    'POST',
    '/api/login',
    {
      datos: {
        email: 'propietario.temporal@prueba.cl',
        password: 'SuperAdminSeguro2026'
      }
    }
  );
  assert.equal(respuesta.estado, 200);
  const tokenSuperadmin = respuesta.cuerpo.token;

  respuesta = await solicitarJson(
    puerto,
    'PATCH',
    '/api/cuenta/password',
    {
      token: tokenSuperadmin,
      datos: {
        passwordActual: 'SuperAdminSeguro2026',
        passwordNueva: '1234567890'
      }
    }
  );
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /al menos 12 caracteres/);

  const datosCliente = {
    nombre: 'Parking política de contraseñas',
    plan: 'LITE',
    administrador: {
      nombre: 'Admin Política',
      email: 'admin.politica@prueba.cl',
      password: '123456'
    }
  };

  respuesta = await solicitarJson(
    puerto,
    'POST',
    '/api/superadmin/clientes',
    { token: tokenSuperadmin, datos: datosCliente }
  );
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /al menos 10 caracteres/);

  datosCliente.administrador.password = 'AdminInicial2026';
  respuesta = await solicitarJson(
    puerto,
    'POST',
    '/api/superadmin/clientes',
    { token: tokenSuperadmin, datos: datosCliente }
  );
  assert.equal(respuesta.estado, 201);
  const clienteId = respuesta.cuerpo.cliente.id;

  respuesta = await solicitarJson(
    puerto,
    'GET',
    `/api/superadmin/clientes/${clienteId}`,
    { token: tokenSuperadmin }
  );
  assert.equal(respuesta.estado, 200);
  const administradorId = respuesta.cuerpo.administradores[0].id;

  respuesta = await solicitarJson(
    puerto,
    'POST',
    '/api/login',
    {
      datos: {
        email: 'admin.politica@prueba.cl',
        password: 'AdminInicial2026'
      }
    }
  );
  assert.equal(respuesta.estado, 200);
  const tokenAdministrador = respuesta.cuerpo.token;

  const datosCajero = {
    nombre: 'Cajero Política',
    email: 'cajero.politica@prueba.cl',
    password: '123456',
    rol: 'cajero'
  };
  respuesta = await solicitarJson(
    puerto,
    'POST',
    '/api/usuarios',
    { token: tokenAdministrador, datos: datosCajero }
  );
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /al menos 10 caracteres/);

  datosCajero.password = 'CajeroSeguro2026';
  respuesta = await solicitarJson(
    puerto,
    'POST',
    '/api/usuarios',
    { token: tokenAdministrador, datos: datosCajero }
  );
  assert.equal(respuesta.estado, 201);
  const cajero = respuesta.cuerpo.usuario;

  respuesta = await solicitarJson(
    puerto,
    'PUT',
    `/api/usuarios/${cajero.id}`,
    {
      token: tokenAdministrador,
      datos: {
        nombre: cajero.nombre,
        email: cajero.email,
        password: '123456',
        rol: cajero.rol,
        registrarEntradas: cajero.registrarEntradas,
        registrarSalidas: cajero.registrarSalidas,
        verReportes: cajero.verReportes
      }
    }
  );
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /al menos 10 caracteres/);

  respuesta = await solicitarJson(
    puerto,
    'PATCH',
    '/api/cuenta/password',
    {
      token: tokenAdministrador,
      datos: {
        passwordActual: 'AdminInicial2026',
        passwordNueva: '123456'
      }
    }
  );
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /al menos 10 caracteres/);

  const rutaReset =
    `/api/superadmin/clientes/${clienteId}/administradores/${administradorId}/password`;
  respuesta = await solicitarJson(
    puerto,
    'PATCH',
    rutaReset,
    {
      token: tokenSuperadmin,
      datos: { password: '123456' }
    }
  );
  assert.equal(respuesta.estado, 400);
  assert.match(respuesta.cuerpo.mensaje, /al menos 10 caracteres/);

  respuesta = await solicitarJson(
    puerto,
    'PATCH',
    rutaReset,
    {
      token: tokenSuperadmin,
      datos: { password: 'AdminReseteada2026' }
    }
  );
  assert.equal(respuesta.estado, 200);

  respuesta = await solicitarJson(
    puerto,
    'POST',
    '/api/login',
    {
      datos: {
        email: 'admin.politica@prueba.cl',
        password: 'AdminReseteada2026'
      }
    }
  );
  assert.equal(respuesta.estado, 200);
}

function limpiarTemporal() {
  const temporalRaiz = path.resolve(os.tmpdir());
  const objetivo = path.resolve(DIRECTORIO_TEMPORAL);
  const nombre = path.basename(objetivo);

  if (!objetivo.startsWith(`${temporalRaiz}${path.sep}`) ||
      !nombre.startsWith('parkcontrol-configuracion-')) {
    throw new Error('Se rechazó limpiar una ruta temporal inesperada.');
  }

  fs.rmSync(objetivo, { recursive: true, force: true });
}

let servidorSano;
let puertoServidorSano;

(async () => {
  // La prueba crea sólo una base temporal vacía; nunca abre ni modifica la
  // base real del proyecto.
  new Database(RUTA_DB_VALIDA).close();
  new Database(RUTA_DB_ARRANQUE_SANO).close();

  debeFallar(
    { PARKCONTROL_ALLOW_SETUP: 'true' },
    /PARKCONTROL_ALLOW_SETUP no puede habilitarse en producción/
  );
  debeFallar(
    { PARKCONTROL_CREAR_USUARIOS_DEMO: 'true' },
    /PARKCONTROL_CREAR_USUARIOS_DEMO no puede habilitarse en producción/
  );
  debeFallar(
    {
      PARKCONTROL_DB_PATH: path.join(
        DIRECTORIO_TEMPORAL,
        'base-que-no-existe.db'
      )
    },
    /PARKCONTROL_DB_PATH no existe/
  );
  debeFallar(
    { PARKCONTROL_DB_PATH: 'base-relativa.db' },
    /PARKCONTROL_DB_PATH debe ser una ruta absoluta/
  );

  const configuracionValida = ejecutarConfiguracion();
  assert.equal(configuracionValida.status, 0, configuracionValida.stderr);

  const salida = JSON.parse(configuracionValida.stdout);
  assert.equal(salida.esProduccion, true);
  assert.equal(salida.rutaBaseDatos, path.resolve(RUTA_DB_VALIDA));
  assert.equal(salida.host, '127.0.0.1');
  assert.equal(salida.sqliteBusyTimeoutMs, 5000);
  assert.equal(salida.passwordMinUsuario, 10);
  assert.equal(salida.passwordMinSuperadmin, 12);
  assert.equal(salida.correoModo, 'no_configurado');
  assert.equal(salida.correoConfigurado, false);

  debeFallar(
    { PARKCONTROL_HOST: '0.0.0.0' },
    /PARKCONTROL_HOST en producción debe ser una dirección loopback/
  );
  debeFallar(
    { PARKCONTROL_HOST: 'https://127.0.0.1' },
    /PARKCONTROL_HOST debe ser una dirección IP válida o localhost/
  );
  debeFallar(
    { PARKCONTROL_EMAIL_PROVIDER: 'resend' },
    /Resend requiere PARKCONTROL_RESEND_API_KEY y PARKCONTROL_EMAIL_FROM/
  );
  debeFallar(
    {
      PARKCONTROL_RESEND_API_KEY: 're_clave_sin_proveedor',
      PARKCONTROL_EMAIL_FROM: 'informes@prueba.cl'
    },
    /No configures claves de correo mientras PARKCONTROL_EMAIL_PROVIDER esté deshabilitado/
  );

  const configuracionCorreoValida = ejecutarConfiguracion({
    PARKCONTROL_EMAIL_PROVIDER: 'resend',
    PARKCONTROL_RESEND_API_KEY: 're_prueba_configuracion',
    PARKCONTROL_EMAIL_FROM: 'ParkControl <informes@prueba.cl>',
    PARKCONTROL_EMAIL_REPLY_TO: 'soporte@prueba.cl'
  });
  assert.equal(
    configuracionCorreoValida.status,
    0,
    configuracionCorreoValida.stderr
  );
  const salidaCorreo = JSON.parse(configuracionCorreoValida.stdout);
  assert.equal(salidaCorreo.correoModo, 'resend');
  assert.equal(salidaCorreo.correoConfigurado, true);

  const configuracionDesarrollo = ejecutarConfiguracionDesarrollo();
  assert.equal(
    configuracionDesarrollo.status,
    0,
    configuracionDesarrollo.stderr
  );
  const salidaDesarrollo = JSON.parse(configuracionDesarrollo.stdout);
  assert.equal(salidaDesarrollo.host, '0.0.0.0');
  assert.equal(salidaDesarrollo.passwordMinUsuario, 6);
  assert.equal(salidaDesarrollo.passwordMinSuperadmin, 12);

  const servidorSinPropietario = ejecutarServidorProduccion();
  assert.notEqual(servidorSinPropietario.status, 0);
  assert.match(
    servidorSinPropietario.stderr,
    /Producción requiere un SuperAdministrador activo/
  );

  servidorSano = await iniciarServidorProduccionSano();

  const baseSana = new Database(RUTA_DB_ARRANQUE_SANO, {
    readonly: true
  });
  assert.equal(
    String(baseSana.pragma('journal_mode', { simple: true })).toLowerCase(),
    'wal'
  );
  assert.equal(
    baseSana.prepare(`
      SELECT COUNT(*) AS total
      FROM usuarios
      WHERE rol = 'superadmin' AND activo = 1
    `).get().total,
    1
  );
  baseSana.close();

  await verificarPoliticaPasswordProduccion(puertoServidorSano);

  console.log('Configuración segura de producción verificada.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  if (servidorSano) {
    try {
      await esperarSalida(servidorSano);
    } catch (error) {
      console.error(error);
      process.exitCode = 1;
    }
  }

  limpiarTemporal();
});
