const {
  ErrorTransporteCorreo
} = require('./transporte_correo');

const ESTADOS_REINTENTABLES = new Set(['pendiente', 'reintento']);
const MAX_INTENTOS = 6;
const DURACION_RESERVA_MS = 10 * 60 * 1000;
const DEMORAS_REINTENTO_MS = [
  60 * 1000,
  5 * 60 * 1000,
  30 * 60 * 1000,
  2 * 60 * 60 * 1000,
  8 * 60 * 60 * 1000,
  24 * 60 * 60 * 1000
];

function fechaCalendario({ year, month, day }) {
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

function sumarDiasCalendario(fecha, dias) {
  const copia = new Date(Date.UTC(fecha.year, fecha.month - 1, fecha.day));
  copia.setUTCDate(copia.getUTCDate() + dias);

  return {
    year: copia.getUTCFullYear(),
    month: copia.getUTCMonth() + 1,
    day: copia.getUTCDate()
  };
}

function mesAnterior(fecha) {
  const copia = new Date(Date.UTC(fecha.year, fecha.month - 2, 1));
  return {
    year: copia.getUTCFullYear(),
    month: copia.getUTCMonth() + 1
  };
}

function ultimaFechaMes(year, month) {
  const fecha = new Date(Date.UTC(year, month, 0));
  return {
    year: fecha.getUTCFullYear(),
    month: fecha.getUTCMonth() + 1,
    day: fecha.getUTCDate()
  };
}

function horaLocalValida(horaLocal) {
  const texto = String(horaLocal || '').trim();
  const coincidencia = /^(\d{2}):(\d{2})$/.exec(texto);

  if (!coincidencia) return null;

  const hora = Number(coincidencia[1]);
  const minuto = Number(coincidencia[2]);

  if (hora > 23 || minuto > 59) return null;

  return {
    texto,
    minutos: hora * 60 + minuto
  };
}

function textoSeguro(valor, maximo = 220) {
  return String(valor ?? '')
    .replace(/[\r\n]/g, ' ')
    .trim()
    .slice(0, maximo);
}

function enmascararCorreo(correo) {
  const [local, dominio] = String(correo || '').split('@');

  if (!local || !dominio) return 'correo protegido';

  return `${local.slice(0, 1)}${'*'.repeat(Math.max(2, Math.min(6, local.length - 1)))}@${dominio}`;
}

function esCorreoValido(correo) {
  return /^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(
    String(correo || '').trim()
  );
}

function esPlanConCorreo(plan, obtenerCapacidadesPlan) {
  return Boolean(obtenerCapacidadesPlan(plan)?.reportesPorCorreo);
}

function crearColaInformesCorreo({
  db,
  transporte,
  servicioInformes,
  obtenerCapacidadesPlan,
  partesFechaZona,
  resolverZonaHoraria,
  ahora = () => new Date()
}) {
  if (!db || !transporte || !servicioInformes ||
      typeof obtenerCapacidadesPlan !== 'function' ||
      typeof partesFechaZona !== 'function' ||
      typeof resolverZonaHoraria !== 'function') {
    throw new Error('La cola de informes por correo requiere sus dependencias');
  }

  function registrarEvento({ estacionamientoId, envioId, tipo, mensaje, fecha }) {
    db.prepare(`
      INSERT INTO informes_correo_eventos
      (
        estacionamiento_id,
        envio_id,
        tipo,
        mensaje,
        creado_en
      )
      VALUES (?, ?, ?, ?, ?)
    `).run(
      estacionamientoId,
      envioId,
      textoSeguro(tipo, 80),
      textoSeguro(mensaje, 220) || null,
      fecha
    );
  }

  function obtenerPeriodoCerrado(programacion, fechaActual) {
    const partes = partesFechaZona(
      fechaActual,
      resolverZonaHoraria(programacion.zona_horaria)
    );
    const horaProgramada = horaLocalValida(programacion.hora_local);

    if (!partes || !horaProgramada ||
        (partes.hour * 60 + Number(partes.minute || 0)) < horaProgramada.minutos) {
      return null;
    }

    const hoy = {
      year: partes.year,
      month: partes.month,
      day: partes.day
    };

    if (programacion.frecuencia === 'diario') {
      const dia = sumarDiasCalendario(hoy, -1);
      const fecha = fechaCalendario(dia);
      return {
        clave: `diario:${fecha}`,
        fechaInicio: fecha,
        fechaFin: fecha
      };
    }

    if (programacion.frecuencia === 'semanal') {
      // Siempre se toma la última semana completamente cerrada. Si el
      // proceso estaba caído el lunes, al volver martes (o cualquier otro
      // día) se recupera el mismo período y la clave evita duplicarlo.
      // En domingo aún no ha cerrado la semana actual, por eso se retrocede
      // una semana completa.
      const diaSemana = new Date(
        Date.UTC(hoy.year, hoy.month - 1, hoy.day)
      ).getUTCDay();
      const diasDesdeDomingoCerrado = diaSemana === 0 ? 7 : diaSemana;
      const fin = sumarDiasCalendario(hoy, -diasDesdeDomingoCerrado);
      const inicio = sumarDiasCalendario(fin, -6);
      return {
        clave: `semanal:${fechaCalendario(inicio)}`,
        fechaInicio: fechaCalendario(inicio),
        fechaFin: fechaCalendario(fin)
      };
    }

    if (programacion.frecuencia === 'mensual') {
      // Del mismo modo, un arranque el día 2 o posterior debe recuperar el
      // último mes ya cerrado. Nunca se genera el mes en curso incompleto.
      const mes = mesAnterior(hoy);
      const inicio = {
        ...mes,
        day: 1
      };
      const fin = ultimaFechaMes(mes.year, mes.month);
      return {
        clave: `mensual:${fechaCalendario(inicio).slice(0, 7)}`,
        fechaInicio: fechaCalendario(inicio),
        fechaFin: fechaCalendario(fin)
      };
    }

    return null;
  }

  function obtenerContextoEstacionamiento(estacionamientoId) {
    return db.prepare(`
      SELECT id, nombre, estado, plan, zona_horaria
      FROM estacionamientos
      WHERE id = ?
    `).get(estacionamientoId);
  }

  function destinatarioSigueAutorizado({ estacionamientoId, usuarioId, correo }) {
    return Boolean(db.prepare(`
      SELECT id
      FROM usuarios
      WHERE id = ?
        AND estacionamiento_id = ?
        AND activo = 1
        AND email = ?
        AND rol IN ('admin', 'admin_estacionamiento')
      LIMIT 1
    `).get(usuarioId, estacionamientoId, correo));
  }

  function listarProgramaciones(estacionamientoId) {
    return db.prepare(`
      SELECT
        id,
        frecuencia,
        hora_local AS horaLocal,
        zona_horaria AS zonaHoraria,
        activo,
        ultima_clave_periodo AS ultimaClavePeriodo,
        ultima_ejecucion_en AS ultimaEjecucionEn,
        creado_en AS creadoEn,
        actualizado_en AS actualizadoEn,
        correo_destino AS correoDestino
      FROM informes_correo_programados
      WHERE estacionamiento_id = ?
      ORDER BY
        CASE frecuencia
          WHEN 'diario' THEN 1
          WHEN 'semanal' THEN 2
          WHEN 'mensual' THEN 3
          ELSE 4
        END,
        id ASC
    `).all(estacionamientoId).map(programacion => ({
      ...programacion,
      activo: Boolean(programacion.activo),
      correoDestino: enmascararCorreo(programacion.correoDestino)
    }));
  }

  function listarEnvios(estacionamientoId, limite = 30) {
    const limiteSeguro = Math.max(1, Math.min(100, Number(limite) || 30));
    return db.prepare(`
      SELECT
        id,
        programacion_id AS programacionId,
        frecuencia,
        periodo_clave AS periodoClave,
        periodo_inicio AS periodoInicio,
        periodo_fin AS periodoFin,
        zona_horaria AS zonaHoraria,
        correo_destino AS correoDestino,
        estado,
        intentos,
        disponible_en AS disponibleEn,
        error_publico AS errorPublico,
        proveedor AS proveedor,
        proveedor_mensaje_id AS proveedorMensajeId,
        creado_en AS creadoEn,
        enviado_en AS enviadoEn,
        actualizado_en AS actualizadoEn
      FROM informes_correo_envios
      WHERE estacionamiento_id = ?
      ORDER BY id DESC
      LIMIT ?
    `).all(estacionamientoId, limiteSeguro).map(envio => ({
      ...envio,
      correoDestino: enmascararCorreo(envio.correoDestino),
      proveedorMensajeId: envio.proveedorMensajeId
        ? 'registrado'
        : null
    }));
  }

  function guardarProgramacion({
    estacionamientoId,
    usuarioId,
    correoDestino,
    frecuencia,
    horaLocal,
    activo
  }) {
    const hora = horaLocalValida(horaLocal);

    if (!['diario', 'semanal', 'mensual'].includes(frecuencia)) {
      return {
        error: 'La frecuencia debe ser diario, semanal o mensual'
      };
    }

    if (!hora) {
      return {
        error: 'La hora local debe tener formato HH:MM'
      };
    }

    if (!esCorreoValido(correoDestino)) {
      return {
        error: 'El correo del administrador no es válido'
      };
    }

    const estacionamiento = obtenerContextoEstacionamiento(estacionamientoId);

    if (!estacionamiento) {
      return { error: 'No se encontró el estacionamiento' };
    }

    const marcaTiempo = ahora().toISOString();
    const resultado = db.transaction(() => {
      const existente = db.prepare(`
        SELECT id
        FROM informes_correo_programados
        WHERE estacionamiento_id = ?
          AND frecuencia = ?
      `).get(estacionamientoId, frecuencia);

      if (existente) {
        db.prepare(`
          UPDATE informes_correo_programados
          SET
            hora_local = ?,
            zona_horaria = ?,
            activo = ?,
            correo_destino = ?,
            destinatario_usuario_id = ?,
            actualizado_en = ?
          WHERE id = ?
            AND estacionamiento_id = ?
        `).run(
          hora.texto,
          resolverZonaHoraria(estacionamiento.zona_horaria),
          activo ? 1 : 0,
          correoDestino.trim().toLowerCase(),
          usuarioId,
          marcaTiempo,
          existente.id,
          estacionamientoId
        );

        return Number(existente.id);
      }

      const insercion = db.prepare(`
        INSERT INTO informes_correo_programados
        (
          estacionamiento_id,
          creado_por_usuario_id,
          destinatario_usuario_id,
          frecuencia,
          hora_local,
          zona_horaria,
          correo_destino,
          activo,
          creado_en,
          actualizado_en
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        estacionamientoId,
        usuarioId,
        usuarioId,
        frecuencia,
        hora.texto,
        resolverZonaHoraria(estacionamiento.zona_horaria),
        correoDestino.trim().toLowerCase(),
        activo ? 1 : 0,
        marcaTiempo,
        marcaTiempo
      );

      return Number(insercion.lastInsertRowid);
    })();

    return {
      id: resultado
    };
  }

  function actualizarProgramacion({
    estacionamientoId,
    programacionId,
    usuarioId,
    correoDestino,
    horaLocal,
    activo
  }) {
    const existente = db.prepare(`
      SELECT id, frecuencia
      FROM informes_correo_programados
      WHERE id = ?
        AND estacionamiento_id = ?
    `).get(programacionId, estacionamientoId);

    if (!existente) return { noEncontrada: true };

    const hora = horaLocal == null ? null : horaLocalValida(horaLocal);

    if (horaLocal != null && !hora) {
      return { error: 'La hora local debe tener formato HH:MM' };
    }

    if (correoDestino != null && !esCorreoValido(correoDestino)) {
      return { error: 'El correo del administrador no es válido' };
    }

    const estacionamiento = obtenerContextoEstacionamiento(estacionamientoId);
    const marcaTiempo = ahora().toISOString();
    const cambios = db.prepare(`
      UPDATE informes_correo_programados
      SET
        hora_local = COALESCE(?, hora_local),
        zona_horaria = ?,
        correo_destino = COALESCE(?, correo_destino),
        destinatario_usuario_id = CASE
          WHEN ? IS NULL THEN destinatario_usuario_id
          ELSE ?
        END,
        activo = COALESCE(?, activo),
        actualizado_en = ?
      WHERE id = ?
        AND estacionamiento_id = ?
    `).run(
      hora?.texto || null,
      resolverZonaHoraria(estacionamiento?.zona_horaria),
      correoDestino == null ? null : correoDestino.trim().toLowerCase(),
      correoDestino == null ? null : correoDestino.trim().toLowerCase(),
      usuarioId,
      typeof activo === 'boolean' ? (activo ? 1 : 0) : null,
      marcaTiempo,
      programacionId,
      estacionamientoId
    );

    return {
      actualizada: cambios.changes === 1
    };
  }

  function desactivarProgramacion({ estacionamientoId, programacionId }) {
    const marcaTiempo = ahora().toISOString();
    return db.transaction(() => {
      const actualizacion = db.prepare(`
        UPDATE informes_correo_programados
        SET activo = 0, actualizado_en = ?
        WHERE id = ?
          AND estacionamiento_id = ?
          AND activo = 1
      `).run(marcaTiempo, programacionId, estacionamientoId);

      if (actualizacion.changes === 0) {
        const existe = db.prepare(`
          SELECT id
          FROM informes_correo_programados
          WHERE id = ?
            AND estacionamiento_id = ?
        `).get(programacionId, estacionamientoId);
        return existe ? { yaDesactivada: true } : { noEncontrada: true };
      }

      const pendientes = db.prepare(`
        SELECT id
        FROM informes_correo_envios
        WHERE estacionamiento_id = ?
          AND programacion_id = ?
          AND estado IN ('pendiente', 'reintento')
      `).all(estacionamientoId, programacionId);

      db.prepare(`
        UPDATE informes_correo_envios
        SET
          estado = 'cancelado',
          error_publico = 'La programación fue desactivada por un administrador',
          actualizado_en = ?
        WHERE estacionamiento_id = ?
          AND programacion_id = ?
          AND estado IN ('pendiente', 'reintento')
      `).run(marcaTiempo, estacionamientoId, programacionId);

      for (const pendiente of pendientes) {
        registrarEvento({
          estacionamientoId,
          envioId: pendiente.id,
          tipo: 'CANCELADO_PROGRAMACION',
          mensaje: 'La programación fue desactivada por un administrador',
          fecha: marcaTiempo
        });
      }

      return { desactivada: true };
    })();
  }

  function encolarEnvio({
    estacionamientoId,
    programacionId = null,
    frecuencia,
    periodoClave,
    fechaInicio,
    fechaFin,
    zonaHoraria,
    correoDestino,
    destinatarioUsuarioId,
    claveDeduplicacion
  }) {
    const marcaTiempo = ahora().toISOString();
    const resultado = db.prepare(`
      INSERT OR IGNORE INTO informes_correo_envios
      (
        estacionamiento_id,
        programacion_id,
        destinatario_usuario_id,
        frecuencia,
        periodo_clave,
        periodo_inicio,
        periodo_fin,
        zona_horaria,
        correo_destino,
        estado,
        intentos,
        disponible_en,
        clave_deduplicacion,
        creado_en,
        actualizado_en
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pendiente', 0, ?, ?, ?, ?)
    `).run(
      estacionamientoId,
      programacionId,
      destinatarioUsuarioId,
      frecuencia,
      periodoClave,
      fechaInicio,
      fechaFin,
      resolverZonaHoraria(zonaHoraria),
      correoDestino.trim().toLowerCase(),
      marcaTiempo,
      claveDeduplicacion,
      marcaTiempo,
      marcaTiempo
    );

    const envio = db.prepare(`
      SELECT id
      FROM informes_correo_envios
      WHERE estacionamiento_id = ?
        AND clave_deduplicacion = ?
    `).get(estacionamientoId, claveDeduplicacion);

    if (resultado.changes > 0 && envio) {
      registrarEvento({
        estacionamientoId,
        envioId: envio.id,
        tipo: 'ENCOLADO',
        mensaje: 'Informe pendiente de envío',
        fecha: marcaTiempo
      });
    }

    return {
      envioId: envio ? Number(envio.id) : null,
      creado: resultado.changes > 0
    };
  }

  function programarInformesVencidos() {
    const fechaActual = ahora();
    const programaciones = db.prepare(`
      SELECT
        p.id,
        p.estacionamiento_id,
        p.destinatario_usuario_id,
        p.frecuencia,
        p.hora_local,
        p.zona_horaria,
        p.correo_destino,
        p.ultima_clave_periodo,
        e.estado AS estacionamiento_estado,
        e.plan AS estacionamiento_plan,
        e.zona_horaria AS estacionamiento_zona_horaria
      FROM informes_correo_programados p
      JOIN estacionamientos e ON e.id = p.estacionamiento_id
      WHERE p.activo = 1
    `).all();

    let creados = 0;

    for (const programacion of programaciones) {
      if (programacion.estacionamiento_estado !== 'activo' ||
          !esPlanConCorreo(
            programacion.estacionamiento_plan,
            obtenerCapacidadesPlan
          )) {
        continue;
      }

      const zonaHorariaActual = resolverZonaHoraria(
        programacion.estacionamiento_zona_horaria || programacion.zona_horaria
      );
      const periodo = obtenerPeriodoCerrado({
        ...programacion,
        zona_horaria: zonaHorariaActual
      }, fechaActual);

      if (!periodo || periodo.clave === programacion.ultima_clave_periodo) {
        continue;
      }

      const resultado = db.transaction(() => {
        const envio = encolarEnvio({
          estacionamientoId: Number(programacion.estacionamiento_id),
          programacionId: Number(programacion.id),
          frecuencia: programacion.frecuencia,
          periodoClave: periodo.clave,
          fechaInicio: periodo.fechaInicio,
          fechaFin: periodo.fechaFin,
          zonaHoraria: zonaHorariaActual,
          correoDestino: programacion.correo_destino,
          destinatarioUsuarioId: Number(programacion.destinatario_usuario_id),
          claveDeduplicacion:
            `programacion:${programacion.id}:${periodo.clave}`
        });

        db.prepare(`
          UPDATE informes_correo_programados
          SET
            ultima_clave_periodo = ?,
            ultima_ejecucion_en = ?,
            zona_horaria = ?,
            actualizado_en = ?
          WHERE id = ?
            AND estacionamiento_id = ?
        `).run(
          periodo.clave,
          fechaActual.toISOString(),
          zonaHorariaActual,
          fechaActual.toISOString(),
          programacion.id,
          programacion.estacionamiento_id
        );

        return envio;
      })();

      if (resultado.creado) creados += 1;
    }

    return creados;
  }

  function periodoManual({ zonaHoraria, fechaActual = ahora() }) {
    const partes = partesFechaZona(fechaActual, resolverZonaHoraria(zonaHoraria));
    const hoy = {
      year: partes.year,
      month: partes.month,
      day: partes.day
    };
    const inicio = {
      year: hoy.year,
      month: hoy.month,
      day: 1
    };

    return {
      fechaInicio: fechaCalendario(inicio),
      fechaFin: fechaCalendario(hoy)
    };
  }

  function encolarEnvioManual({
    estacionamientoId,
    usuarioId,
    correoDestino,
    fechaInicio,
    fechaFin,
    claveIdempotencia
  }) {
    if (!transporte.disponible) {
      return { correoNoConfigurado: true };
    }

    const estacionamiento = obtenerContextoEstacionamiento(estacionamientoId);

    if (!estacionamiento ||
        estacionamiento.estado !== 'activo' ||
        !esPlanConCorreo(estacionamiento.plan, obtenerCapacidadesPlan)) {
      return { noDisponible: true };
    }

    const clave = textoSeguro(claveIdempotencia, 160);

    if (!clave) {
      return { error: 'Se requiere una clave de idempotencia para solicitar el informe' };
    }

    const periodo = fechaInicio || fechaFin
      ? {
          fechaInicio: fechaInicio || fechaFin,
          fechaFin: fechaFin || fechaInicio
        }
      : periodoManual({ zonaHoraria: estacionamiento.zona_horaria });

    return encolarEnvio({
      estacionamientoId,
      frecuencia: 'manual',
      periodoClave: `manual:${periodo.fechaInicio}:${periodo.fechaFin}`,
      fechaInicio: periodo.fechaInicio,
      fechaFin: periodo.fechaFin,
      zonaHoraria: estacionamiento.zona_horaria,
      correoDestino,
      destinatarioUsuarioId: usuarioId,
      claveDeduplicacion: `manual:${clave}`
    });
  }

  function recuperarReservasVencidas(fecha) {
    const vencidos = db.prepare(`
      SELECT id, estacionamiento_id
      FROM informes_correo_envios
      WHERE estado = 'enviando'
        AND reservado_hasta IS NOT NULL
        AND reservado_hasta < ?
    `).all(fecha);

    if (vencidos.length === 0) return 0;

    db.prepare(`
      UPDATE informes_correo_envios
      SET
        estado = 'reintento',
        disponible_en = ?,
        reservado_hasta = NULL,
        error_publico = 'Se recuperó una reserva interrumpida',
        actualizado_en = ?
      WHERE estado = 'enviando'
        AND reservado_hasta IS NOT NULL
        AND reservado_hasta < ?
    `).run(fecha, fecha, fecha);

    for (const vencido of vencidos) {
      registrarEvento({
        estacionamientoId: vencido.estacionamiento_id,
        envioId: vencido.id,
        tipo: 'RESERVA_RECUPERADA',
        mensaje: 'Se recuperó una reserva interrumpida',
        fecha
      });
    }

    return vencidos.length;
  }

  function reservarSiguiente() {
    const marcaTiempo = ahora().toISOString();

    return db.transaction(() => {
      recuperarReservasVencidas(marcaTiempo);

      const candidata = db.prepare(`
        SELECT *
        FROM informes_correo_envios
        WHERE estado IN ('pendiente', 'reintento')
          AND disponible_en <= ?
        ORDER BY disponible_en ASC, id ASC
        LIMIT 1
      `).get(marcaTiempo);

      if (!candidata) return null;

      const reservadoHasta = new Date(
        new Date(marcaTiempo).getTime() + DURACION_RESERVA_MS
      ).toISOString();
      const reservado = db.prepare(`
        UPDATE informes_correo_envios
        SET
          estado = 'enviando',
          intentos = intentos + 1,
          reservado_hasta = ?,
          actualizado_en = ?
        WHERE id = ?
          AND estado IN ('pendiente', 'reintento')
      `).run(reservadoHasta, marcaTiempo, candidata.id);

      if (reservado.changes !== 1) return null;

      return db.prepare(`
        SELECT *
        FROM informes_correo_envios
        WHERE id = ?
      `).get(candidata.id);
    })();
  }

  function cancelarEnvio({ envio, motivo }) {
    const marcaTiempo = ahora().toISOString();
    db.transaction(() => {
      db.prepare(`
        UPDATE informes_correo_envios
        SET
          estado = 'cancelado',
          reservado_hasta = NULL,
          error_publico = ?,
          actualizado_en = ?
        WHERE id = ?
          AND estacionamiento_id = ?
          AND estado = 'enviando'
      `).run(motivo, marcaTiempo, envio.id, envio.estacionamiento_id);
      registrarEvento({
        estacionamientoId: envio.estacionamiento_id,
        envioId: envio.id,
        tipo: 'CANCELADO',
        mensaje: motivo,
        fecha: marcaTiempo
      });
    })();
  }

  function finalizarEnvio({ envio, proveedorMensajeId }) {
    const marcaTiempo = ahora().toISOString();
    db.transaction(() => {
      db.prepare(`
        UPDATE informes_correo_envios
        SET
          estado = 'enviado',
          reservado_hasta = NULL,
          error_publico = NULL,
          proveedor = ?,
          proveedor_mensaje_id = ?,
          enviado_en = ?,
          actualizado_en = ?
        WHERE id = ?
          AND estacionamiento_id = ?
          AND estado = 'enviando'
      `).run(
        transporte.proveedor,
        textoSeguro(proveedorMensajeId, 180),
        marcaTiempo,
        marcaTiempo,
        envio.id,
        envio.estacionamiento_id
      );
      registrarEvento({
        estacionamientoId: envio.estacionamiento_id,
        envioId: envio.id,
        tipo: 'ENVIADO',
        mensaje: 'El proveedor confirmó la entrega del informe',
        fecha: marcaTiempo
      });
    })();
  }

  function fallarEnvio({ envio, error }) {
    const marcaTiempo = ahora().toISOString();
    const reintentable = Boolean(error?.reintentable) &&
      Number(envio.intentos || 0) < MAX_INTENTOS;
    const demora = DEMORAS_REINTENTO_MS[
      Math.min(
        Math.max(0, Number(envio.intentos || 1) - 1),
        DEMORAS_REINTENTO_MS.length - 1
      )
    ];
    const disponibleEn = new Date(
      new Date(marcaTiempo).getTime() + demora
    ).toISOString();
    const mensaje = textoSeguro(
      error?.mensaje || 'No fue posible enviar el informe',
      220
    );

    db.transaction(() => {
      db.prepare(`
        UPDATE informes_correo_envios
        SET
          estado = ?,
          reservado_hasta = NULL,
          disponible_en = ?,
          error_publico = ?,
          actualizado_en = ?
        WHERE id = ?
          AND estacionamiento_id = ?
          AND estado = 'enviando'
      `).run(
        reintentable ? 'reintento' : 'fallido',
        reintentable ? disponibleEn : marcaTiempo,
        mensaje,
        marcaTiempo,
        envio.id,
        envio.estacionamiento_id
      );
      registrarEvento({
        estacionamientoId: envio.estacionamiento_id,
        envioId: envio.id,
        tipo: reintentable ? 'REINTENTO_PROGRAMADO' : 'FALLIDO',
        mensaje,
        fecha: marcaTiempo
      });
    })();
  }

  async function procesarEnvio(envio) {
    const estacionamiento = obtenerContextoEstacionamiento(
      envio.estacionamiento_id
    );

    if (!estacionamiento || estacionamiento.estado !== 'activo' ||
        !esPlanConCorreo(estacionamiento.plan, obtenerCapacidadesPlan)) {
      cancelarEnvio({
        envio,
        motivo: 'El estacionamiento ya no tiene informes por correo disponibles'
      });
      return { estado: 'cancelado' };
    }

    if (!destinatarioSigueAutorizado({
      estacionamientoId: envio.estacionamiento_id,
      usuarioId: envio.destinatario_usuario_id,
      correo: envio.correo_destino
    })) {
      cancelarEnvio({
        envio,
        motivo: 'El destinatario ya no es un administrador activo del estacionamiento'
      });
      return { estado: 'cancelado' };
    }

    try {
      const informe = servicioInformes.obtenerContabilidad({
        estacionamientoId: envio.estacionamiento_id,
        zonaHoraria: envio.zona_horaria,
        fechaInicio: envio.periodo_inicio,
        fechaFin: envio.periodo_fin
      });
      const csv = servicioInformes.crearCsvContabilidad({ informe });
      const pdf = await servicioInformes.crearPdfResumenContable({
        nombreEstacionamiento: estacionamiento.nombre,
        informe
      });
      const notaCsv = csv.registrosOmitidos > 0
        ? ` El CSV incluye los primeros ${csv.registrosIncluidos} registros; ${csv.registrosOmitidos} quedaron fuera para proteger el tamaño del correo.`
        : '';
      const asunto = `ParkControl · Informe ${envio.frecuencia} ${envio.periodo_inicio}`;
      const html = servicioInformes.crearHtmlResumenContable({
        nombreEstacionamiento: estacionamiento.nombre,
        informe
      }).replace('</body>', `<p>${textoSeguro(notaCsv, 260)}</p></body>`);
      const texto = `${servicioInformes.crearTextoResumenContable({
        nombreEstacionamiento: estacionamiento.nombre,
        informe
      })}${notaCsv}`;
      const respuesta = await transporte.enviar({
        para: envio.correo_destino,
        asunto,
        html,
        texto,
        adjuntos: [
          {
            nombre: `parkcontrol-informe-${envio.periodo_inicio}-${envio.periodo_fin}.pdf`,
            contenido: pdf
          },
          {
            nombre: `parkcontrol-informe-${envio.periodo_inicio}-${envio.periodo_fin}.csv`,
            contenido: Buffer.from(csv.contenido, 'utf8')
          }
        ],
        claveIdempotencia: `informe-correo/${envio.id}`
      });

      finalizarEnvio({
        envio,
        proveedorMensajeId: respuesta.mensajeId
      });
      return { estado: 'enviado' };
    } catch (error) {
      const errorSeguro = error instanceof ErrorTransporteCorreo
        ? error
        : new ErrorTransporteCorreo({
            codigo: 'INFORME_GENERACION_FALLIDA',
            mensaje: 'No fue posible generar el informe para enviarlo',
            reintentable: true
          });
      fallarEnvio({ envio, error: errorSeguro });
      return {
        estado: errorSeguro.reintentable ? 'reintento' : 'fallido'
      };
    }
  }

  async function procesarDisponibles({ limite = 3, incluirProgramacion = true } = {}) {
    if (!transporte.disponible) {
      return {
        procesados: 0,
        configurado: false
      };
    }

    const creados = incluirProgramacion ? programarInformesVencidos() : 0;
    const limiteSeguro = Math.max(1, Math.min(10, Number(limite) || 3));
    let procesados = 0;

    for (let indice = 0; indice < limiteSeguro; indice += 1) {
      const envio = reservarSiguiente();

      if (!envio) break;

      await procesarEnvio(envio);
      procesados += 1;
    }

    return {
      procesados,
      creados,
      configurado: true
    };
  }

  function reintentarEnvio({ estacionamientoId, envioId }) {
    const marcaTiempo = ahora().toISOString();
    const resultado = db.transaction(() => {
      const envio = db.prepare(`
        SELECT id, estado
        FROM informes_correo_envios
        WHERE id = ?
          AND estacionamiento_id = ?
      `).get(envioId, estacionamientoId);

      if (!envio) return { noEncontrada: true };

      if (!['fallido', 'cancelado'].includes(envio.estado)) {
        return { noReintentable: true };
      }

      db.prepare(`
        UPDATE informes_correo_envios
        SET
          estado = 'pendiente',
          intentos = 0,
          disponible_en = ?,
          reservado_hasta = NULL,
          error_publico = NULL,
          actualizado_en = ?
        WHERE id = ?
          AND estacionamiento_id = ?
      `).run(marcaTiempo, marcaTiempo, envioId, estacionamientoId);
      registrarEvento({
        estacionamientoId,
        envioId,
        tipo: 'REINTENTO_MANUAL',
        mensaje: 'Un administrador solicitó reintentar el informe',
        fecha: marcaTiempo
      });
      return { reintentado: true };
    })();

    return resultado;
  }

  return {
    transporteDisponible: Boolean(transporte.disponible),
    proveedor: transporte.proveedor,
    listarProgramaciones,
    listarEnvios,
    guardarProgramacion,
    actualizarProgramacion,
    desactivarProgramacion,
    encolarEnvioManual,
    programarInformesVencidos,
    procesarDisponibles,
    reintentarEnvio,
    obtenerPeriodoCerrado
  };
}

module.exports = {
  crearColaInformesCorreo,
  horaLocalValida,
  enmascararCorreo,
  MAX_INTENTOS
};
