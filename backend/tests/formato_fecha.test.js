const assert = require('node:assert/strict');
const {
  formatearFechaPDF,
  resolverZonaHorariaParaFormato
} = require('../servicios/formato_fecha');

const fecha = '2026-08-01T12:30:00.000Z';
const opciones = {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit'
};
const esperadoKiritimati = new Date(fecha).toLocaleString('es-CL', {
  ...opciones,
  timeZone: 'Pacific/Kiritimati'
});
const esperadoSantiago = new Date(fecha).toLocaleString('es-CL', {
  ...opciones,
  timeZone: 'America/Santiago'
});

assert.equal(
  formatearFechaPDF(fecha, 'Pacific/Kiritimati'),
  esperadoKiritimati
);
assert.notEqual(esperadoKiritimati, esperadoSantiago);
assert.equal(
  resolverZonaHorariaParaFormato('zona/inexistente'),
  'America/Santiago'
);
assert.equal(formatearFechaPDF(null, 'Pacific/Kiritimati'), '-');
assert.equal(
  formatearFechaPDF('fecha no válida', 'Pacific/Kiritimati'),
  'fecha no válida'
);

console.log('Prueba de formato PDF por zona horaria aprobada');
