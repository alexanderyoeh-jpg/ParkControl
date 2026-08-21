const assert = require('node:assert/strict');
const Database = require('better-sqlite3');
const {
  crearServicioResumenDiario
} = require('../servicios/resumen_diario');

function resolverZonaHoraria(zonaHoraria) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: zonaHoraria
  }).resolvedOptions().timeZone;
}

function partesFechaZona(fecha, zonaHoraria) {
  const partes = new Intl.DateTimeFormat('en-US', {
    timeZone: resolverZonaHoraria(zonaHoraria),
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(fecha);
  const valor = tipo => Number(
    partes.find(parte => parte.type === tipo)?.value
  );

  return {
    year: valor('year'),
    month: valor('month'),
    day: valor('day')
  };
}

function claveDia({ year, month, day }) {
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

function crearFiltroDiasLocales({ fechaInicio, fechaFin, zonaHoraria }) {
  return {
    // Ventana intencionalmente amplia: esta prueba valida que el servicio
    // confirme el día con IANA, no una conversión del huso del equipo.
    inicioAproximado: '2000-01-01T00:00:00.000Z',
    finAproximadoExclusivo: '2030-01-01T00:00:00.000Z',
    incluye(fecha) {
      const clave = claveDia(partesFechaZona(new Date(fecha), zonaHoraria));
      return clave >= fechaInicio && clave <= fechaFin;
    }
  };
}

const db = new Database(':memory:');
db.exec(`
  CREATE TABLE movimientos (
    estacionamiento_id INTEGER NOT NULL,
    patente TEXT NOT NULL,
    hora_entrada TEXT NOT NULL,
    hora_salida TEXT,
    monto REAL,
    estado TEXT NOT NULL
  );
`);

const insertar = db.prepare(`
  INSERT INTO movimientos
  (estacionamiento_id, patente, hora_entrada, hora_salida, monto, estado)
  VALUES (?, ?, ?, ?, ?, ?)
`);

// 2026-08-01 13:00 UTC es 2026-08-02 03:00 en Pacific/Kiritimati.
// La fila ANTERIOR sigue siendo el 1 de agosto para el cliente aunque es el
// mismo día UTC, que es justo el límite que no debe delegarse al VPS.
insertar.run(1, 'DENTRO', '2026-08-01T12:15:00.000Z', null, 0, 'dentro');
insertar.run(
  1,
  'HOY',
  '2026-08-01T12:30:00.000Z',
  '2026-08-01T12:45:00.000Z',
  99,
  'salio'
);
insertar.run(
  1,
  'ANTERIOR',
  '2026-08-01T09:30:00.000Z',
  '2026-08-01T09:45:00.000Z',
  500,
  'salio'
);
insertar.run(
  1,
  'ELIMINADO',
  '2026-08-01T12:40:00.000Z',
  null,
  0,
  'eliminado'
);
insertar.run(
  2,
  'OTRO_TENANT',
  '2026-08-01T12:30:00.000Z',
  '2026-08-01T12:45:00.000Z',
  999,
  'salio'
);

const servicio = crearServicioResumenDiario({
  db,
  resolverZonaHoraria,
  partesFechaZona,
  claveDia,
  crearFiltroDiasLocales,
  obtenerAhora: () => new Date('2026-08-01T13:00:00.000Z')
});

assert.deepEqual(
  servicio.obtenerResumen({
    estacionamientoId: 1,
    zonaHoraria: 'Pacific/Kiritimati'
  }),
  {
    vehiculosDentro: 1,
    entradasHoy: 2,
    salidasHoy: 1,
    recaudacionHoy: 99
  }
);

db.close();
console.log('Prueba de resumen diario por zona horaria aprobada');
