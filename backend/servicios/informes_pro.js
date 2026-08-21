const PDFDocument = require('pdfkit');

const MAX_REGISTROS_CSV_POR_DEFECTO = 10000;

function numeroSeguro(valor) {
  const numero = Number(valor || 0);
  return Number.isFinite(numero) ? numero : 0;
}

function escaparCsv(valor) {
  const textoOriginal = String(valor ?? '');
  // Evita que una patente, observación u otro dato controlado por una persona
  // se interprete como fórmula al abrir el CSV en una planilla.
  const texto = /^[=+\-@]/.test(textoOriginal)
    ? `'${textoOriginal}`
    : textoOriginal;

  return `"${texto.replace(/"/g, '""')}"`;
}

function escaparHtml(valor) {
  return String(valor ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function formatearMonto(valor) {
  return Math.round(numeroSeguro(valor))
    .toLocaleString('es-CL');
}

function crearServicioInformesPro({
  db,
  resolverZonaHoraria,
  crearFiltroDiasLocales
}) {
  if (!db ||
      typeof resolverZonaHoraria !== 'function' ||
      typeof crearFiltroDiasLocales !== 'function') {
    throw new Error('El servicio de informes Pro requiere sus dependencias');
  }

  function obtenerContabilidad({
    estacionamientoId,
    zonaHoraria,
    fechaInicio = '',
    fechaFin = ''
  }) {
    const zonaResuelta = resolverZonaHoraria(zonaHoraria);
    const filtroDiasLocales = crearFiltroDiasLocales({
      fechaInicio,
      fechaFin,
      zonaHoraria: zonaResuelta
    });

    let sql = `
      SELECT
        id,
        id AS folio,
        patente,
        tipo,
        color,
        observacion,
        hora_entrada AS horaEntrada,
        hora_salida AS horaSalida,
        minutos,
        tarifa_por_minuto AS tarifaPorMinuto,
        monto,
        monto AS totalCobrado,
        COALESCE(metodo_pago, 'efectivo') AS metodoPago,
        estado
      FROM movimientos
      WHERE estacionamiento_id = ?
        AND estado = 'salio'
    `;
    const parametros = [estacionamientoId];

    if (filtroDiasLocales.inicioAproximado) {
      sql += ' AND hora_salida >= ?';
      parametros.push(filtroDiasLocales.inicioAproximado);
    }

    if (filtroDiasLocales.finAproximadoExclusivo) {
      sql += ' AND hora_salida < ?';
      parametros.push(filtroDiasLocales.finAproximadoExclusivo);
    }

    sql += ' ORDER BY hora_salida DESC, id DESC';

    const registros = db
      .prepare(sql)
      .all(...parametros)
      .filter(registro => filtroDiasLocales.incluye(registro.horaSalida));

    const resumen = registros.reduce((acumulado, registro) => {
      acumulado.cantidadVehiculos += 1;
      acumulado.ingresosTotales += numeroSeguro(registro.monto);
      acumulado.minutosTotales += Number(registro.minutos || 0);
      return acumulado;
    }, {
      cantidadVehiculos: 0,
      ingresosTotales: 0,
      minutosTotales: 0
    });

    resumen.promedioPorVehiculo = resumen.cantidadVehiculos > 0
      ? resumen.ingresosTotales / resumen.cantidadVehiculos
      : 0;

    return {
      fechaInicio: fechaInicio || null,
      fechaFin: fechaFin || null,
      zonaHoraria: zonaResuelta,
      resumen,
      registros
    };
  }

  function crearCsvContabilidad({
    informe,
    maxRegistros = MAX_REGISTROS_CSV_POR_DEFECTO
  }) {
    const limite = Number.isInteger(maxRegistros) && maxRegistros > 0
      ? maxRegistros
      : MAX_REGISTROS_CSV_POR_DEFECTO;
    const registrosIncluidos = informe.registros.slice(0, limite);
    const filas = [
      [
        'Folio',
        'Patente',
        'Tipo',
        'Color',
        'Observación',
        'Entrada ISO',
        'Salida ISO',
        'Minutos',
        'Tarifa por minuto',
        'Monto',
        'Método de pago'
      ]
    ];

    for (const registro of registrosIncluidos) {
      filas.push([
        registro.folio,
        registro.patente,
        registro.tipo,
        registro.color,
        registro.observacion || '',
        registro.horaEntrada,
        registro.horaSalida,
        registro.minutos,
        registro.tarifaPorMinuto,
        registro.monto,
        registro.metodoPago
      ]);
    }

    return {
      contenido: `\ufeff${filas
        .map(fila => fila.map(escaparCsv).join(','))
        .join('\r\n')}\r\n`,
      registrosIncluidos: registrosIncluidos.length,
      registrosOmitidos: Math.max(0, informe.registros.length - registrosIncluidos.length)
    };
  }

  function crearHtmlResumenContable({ nombreEstacionamiento, informe }) {
    const periodo = informe.fechaInicio || informe.fechaFin
      ? `${informe.fechaInicio || 'inicio'} a ${informe.fechaFin || 'hoy'}`
      : 'período disponible';
    const resumen = informe.resumen;

    return `<!doctype html>
<html lang="es">
  <body style="font-family:Arial,sans-serif;color:#17324d;line-height:1.5">
    <h2>Informe contable ParkControl</h2>
    <p><strong>${escaparHtml(nombreEstacionamiento)}</strong></p>
    <p>Período: ${escaparHtml(periodo)} · Zona horaria: ${escaparHtml(informe.zonaHoraria)}</p>
    <table style="border-collapse:collapse">
      <tr><td style="padding:4px 16px 4px 0">Vehículos cobrados</td><td><strong>${resumen.cantidadVehiculos}</strong></td></tr>
      <tr><td style="padding:4px 16px 4px 0">Ingresos brutos</td><td><strong>$${formatearMonto(resumen.ingresosTotales)}</strong></td></tr>
      <tr><td style="padding:4px 16px 4px 0">Promedio por vehículo</td><td><strong>$${formatearMonto(resumen.promedioPorVehiculo)}</strong></td></tr>
      <tr><td style="padding:4px 16px 4px 0">Minutos cobrados</td><td><strong>${resumen.minutosTotales}</strong></td></tr>
    </table>
    <p>Se adjunta un CSV con el detalle disponible. Este informe es operacional y no sustituye la asesoría contable ni un documento tributario.</p>
  </body>
</html>`;
  }

  function crearTextoResumenContable({ nombreEstacionamiento, informe }) {
    const resumen = informe.resumen;
    const periodo = informe.fechaInicio || informe.fechaFin
      ? `${informe.fechaInicio || 'inicio'} a ${informe.fechaFin || 'hoy'}`
      : 'período disponible';

    return [
      'Informe contable ParkControl',
      nombreEstacionamiento,
      `Período: ${periodo}`,
      `Zona horaria: ${informe.zonaHoraria}`,
      `Vehículos cobrados: ${resumen.cantidadVehiculos}`,
      `Ingresos brutos: $${formatearMonto(resumen.ingresosTotales)}`,
      `Promedio por vehículo: $${formatearMonto(resumen.promedioPorVehiculo)}`,
      `Minutos cobrados: ${resumen.minutosTotales}`,
      '',
      'Este informe es operacional y no sustituye la asesoría contable ni un documento tributario.'
    ].join('\n');
  }

  function crearPdfResumenContable({ nombreEstacionamiento, informe }) {
    return new Promise((resolve, reject) => {
      const fragmentos = [];
      const doc = new PDFDocument({ size: 'A4', margin: 48 });

      doc.on('data', fragmento => fragmentos.push(fragmento));
      doc.once('error', reject);
      doc.once('end', () => resolve(Buffer.concat(fragmentos)));

      const resumen = informe.resumen;
      const periodo = informe.fechaInicio || informe.fechaFin
        ? `${informe.fechaInicio || 'inicio'} a ${informe.fechaFin || 'hoy'}`
        : 'Período disponible';

      doc.font('Helvetica-Bold').fontSize(20).fillColor('#16345F')
        .text('Informe contable ParkControl');
      doc.moveDown(0.4);
      doc.font('Helvetica-Bold').fontSize(12).fillColor('#1B2938')
        .text(String(nombreEstacionamiento || 'Estacionamiento'));
      doc.font('Helvetica').fontSize(10).fillColor('#4C5C6D')
        .text(`Período: ${periodo}`)
        .text(`Zona horaria: ${informe.zonaHoraria}`);
      doc.moveDown(1.4);
      doc.font('Helvetica-Bold').fontSize(13).fillColor('#16345F')
        .text('Resumen');
      doc.moveDown(0.5);

      const filas = [
        ['Vehículos cobrados', String(resumen.cantidadVehiculos)],
        ['Ingresos brutos', `$${formatearMonto(resumen.ingresosTotales)}`],
        ['Promedio por vehículo', `$${formatearMonto(resumen.promedioPorVehiculo)}`],
        ['Minutos cobrados', String(resumen.minutosTotales)]
      ];

      for (const [etiqueta, valor] of filas) {
        doc.font('Helvetica').fontSize(11).fillColor('#1B2938')
          .text(etiqueta, { continued: true })
          .font('Helvetica-Bold')
          .text(`  ${valor}`, { align: 'right' });
        doc.moveDown(0.25);
      }

      doc.moveDown(2);
      doc.font('Helvetica').fontSize(8).fillColor('#617181')
        .text(
          'Documento operacional generado por ParkControl. No sustituye una boleta tributaria ni asesoría contable.',
          { align: 'center' }
        );
      doc.end();
    });
  }

  return {
    obtenerContabilidad,
    crearCsvContabilidad,
    crearHtmlResumenContable,
    crearTextoResumenContable,
    crearPdfResumenContable
  };
}

module.exports = {
  crearServicioInformesPro,
  MAX_REGISTROS_CSV_POR_DEFECTO
};
