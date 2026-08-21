'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const Database = require('better-sqlite3');

const DIRECTORIO_TEMPORAL = fs.mkdtempSync(
  path.join(os.tmpdir(), 'parkcontrol-preflight-prueba-')
);
const DIRECTORIO_RESPALDOS = path.join(DIRECTORIO_TEMPORAL, 'respaldos');
const RUTA_DB = path.join(DIRECTORIO_TEMPORAL, 'parkcontrol-prueba.sqlite');
const DIRECTORIO_BACKEND = path.join(__dirname, '..');
const SECRETO_PRUEBA = 'secreto-preflight-prueba-de-32-caracteres';

function ejecutarPreflight(variables = {}) {
  return spawnSync(process.execPath, ['scripts/preflight_produccion.js'], {
    cwd: DIRECTORIO_BACKEND,
    encoding: 'utf8',
    windowsHide: true,
    env: {
      ...process.env,
      NODE_ENV: 'production',
      PARKCONTROL_AUTH_SECRET: SECRETO_PRUEBA,
      PARKCONTROL_DB_PATH: RUTA_DB,
      PARKCONTROL_HOST: '',
      PARKCONTROL_ALLOW_SETUP: 'false',
      PARKCONTROL_CREAR_USUARIOS_DEMO: 'false',
      PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN: '',
      PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET: '',
      PARKCONTROL_PUBLIC_URL: '',
      PARKCONTROL_BACKUP_DIR: DIRECTORIO_RESPALDOS,
      PARKCONTROL_BACKUP_MIN_FREE_BYTES: '1',
      ...variables
    }
  });
}

function debeFallar(variables, patron) {
  const resultado = ejecutarPreflight(variables);
  assert.notEqual(resultado.status, 0);
  assert.match(resultado.stderr, patron);
}

function limpiarTemporal() {
  const temporalRaiz = path.resolve(os.tmpdir());
  const objetivo = path.resolve(DIRECTORIO_TEMPORAL);
  const nombre = path.basename(objetivo);

  if (
    !objetivo.startsWith(`${temporalRaiz}${path.sep}`) ||
    !nombre.startsWith('parkcontrol-preflight-prueba-')
  ) {
    throw new Error('Se rechazó limpiar una ruta de prueba inesperada.');
  }

  // Sólo borra la carpeta temporal generada por esta prueba. No abre ni toca
  // backend/parkcontrol.db.
  fs.rmSync(objetivo, { recursive: true, force: true });
}

try {
  fs.mkdirSync(DIRECTORIO_RESPALDOS);
  // La prueba crea una base temporal mínima. Nunca usa la base real.
  new Database(RUTA_DB).close();

  const resultadoSano = ejecutarPreflight();
  assert.equal(resultadoSano.status, 0, resultadoSano.stderr);

  const salida = JSON.parse(resultadoSano.stdout);
  assert.equal(salida.estado, 'listo_para_produccion');
  assert.equal(salida.entorno, 'production');
  assert.equal(salida.baseDatos.archivo, path.basename(RUTA_DB));
  assert.equal(salida.baseDatos.legible, true);
  assert.equal(salida.respaldos.escribible, true);
  assert.equal(BigInt(salida.respaldos.espacioLibreBytes) >= 1n, true);
  assert.equal(resultadoSano.stdout.includes(DIRECTORIO_TEMPORAL), false);
  assert.deepEqual(
    fs.readdirSync(DIRECTORIO_RESPALDOS)
      .filter((nombre) => nombre.startsWith('.parkcontrol-preflight-tmp-')),
    []
  );

  debeFallar(
    { NODE_ENV: 'development' },
    /El preflight sólo puede ejecutarse con NODE_ENV=production/
  );
  debeFallar(
    { PARKCONTROL_BACKUP_DIR: 'respaldos-relativos' },
    /PARKCONTROL_BACKUP_DIR debe ser una ruta absoluta/
  );
  debeFallar(
    { PARKCONTROL_BACKUP_DIR: DIRECTORIO_TEMPORAL },
    /no puede ser el mismo directorio que la base de datos/
  );
  debeFallar(
    { PARKCONTROL_BACKUP_DIR: '' },
    /PARKCONTROL_BACKUP_DIR es obligatorio/
  );
  debeFallar(
    { PARKCONTROL_BACKUP_MIN_FREE_BYTES: '0' },
    /debe ser mayor que cero/
  );
  debeFallar(
    { PARKCONTROL_BACKUP_MIN_FREE_BYTES: '999999999999999999999999999999' },
    /no tiene espacio suficiente/
  );

  console.log('Preflight de producción verificado sólo con rutas temporales.');
} finally {
  limpiarTemporal();
}
