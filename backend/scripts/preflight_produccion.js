'use strict';

// Comprobación previa para un despliegue de producción. Lee la configuración
// ya validada por config.js y sólo realiza verificaciones de lectura/escritura
// en rutas explícitas. No inicia el servidor ni abre la base con SQLite.

const fs = require('node:fs');
const path = require('node:path');
const configuracion = require('../config');

const PREFIJO_TEMPORAL_PREFLIGHT = '.parkcontrol-preflight-tmp-';
const ESPACIO_LIBRE_MINIMO_PREDETERMINADO = 1024n * 1024n * 1024n;

class ErrorPreflightProduccion extends Error {
  constructor(message) {
    super(message);
    this.name = 'ErrorPreflightProduccion';
  }
}

function normalizarRutaParaComparar(ruta) {
  const normalizada = path.resolve(ruta);
  return process.platform === 'win32'
    ? normalizada.toLocaleLowerCase('en-US')
    : normalizada;
}

function leerEspacioLibreMinimo(valor) {
  if (valor === undefined || valor === null || String(valor).trim() === '') {
    return ESPACIO_LIBRE_MINIMO_PREDETERMINADO;
  }

  const texto = String(valor).trim();
  if (!/^\d+$/.test(texto)) {
    throw new ErrorPreflightProduccion(
      'PARKCONTROL_BACKUP_MIN_FREE_BYTES debe ser un entero positivo expresado en bytes.'
    );
  }

  const bytes = BigInt(texto);
  if (bytes < 1n) {
    throw new ErrorPreflightProduccion(
      'PARKCONTROL_BACKUP_MIN_FREE_BYTES debe ser mayor que cero.'
    );
  }

  return bytes;
}

function abrirSoloLectura(ruta) {
  let descriptor;

  try {
    descriptor = fs.openSync(ruta, 'r');
  } catch (_) {
    throw new ErrorPreflightProduccion(
      'La base de datos configurada existe, pero el proceso no puede leerla.'
    );
  } finally {
    if (descriptor !== undefined) {
      fs.closeSync(descriptor);
    }
  }
}

function validarBaseDatos(rutaConfigurada) {
  if (typeof rutaConfigurada !== 'string' || !path.isAbsolute(rutaConfigurada)) {
    throw new ErrorPreflightProduccion(
      'La configuración validada no contiene una ruta absoluta de base de datos.'
    );
  }

  let ruta;
  let estadisticas;

  try {
    ruta = fs.realpathSync.native(rutaConfigurada);
    estadisticas = fs.statSync(ruta);
  } catch (_) {
    throw new ErrorPreflightProduccion('La base de datos configurada no existe.');
  }

  if (!estadisticas.isFile()) {
    throw new ErrorPreflightProduccion('La ruta configurada de base de datos no es un archivo.');
  }

  abrirSoloLectura(ruta);
  return { ruta, bytes: BigInt(estadisticas.size) };
}

function validarDirectorioRespaldo(valor, rutaBaseDatos) {
  if (typeof valor !== 'string' || valor.trim() === '') {
    throw new ErrorPreflightProduccion(
      'PARKCONTROL_BACKUP_DIR es obligatorio y debe ser una ruta absoluta existente.'
    );
  }

  const solicitado = valor.trim();
  if (!path.isAbsolute(solicitado)) {
    throw new ErrorPreflightProduccion('PARKCONTROL_BACKUP_DIR debe ser una ruta absoluta.');
  }

  let directorio;
  let estadisticas;
  try {
    directorio = fs.realpathSync.native(path.resolve(solicitado));
    estadisticas = fs.statSync(directorio);
  } catch (_) {
    throw new ErrorPreflightProduccion('PARKCONTROL_BACKUP_DIR no existe.');
  }

  if (!estadisticas.isDirectory()) {
    throw new ErrorPreflightProduccion('PARKCONTROL_BACKUP_DIR debe apuntar a un directorio.');
  }

  const directorioBaseDatos = fs.realpathSync.native(path.dirname(rutaBaseDatos));
  if (
    normalizarRutaParaComparar(directorio) ===
    normalizarRutaParaComparar(directorioBaseDatos)
  ) {
    throw new ErrorPreflightProduccion(
      'PARKCONTROL_BACKUP_DIR no puede ser el mismo directorio que la base de datos.'
    );
  }

  try {
    fs.accessSync(directorio, fs.constants.W_OK);
  } catch (_) {
    throw new ErrorPreflightProduccion('PARKCONTROL_BACKUP_DIR no permite escritura.');
  }

  return directorio;
}

