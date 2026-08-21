const ZONA_HORARIA_POR_DEFECTO = 'America/Santiago';

function resolverZonaHorariaParaFormato(zonaHoraria) {
  const candidata = String(zonaHoraria ?? '').trim() ||
    ZONA_HORARIA_POR_DEFECTO;

  try {
    return new Intl.DateTimeFormat('en-US', {
      timeZone: candidata
    }).resolvedOptions().timeZone || candidata;
  } catch (_) {
    return ZONA_HORARIA_POR_DEFECTO;
  }
}

function formatearFechaPDF(valor, zonaHoraria) {
  if (!valor) {
    return '-';
  }

  try {
    const fecha = new Date(valor);

    if (Number.isNaN(fecha.getTime())) {
      return String(valor);
    }

    return fecha.toLocaleString('es-CL', {
      timeZone: resolverZonaHorariaParaFormato(zonaHoraria),
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch (_) {
    return String(valor);
  }
}

module.exports = {
  formatearFechaPDF,
  resolverZonaHorariaParaFormato
};
