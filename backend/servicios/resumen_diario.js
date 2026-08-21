function numeroSeguro(valor) {
  const numero = Number(valor || 0);
  return Number.isFinite(numero) ? numero : 0;
}

function crearServicioResumenDiario({
  db,
  resolverZonaHoraria,
  partesFechaZona,
  claveDia,
  crearFiltroDiasLocales,
  obtenerAhora = () => new Date()
}) {
  if (!db ||
      typeof db.prepare !== 'function' ||
      typeof resolverZonaHoraria !== 'function' ||
      typeof partesFechaZona !== 'function' ||
      typeof claveDia !== 'function' ||
      typeof crearFiltroDiasLocales !== 'function' ||
      typeof obtenerAhora !== 'function') {
    throw new Error('El servicio de resumen diario requiere sus dependencias');
  }

  function obtenerResumen({ estacionamientoId, zonaHoraria }) {
    const id = Number(estacionamientoId);

    if (!Number.isInteger(id) || id < 1) {
      throw new Error('El estacionamiento del resumen diario no es válido');
    }

    const zonaResuelta = resolverZonaHoraria(zonaHoraria);
    const ahora = obtenerAhora();
    const partesHoy = partesFechaZona(ahora, zonaResuelta);

    if (!partesHoy) {
      throw new Error('No se pudo resolver la fecha local del estacionamiento');
    }

    const fechaHoy = claveDia(partesHoy);
    const filtroHoy = crearFiltroDiasLocales({
      fechaInicio: fechaHoy,
      fechaFin: fechaHoy,
      zonaHoraria: zonaResuelta
    });
    const vehiculosDentro = db.prepare(`
      SELECT COUNT(*) AS total
      FROM movimientos
      WHERE estacionamiento_id = ?
        AND estado = 'dentro'
    `).get(id);

    // SQLite no conoce IANA de forma portable. La ventana previa evita leer
    // toda la historia y el filtro Intl confirma el día civil exacto del
    // estacionamiento. datetime() acepta tanto los ISO actuales como las
    // fechas heredadas de SQLite con un espacio entre día y hora.
    const entradas = db.prepare(`
      SELECT hora_entrada AS fecha
      FROM movimientos
      WHERE estacionamiento_id = ?
        AND estado != 'eliminado'
        AND datetime(hora_entrada) >= datetime(?)
        AND datetime(hora_entrada) < datetime(?)
    `).all(
      id,
      filtroHoy.inicioAproximado,
      filtroHoy.finAproximadoExclusivo
    ).filter(registro => filtroHoy.incluye(registro.fecha));

    const salidas = db.prepare(`
      SELECT hora_salida AS fecha, monto
      FROM movimientos
      WHERE estacionamiento_id = ?
        AND estado = 'salio'
        AND datetime(hora_salida) >= datetime(?)
        AND datetime(hora_salida) < datetime(?)
    `).all(
      id,
      filtroHoy.inicioAproximado,
      filtroHoy.finAproximadoExclusivo
    ).filter(registro => filtroHoy.incluye(registro.fecha));

    return {
      vehiculosDentro: Number(vehiculosDentro?.total || 0),
      entradasHoy: entradas.length,
      salidasHoy: salidas.length,
      recaudacionHoy: salidas.reduce(
        (total, salida) => total + numeroSeguro(salida.monto),
        0
      )
    };
  }

  return { obtenerResumen };
}

module.exports = {
  crearServicioResumenDiario
};
