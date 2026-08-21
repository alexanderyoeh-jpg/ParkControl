'use strict';

// Respaldo seguro de SQLite para ParkControl.
//
// Este script no copia archivos .db/-wal/-shm. Usa la API online backup de
// better-sqlite3 para obtener una instantánea coherente, incluso si la base de
// origen está usando WAL. El archivo final se publica mediante un hard link
// exclusivo desde un directorio temporal creado por el proceso, por lo que no
// se sobrescribe un respaldo existente.

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const Database = require('better-sqlite3');

const PREFIJO_TEMPORAL_RESPALDO = '.parkcontrol-respaldo-tmp-';

class ErrorRespaldoSQLite extends Error {
  constructor(message) {
    super(message);
    this.name = 'ErrorRespaldoSQLite';
  }
}

function normalizarRutaParaComparar(ruta) {
  const normalizada = path.resolve(ruta);
  return process.platform === 'win32'
    ? normalizada.toLocaleLowerCase('en-US')
    : normalizada;
}

function resolverRutaAbsolutaExplicita(valor, nombre) {
  if (typeof valor !== 'string' || valor.trim() === '') {
    throw new ErrorRespaldoSQLite(`${nombre} debe indicarse como una ruta absoluta.`);
  }

  const ruta = valor.trim();
  if (!path.isAbsolute(ruta)) {
    throw new ErrorRespaldoSQLite(`${nombre} debe ser una ruta absoluta.`);
  }

  return path.resolve(ruta);
}

function obtenerArchivoRegularExistente(valor, nombre) {
  const ruta = resolverRutaAbsolutaExplicita(valor, nombre);
  let estadisticas;

  try {
    estadisticas = fs.statSync(ruta);
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new ErrorRespaldoSQLite(`${nombre} no existe.`);
    }
    throw error;
  }

  if (!estadisticas.isFile()) {
    throw new ErrorRespaldoSQLite(`${nombre} debe ser un archivo regular.`);
  }

  return fs.realpathSync.native(ruta);
}

function existeRutaInclusoSiEsEnlaceRoto(ruta) {
  try {
    fs.lstatSync(ruta);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') {
      return false;
    }
    throw error;
  }
}

function validarRutasRespaldo({ origen, destino }) {
  const rutaOrigen = obtenerArchivoRegularExistente(origen, 'origen');
  const destinoSolicitado = resolverRutaAbsolutaExplicita(destino, 'destino');
  const directorioDestinoSolicitado = path.dirname(destinoSolicitado);
  let directorioDestino;

  try {
    directorioDestino = fs.realpathSync.native(directorioDestinoSolicitado);
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new ErrorRespaldoSQLite('El directorio de destino no existe.');
    }
    throw error;
  }

  if (!fs.statSync(directorioDestino).isDirectory()) {
    throw new ErrorRespaldoSQLite('El directorio de destino no es válido.');
  }

  const rutaDestino = path.join(directorioDestino, path.basename(destinoSolicitado));
  if (normalizarRutaParaComparar(rutaOrigen) === normalizarRutaParaComparar(rutaDestino)) {
    throw new ErrorRespaldoSQLite('Origen y destino no pueden ser iguales.');
  }

  if (existeRutaInclusoSiEsEnlaceRoto(rutaDestino)) {
    throw new ErrorRespaldoSQLite(
      'El destino ya existe. El respaldo no sobrescribe archivos existentes.'
    );
  }

  return {
    origen: rutaOrigen,
    destino: rutaDestino,
    directorioDestino
  };
}

function crearDirectorioTemporalSeguro(directorioPadre, prefijo) {
  const padre = fs.realpathSync.native(directorioPadre);
  if (!fs.statSync(padre).isDirectory()) {
    throw new ErrorRespaldoSQLite('El directorio temporal padre no es válido.');
  }

  return fs.mkdtempSync(path.join(padre, prefijo));
}

function limpiarDirectorioTemporalSeguro(directorio, directorioPadre, prefijo) {
  const padre = fs.realpathSync.native(directorioPadre);
  const objetivo = path.resolve(directorio);
  const esHijoDirecto =
    normalizarRutaParaComparar(path.dirname(objetivo)) === normalizarRutaParaComparar(padre);
  const nombreSeguro = path.basename(objetivo).startsWith(prefijo);

  if (!esHijoDirecto || !nombreSeguro) {
    throw new ErrorRespaldoSQLite('Se rechazó limpiar una ruta temporal inesperada.');
  }

  let estadisticas;
  try {
    estadisticas = fs.lstatSync(objetivo);
  } catch (error) {
    if (error.code === 'ENOENT') {
      return;
    }
    throw error;
  }

  // Sólo se elimina un directorio temporal creado por este script. Nunca se
  // elimina el origen, el destino ni una ruta proporcionada por el operador.
  if (!estadisticas.isDirectory() || estadisticas.isSymbolicLink()) {
    throw new ErrorRespaldoSQLite('La ruta temporal no es un directorio seguro.');
  }

  fs.rmSync(objetivo, { recursive: true, force: true, maxRetries: 3 });
}

