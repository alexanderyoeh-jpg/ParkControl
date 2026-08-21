'use strict';

// Verifica un respaldo de SQLite sin abrirlo como base operativa. Primero crea
// una restauración temporal mediante sqlite3_backup, luego ejecuta los PRAGMA
// de integridad y cuenta las tablas esenciales de ParkControl.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Database = require('better-sqlite3');
const {
  ErrorRespaldoSQLite,
  calcularSha256Archivo,
  crearDirectorioTemporalSeguro,
  limpiarDirectorioTemporalSeguro,
  obtenerArchivoRegularExistente,
  parsearArgumentos
} = require('./respaldo_sqlite');

const PREFIJO_TEMPORAL_VERIFICACION = 'parkcontrol-restauracion-tmp-';
const TABLAS_OBLIGATORIAS = [
  'estacionamientos',
  'usuarios',
  'movimientos',
  'auditoria'
];
const TABLAS_CONTEO = [
  ...TABLAS_OBLIGATORIAS,
  'vehiculos_estacionamiento',
  'tarifas',
  'turnos_caja',
  'alertas_administrativas',
  'pagos_suscripcion',
  'suscripciones_pago',
  'operaciones_idempotentes'
];

function validarSha256Esperado(valor) {
  if (valor === undefined || valor === null || valor === '') {
    return undefined;
  }

  if (typeof valor !== 'string' || !/^[a-fA-F0-9]{64}$/.test(valor)) {
    throw new ErrorRespaldoSQLite('sha256 debe contener exactamente 64 caracteres hexadecimales.');
  }

  return valor.toLowerCase();
}

function resultadoPragmaEsOk(filas) {
  return filas.length > 0 && filas.every((fila) => String(Object.values(fila)[0]).toLowerCase() === 'ok');
}

function obtenerConteosClave(base) {
  const tablasDisponibles = new Set(
    base
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
      .all()
      .map((fila) => fila.name)
  );
  const faltantes = TABLAS_OBLIGATORIAS.filter((tabla) => !tablasDisponibles.has(tabla));
  if (faltantes.length > 0) {
    throw new ErrorRespaldoSQLite(
      `El respaldo no contiene tablas esenciales de ParkControl: ${faltantes.join(', ')}.`
    );
  }

  const tablas = {};
  for (const tabla of TABLAS_CONTEO) {
    if (tablasDisponibles.has(tabla)) {
      // Los nombres proceden de TABLAS_CONTEO, una lista cerrada y no de una
      // entrada del operador, por lo que no se interpolan identificadores no
      // confiables en SQL.
      tablas[tabla] = base.prepare(`SELECT COUNT(*) AS total FROM "${tabla}"`).get().total;
    }
  }

  const movimientosPorEstado = Object.fromEntries(
    base
      .prepare('SELECT estado, COUNT(*) AS total FROM movimientos GROUP BY estado ORDER BY estado')
      .all()
      .map((fila) => [fila.estado, fila.total])
  );

  return { tablas, movimientosPorEstado };
}

async function verificarRestauracionSQLite({ respaldo, sha256Esperado }) {
  const rutaRespaldo = obtenerArchivoRegularExistente(respaldo, 'respaldo');
  const hashEsperado = validarSha256Esperado(sha256Esperado);
  const sha256 = await calcularSha256Archivo(rutaRespaldo);

  if (hashEsperado && sha256 !== hashEsperado) {
    throw new ErrorRespaldoSQLite('La suma SHA-256 del respaldo no coincide con la esperada.');
  }

  const directorioTemporal = crearDirectorioTemporalSeguro(
    os.tmpdir(),
    PREFIJO_TEMPORAL_VERIFICACION
  );
  const rutaRestauracionTemporal = path.join(directorioTemporal, 'restauracion.sqlite');
  let baseOrigen;
  let baseRestaurada;

  try {
    // Se usa otra vez sqlite3_backup; no se copian físicamente el .db ni sus
    // archivos -wal/-shm. La única base que se elimina al terminar es la
    // restauración temporal creada arriba.
    baseOrigen = new Database(rutaRespaldo, {
      readonly: true,
      fileMustExist: true,
      timeout: 5000
    });
    await baseOrigen.backup(rutaRestauracionTemporal);
    baseOrigen.close();
    baseOrigen = undefined;

    baseRestaurada = new Database(rutaRestauracionTemporal, {
      readonly: true,
      fileMustExist: true,
      timeout: 5000
    });
    const resultadoQuickCheck = baseRestaurada.prepare('PRAGMA quick_check').all();
    if (!resultadoPragmaEsOk(resultadoQuickCheck)) {
      throw new ErrorRespaldoSQLite('PRAGMA quick_check informó un problema de integridad.');
    }

    const problemasClavesForaneas = baseRestaurada.prepare('PRAGMA foreign_key_check').all();
    if (problemasClavesForaneas.length > 0) {
      throw new ErrorRespaldoSQLite('PRAGMA foreign_key_check informó claves foráneas inválidas.');
    }

    const conteos = obtenerConteosClave(baseRestaurada);
    const bytes = fs.statSync(rutaRespaldo).size;
    return {
      respaldo: rutaRespaldo,
      bytes,
      sha256,
      integridad: {
        quickCheck: 'ok',
        clavesForaneas: 'ok'
      },
      conteos,
      verificadoEn: new Date().toISOString()
    };
  } finally {
    try {
      if (baseRestaurada) {
        baseRestaurada.close();
      }
    } finally {
      try {
        if (baseOrigen) {
          baseOrigen.close();
        }
      } finally {
        limpiarDirectorioTemporalSeguro(
          directorioTemporal,
          os.tmpdir(),
          PREFIJO_TEMPORAL_VERIFICACION
        );
      }
    }
  }
}

async function ejecutarCli() {
  const argumentos = parsearArgumentos(process.argv.slice(2), ['respaldo', 'sha256']);
  if (!argumentos.respaldo) {
    throw new ErrorRespaldoSQLite('Uso: --respaldo <ruta-absoluta> [--sha256 <hash-hexadecimal>]');
  }

  const resultado = await verificarRestauracionSQLite({
    respaldo: argumentos.respaldo,
    sha256Esperado: argumentos.sha256
  });
  process.stdout.write(`${JSON.stringify(resultado, null, 2)}\n`);
}

if (require.main === module) {
  ejecutarCli().catch((error) => {
    process.stderr.write(`Error de verificación de restauración SQLite: ${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  PREFIJO_TEMPORAL_VERIFICACION,
  TABLAS_CONTEO,
  TABLAS_OBLIGATORIAS,
  obtenerConteosClave,
  resultadoPragmaEsOk,
  validarSha256Esperado,
  verificarRestauracionSQLite
};
