'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Database = require('better-sqlite3');
const {
  calcularSha256Archivo,
  crearRespaldoSQLite,
  parsearArgumentos
} = require('../scripts/respaldo_sqlite');
const {
  verificarRestauracionSQLite
} = require('../scripts/verificar_restauracion_sqlite');

const DIRECTORIO_TEMPORAL = fs.mkdtempSync(
  path.join(os.tmpdir(), 'parkcontrol-respaldo-prueba-')
);
const RUTA_ORIGEN = path.join(DIRECTORIO_TEMPORAL, 'origen.sqlite');
const RUTA_RESPALDO = path.join(DIRECTORIO_TEMPORAL, 'respaldo.sqlite');

function limpiarTemporal() {
  const temporalRaiz = path.resolve(os.tmpdir());
  const objetivo = path.resolve(DIRECTORIO_TEMPORAL);
  const nombre = path.basename(objetivo);

  if (
    !objetivo.startsWith(`${temporalRaiz}${path.sep}`) ||
    !nombre.startsWith('parkcontrol-respaldo-prueba-')
  ) {
    throw new Error('Se rechazó limpiar una ruta de prueba inesperada.');
  }

  // La prueba elimina solamente el directorio temporal que ella misma creó.
  // Nunca abre, copia ni modifica backend/parkcontrol.db.
  fs.rmSync(objetivo, { recursive: true, force: true });
}

async function debeRechazar(operacion, patron) {
  await assert.rejects(operacion, patron);
}

async function ejecutarPrueba() {
  let baseOrigen;

  try {
    // Esta base está en el directorio temporal de la prueba. El dato insertado
    // tras habilitar WAL permanece disponible aunque aún exista el archivo WAL,
    // demostrando que sqlite3_backup toma una instantánea consistente.
    baseOrigen = new Database(RUTA_ORIGEN);
    baseOrigen.pragma('journal_mode = WAL');
    baseOrigen.pragma('foreign_keys = ON');
    baseOrigen.exec(`
      CREATE TABLE estacionamientos (
        id INTEGER PRIMARY KEY,
        nombre TEXT NOT NULL
      );
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY,
        estacionamiento_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id)
      );
      CREATE TABLE movimientos (
        id INTEGER PRIMARY KEY,
        estacionamiento_id INTEGER NOT NULL,
        patente TEXT NOT NULL,
        estado TEXT NOT NULL,
        FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id)
      );
      CREATE TABLE auditoria (
        id INTEGER PRIMARY KEY,
        estacionamiento_id INTEGER NOT NULL,
        accion TEXT NOT NULL,
        FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id)
      );
    `);
    baseOrigen.prepare('INSERT INTO estacionamientos (id, nombre) VALUES (?, ?)').run(1, 'Temporal');
    baseOrigen.prepare('INSERT INTO usuarios (id, estacionamiento_id, nombre) VALUES (?, ?, ?)').run(1, 1, 'Cajero');
    baseOrigen.prepare('INSERT INTO movimientos (id, estacionamiento_id, patente, estado) VALUES (?, ?, ?, ?)').run(1, 1, 'ABCD12', 'dentro');
    baseOrigen.prepare('INSERT INTO movimientos (id, estacionamiento_id, patente, estado) VALUES (?, ?, ?, ?)').run(2, 1, 'EFGH34', 'salio');
    baseOrigen.prepare('INSERT INTO auditoria (id, estacionamiento_id, accion) VALUES (?, ?, ?)').run(1, 1, 'ENTRADA');
    assert.equal(fs.existsSync(`${RUTA_ORIGEN}-wal`), true);

    const resultadoRespaldo = await crearRespaldoSQLite({
      origen: RUTA_ORIGEN,
      destino: RUTA_RESPALDO
    });
    assert.equal(resultadoRespaldo.destino, RUTA_RESPALDO);
    assert.equal(resultadoRespaldo.bytes > 0, true);
    assert.match(resultadoRespaldo.sha256, /^[a-f0-9]{64}$/);
    assert.equal(resultadoRespaldo.sha256, await calcularSha256Archivo(RUTA_RESPALDO));
    assert.equal(fs.existsSync(`${RUTA_RESPALDO}-wal`), false);

    const lecturaRespaldo = new Database(RUTA_RESPALDO, {
      readonly: true,
      fileMustExist: true
    });
    assert.equal(lecturaRespaldo.prepare('SELECT COUNT(*) AS total FROM movimientos').get().total, 2);
    lecturaRespaldo.close();

    const verificacion = await verificarRestauracionSQLite({
      respaldo: RUTA_RESPALDO,
      sha256Esperado: resultadoRespaldo.sha256
    });
    assert.equal(verificacion.integridad.quickCheck, 'ok');
    assert.equal(verificacion.integridad.clavesForaneas, 'ok');
    assert.equal(verificacion.conteos.tablas.estacionamientos, 1);
    assert.equal(verificacion.conteos.tablas.usuarios, 1);
    assert.equal(verificacion.conteos.tablas.movimientos, 2);
    assert.deepEqual(verificacion.conteos.movimientosPorEstado, {
      dentro: 1,
      salio: 1
    });

    await debeRechazar(
      () => crearRespaldoSQLite({ origen: RUTA_ORIGEN, destino: RUTA_ORIGEN }),
      /Origen y destino no pueden ser iguales/
    );
    await debeRechazar(
      () => crearRespaldoSQLite({ origen: 'origen-relativo.sqlite', destino: RUTA_RESPALDO }),
      /origen debe ser una ruta absoluta/
    );
    await debeRechazar(
      () => crearRespaldoSQLite({ origen: RUTA_ORIGEN, destino: RUTA_RESPALDO }),
      /El destino ya existe/
    );
    await debeRechazar(
      () => verificarRestauracionSQLite({
        respaldo: RUTA_RESPALDO,
        sha256Esperado: '0'.repeat(64)
      }),
      /SHA-256 del respaldo no coincide/
    );
    assert.throws(
      () => parsearArgumentos(['--origen', RUTA_ORIGEN, '--origen', RUTA_ORIGEN], ['origen']),
      /no puede repetirse/
    );

    console.log('Respaldo y restauración SQLite verificados con una base temporal.');
  } finally {
    if (baseOrigen) {
      baseOrigen.close();
    }
    limpiarTemporal();
  }
}

ejecutarPrueba().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