function calcularSha256Archivo(ruta) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const lectura = fs.createReadStream(ruta);

    lectura.on('error', reject);
    lectura.on('data', (fragmento) => hash.update(fragmento));
    lectura.on('end', () => resolve(hash.digest('hex')));
  });
}

async function crearRespaldoSQLite({ origen, destino }) {
  const rutas = validarRutasRespaldo({ origen, destino });
  const directorioTemporal = crearDirectorioTemporalSeguro(
    rutas.directorioDestino,
    PREFIJO_TEMPORAL_RESPALDO
  );
  const instantaneaTemporal = path.join(directorioTemporal, 'snapshot.sqlite');
  let baseOrigen;

  try {
    // fileMustExist impide que un error de ruta cree una base vacía. La base
    // se abre sólo en lectura; better-sqlite3 realiza la copia consistente con
    // sqlite3_backup, no mediante una copia física del archivo ni de su WAL.
    baseOrigen = new Database(rutas.origen, {
      readonly: true,
      fileMustExist: true,
      timeout: 5000
    });
    await baseOrigen.backup(instantaneaTemporal);
    baseOrigen.close();
    baseOrigen = undefined;

    const estadisticasTemporales = fs.statSync(instantaneaTemporal);
    if (!estadisticasTemporales.isFile() || estadisticasTemporales.size === 0) {
      throw new ErrorRespaldoSQLite('La instantánea generada no es un archivo SQLite válido.');
    }

    // linkSync falla si otro proceso creó el destino entre la validación y esta
    // operación. Así se mantiene la política de no sobrescritura sin copiar el
    // archivo terminado ni borrar una ruta del operador.
    try {
      fs.linkSync(instantaneaTemporal, rutas.destino);
    } catch (error) {
      if (error.code === 'EEXIST') {
        throw new ErrorRespaldoSQLite(
          'El destino apareció durante el respaldo y no fue sobrescrito.'
        );
      }
      throw error;
    }

    const estadisticasResultado = fs.statSync(rutas.destino);
    return {
      origen: rutas.origen,
      destino: rutas.destino,
      bytes: estadisticasResultado.size,
      sha256: await calcularSha256Archivo(rutas.destino),
      creadoEn: new Date().toISOString()
    };
  } finally {
    try {
      if (baseOrigen) {
        baseOrigen.close();
      }
    } finally {
      limpiarDirectorioTemporalSeguro(
        directorioTemporal,
        rutas.directorioDestino,
        PREFIJO_TEMPORAL_RESPALDO
      );
    }
  }
}

function parsearArgumentos(argv, opcionesPermitidas) {
  const argumentos = {};

  for (let indice = 0; indice < argv.length; indice += 1) {
    const opcion = argv[indice];
    if (!opcion.startsWith('--')) {
      throw new ErrorRespaldoSQLite(`Argumento no reconocido: ${opcion}`);
    }

    const nombre = opcion.slice(2);
    if (!opcionesPermitidas.includes(nombre)) {
      throw new ErrorRespaldoSQLite(`Opción no reconocida: ${opcion}`);
    }
    if (Object.hasOwn(argumentos, nombre)) {
      throw new ErrorRespaldoSQLite(`La opción ${opcion} no puede repetirse.`);
    }

    const valor = argv[indice + 1];
    if (!valor || valor.startsWith('--')) {
      throw new ErrorRespaldoSQLite(`Falta el valor para ${opcion}.`);
    }

    argumentos[nombre] = valor;
    indice += 1;
  }

  return argumentos;
}

async function ejecutarCli() {
  const argumentos = parsearArgumentos(process.argv.slice(2), ['origen', 'destino']);
  if (!argumentos.origen || !argumentos.destino) {
    throw new ErrorRespaldoSQLite('Uso: --origen <ruta-absoluta> --destino <ruta-absoluta>');
  }

  const resultado = await crearRespaldoSQLite({
    origen: argumentos.origen,
    destino: argumentos.destino
  });
  process.stdout.write(`${JSON.stringify(resultado, null, 2)}\n`);
}

if (require.main === module) {
  ejecutarCli().catch((error) => {
    process.stderr.write(`Error de respaldo SQLite: ${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  ErrorRespaldoSQLite,
  PREFIJO_TEMPORAL_RESPALDO,
  calcularSha256Archivo,
  crearDirectorioTemporalSeguro,
  crearRespaldoSQLite,
  limpiarDirectorioTemporalSeguro,
  normalizarRutaParaComparar,
  obtenerArchivoRegularExistente,
  parsearArgumentos,
  resolverRutaAbsolutaExplicita,
  validarRutasRespaldo
};