function obtenerEspacioLibreBytes(directorio) {
  if (typeof fs.statfsSync !== 'function') {
    throw new ErrorPreflightProduccion(
      'No se puede comprobar el espacio libre: fs.statfs no está disponible en esta versión de Node.js.'
    );
  }

  let informacion;
  try {
    informacion = fs.statfsSync(directorio, { bigint: true });
  } catch (_) {
    throw new ErrorPreflightProduccion(
      'No se puede comprobar el espacio libre del directorio de respaldos mediante fs.statfs.'
    );
  }

  const bloquesDisponibles = informacion.bavail ?? informacion.bfree;
  const tamanoBloque = informacion.bsize;
  if (bloquesDisponibles === undefined || tamanoBloque === undefined) {
    throw new ErrorPreflightProduccion(
      'fs.statfs no devolvió la información necesaria para comprobar el espacio libre.'
    );
  }

  try {
    const disponibles = BigInt(bloquesDisponibles) * BigInt(tamanoBloque);
    if (disponibles < 0n) {
      throw new Error('Valor negativo');
    }
    return disponibles;
  } catch (_) {
    throw new ErrorPreflightProduccion(
      'No se pudo interpretar el espacio libre informado por fs.statfs.'
    );
  }
}

function limpiarDirectorioTemporalSeguro(directorio, directorioPadre) {
  const padre = fs.realpathSync.native(directorioPadre);
  const objetivo = path.resolve(directorio);
  const esHijoDirecto =
    normalizarRutaParaComparar(path.dirname(objetivo)) ===
    normalizarRutaParaComparar(padre);
  const nombreSeguro = path.basename(objetivo).startsWith(PREFIJO_TEMPORAL_PREFLIGHT);

  if (!esHijoDirecto || !nombreSeguro) {
    throw new ErrorPreflightProduccion('Se rechazó limpiar una ruta temporal inesperada.');
  }

  const estadisticas = fs.lstatSync(objetivo);
  if (!estadisticas.isDirectory() || estadisticas.isSymbolicLink()) {
    throw new ErrorPreflightProduccion('La ruta temporal de preflight no es segura.');
  }

  // Es el único borrado de este script y corresponde a una carpeta temporal
  // creada por mkdtempSync dentro del directorio de respaldos validado.
  fs.rmSync(objetivo, { recursive: true, force: true, maxRetries: 3 });
}

function comprobarEscrituraDirectorio(directorio) {
  let temporal;

  try {
    temporal = fs.mkdtempSync(path.join(directorio, PREFIJO_TEMPORAL_PREFLIGHT));
    const prueba = path.join(temporal, 'comprobacion');
    const descriptor = fs.openSync(prueba, 'wx');
    fs.closeSync(descriptor);
  } catch (_) {
    throw new ErrorPreflightProduccion(
      'PARKCONTROL_BACKUP_DIR no permite crear un respaldo de forma segura.'
    );
  } finally {
    if (temporal) {
      limpiarDirectorioTemporalSeguro(temporal, directorio);
    }
  }
}

function ejecutarPreflightProduccion({
  configuracionValidada = configuracion,
  variablesEntorno = process.env
} = {}) {
  if (!configuracionValidada.esProduccion) {
    throw new ErrorPreflightProduccion(
      'El preflight sólo puede ejecutarse con NODE_ENV=production.'
    );
  }

  const baseDatos = validarBaseDatos(configuracionValidada.rutaBaseDatos);
  const directorioRespaldos = validarDirectorioRespaldo(
    variablesEntorno.PARKCONTROL_BACKUP_DIR,
    baseDatos.ruta
  );
  const espacioMinimo = leerEspacioLibreMinimo(
    variablesEntorno.PARKCONTROL_BACKUP_MIN_FREE_BYTES
  );
  comprobarEscrituraDirectorio(directorioRespaldos);
  const espacioDisponible = obtenerEspacioLibreBytes(directorioRespaldos);

  if (espacioDisponible < espacioMinimo) {
    throw new ErrorPreflightProduccion(
      `El directorio de respaldos no tiene espacio suficiente: disponibles ${espacioDisponible} bytes; mínimo requerido ${espacioMinimo} bytes.`
    );
  }

  // La salida no contiene secretos, tokens ni rutas absolutas del servidor.
  return {
    estado: 'listo_para_produccion',
    entorno: configuracionValidada.entorno,
    baseDatos: {
      archivo: path.basename(baseDatos.ruta),
      legible: true,
      bytes: baseDatos.bytes.toString()
    },
    respaldos: {
      directorioConfigurado: true,
      escribible: true,
      espacioLibreBytes: espacioDisponible.toString(),
      espacioMinimoBytes: espacioMinimo.toString(),
      margenBytes: (espacioDisponible - espacioMinimo).toString()
    },
    verificadoEn: new Date().toISOString()
  };
}

function ejecutarCli() {
  const resultado = ejecutarPreflightProduccion();
  process.stdout.write(`${JSON.stringify(resultado, null, 2)}\n`);
}

if (require.main === module) {
  try {
    ejecutarCli();
  } catch (error) {
    process.stderr.write(`Error de preflight de producción: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  ESPACIO_LIBRE_MINIMO_PREDETERMINADO,
  ErrorPreflightProduccion,
  PREFIJO_TEMPORAL_PREFLIGHT,
  comprobarEscrituraDirectorio,
  ejecutarPreflightProduccion,
  leerEspacioLibreMinimo,
  obtenerEspacioLibreBytes,
  validarBaseDatos,
  validarDirectorioRespaldo
};
