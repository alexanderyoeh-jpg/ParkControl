const express = require('express');
const cors = require('cors');
const Database = require('better-sqlite3');
const PDFDocument = require('pdfkit');
const crypto = require('crypto');
const configuracion = require('./config');
const {
  crearProteccionIntentos
} = require('./proteccion_intentos');
const {
  crearRepositorioOperacionesIdempotentes
} = require('./repositorios/operaciones_idempotentes');
const {
  crearServicioInformesPro
} = require('./servicios/informes_pro');
const {
  crearServicioResumenDiario
} = require('./servicios/resumen_diario');
const {
  formatearFechaPDF
} = require('./servicios/formato_fecha');
const {
  crearTransporteCorreo
} = require('./servicios/transporte_correo');
const {
  crearColaInformesCorreo
} = require('./servicios/cola_informes_correo');

const app = express();
const PORT = configuracion.puerto;
const proteccionLogin = crearProteccionIntentos({
  maxIntentos: configuracion.maxIntentosLogin,
  ventanaMs: configuracion.ventanaIntentosLoginMs
});

app.disable('x-powered-by');

if (configuracion.confiarProxy) {
  app.set('trust proxy', 1);
}

app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store');

  const origen = req.get('origin');

  if (!configuracion.origenPermitido(origen)) {
    return res.status(403).json({
      mensaje: 'Origen no autorizado'
    });
  }

  next();
});

app.use(cors({
  origin(origen, callback) {
    callback(null, configuracion.origenPermitido(origen));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],
  exposedHeaders: ['Idempotency-Replayed']
}));
app.use(express.json({ limit: configuracion.limiteJson }));

// ============================================================
// BASE DE DATOS
// ============================================================

const RUTA_BASE_DATOS = configuracion.rutaBaseDatos;

const db = new Database(RUTA_BASE_DATOS);
const repositorioIdempotencia =
  crearRepositorioOperacionesIdempotentes({ db });

function configurarConexionSqlite() {
  try {
    db.pragma(`busy_timeout = ${configuracion.sqliteBusyTimeoutMs}`);
    const resultadoBusyTimeout = db.pragma('busy_timeout');
    const busyTimeout = Number(
      Object.values(resultadoBusyTimeout?.[0] || {})[0]
    );

    if (busyTimeout !== configuracion.sqliteBusyTimeoutMs) {
      throw new Error(
        `SQLite no confirmó busy_timeout=${configuracion.sqliteBusyTimeoutMs}`
      );
    }

    // WAL permite que las lecturas del dashboard sigan atendidas mientras se
    // registra una operación corta de caja. SQLite puede no admitirlo en un
    // volumen mal configurado; en ese caso se detiene el arranque para no
    // degradar silenciosamente la concurrencia de producción.
    const resultadoModoJournal = db.pragma('journal_mode = WAL');
    const modoJournal = String(
      Object.values(resultadoModoJournal?.[0] || {})[0] || ''
    ).toLowerCase();

    if (modoJournal !== 'wal') {
      throw new Error(
        `SQLite no confirmó journal_mode=WAL (valor recibido: ${modoJournal || 'vacío'})`
      );
    }

    db.pragma('foreign_keys = ON');
  } catch (error) {
    db.close();
    throw new Error(
      `Se rechazó iniciar ParkControl: no fue posible configurar SQLite de forma segura. ${error.message}`
    );
  }
}

configurarConexionSqlite();

// En desarrollo SQLite puede crear una base nueva para facilitar el trabajo
// local. En producción config.js ya exige un archivo existente; antes de
// aplicar migraciones se comprueba que ese archivo esté íntegro y que no haya
// relaciones rotas. Así un despliegue nunca continúa con datos dañados.
if (configuracion.esProduccion) {
  try {
    const resultadoQuickCheck = db.pragma('quick_check');
    const valorQuickCheck = Object.values(
      resultadoQuickCheck?.[0] || {}
    )[0];
    const erroresClavesForaneas = db.pragma('foreign_key_check');

    if (valorQuickCheck !== 'ok' || erroresClavesForaneas.length > 0) {
      throw new Error(
        'La base de datos no superó las comprobaciones de integridad'
      );
    }
  } catch (error) {
    db.close();
    throw new Error(
      `Se rechazó iniciar ParkControl en producción: ${error.message}`
    );
  }
}

// ============================================================
// PLANES Y CAPACIDADES SaaS
// ============================================================
//
// Esta tabla vive en el backend porque el cliente Flutter sólo debe
// representar lo que el servidor autoriza. Nunca se confía en botones
// ocultos o permisos almacenados en la aplicación para proteger un plan.
//
const CAPACIDADES_POR_PLAN = Object.freeze({
  LITE: Object.freeze({
    maxAdministradores: 1,
    maxCajeros: 1,
    boletasPdf: false,
    contabilidadAvanzada: false,
    exportacionDatos: false,
    graficosAvanzados: false,
    reportesPorCorreo: false,
    cierreCaja: false
  }),
  PRO: Object.freeze({
    maxAdministradores: 2,
    maxCajeros: 3,
    boletasPdf: true,
    contabilidadAvanzada: true,
    exportacionDatos: true,
    graficosAvanzados: true,
    reportesPorCorreo: true,
    cierreCaja: true
  })
});

function normalizarPlan(plan) {
  const planNormalizado = String(plan || 'LITE')
    .trim()
    .toUpperCase();

  return Object.prototype.hasOwnProperty.call(
    CAPACIDADES_POR_PLAN,
    planNormalizado
  )
    ? planNormalizado
    : 'LITE';
}

function obtenerCapacidadesPlan(plan) {
  const planNormalizado = normalizarPlan(plan);

  return {
    plan: planNormalizado,
    ...CAPACIDADES_POR_PLAN[planNormalizado]
  };
}

// Las zonas horarias se guardan como identificadores IANA y se convierten a
// la forma canónica que reconoce Node. Las bases antiguas pueden contener un
// valor inválido; al leerlas se usa una alternativa segura, sin modificar los
// datos históricos de manera silenciosa.
const ZONA_HORARIA_POR_DEFECTO = 'America/Santiago';

function normalizarZonaHorariaIana(zonaHoraria) {
  const candidata = String(zonaHoraria ?? '').trim();

  if (!candidata) return null;

  try {
    return new Intl.DateTimeFormat('en-US', {
      timeZone: candidata
    }).resolvedOptions().timeZone || candidata;
  } catch (_) {
    return null;
  }
}

function resolverZonaHoraria(zonaHoraria) {
  return normalizarZonaHorariaIana(zonaHoraria) ||
    ZONA_HORARIA_POR_DEFECTO;
}

function partesFechaZona(fecha, zonaHoraria) {
  const fechaValida = fecha instanceof Date
    ? fecha
    : new Date(fecha);

  if (Number.isNaN(fechaValida.getTime())) {
    return null;
  }

  const partes = new Intl.DateTimeFormat('en-US', {
    timeZone: resolverZonaHoraria(zonaHoraria),
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(fechaValida);

  const valor = tipo => Number(
    partes.find(parte => parte.type === tipo)?.value
  );

  return {
    year: valor('year'),
    month: valor('month'),
    day: valor('day'),
    hour: valor('hour'),
    minute: valor('minute')
  };
}

function claveDia({ year, month, day }) {
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

function sumarDias(fecha, dias) {
  const copia = new Date(
    Date.UTC(fecha.year, fecha.month - 1, fecha.day)
  );
  copia.setUTCDate(copia.getUTCDate() + dias);

  return {
    year: copia.getUTCFullYear(),
    month: copia.getUTCMonth() + 1,
    day: copia.getUTCDate()
  };
}

// La fecha que selecciona un administrador es un día de calendario de su
// estacionamiento, no una fecha del huso horario del VPS. SQLite no conoce
// los identificadores IANA de forma portable, por lo que se limita primero
// una ventana UTC conservadora y luego se confirma el día local con Intl.
// El margen de 18 h cubre todos los husos IANA vigentes sin excluir un cierre
// válido cerca de medianoche.
const MARGEN_ZONA_HORARIA_MS = 18 * 60 * 60 * 1000;

function fechaCalendarioValida(texto) {
  const coincidencia = /^(\d{4})-(\d{2})-(\d{2})$/.exec(texto || '');

  if (!coincidencia) return false;

  const year = Number(coincidencia[1]);
  const month = Number(coincidencia[2]);
  const day = Number(coincidencia[3]);
  const fecha = new Date(Date.UTC(year, month - 1, day));

  return fecha.getUTCFullYear() === year &&
    fecha.getUTCMonth() + 1 === month &&
    fecha.getUTCDate() === day;
}

function inicioUtcAproximadoDia(fechaTexto) {
  const [year, month, day] = fechaTexto.split('-').map(Number);
  return new Date(
    Date.UTC(year, month - 1, day) - MARGEN_ZONA_HORARIA_MS
  ).toISOString();
}

function finUtcAproximadoDiaInclusivo(fechaTexto) {
  const [year, month, day] = fechaTexto.split('-').map(Number);
  return new Date(
    Date.UTC(year, month - 1, day + 1) + MARGEN_ZONA_HORARIA_MS
  ).toISOString();
}

function crearFiltroDiasLocales({ fechaInicio, fechaFin, zonaHoraria }) {
  const inicioAproximado = fechaInicio
    ? inicioUtcAproximadoDia(fechaInicio)
    : null;
  const finAproximadoExclusivo = fechaFin
    ? finUtcAproximadoDiaInclusivo(fechaFin)
    : null;

  return {
    inicioAproximado,
    finAproximadoExclusivo,
    incluye(fecha) {
      if (!fechaInicio && !fechaFin) return true;

      const partes = partesFechaZona(fecha, zonaHoraria);
      if (!partes) return false;

      const clave = claveDia(partes);
      return (!fechaInicio || clave >= fechaInicio) &&
        (!fechaFin || clave <= fechaFin);
    }
  };
}

function crearPeriodoAnalitica(periodoSolicitado, zonaHoraria) {
  const periodo = String(periodoSolicitado || 'mes')
    .trim()
    .toLowerCase();
  const periodoValido = ['dia', 'semana', 'mes', 'semestre', 'ano']
    .includes(periodo)
    ? periodo
    : null;

  if (!periodoValido) {
    return null;
  }

  const ahora = partesFechaZona(new Date(), zonaHoraria);
  const puntos = [];
  const nombresMeses = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];
  const nombresDias = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

  const agregarPunto = ({ clave, etiqueta, disponible }) => {
    puntos.push({
      clave,
      etiqueta,
      disponible,
      ingresos: 0,
      entradas: 0,
      salidas: 0,
      modificaciones: 0,
      eliminaciones: 0
    });
  };

  if (periodo === 'dia') {
    for (let hora = 0; hora < 24; hora++) {
      agregarPunto({
        clave: `${claveDia(ahora)}T${String(hora).padStart(2, '0')}`,
        etiqueta: `${String(hora).padStart(2, '0')}:00`,
        disponible: hora <= ahora.hour
      });
    }
  } else if (periodo === 'semana') {
    const fechaActualUtc = new Date(
      Date.UTC(ahora.year, ahora.month - 1, ahora.day)
    );
    const desplazamientoLunes =
      (fechaActualUtc.getUTCDay() + 6) % 7;
    const lunes = sumarDias(ahora, -desplazamientoLunes);

    for (let indice = 0; indice < 7; indice++) {
      const fecha = sumarDias(lunes, indice);
      const clave = claveDia(fecha);
      agregarPunto({
        clave,
        etiqueta: nombresDias[
          new Date(Date.UTC(fecha.year, fecha.month - 1, fecha.day))
            .getUTCDay()
        ],
        disponible: clave <= claveDia(ahora)
      });
    }
  } else if (periodo === 'mes') {
    const diasMes = new Date(
      Date.UTC(ahora.year, ahora.month, 0)
    ).getUTCDate();

    for (let dia = 1; dia <= diasMes; dia++) {
      const fecha = { year: ahora.year, month: ahora.month, day: dia };
      agregarPunto({
        clave: claveDia(fecha),
        etiqueta: String(dia),
        disponible: dia <= ahora.day
      });
    }
  } else if (periodo === 'semestre') {
    const primerMes = ahora.month <= 6 ? 1 : 7;

    for (let indice = 0; indice < 6; indice++) {
      const mes = primerMes + indice;
      agregarPunto({
        clave: `${ahora.year}-${String(mes).padStart(2, '0')}`,
        etiqueta: nombresMeses[mes - 1],
        disponible: mes <= ahora.month
      });
    }
  } else {
    for (let mes = 1; mes <= 12; mes++) {
      agregarPunto({
        clave: `${ahora.year}-${String(mes).padStart(2, '0')}`,
        etiqueta: nombresMeses[mes - 1],
        disponible: mes <= ahora.month
      });
    }
  }

  const primeraClave = puntos[0]?.clave || claveDia(ahora);

  return {
    periodo,
    ahora,
    puntos,
    primeraClave,
    claveParaFecha(fecha) {
      const partes = partesFechaZona(fecha, zonaHoraria);

      if (!partes) return null;

      if (periodo === 'dia') {
        return `${claveDia(partes)}T${String(partes.hour).padStart(2, '0')}`;
      }

      if (periodo === 'semestre' || periodo === 'ano') {
        return `${partes.year}-${String(partes.month).padStart(2, '0')}`;
      }

      return claveDia(partes);
    }
  };
}

// ============================================================
// CREAR TABLAS
// ============================================================

db.exec(`
  CREATE TABLE IF NOT EXISTS estacionamientos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo TEXT NOT NULL UNIQUE,
    nombre TEXT NOT NULL,
    razon_social TEXT,
    rut TEXT,
    email_contacto TEXT,
    telefono TEXT,
    direccion TEXT,
    plan TEXT NOT NULL DEFAULT 'LITE',
    estado TEXT NOT NULL DEFAULT 'activo',
    zona_horaria TEXT NOT NULL DEFAULT 'America/Santiago',
    fecha_inicio TEXT NOT NULL,
    fecha_vencimiento TEXT,
    fecha_ultimo_pago TEXT,
    motivo_suspension TEXT,
    suspendido_en TEXT,
    suspendido_por INTEGER,
    visible_superadmin INTEGER NOT NULL DEFAULT 1,
    creado_en TEXT NOT NULL,
    actualizado_en TEXT NOT NULL,
    FOREIGN KEY (suspendido_por)
      REFERENCES usuarios(id)
  );

  CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    rol TEXT NOT NULL DEFAULT 'cajero',
    registrarEntradas INTEGER NOT NULL DEFAULT 1,
    registrarSalidas INTEGER NOT NULL DEFAULT 1,
    verReportes INTEGER NOT NULL DEFAULT 0,
    sesionVersion INTEGER NOT NULL DEFAULT 0,
    estacionamiento_id INTEGER,
    activo INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  CREATE TABLE IF NOT EXISTS seguridad_configuracion (
    clave TEXT PRIMARY KEY,
    valor TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS vehiculos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    patente TEXT NOT NULL UNIQUE,
    tipo TEXT NOT NULL,
    color TEXT NOT NULL,
    observacion TEXT,
    horaEntrada TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS vehiculos_estacionamiento (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    patente TEXT NOT NULL,
    tipo TEXT NOT NULL,
    color TEXT NOT NULL,
    observacion TEXT,
    horaEntrada TEXT NOT NULL,
    UNIQUE (estacionamiento_id, patente),
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  CREATE TABLE IF NOT EXISTS tarifas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    tarifa_por_minuto REAL NOT NULL,
    activa INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  CREATE TABLE IF NOT EXISTS movimientos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    patente TEXT NOT NULL,
    tipo TEXT NOT NULL,
    color TEXT NOT NULL,
    observacion TEXT,
    hora_entrada TEXT NOT NULL,
    -- La hora oficial la fija el servidor. Estos dos campos conservan el
    -- valor informado por el dispositivo y el instante en que la API lo
    -- recibió, sin permitir que un reloj local altere caja o contabilidad.
    hora_entrada_reportada TEXT,
    entrada_recibida_en TEXT,
    hora_salida TEXT,
    hora_salida_reportada TEXT,
    salida_recibida_en TEXT,
    origen_salida TEXT NOT NULL DEFAULT 'online',
    minutos INTEGER,
    tarifa_por_minuto REAL,
    monto REAL,
    metodo_pago TEXT,
    usuario_entrada_id INTEGER,
    usuario_salida_id INTEGER,
    turno_caja_id INTEGER,
    estado TEXT NOT NULL DEFAULT 'dentro',
    version INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id),
    FOREIGN KEY (turno_caja_id)
      REFERENCES turnos_caja(id)
  );

  CREATE TABLE IF NOT EXISTS turnos_caja (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    cajero_usuario_id INTEGER NOT NULL,
    abierto_en TEXT NOT NULL,
    cerrado_en TEXT,
    monto_inicial REAL NOT NULL DEFAULT 0,
    monto_recaudado REAL,
    monto_efectivo REAL,
    monto_transferencia REAL,
    monto_tarjeta REAL,
    monto_otros REAL,
    monto_esperado REAL,
    monto_declarado REAL,
    diferencia REAL,
    novedad_apertura TEXT,
    novedad_cierre TEXT,
    vehiculos_dentro_cierre INTEGER,
    estado_revision TEXT NOT NULL DEFAULT 'pendiente',
    revisado_en TEXT,
    revisado_por_usuario_id INTEGER,
    observacion_revision TEXT,
    -- Los turnos v2 totalizan únicamente salidas vinculadas de forma
    -- inmutable. Los turnos anteriores conservan su conciliación histórica.
    version_conciliacion INTEGER NOT NULL DEFAULT 2,
    estado TEXT NOT NULL DEFAULT 'abierto',
    FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id),
    FOREIGN KEY (cajero_usuario_id) REFERENCES usuarios(id)
  );

  CREATE TABLE IF NOT EXISTS turnos_caja_vehiculos_abiertos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    turno_caja_id INTEGER NOT NULL,
    movimiento_id INTEGER NOT NULL,
    patente TEXT NOT NULL,
    tipo TEXT NOT NULL,
    color TEXT NOT NULL,
    hora_entrada TEXT NOT NULL,
    FOREIGN KEY (turno_caja_id) REFERENCES turnos_caja(id),
    FOREIGN KEY (movimiento_id) REFERENCES movimientos(id),
    UNIQUE (turno_caja_id, movimiento_id)
  );

  -- Alertas operativas de alta señal. Se conservan separadas de auditoría:
  -- una alerta representa una tarea para el administrador, mientras la
  -- auditoría conserva el detalle inmutable de las acciones realizadas.
  CREATE TABLE IF NOT EXISTS alertas_administrativas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    tipo TEXT NOT NULL,
    severidad TEXT NOT NULL DEFAULT 'alta',
    estado TEXT NOT NULL DEFAULT 'pendiente',
    entidad_tipo TEXT NOT NULL,
    entidad_id INTEGER NOT NULL,
    clave_deduplicacion TEXT NOT NULL,
    titulo TEXT NOT NULL,
    detalle TEXT NOT NULL,
    monto_diferencia REAL,
    ocurrida_en TEXT NOT NULL,
    revisada_en TEXT,
    revisada_por_usuario_id INTEGER,
    observacion_revision TEXT,
    resuelta_en TEXT,
    resuelta_por_usuario_id INTEGER,
    FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id),
    FOREIGN KEY (revisada_por_usuario_id) REFERENCES usuarios(id),
    FOREIGN KEY (resuelta_por_usuario_id) REFERENCES usuarios(id),
    CHECK (estado IN ('pendiente', 'revisada', 'resuelta'))
  );

  CREATE TABLE IF NOT EXISTS auditoria (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    accion TEXT NOT NULL,
    movimiento_id INTEGER,
    patente_anterior TEXT,
    patente_nueva TEXT,
    tipo_anterior TEXT,
    tipo_nuevo TEXT,
    color_anterior TEXT,
    color_nuevo TEXT,
    observacion_anterior TEXT,
    observacion_nueva TEXT,
    usuario_id INTEGER,
    usuario_nombre TEXT,
    usuario_email TEXT,
    fecha TEXT NOT NULL,
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  CREATE TABLE IF NOT EXISTS pagos_suscripcion (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    monto REAL NOT NULL,
    metodo TEXT NOT NULL,
    fecha_pago TEXT NOT NULL,
    periodo_desde TEXT,
    periodo_hasta TEXT,
    referencia TEXT,
    observacion TEXT,
    fecha_vencimiento_anterior TEXT,
    fecha_ultimo_pago_anterior TEXT,
    estado_cliente_anterior TEXT,
    motivo_suspension_anterior TEXT,
    suspendido_en_anterior TEXT,
    suspendido_por_anterior INTEGER,
    reactivar_solicitado INTEGER NOT NULL DEFAULT 0,
    estado TEXT NOT NULL DEFAULT 'confirmado',
    motivo_anulacion TEXT,
    registrado_por_usuario_id INTEGER NOT NULL,
    creado_en TEXT NOT NULL,
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id),
    FOREIGN KEY (registrado_por_usuario_id)
      REFERENCES usuarios(id)
  );

  -- La suscripción automática se mantiene separada del pago confirmado.
  -- Nunca se guardan PAN, CVV ni tokens de tarjeta: sólo identificadores
  -- externos no sensibles y la representación enmascarada que entregue el
  -- proveedor.
  CREATE TABLE IF NOT EXISTS suscripciones_pago (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL UNIQUE,
    proveedor TEXT NOT NULL,
    suscripcion_externa_id TEXT UNIQUE,
    plan_externo_id TEXT,
    estado TEXT NOT NULL DEFAULT 'no_configurado',
    renovacion_automatica INTEGER NOT NULL DEFAULT 0,
    tarjeta_marca TEXT,
    tarjeta_ultimos4 TEXT,
    proximo_cobro TEXT,
    ultima_sincronizacion TEXT,
    creado_en TEXT NOT NULL,
    actualizado_en TEXT NOT NULL,
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  -- Cada aviso de pasarela se conserva sin su payload crudo. Esto permite
  -- deduplicar y auditar eventos sin guardar datos personales o de tarjeta.
  CREATE TABLE IF NOT EXISTS eventos_pasarela (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    proveedor TEXT NOT NULL,
    evento_externo_id TEXT NOT NULL,
    tipo TEXT,
    recurso_externo_id TEXT,
    estacionamiento_id INTEGER,
    firma_valida INTEGER NOT NULL DEFAULT 0,
    estado_procesamiento TEXT NOT NULL DEFAULT 'pendiente_verificacion',
    hash_payload TEXT NOT NULL,
    recibido_en TEXT NOT NULL,
    procesado_en TEXT,
    error_publico TEXT,
    UNIQUE (proveedor, evento_externo_id),
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  -- Los cobros de un proveedor no se mezclan con pagos manuales: no hay un
  -- usuario humano que los haya registrado y su ciclo incluye rechazos,
  -- reembolsos y contracargos propios de la pasarela.
  CREATE TABLE IF NOT EXISTS pagos_pasarela (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    suscripcion_pago_id INTEGER,
    evento_pasarela_id INTEGER,
    proveedor TEXT NOT NULL,
    pago_externo_id TEXT NOT NULL,
    referencia_externa TEXT,
    estado TEXT NOT NULL,
    monto REAL,
    moneda TEXT,
    comision REAL,
    monto_neto REAL,
    aprobado_en TEXT,
    creado_en TEXT NOT NULL,
    actualizado_en TEXT NOT NULL,
    UNIQUE (proveedor, pago_externo_id),
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id),
    FOREIGN KEY (suscripcion_pago_id)
      REFERENCES suscripciones_pago(id),
    FOREIGN KEY (evento_pasarela_id)
      REFERENCES eventos_pasarela(id)
  );

  -- Informes Pro por correo. Las credenciales del proveedor viven sólo en
  -- variables de entorno; esta cola guarda lo mínimo para entregar y auditar
  -- un informe, sin contenido de adjuntos ni secretos.
  CREATE TABLE IF NOT EXISTS informes_correo_programados (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    creado_por_usuario_id INTEGER NOT NULL,
    destinatario_usuario_id INTEGER NOT NULL,
    frecuencia TEXT NOT NULL,
    hora_local TEXT NOT NULL,
    zona_horaria TEXT NOT NULL,
    correo_destino TEXT NOT NULL,
    activo INTEGER NOT NULL DEFAULT 1,
    ultima_clave_periodo TEXT,
    ultima_ejecucion_en TEXT,
    creado_en TEXT NOT NULL,
    actualizado_en TEXT NOT NULL,
    FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id),
    FOREIGN KEY (creado_por_usuario_id) REFERENCES usuarios(id),
    FOREIGN KEY (destinatario_usuario_id) REFERENCES usuarios(id),
    UNIQUE (estacionamiento_id, frecuencia),
    CHECK (frecuencia IN ('diario', 'semanal', 'mensual')),
    CHECK (activo IN (0, 1))
  );

  CREATE TABLE IF NOT EXISTS informes_correo_envios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    programacion_id INTEGER,
    destinatario_usuario_id INTEGER NOT NULL,
    frecuencia TEXT NOT NULL,
    periodo_clave TEXT NOT NULL,
    periodo_inicio TEXT NOT NULL,
    periodo_fin TEXT NOT NULL,
    zona_horaria TEXT NOT NULL,
    correo_destino TEXT NOT NULL,
    estado TEXT NOT NULL DEFAULT 'pendiente',
    intentos INTEGER NOT NULL DEFAULT 0,
    disponible_en TEXT NOT NULL,
    reservado_hasta TEXT,
    error_publico TEXT,
    proveedor TEXT,
    proveedor_mensaje_id TEXT,
    clave_deduplicacion TEXT NOT NULL,
    creado_en TEXT NOT NULL,
    enviado_en TEXT,
    actualizado_en TEXT NOT NULL,
    FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id),
    FOREIGN KEY (programacion_id) REFERENCES informes_correo_programados(id),
    FOREIGN KEY (destinatario_usuario_id) REFERENCES usuarios(id),
    UNIQUE (estacionamiento_id, clave_deduplicacion),
    CHECK (frecuencia IN ('diario', 'semanal', 'mensual', 'manual')),
    CHECK (estado IN ('pendiente', 'enviando', 'reintento', 'enviado', 'fallido', 'cancelado'))
  );

  CREATE TABLE IF NOT EXISTS informes_correo_eventos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    envio_id INTEGER NOT NULL,
    tipo TEXT NOT NULL,
    mensaje TEXT,
    creado_en TEXT NOT NULL,
    FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id),
    FOREIGN KEY (envio_id) REFERENCES informes_correo_envios(id)
  );

  CREATE TABLE IF NOT EXISTS auditoria_sistema (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    superadmin_id INTEGER NOT NULL,
    accion TEXT NOT NULL,
    entidad TEXT NOT NULL,
    entidad_id INTEGER,
    datos_anteriores TEXT,
    datos_nuevos TEXT,
    motivo TEXT,
    fecha TEXT NOT NULL,
    FOREIGN KEY (superadmin_id)
      REFERENCES usuarios(id)
  );

  CREATE TABLE IF NOT EXISTS operaciones_idempotentes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    tipo TEXT NOT NULL,
    clave TEXT NOT NULL,
    hash_solicitud TEXT NOT NULL,
    estado_http INTEGER NOT NULL,
    respuesta_json TEXT NOT NULL,
    usuario_id INTEGER,
    creado_en TEXT NOT NULL,
    UNIQUE (estacionamiento_id, tipo, clave),
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  CREATE TABLE IF NOT EXISTS abonados (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    nombre_titular TEXT NOT NULL,
    rut TEXT,
    telefono TEXT,
    email TEXT,
    patente TEXT NOT NULL,
    tipo_vehiculo TEXT NOT NULL DEFAULT 'Auto',
    monto_mensual REAL NOT NULL DEFAULT 0,
    fecha_inicio TEXT NOT NULL,
    fecha_vencimiento TEXT NOT NULL,
    estado TEXT NOT NULL DEFAULT 'activo',
    observacion TEXT,
    creado_en TEXT NOT NULL DEFAULT (datetime('now')),
    actualizado_en TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (estacionamiento_id)
      REFERENCES estacionamientos(id)
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_abonados_estacionamiento_patente
    ON abonados (estacionamiento_id, patente);

  CREATE INDEX IF NOT EXISTS idx_abonados_estacionamiento_estado
    ON abonados (estacionamiento_id, estado);

  CREATE TABLE IF NOT EXISTS configuracion_multas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL UNIQUE,
    multa_monto REAL NOT NULL DEFAULT 15000,
    motivo_predeterminado TEXT NOT NULL DEFAULT 'Salida sin pago / Fuga de vehículo',
    actualizado_en TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id)
  );

  CREATE TABLE IF NOT EXISTS morosidad_patentes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    estacionamiento_id INTEGER NOT NULL,
    patente TEXT NOT NULL,
    movimiento_id INTEGER,
    monto_adeudado REAL NOT NULL DEFAULT 0,
    monto_multa REAL NOT NULL DEFAULT 15000,
    monto_pagado REAL NOT NULL DEFAULT 0,
    estado TEXT NOT NULL DEFAULT 'pendiente',
    motivo TEXT DEFAULT 'Salida sin pago / Fuga de vehículo',
    registrado_por_usuario_id INTEGER,
    creado_en TEXT NOT NULL DEFAULT (datetime('now')),
    pagado_en TEXT,
    cobrado_por_usuario_id INTEGER,
    observaciones TEXT,
    FOREIGN KEY (estacionamiento_id) REFERENCES estacionamientos(id),
    FOREIGN KEY (movimiento_id) REFERENCES movimientos(id),
    FOREIGN KEY (registrado_por_usuario_id) REFERENCES usuarios(id),
    FOREIGN KEY (cobrado_por_usuario_id) REFERENCES usuarios(id)
  );

  CREATE INDEX IF NOT EXISTS idx_morosidad_estacionamiento_patente
    ON morosidad_patentes (estacionamiento_id, patente);

  CREATE INDEX IF NOT EXISTS idx_morosidad_estacionamiento_estado
    ON morosidad_patentes (estacionamiento_id, estado);

  CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    nombre TEXT NOT NULL,
    aplicada_en TEXT NOT NULL
  );
`);

// ============================================================
// FUNCIÓN PARA COMPROBAR COLUMNAS
// ============================================================

function obtenerColumnas(tabla) {
  return db
    .prepare(`PRAGMA table_info(${tabla})`)
    .all();
}

function registrarMigracion(version, nombre) {
  db.prepare(`
    INSERT OR IGNORE INTO schema_migrations
    (
      version,
      nombre,
      aplicada_en
    )
    VALUES (?, ?, ?)
  `).run(
    version,
    nombre,
    new Date().toISOString()
  );
}

function migracionAplicada(version) {
  return Boolean(
    db.prepare(`
      SELECT version
      FROM schema_migrations
      WHERE version = ?
    `).get(version)
  );
}

let columnasEstacionamientos = obtenerColumnas('estacionamientos');

if (!columnasEstacionamientos.some(c => c.name === 'visible_superadmin')) {
  db.exec(`
    ALTER TABLE estacionamientos
    ADD COLUMN visible_superadmin INTEGER NOT NULL DEFAULT 1
  `);
}

// Antes de crear el registro de compatibilidad se comprueba si esta base ya
// contenía una operación real. En una instalación nueva el registro queda
// oculto y el panel comienza con cero clientes, no con un cliente ficticio.
const baseConOperacionHeredada = [
  'usuarios',
  'vehiculos',
  'movimientos',
  'tarifas'
].some(tabla =>
  Number(
    db.prepare(`
      SELECT COUNT(*) AS total
      FROM ${tabla}
    `).get().total
  ) > 0
);

// El registro inicial recibe todos los datos que ya existían antes de que
// ParkControl incorporara múltiples clientes. No se borra ni se reemplaza
// ninguna fila de la base actual.
const fechaInicial = new Date().toISOString();

let estacionamientoInicial = db
  .prepare(`
    SELECT id
    FROM estacionamientos
    WHERE codigo = ?
  `)
  .get('principal-inicial');

if (!estacionamientoInicial) {
  const resultadoEstacionamientoInicial = db
    .prepare(`
      INSERT INTO estacionamientos
      (
        codigo,
        nombre,
        plan,
        estado,
        zona_horaria,
        fecha_inicio,
        visible_superadmin,
        creado_en,
        actualizado_en
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .run(
      'principal-inicial',
      'Estacionamiento principal',
      'LITE',
      'activo',
      'America/Santiago',
      fechaInicial,
      baseConOperacionHeredada ? 1 : 0,
      fechaInicial,
      fechaInicial
    );

  estacionamientoInicial = {
    id: Number(
      resultadoEstacionamientoInicial.lastInsertRowid
    )
  };
}

const ESTACIONAMIENTO_INICIAL_ID =
  Number(estacionamientoInicial.id);

// ============================================================
// MIGRACIONES USUARIOS
// ============================================================

let columnasUsuarios = obtenerColumnas('usuarios');

if (!columnasUsuarios.some(c => c.name === 'registrarEntradas')) {
  db.exec(`
    ALTER TABLE usuarios
    ADD COLUMN registrarEntradas INTEGER NOT NULL DEFAULT 1
  `);
}

columnasUsuarios = obtenerColumnas('usuarios');

if (!columnasUsuarios.some(c => c.name === 'registrarSalidas')) {
  db.exec(`
    ALTER TABLE usuarios
    ADD COLUMN registrarSalidas INTEGER NOT NULL DEFAULT 1
  `);
}

columnasUsuarios = obtenerColumnas('usuarios');

if (!columnasUsuarios.some(c => c.name === 'verReportes')) {
  db.exec(`
    ALTER TABLE usuarios
    ADD COLUMN verReportes INTEGER NOT NULL DEFAULT 0
  `);
}

columnasUsuarios = obtenerColumnas('usuarios');

if (!columnasUsuarios.some(c => c.name === 'sesionVersion')) {
  db.exec(`
    ALTER TABLE usuarios
    ADD COLUMN sesionVersion INTEGER NOT NULL DEFAULT 0
  `);
}

columnasUsuarios = obtenerColumnas('usuarios');

if (!columnasUsuarios.some(c => c.name === 'estacionamiento_id')) {
  db.exec(`
    ALTER TABLE usuarios
    ADD COLUMN estacionamiento_id INTEGER
    REFERENCES estacionamientos(id)
  `);
}

columnasUsuarios = obtenerColumnas('usuarios');

if (!columnasUsuarios.some(c => c.name === 'activo')) {
  db.exec(`
    ALTER TABLE usuarios
    ADD COLUMN activo INTEGER NOT NULL DEFAULT 1
  `);
}

db.prepare(`
  UPDATE usuarios
  SET estacionamiento_id = ?
  WHERE estacionamiento_id IS NULL
    AND rol != 'superadmin'
`).run(ESTACIONAMIENTO_INICIAL_ID);

// ============================================================
// MIGRACIONES VEHÍCULOS
// ============================================================

let columnasVehiculos = obtenerColumnas('vehiculos');

if (!columnasVehiculos.some(c => c.name === 'observacion')) {
  db.exec(`
    ALTER TABLE vehiculos
    ADD COLUMN observacion TEXT
  `);
}

// ============================================================
// MIGRACIONES MOVIMIENTOS
// ============================================================

let columnasMovimientos = obtenerColumnas('movimientos');

if (!columnasMovimientos.some(c => c.name === 'observacion')) {
  db.exec(`
    ALTER TABLE movimientos
    ADD COLUMN observacion TEXT
  `);
}

columnasMovimientos = obtenerColumnas('movimientos');

if (!columnasMovimientos.some(c => c.name === 'estado')) {
  db.exec(`
    ALTER TABLE movimientos
    ADD COLUMN estado TEXT NOT NULL DEFAULT 'dentro'
  `);
}

columnasMovimientos = obtenerColumnas('movimientos');

if (!columnasMovimientos.some(c => c.name === 'estacionamiento_id')) {
  db.exec(`
    ALTER TABLE movimientos
    ADD COLUMN estacionamiento_id INTEGER
    REFERENCES estacionamientos(id)
  `);
}

db.prepare(`
  UPDATE movimientos
  SET estacionamiento_id = ?
  WHERE estacionamiento_id IS NULL
`).run(ESTACIONAMIENTO_INICIAL_ID);

columnasMovimientos = obtenerColumnas('movimientos');

if (!columnasMovimientos.some(c => c.name === 'version')) {
  db.exec(`
    ALTER TABLE movimientos
    ADD COLUMN version INTEGER NOT NULL DEFAULT 1
  `);
}

columnasMovimientos = obtenerColumnas('movimientos');

if (!columnasMovimientos.some(c => c.name === 'usuario_entrada_id')) {
  db.exec(`
    ALTER TABLE movimientos
    ADD COLUMN usuario_entrada_id INTEGER
  `);
}

columnasMovimientos = obtenerColumnas('movimientos');

if (!columnasMovimientos.some(c => c.name === 'usuario_salida_id')) {
  db.exec(`
    ALTER TABLE movimientos
    ADD COLUMN usuario_salida_id INTEGER
  `);
}

columnasMovimientos = obtenerColumnas('movimientos');

if (!columnasMovimientos.some(c => c.name === 'metodo_pago')) {
  db.exec(`
    ALTER TABLE movimientos
    ADD COLUMN metodo_pago TEXT
  `);
}

// Integridad de caja v2: las salidas Pro se vinculan al turno que estaba
// abierto en la misma transacción. Nunca se intenta deducir ni reescribir la
// asociación de movimientos históricos, porque eso alteraría una auditoría ya
// cerrada. Las horas reportadas sólo sirven como trazabilidad de dispositivo;
// las columnas hora_entrada/hora_salida continúan siendo oficiales del servidor.
columnasMovimientos = obtenerColumnas('movimientos');

for (const columna of [
  ['turno_caja_id', 'INTEGER REFERENCES turnos_caja(id)'],
  ['hora_entrada_reportada', 'TEXT'],
  ['entrada_recibida_en', 'TEXT'],
  ['hora_salida_reportada', 'TEXT'],
  ['salida_recibida_en', 'TEXT'],
  ['origen_salida', "TEXT NOT NULL DEFAULT 'online'"],
  ['es_abonado', 'INTEGER NOT NULL DEFAULT 0'],
  ['abonado_id', 'INTEGER REFERENCES abonados(id)']
]) {
  if (!columnasMovimientos.some(c => c.name === columna[0])) {
    db.exec(`
      ALTER TABLE movimientos
      ADD COLUMN ${columna[0]} ${columna[1]}
    `);
    columnasMovimientos = obtenerColumnas('movimientos');
  }
}

// ============================================================
// MIGRACIONES TURNOS DE CAJA PRO
// ============================================================

let columnasTurnosCaja = obtenerColumnas('turnos_caja');

for (const columna of [
  ['monto_efectivo', 'REAL'],
  ['monto_transferencia', 'REAL'],
  ['monto_tarjeta', 'REAL'],
  ['monto_otros', 'REAL'],
  ['vehiculos_dentro_cierre', 'INTEGER'],
  ['estado_revision', "TEXT NOT NULL DEFAULT 'pendiente'"],
  ['revisado_en', 'TEXT'],
  ['revisado_por_usuario_id', 'INTEGER'],
  ['observacion_revision', 'TEXT'],
  // Las filas que ya existían se consideran v1 y se cierran con el resumen
  // legado. Todo turno creado desde esta versión nace explícitamente en v2.
  ['version_conciliacion', 'INTEGER NOT NULL DEFAULT 1']
]) {
  if (!columnasTurnosCaja.some(c => c.name === columna[0])) {
    db.exec(`
      ALTER TABLE turnos_caja
      ADD COLUMN ${columna[0]} ${columna[1]}
    `);
    columnasTurnosCaja = obtenerColumnas('turnos_caja');
  }
}

// ============================================================
// MIGRACIONES TARIFAS
// ============================================================

let columnasTarifas = obtenerColumnas('tarifas');

if (!columnasTarifas.some(c => c.name === 'estacionamiento_id')) {
  db.exec(`
    ALTER TABLE tarifas
    ADD COLUMN estacionamiento_id INTEGER
    REFERENCES estacionamientos(id)
  `);
}

db.prepare(`
  UPDATE tarifas
  SET estacionamiento_id = ?
  WHERE estacionamiento_id IS NULL
`).run(ESTACIONAMIENTO_INICIAL_ID);

// ============================================================
// MIGRACIÓN DEFINITIVA DE AUDITORÍA
// ============================================================
//
// IMPORTANTE:
// Esto soluciona específicamente el error:
//
// SQLITE_ERROR:
// table auditoria has no column named patente_anterior
//
// No se borra la tabla.
// No se borran registros.
// Solo se agregan las columnas que falten.
// ============================================================

let columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'accion')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN accion TEXT NOT NULL DEFAULT 'MODIFICACION'
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'movimiento_id')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN movimiento_id INTEGER
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'patente_anterior')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN patente_anterior TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'patente_nueva')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN patente_nueva TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'tipo_anterior')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN tipo_anterior TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'tipo_nuevo')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN tipo_nuevo TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'color_anterior')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN color_anterior TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'color_nuevo')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN color_nuevo TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'observacion_anterior')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN observacion_anterior TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'observacion_nueva')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN observacion_nueva TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'usuario_id')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN usuario_id INTEGER
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'usuario_nombre')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN usuario_nombre TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'usuario_email')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN usuario_email TEXT
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'fecha')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN fecha TEXT NOT NULL DEFAULT ''
  `);
}

columnasAuditoria = obtenerColumnas('auditoria');

if (!columnasAuditoria.some(c => c.name === 'estacionamiento_id')) {
  db.exec(`
    ALTER TABLE auditoria
    ADD COLUMN estacionamiento_id INTEGER
    REFERENCES estacionamientos(id)
  `);
}

db.prepare(`
  UPDATE auditoria
  SET estacionamiento_id = ?
  WHERE estacionamiento_id IS NULL
`).run(ESTACIONAMIENTO_INICIAL_ID);

// ============================================================
// MIGRACIONES DE PAGOS MANUALES
// ============================================================
// Estos datos permiten deshacer de forma segura el efecto comercial de un
// pago anulado, sin borrar el comprobante ni su trazabilidad.

let columnasPagos = obtenerColumnas('pagos_suscripcion');

if (!columnasPagos.some(c => c.name === 'fecha_vencimiento_anterior')) {
  db.exec(`
    ALTER TABLE pagos_suscripcion
    ADD COLUMN fecha_vencimiento_anterior TEXT
  `);
}

columnasPagos = obtenerColumnas('pagos_suscripcion');

if (!columnasPagos.some(c => c.name === 'fecha_ultimo_pago_anterior')) {
  db.exec(`
    ALTER TABLE pagos_suscripcion
    ADD COLUMN fecha_ultimo_pago_anterior TEXT
  `);
}

columnasPagos = obtenerColumnas('pagos_suscripcion');

if (!columnasPagos.some(c => c.name === 'estado_cliente_anterior')) {
  db.exec(`
    ALTER TABLE pagos_suscripcion
    ADD COLUMN estado_cliente_anterior TEXT
  `);
}

columnasPagos = obtenerColumnas('pagos_suscripcion');

if (!columnasPagos.some(c => c.name === 'motivo_suspension_anterior')) {
  db.exec(`
    ALTER TABLE pagos_suscripcion
    ADD COLUMN motivo_suspension_anterior TEXT
  `);
}

columnasPagos = obtenerColumnas('pagos_suscripcion');

if (!columnasPagos.some(c => c.name === 'suspendido_en_anterior')) {
  db.exec(`
    ALTER TABLE pagos_suscripcion
    ADD COLUMN suspendido_en_anterior TEXT
  `);
}

columnasPagos = obtenerColumnas('pagos_suscripcion');

if (!columnasPagos.some(c => c.name === 'suspendido_por_anterior')) {
  db.exec(`
    ALTER TABLE pagos_suscripcion
    ADD COLUMN suspendido_por_anterior INTEGER
  `);
}

columnasPagos = obtenerColumnas('pagos_suscripcion');

if (!columnasPagos.some(c => c.name === 'reactivar_solicitado')) {
  db.exec(`
    ALTER TABLE pagos_suscripcion
    ADD COLUMN reactivar_solicitado INTEGER NOT NULL DEFAULT 0
  `);
}

if (!migracionAplicada(1)) {
  const migrarVehiculosHeredados = db.transaction(() => {
    // Se conserva la tabla vehiculos original como respaldo compatible. La
    // importación se ejecuta una sola vez; luego la operación usa únicamente
    // la tabla aislada por estacionamiento.
    db.prepare(`
      INSERT OR IGNORE INTO vehiculos_estacionamiento
      (
        estacionamiento_id,
        patente,
        tipo,
        color,
        observacion,
        horaEntrada
      )
      SELECT
        ?,
        patente,
        tipo,
        color,
        observacion,
        horaEntrada
      FROM vehiculos
    `).run(ESTACIONAMIENTO_INICIAL_ID);

    registrarMigracion(
      1,
      'Nucleo multi-estacionamiento y datos heredados'
    );
  });

  migrarVehiculosHeredados();
}

// Índices compatibles con bases existentes: se crean sólo después
// de que las migraciones hayan garantizado las columnas necesarias.
db.exec(`
  CREATE INDEX IF NOT EXISTS idx_movimientos_estacionamiento_estado
  ON movimientos (
    estacionamiento_id,
    estado,
    hora_entrada,
    id
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_movimientos_dentro_patente
  ON movimientos (estacionamiento_id, patente)
  WHERE estado = 'dentro';

  CREATE INDEX IF NOT EXISTS idx_auditoria_estacionamiento_movimiento
  ON auditoria (estacionamiento_id, movimiento_id, id);

  CREATE INDEX IF NOT EXISTS idx_usuarios_estacionamiento_rol
  ON usuarios (estacionamiento_id, rol, activo);

  CREATE INDEX IF NOT EXISTS idx_tarifas_estacionamiento_activa
  ON tarifas (estacionamiento_id, activa, id);

  CREATE INDEX IF NOT EXISTS idx_turnos_caja_estacionamiento_cajero
  ON turnos_caja (estacionamiento_id, cajero_usuario_id, estado, abierto_en);

  CREATE UNIQUE INDEX IF NOT EXISTS idx_turnos_caja_un_turno_abierto
  ON turnos_caja (estacionamiento_id)
  WHERE estado = 'abierto';

  CREATE INDEX IF NOT EXISTS idx_movimientos_salida_usuario
  ON movimientos (estacionamiento_id, usuario_salida_id, hora_salida, estado);

  CREATE INDEX IF NOT EXISTS idx_movimientos_turno_caja_salida
  ON movimientos (estacionamiento_id, turno_caja_id, estado, hora_salida);

  CREATE INDEX IF NOT EXISTS idx_turnos_caja_vehiculos_abiertos_turno
  ON turnos_caja_vehiculos_abiertos (turno_caja_id, id);

  CREATE INDEX IF NOT EXISTS idx_alertas_administrativas_estado
  ON alertas_administrativas (
    estacionamiento_id,
    estado,
    ocurrida_en DESC,
    id DESC
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_alertas_administrativas_deduplicacion
  ON alertas_administrativas (estacionamiento_id, clave_deduplicacion);

  CREATE INDEX IF NOT EXISTS idx_pagos_estacionamiento_fecha
  ON pagos_suscripcion (estacionamiento_id, fecha_pago, id);

  CREATE INDEX IF NOT EXISTS idx_eventos_pasarela_pendientes
  ON eventos_pasarela (proveedor, estado_procesamiento, recibido_en, id);

  CREATE INDEX IF NOT EXISTS idx_eventos_pasarela_estacionamiento
  ON eventos_pasarela (estacionamiento_id, recibido_en, id);

  CREATE INDEX IF NOT EXISTS idx_pagos_pasarela_estacionamiento
  ON pagos_pasarela (estacionamiento_id, creado_en, id);

  CREATE INDEX IF NOT EXISTS idx_informes_correo_programados_activos
  ON informes_correo_programados (activo, estacionamiento_id, frecuencia);

  CREATE INDEX IF NOT EXISTS idx_informes_correo_envios_disponibles
  ON informes_correo_envios (estado, disponible_en, id);

  CREATE INDEX IF NOT EXISTS idx_informes_correo_envios_estacionamiento
  ON informes_correo_envios (estacionamiento_id, creado_en, id);

  CREATE INDEX IF NOT EXISTS idx_informes_correo_eventos_envio
  ON informes_correo_eventos (estacionamiento_id, envio_id, id);

  CREATE INDEX IF NOT EXISTS idx_idempotencia_estacionamiento_fecha
  ON operaciones_idempotentes (estacionamiento_id, creado_en, id);
`);

registrarMigracion(
  2,
  'Indices de aislamiento por estacionamiento'
);

registrarMigracion(
  3,
  'Registro idempotente de operaciones sincronizables'
);

registrarMigracion(
  4,
  'Version optimista de movimientos para sincronizacion offline'
);

registrarMigracion(
  5,
  'Base segura para suscripciones y eventos de pasarela'
);

registrarMigracion(
  6,
  'Alertas administrativas Pro de cierres de caja'
);

registrarMigracion(
  7,
  'Cola segura de informes Pro por correo'
);

registrarMigracion(
  8,
  'Integridad v2 de cierre de caja y horas oficiales de operación'
);

// Los informes reutilizan la misma consulta contable que expone la API. Así
// el correo no depende de Flutter, del huso horario del VPS ni de una llamada
// HTTP interna. El transporte permanece deshabilitado hasta que el VPS tenga
// dominio/remitente verificado y una clave de Resend configurada.
const servicioInformesPro = crearServicioInformesPro({
  db,
  resolverZonaHoraria,
  crearFiltroDiasLocales
});
const servicioResumenDiario = crearServicioResumenDiario({
  db,
  resolverZonaHoraria,
  partesFechaZona,
  claveDia,
  crearFiltroDiasLocales
});
const transporteCorreo = crearTransporteCorreo({
  configuracionCorreo: configuracion.correo
});
const colaInformesCorreo = crearColaInformesCorreo({
  db,
  transporte: transporteCorreo,
  servicioInformes: servicioInformesPro,
  obtenerCapacidadesPlan,
  partesFechaZona,
  resolverZonaHoraria
});

// ============================================================
// USUARIO ADMINISTRADOR PRINCIPAL
// ============================================================

const crearUsuariosIniciales = configuracion.crearUsuariosDemo;

if (crearUsuariosIniciales) {
  db.prepare(`
    UPDATE estacionamientos
    SET visible_superadmin = 1
    WHERE id = ?
  `).run(ESTACIONAMIENTO_INICIAL_ID);
}

const usuarioAdmin = db
  .prepare(`
    SELECT id
    FROM usuarios
    WHERE email = ?
  `)
  .get('admin@parkcontrol.cl');

if (!usuarioAdmin && crearUsuariosIniciales) {
  db.prepare(`
    INSERT INTO usuarios
    (
      nombre,
      email,
      password,
      rol,
      registrarEntradas,
      registrarSalidas,
      verReportes,
      estacionamiento_id,
      activo
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
  `).run(
    'Administrador',
    'admin@parkcontrol.cl',
    crearHashPassword('123456'),
    'admin',
    1,
    1,
    1,
    ESTACIONAMIENTO_INICIAL_ID
  );
} else if (usuarioAdmin && crearUsuariosIniciales) {
  db.prepare(`
    UPDATE usuarios
    SET
      registrarEntradas = 1,
      registrarSalidas = 1,
      verReportes = 1,
      estacionamiento_id = COALESCE(
        estacionamiento_id,
        ?
      )
    WHERE email = ?
  `).run(
    ESTACIONAMIENTO_INICIAL_ID,
    'admin@parkcontrol.cl'
  );
}

// ============================================================
// USUARIO CAJERO INICIAL
// ============================================================

const usuarioCajero = db
  .prepare(`
    SELECT id
    FROM usuarios
    WHERE email = ?
  `)
  .get('cajero@parkcontrol.cl');

if (!usuarioCajero && crearUsuariosIniciales) {
  db.prepare(`
    INSERT INTO usuarios
    (
      nombre,
      email,
      password,
      rol,
      registrarEntradas,
      registrarSalidas,
      verReportes,
      estacionamiento_id,
      activo
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
  `).run(
    'Erick',
    'cajero@parkcontrol.cl',
    crearHashPassword('123456'),
    'cajero',
    1,
    1,
    0,
    ESTACIONAMIENTO_INICIAL_ID
  );
}

// ============================================================
// TARIFA INICIAL
// ============================================================

const tarifaExiste = db
  .prepare(`
    SELECT id
    FROM tarifas
    WHERE estacionamiento_id = ?
      AND activa = 1
    ORDER BY id DESC
    LIMIT 1
  `)
  .get(ESTACIONAMIENTO_INICIAL_ID);

if (!tarifaExiste) {
  db.prepare(`
    INSERT INTO tarifas
    (
      tarifa_por_minuto,
      estacionamiento_id,
      activa
    )
    VALUES (?, ?, 1)
  `).run(
    48,
    ESTACIONAMIENTO_INICIAL_ID
  );
}

// ============================================================
// FUNCIONES AUXILIARES
// ============================================================

function normalizarPatente(patente) {
  return String(patente || '')
    .trim()
    .toUpperCase();
}

function normalizarEmail(email) {
  return String(email || '')
    .trim()
    .toLowerCase();
}

function normalizarClaveConfiguracion(valor) {
  return String(valor || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}

function claveIdempotenciaSolicitud(req) {
  return String(req.get('idempotency-key') || '').trim();
}

function consultarOperacionIdempotente({ req, tipo, datos }) {
  return repositorioIdempotencia.consultar({
    estacionamientoId: req.usuario.estacionamientoId,
    clave: claveIdempotenciaSolicitud(req),
    tipo,
    datos
  });
}

function ejecutarOperacionIdempotente({
  req,
  tipo,
  datos,
  operacion
}) {
  return repositorioIdempotencia.ejecutar({
    estacionamientoId: req.usuario.estacionamientoId,
    usuarioId: req.usuario.id,
    clave: claveIdempotenciaSolicitud(req),
    tipo,
    datos,
    operacion
  });
}

function responderOperacionIdempotente(res, resultado) {
  res.setHeader(
    'Idempotency-Replayed',
    resultado.reutilizada ? 'true' : 'false'
  );

  return res
    .status(resultado.estadoHttp)
    .json(resultado.cuerpo);
}

function convertirBooleano(valor, valorPorDefecto = false) {
  if (valor === true || valor === 1) {
    return 1;
  }

  if (valor === false || valor === 0) {
    return 0;
  }

  return valorPorDefecto ? 1 : 0;
}

function obtenerTarifaActiva(estacionamientoId) {
  const tarifa = db
    .prepare(`
      SELECT id, tarifa_por_minuto
      FROM tarifas
      WHERE estacionamiento_id = ?
        AND activa = 1
      ORDER BY id DESC
      LIMIT 1
    `)
    .get(estacionamientoId);

  return tarifa
    ? {
        id: Number(tarifa.id),
        tarifaPorMinuto: Number(tarifa.tarifa_por_minuto)
      }
    : {
        id: null,
        tarifaPorMinuto: 48
      };
}

function obtenerTarifa(estacionamientoId) {
  return obtenerTarifaActiva(estacionamientoId).tarifaPorMinuto;
}

function textoOpcional(valor) {
  const texto = String(valor ?? '').trim();
  return texto || null;
}

const METODOS_PAGO_ESTACIONAMIENTO = Object.freeze([
  'efectivo',
  'transferencia',
  'tarjeta',
  'no_pago',
  'abonado',
  'otro'
]);

function normalizarMetodoPagoEstacionamiento(valor) {
  const metodo = String(valor ?? 'efectivo')
    .trim()
    .toLowerCase();
  const equivalencias = {
    credito: 'tarjeta',
    debito: 'tarjeta',
    tarjeta_credito: 'tarjeta',
    tarjeta_debito: 'tarjeta',
    mercadopago: 'tarjeta',
    no_pago: 'no_pago',
    fuga: 'no_pago',
    moroso: 'no_pago',
    morosidad: 'no_pago'
  };
  const normalizado = equivalencias[metodo] || metodo;

  return METODOS_PAGO_ESTACIONAMIENTO.includes(normalizado)
    ? normalizado
    : 'efectivo';
}

function fechaIsoValida(valor, obligatoria = false) {
  const texto = textoOpcional(valor);

  if (!texto) {
    return obligatoria ? null : undefined;
  }

  // Las fechas de suscripción son días calendario. Se usa mediodía UTC para
  // evitar que al mostrarlas en Chile retrocedan al día anterior.
  const fecha = /^\d{4}-\d{2}-\d{2}$/.test(texto)
    ? new Date(`${texto}T12:00:00.000Z`)
    : new Date(texto);

  return Number.isNaN(fecha.getTime())
    ? null
    : fecha.toISOString();
}

function textoSeguroPasarela(valor, largoMaximo = 180) {
  const texto = String(valor ?? '').trim();

  return texto
    ? texto.slice(0, largoMaximo)
    : null;
}

function extraerFirmaMercadoPago(valor) {
  const campos = new Map();

  for (const parte of String(valor || '').split(',')) {
    const separador = parte.indexOf('=');

    if (separador < 1) continue;

    const clave = parte.slice(0, separador).trim().toLowerCase();
    const dato = parte.slice(separador + 1).trim();

    if (clave && dato && !campos.has(clave)) {
      campos.set(clave, dato);
    }
  }

  return {
    ts: campos.get('ts') || null,
    v1: campos.get('v1') || null
  };
}

function extraerIdRecursoMercadoPago(req) {
  const consulta = req.query || {};
  const cuerpo = req.body && typeof req.body === 'object'
    ? req.body
    : {};
  const valor = consulta['data.id'] ??
    consulta.data_id ??
    cuerpo?.data?.id ??
    cuerpo.data_id ??
    null;

  return textoSeguroPasarela(valor, 180);
}

// Mercado Pago firma el manifiesto con HMAC-SHA256. Se preserva el caso del
// data.id: el SDK oficial actual también lo conserva al formar el manifiesto.
// No basta con que una llamada llegue a esta ruta: sin esta verificación no se
// guarda ni se procesa un evento.
function verificarFirmaWebhookMercadoPago(req) {
  const secreto = configuracion.mercadoPago.webhookSecret;

  if (!secreto) {
    return {
      valida: false,
      motivo: 'WEBHOOK_NO_CONFIGURADO'
    };
  }

  const { ts, v1 } = extraerFirmaMercadoPago(req.get('x-signature'));
  const requestId = textoSeguroPasarela(req.get('x-request-id'), 180);
  const dataId = extraerIdRecursoMercadoPago(req);

  if (!ts || !/^\d{1,16}$/.test(ts) || !v1 || !/^[a-f0-9]{64}$/i.test(v1)) {
    return {
      valida: false,
      motivo: 'FIRMA_INCOMPLETA'
    };
  }

  let manifiesto = '';

  if (dataId) {
    manifiesto += `id:${dataId};`;
  }

  if (requestId) {
    manifiesto += `request-id:${requestId};`;
  }

  manifiesto += `ts:${ts};`;

  const firmaCalculada = crypto
    .createHmac('sha256', secreto)
    .update(manifiesto)
    .digest();
  const firmaRecibida = Buffer.from(v1, 'hex');

  if (firmaCalculada.length !== firmaRecibida.length ||
      !crypto.timingSafeEqual(firmaCalculada, firmaRecibida)) {
    return {
      valida: false,
      motivo: 'FIRMA_INVALIDA'
    };
  }

  return {
    valida: true,
    dataId,
    requestId,
    ts
  };
}

function huellaSeguraEventoPasarela(req) {
  const resumen = {
    tipo: textoSeguroPasarela(req.body?.type || req.body?.topic, 80),
    accion: textoSeguroPasarela(req.body?.action, 120),
    id: textoSeguroPasarela(req.body?.id, 180),
    dataId: extraerIdRecursoMercadoPago(req),
    requestId: textoSeguroPasarela(req.get('x-request-id'), 180)
  };

  return crypto
    .createHash('sha256')
    .update(JSON.stringify(resumen))
    .digest('hex');
}

const LIMITE_FECHA_OPERACION_FUTURA_MS = 5 * 60 * 1000;
const LIMITE_FECHA_OPERACION_ANTIGUA_MS = 30 * 24 * 60 * 60 * 1000;

// El dispositivo puede informar cuándo cree que ocurrió una operación (por
// ejemplo, si estuvo sin red), pero no es una fuente confiable para calcular
// dinero, turnos ni reportes. Esta función sólo valida y normaliza ese dato de
// trazabilidad. La hora oficial siempre se toma cuando el servidor procesa la
// operación mediante crearHoraOperacionOficial().
function fechaOperacionReportadaValida(valor, campo) {
  const texto = textoOpcional(valor);

  if (!texto) {
    return {
      ok: true,
      iso: undefined
    };
  }

  const fecha = new Date(texto);

  if (Number.isNaN(fecha.getTime())) {
    return {
      ok: false,
      mensaje: `${campo} no es una fecha válida`
    };
  }

  const ahora = Date.now();

  if (fecha.getTime() > ahora + LIMITE_FECHA_OPERACION_FUTURA_MS) {
    return {
      ok: false,
      mensaje: `${campo} no puede estar en el futuro`
    };
  }

  if (fecha.getTime() < ahora - LIMITE_FECHA_OPERACION_ANTIGUA_MS) {
    return {
      ok: false,
      mensaje: `${campo} es demasiado antigua para sincronizarse`
    };
  }

  return {
    ok: true,
    iso: fecha.toISOString()
  };
}

function crearHoraOperacionOficial(fechaReportada) {
  const recibidaEn = new Date().toISOString();

  return {
    oficial: recibidaEn,
    recibidaEn,
    reportada: fechaReportada || null
  };
}

function crearCodigoCliente(nombre) {
  const base = String(nombre || 'cliente')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 36) || 'cliente';

  let codigo = base;
  let intento = 1;

  while (db.prepare(`
    SELECT id
    FROM estacionamientos
    WHERE codigo = ?
  `).get(codigo)) {
    intento++;
    codigo = `${base}-${intento}`;
  }

  return codigo;
}

function registrarAuditoriaSistema({
  superadminId,
  accion,
  entidad,
  entidadId = null,
  anterior = null,
  nuevo = null,
  motivo = null
}) {
  db.prepare(`
    INSERT INTO auditoria_sistema
    (
      superadmin_id,
      accion,
      entidad,
      entidad_id,
      datos_anteriores,
      datos_nuevos,
      motivo,
      fecha
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    superadminId,
    accion,
    entidad,
    entidadId,
    anterior == null
      ? null
      : JSON.stringify(anterior),
    nuevo == null
      ? null
      : JSON.stringify(nuevo),
    textoOpcional(motivo),
    new Date().toISOString()
  );
}

function estadoComercialCliente(cliente) {
  if (cliente.estado === 'suspendido') {
    return 'suspendido';
  }

  if (!cliente.fecha_vencimiento) {
    return 'sin_vencimiento';
  }

  const fechaVencimiento = String(
    cliente.fecha_vencimiento
  ).slice(0, 10);
  const vencimiento = new Date(
    `${fechaVencimiento}T12:00:00.000Z`
  );

  if (Number.isNaN(vencimiento.getTime())) {
    return 'sin_vencimiento';
  }

  let fechaActual;

  try {
    const partes = new Intl.DateTimeFormat(
      'en-US',
      {
        timeZone:
          resolverZonaHoraria(cliente.zona_horaria),
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
      }
    ).formatToParts(new Date());

    const parte = tipo =>
      partes.find(item => item.type === tipo)?.value;

    fechaActual = `${parte('year')}-${parte('month')}-${parte('day')}`;
  } catch (_) {
    fechaActual = new Date()
      .toISOString()
      .slice(0, 10);
  }

  if (fechaVencimiento < fechaActual) {
    return 'vencido';
  }

  const hoy = new Date(`${fechaActual}T12:00:00.000Z`);
  const sieteDias = 7 * 24 * 60 * 60 * 1000;

  if (vencimiento.getTime() <=
      hoy.getTime() + sieteDias) {
    return 'por_vencer';
  }

  return 'al_dia';
}

function mapearCliente(cliente) {
  if (!cliente) {
    return null;
  }

  return {
    id: Number(cliente.id),
    codigo: cliente.codigo,
    nombre: cliente.nombre,
    razonSocial: cliente.razon_social || '',
    rut: cliente.rut || '',
    emailContacto: cliente.email_contacto || '',
    telefono: cliente.telefono || '',
    direccion: cliente.direccion || '',
    plan: cliente.plan,
    estado: cliente.estado,
    estadoComercial:
      estadoComercialCliente(cliente),
    zonaHoraria: resolverZonaHoraria(cliente.zona_horaria),
    fechaInicio: cliente.fecha_inicio,
    fechaVencimiento:
      cliente.fecha_vencimiento || null,
    fechaUltimoPago:
      cliente.fecha_ultimo_pago || null,
    referenciaPago:
      cliente.referencia_pago || '',
    observacion:
      cliente.observacion_pago || '',
    motivoSuspension:
      cliente.motivo_suspension || '',
    creadoEn: cliente.creado_en,
    actualizadoEn: cliente.actualizado_en,
    administradorPrincipal:
      cliente.administrador_id == null
        ? null
        : {
            id: Number(cliente.administrador_id),
            nombre: cliente.administrador_nombre,
            email: cliente.administrador_email,
            activo: Boolean(cliente.administrador_activo)
          },
    totalUsuarios:
      Number(cliente.total_usuarios || 0)
  };
}

function consultarClientePorId(id) {
  return db.prepare(`
    SELECT
      e.*,
      (
        SELECT u.id
        FROM usuarios u
        WHERE u.estacionamiento_id = e.id
          AND u.rol IN ('admin', 'admin_estacionamiento')
        ORDER BY u.activo DESC, u.id ASC
        LIMIT 1
      ) AS administrador_id,
      (
        SELECT u.nombre
        FROM usuarios u
        WHERE u.estacionamiento_id = e.id
          AND u.rol IN ('admin', 'admin_estacionamiento')
        ORDER BY u.activo DESC, u.id ASC
        LIMIT 1
      ) AS administrador_nombre,
      (
        SELECT u.email
        FROM usuarios u
        WHERE u.estacionamiento_id = e.id
          AND u.rol IN ('admin', 'admin_estacionamiento')
        ORDER BY u.activo DESC, u.id ASC
        LIMIT 1
      ) AS administrador_email,
      (
        SELECT u.activo
        FROM usuarios u
        WHERE u.estacionamiento_id = e.id
          AND u.rol IN ('admin', 'admin_estacionamiento')
        ORDER BY u.activo DESC, u.id ASC
        LIMIT 1
      ) AS administrador_activo,
      (
        SELECT COUNT(*)
        FROM usuarios u
        WHERE u.estacionamiento_id = e.id
          AND u.activo = 1
      ) AS total_usuarios,
      (
        SELECT p.referencia
        FROM pagos_suscripcion p
        WHERE p.estacionamiento_id = e.id
          AND p.estado = 'confirmado'
        ORDER BY p.fecha_pago DESC, p.id DESC
        LIMIT 1
      ) AS referencia_pago,
      (
        SELECT p.observacion
        FROM pagos_suscripcion p
        WHERE p.estacionamiento_id = e.id
          AND p.estado = 'confirmado'
        ORDER BY p.fecha_pago DESC, p.id DESC
        LIMIT 1
      ) AS observacion_pago
    FROM estacionamientos e
    WHERE e.id = ?
      AND e.visible_superadmin = 1
  `).get(id);
}

function formatearPesos(valor) {
  const numero = Number(valor || 0);

  return `$${numero.toLocaleString(
    'es-CL',
    {
      maximumFractionDigits: 0
    }
  )}`;
}

// ============================================================
// AUTENTICACIÓN Y SESIONES
// ============================================================

const DURACION_SESION_SEGUNDOS = 12 * 60 * 60;

function obtenerClaveConfiguracionInicial() {
  const propietarioConfigurado = Boolean(
    db.prepare(`
      SELECT id
      FROM usuarios
      WHERE rol = 'superadmin'
        AND activo = 1
      LIMIT 1
    `).get()
  );

  if (propietarioConfigurado) {
    db.prepare(`
      DELETE FROM seguridad_configuracion
      WHERE clave = 'superadmin_setup_key'
    `).run();
    return '';
  }

  const clavePorEntorno = normalizarClaveConfiguracion(
    process.env.PARKCONTROL_SETUP_KEY
  );

  if (clavePorEntorno) {
    return clavePorEntorno;
  }

  const claveGuardada = db.prepare(`
    SELECT valor
    FROM seguridad_configuracion
    WHERE clave = 'superadmin_setup_key'
  `).get();
  const claveExistente = normalizarClaveConfiguracion(
    claveGuardada?.valor
  );

  if (claveExistente) {
    return claveExistente;
  }

  const nuevaClave = crypto
    .randomBytes(6)
    .toString('hex')
    .toUpperCase();

  db.prepare(`
    INSERT INTO seguridad_configuracion
    (
      clave,
      valor
    )
    VALUES ('superadmin_setup_key', ?)
    ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor
  `).run(nuevaClave);

  return nuevaClave;
}

const CLAVE_CONFIGURACION_INICIAL =
  obtenerClaveConfiguracionInicial();

function codificarBase64Url(valor) {
  return Buffer
    .from(valor)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function decodificarBase64Url(valor) {
  const base64 = String(valor)
    .replace(/-/g, '+')
    .replace(/_/g, '/');

  const relleno =
    '='.repeat((4 - (base64.length % 4)) % 4);

  return Buffer
    .from(`${base64}${relleno}`, 'base64')
    .toString('utf8');
}

function crearHashPassword(password) {
  const salt = crypto
    .randomBytes(16)
    .toString('hex');

  const hash = crypto
    .scryptSync(password, salt, 64)
    .toString('hex');

  return `scrypt$${salt}$${hash}`;
}

function esHashPassword(valor) {
  return String(valor || '')
    .startsWith('scrypt$');
}

function compararValoresSeguros(izquierdo, derecho) {
  const primerValor = Buffer.from(String(izquierdo));
  const segundoValor = Buffer.from(String(derecho));

  if (primerValor.length !== segundoValor.length) {
    return false;
  }

  return crypto.timingSafeEqual(
    primerValor,
    segundoValor
  );
}

function verificarPassword(password, passwordGuardada) {
  const almacenada = String(passwordGuardada || '');

  if (!esHashPassword(almacenada)) {
    return compararValoresSeguros(
      password,
      almacenada
    );
  }

  const partes = almacenada.split('$');

  if (partes.length !== 3 ||
      !partes[1] ||
      !partes[2]) {
    return false;
  }

  const hashCalculado = crypto
    .scryptSync(password, partes[1], 64)
    .toString('hex');

  return compararValoresSeguros(
    hashCalculado,
    partes[2]
  );
}

// Todas las rutas que crean o reemplazan una contraseña pasan por esta
// política. El cliente Flutter puede mostrar su propia ayuda, pero la regla
// efectiva vive aquí para que una petición directa a la API no pueda eludirla.
function obtenerLongitudMinimaPassword(rol = '') {
  return String(rol).trim().toLowerCase() === 'superadmin'
    ? configuracion.politicaPassword.longitudMinimaSuperadmin
    : configuracion.politicaPassword.longitudMinimaUsuario;
}

function mensajePasswordDemasiadoCorta(
  password,
  {
    rol = '',
    etiqueta = 'La contraseña'
  } = {}
) {
  const longitudMinima = obtenerLongitudMinimaPassword(rol);

  if (String(password || '').length >= longitudMinima) {
    return null;
  }

  return `${etiqueta} debe tener al menos ${longitudMinima} caracteres`;
}

function migrarPasswordsExistentes() {
  const usuariosConPasswordAntigua = db
    .prepare(`
      SELECT
        id,
        password
      FROM usuarios
    `)
    .all()
    .filter(
      usuario =>
        !esHashPassword(usuario.password)
    );

  if (usuariosConPasswordAntigua.length === 0) {
    return;
  }

  const actualizarPassword = db.prepare(`
    UPDATE usuarios
    SET password = ?
    WHERE id = ?
  `);

  const migrar = db.transaction(() => {
    for (const usuario of usuariosConPasswordAntigua) {
      actualizarPassword.run(
        crearHashPassword(usuario.password),
        usuario.id
      );
    }
  });

  migrar();

  console.log(
    `Se protegieron ${usuariosConPasswordAntigua.length} contraseña(s) existente(s).`
  );
}

function obtenerSecretoAutenticacion() {
  const secretoPorEntorno =
    String(
      process.env.PARKCONTROL_AUTH_SECRET || ''
    ).trim();

  if (secretoPorEntorno.length >= 32) {
    return secretoPorEntorno;
  }

  const secretoGuardado = db
    .prepare(`
      SELECT valor
      FROM seguridad_configuracion
      WHERE clave = ?
    `)
    .get('auth_secret');

  if (secretoGuardado?.valor) {
    return secretoGuardado.valor;
  }

  const nuevoSecreto = crypto
    .randomBytes(48)
    .toString('hex');

  db.prepare(`
    INSERT INTO seguridad_configuracion
    (
      clave,
      valor
    )
    VALUES (?, ?)
  `).run(
    'auth_secret',
    nuevoSecreto
  );

  return nuevoSecreto;
}

// Compatible con la base actual: no borra usuarios ni modifica sus datos
// operativos; únicamente transforma contraseñas antiguas a hashes seguros.
migrarPasswordsExistentes();

const secretoAutenticacion =
  obtenerSecretoAutenticacion();

function firmarToken(contenido) {
  return crypto
    .createHmac(
      'sha256',
      secretoAutenticacion
    )
    .update(contenido)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function crearTokenSesion(usuario, opciones = {}) {
  const ahora = Math.floor(Date.now() / 1000);
  const duracion = opciones.duracionSegundos || DURACION_SESION_SEGUNDOS;

  const encabezado = codificarBase64Url(
    JSON.stringify({
      alg: 'HS256',
      typ: 'JWT'
    })
  );

  const payload = {
    sub: usuario.id,
    sv: Number(usuario.sesionVersion || 0),
    iat: ahora,
    exp: ahora + duracion
  };

  if (opciones.estacionamientoId) {
    payload.est = Number(opciones.estacionamientoId);
    payload.sop = true;
    if (opciones.motivo) {
      payload.mot = String(opciones.motivo).slice(0, 500);
    }
  }

  const carga = codificarBase64Url(
    JSON.stringify(payload)
  );

  const contenido = `${encabezado}.${carga}`;

  return `${contenido}.${firmarToken(contenido)}`;
}

function verificarTokenSesion(token) {
  const partes = String(token || '').split('.');

  if (partes.length !== 3) {
    throw new Error('Token con formato inválido');
  }

  const contenido = `${partes[0]}.${partes[1]}`;
  const firmaEsperada = firmarToken(contenido);

  if (!compararValoresSeguros(
        partes[2],
        firmaEsperada
      )) {
    throw new Error('Token con firma inválida');
  }

  const carga = JSON.parse(
    decodificarBase64Url(partes[1])
  );

  const ahora = Math.floor(Date.now() / 1000);

  if (!Number.isInteger(carga.sub) ||
      !Number.isInteger(carga.sv) ||
      !Number.isInteger(carga.exp) ||
      carga.exp <= ahora) {
    throw new Error('Token vencido o inválido');
  }

  return carga;
}

function obtenerTokenSolicitud(req) {
  const autorizacion =
    String(req.get('authorization') || '');

  if (autorizacion.startsWith('Bearer ')) {
    return autorizacion.slice(7).trim();
  }

  // Los tokens de sesión sólo se aceptan en Authorization. Aceptarlos en la
  // URL los expone en historiales, registros de proxy, referers y capturas de
  // navegador. Las descargas de PDF se realizan desde Flutter con headers.
  return '';
}

function requerirAutenticacion(req, res, next) {
  try {
    const token = obtenerTokenSolicitud(req);

    if (!token) {
      return res.status(401).json({
        mensaje: 'Debes iniciar sesión para continuar'
      });
    }

    const carga = verificarTokenSesion(token);

    const usuario = db
      .prepare(`
        SELECT
          u.id,
          u.nombre,
          u.email,
          u.rol,
          u.registrarEntradas,
          u.registrarSalidas,
          u.verReportes,
          u.sesionVersion,
          u.estacionamiento_id,
          u.activo,
          e.nombre AS estacionamiento_nombre,
          e.estado AS estacionamiento_estado,
          e.plan AS estacionamiento_plan
        FROM usuarios u
        LEFT JOIN estacionamientos e
          ON e.id = u.estacionamiento_id
        WHERE u.id = ?
      `)
      .get(carga.sub);

    if (!usuario || !Boolean(usuario.activo)) {
      return res.status(401).json({
        mensaje: 'La sesión ya no es válida'
      });
    }

    if (carga.sop === true && carga.est) {
      if (usuario.rol !== 'superadmin') {
        return res.status(403).json({
          codigo: 'SOLO_SUPERADMIN_PUEDE_DELEGAR',
          mensaje: 'Solo el SuperAdministrador puede ingresar en modo soporte.'
        });
      }

      const targetEst = db.prepare(`
        SELECT id, nombre, estado, plan
        FROM estacionamientos
        WHERE id = ?
      `).get(carga.est);

      if (!targetEst) {
        return res.status(404).json({
          mensaje: 'El estacionamiento objetivo no existe'
        });
      }

      req.usuario = {
        id: usuario.id,
        nombre: usuario.nombre,
        email: usuario.email,
        rol: 'admin',
        rolReal: 'superadmin',
        esSuperadminDelegado: true,
        motivoSoporte: carga.mot || null,
        estacionamientoId: Number(targetEst.id),
        estacionamientoNombre: targetEst.nombre,
        estacionamientoEstado: targetEst.estado,
        estacionamientoPlan: normalizarPlan(targetEst.plan),
        registrarEntradas: true,
        registrarSalidas: true,
        verReportes: true
      };

      return next();
    }

    if (usuario.rol !== 'superadmin' &&
        usuario.estacionamiento_estado !== 'activo') {
      return res.status(403).json({
        codigo: 'ESTACIONAMIENTO_SUSPENDIDO',
        mensaje: 'La cuenta del estacionamiento está suspendida. Contacta a ParkControl.'
      });
    }

    if (Number(usuario.sesionVersion) !== carga.sv) {
      return res.status(401).json({
        mensaje: 'La sesión ya no es válida'
      });
    }

    req.usuario = {
      id: usuario.id,
      nombre: usuario.nombre,
      email: usuario.email,
      rol: usuario.rol,
      estacionamientoId:
        usuario.estacionamiento_id == null
          ? null
          : Number(usuario.estacionamiento_id),
      estacionamientoNombre:
        usuario.estacionamiento_nombre || null,
      estacionamientoEstado:
        usuario.estacionamiento_estado || null,
      estacionamientoPlan:
        usuario.estacionamiento_plan
          ? normalizarPlan(usuario.estacionamiento_plan)
          : null,
      registrarEntradas:
        Boolean(usuario.registrarEntradas),
      registrarSalidas:
        Boolean(usuario.registrarSalidas),
      verReportes:
        Boolean(usuario.verReportes)
    };

    return next();
  } catch (_) {
    return res.status(401).json({
      mensaje: 'La sesión es inválida o venció'
    });
  }
}

function requerirAdministrador(req, res, next) {
  if (req.usuario?.rol === 'admin' ||
      req.usuario?.rol === 'admin_estacionamiento') {
    return next();
  }

  return res.status(403).json({
    mensaje: 'No tienes permisos de administrador'
  });
}

function requerirSuperAdministrador(req, res, next) {
  if (req.usuario?.rol === 'superadmin' || req.usuario?.rolReal === 'superadmin') {
    return next();
  }

  return res.status(403).json({
    codigo: 'SOLO_SUPERADMIN',
    mensaje: 'Esta operación requiere la cuenta propietaria de ParkControl'
  });
}

function requerirEstacionamientoActivo(req, res, next) {
  if (req.usuario?.rol === 'superadmin' && !req.usuario?.esSuperadminDelegado) {
    return res.status(403).json({
      codigo: 'OPERACION_NO_DISPONIBLE_SUPERADMIN',
      mensaje: 'El SuperAdministrador no opera dentro de un estacionamiento'
    });
  }

  if (!Number.isInteger(req.usuario?.estacionamientoId)) {
    return res.status(403).json({
      codigo: 'SIN_ESTACIONAMIENTO',
      mensaje: 'El usuario no tiene un estacionamiento asignado'
    });
  }

  if (!req.usuario?.esSuperadminDelegado &&
      req.usuario.estacionamientoEstado !== 'activo') {
    return res.status(403).json({
      codigo: 'ESTACIONAMIENTO_SUSPENDIDO',
      mensaje: 'La cuenta del estacionamiento está suspendida. Contacta a ParkControl.'
    });
  }

  return next();
}

function requerirPermiso(...permisos) {
  return (req, res, next) => {
    if (req.usuario?.rol === 'admin' ||
        req.usuario?.rol === 'admin_estacionamiento' ||
        permisos.some(
          permiso => req.usuario?.[permiso] === true
        )) {
      return next();
    }

    return res.status(403).json({
      mensaje: 'No tienes permisos para esta operación'
    });
  };
}

function requerirCapacidad(capacidad) {
  return (req, res, next) => {
    const plan = normalizarPlan(
      req.usuario?.estacionamientoPlan
    );
    const capacidades = obtenerCapacidadesPlan(plan);

    if (capacidades[capacidad] === true) {
      return next();
    }

    return res.status(403).json({
      codigo: 'FUNCION_NO_DISPONIBLE_PLAN',
      mensaje: 'Esta función está disponible sólo en el plan Pro',
      plan,
      capacidad
    });
  };
}

function contarUsuariosActivosPorRol(estacionamientoId, rol) {
  const roles = rol === 'admin'
    ? ['admin', 'admin_estacionamiento']
    : ['cajero'];

  const marcadores = roles.map(() => '?').join(', ');

  const resultado = db.prepare(`
    SELECT COUNT(*) AS total
    FROM usuarios
    WHERE estacionamiento_id = ?
      AND activo = 1
      AND rol IN (${marcadores})
  `).get(estacionamientoId, ...roles);

  return Number(resultado?.total || 0);
}

function obtenerLimitesUsuariosPlan(estacionamientoId) {
  const estacionamiento = db.prepare(`
    SELECT plan
    FROM estacionamientos
    WHERE id = ?
  `).get(estacionamientoId);

  const capacidades = obtenerCapacidadesPlan(
    estacionamiento?.plan
  );

  return {
    plan: capacidades.plan,
    maxAdministradores: capacidades.maxAdministradores,
    maxCajeros: capacidades.maxCajeros,
    administradoresActivos: contarUsuariosActivosPorRol(
      estacionamientoId,
      'admin'
    ),
    cajerosActivos: contarUsuariosActivosPorRol(
      estacionamientoId,
      'cajero'
    )
  };
}

function validarCupoUsuario({ estacionamientoId, rol }) {
  const limites = obtenerLimitesUsuariosPlan(estacionamientoId);
  const esAdministrador = rol === 'admin' ||
    rol === 'admin_estacionamiento';
  const total = esAdministrador
    ? limites.administradoresActivos
    : limites.cajerosActivos;
  const maximo = esAdministrador
    ? limites.maxAdministradores
    : limites.maxCajeros;

  if (total >= maximo) {
    return {
      permitido: false,
      limites,
      mensaje: esAdministrador
        ? `El plan ${limites.plan} permite hasta ${maximo} administrador(es) activo(s)`
        : `El plan ${limites.plan} permite hasta ${maximo} cajero(s) activo(s)`
    };
  }

  return {
    permitido: true,
    limites
  };
}

function existeSuperAdministrador() {
  return Boolean(
    db.prepare(`
      SELECT id
      FROM usuarios
      WHERE rol = 'superadmin'
        AND activo = 1
      LIMIT 1
    `).get()
  );
}

function crearSuperAdministrador({
  nombre,
  email,
  password
}) {
  const crear = db.transaction(() => {
    if (existeSuperAdministrador()) {
      const error = new Error(
        'El SuperAdministrador ya fue configurado'
      );
      error.codigo = 'SUPERADMIN_YA_CONFIGURADO';
      throw error;
    }

    const resultado = db.prepare(`
      INSERT INTO usuarios
      (
        nombre,
        email,
        password,
        rol,
        registrarEntradas,
        registrarSalidas,
        verReportes,
        sesionVersion,
        estacionamiento_id,
        activo
      )
      VALUES (?, ?, ?, 'superadmin', 0, 0, 0, 0, NULL, 1)
    `).run(
      nombre,
      email,
      crearHashPassword(password)
    );

    const id = Number(resultado.lastInsertRowid);

    // El código solo existe para reclamar la primera cuenta propietaria.
    // Una vez creada, se elimina de la base y deja de tener utilidad.
    db.prepare(`
      DELETE FROM seguridad_configuracion
      WHERE clave = 'superadmin_setup_key'
    `).run();

    registrarAuditoriaSistema({
      superadminId: id,
      accion: 'CONFIGURACION_INICIAL',
      entidad: 'superadmin',
      entidadId: id,
      nuevo: {
        nombre,
        email
      }
    });

    return db.prepare(`
      SELECT
        id,
        nombre,
        email,
        rol,
        sesionVersion
      FROM usuarios
      WHERE id = ?
    `).get(id);
  });

  return crear();
}

function configurarSuperAdministradorDesdeEntorno() {
  if (existeSuperAdministrador()) {
    return;
  }

  const email = normalizarEmail(
    process.env.PARKCONTROL_SUPERADMIN_EMAIL
  );
  const password = String(
    process.env.PARKCONTROL_SUPERADMIN_PASSWORD || ''
  );

  if (!email && !password) {
    return;
  }

  if (!email || mensajePasswordDemasiadoCorta(password, {
    rol: 'superadmin'
  })) {
    console.warn(
      'No se creó el SuperAdministrador: revisa PARKCONTROL_SUPERADMIN_EMAIL y usa una contraseña de al menos 12 caracteres.'
    );
    return;
  }

  crearSuperAdministrador({
    nombre: String(
      process.env.PARKCONTROL_SUPERADMIN_NOMBRE ||
      'Propietario ParkControl'
    ).trim(),
    email,
    password
  });

  console.log(
    'SuperAdministrador creado de forma segura desde las variables de entorno.'
  );
}

function configuracionInicialPermitida(req) {
  if (configuracion.permitirConfiguracionInicialForzada) {
    return true;
  }

  if (configuracion.esProduccion ||
      configuracion.configuracionInicialDeshabilitada) {
    return false;
  }

  const direccion = String(
    req.socket?.remoteAddress || req.ip || ''
  ).toLowerCase();

  return direccion === '127.0.0.1' ||
    direccion === '::1' ||
    direccion === '::ffff:127.0.0.1';
}

configurarSuperAdministradorDesdeEntorno();

// El bootstrap HTTP se mantiene cerrado en producción. Si la base restaurada
// aún no tiene propietario y tampoco se entregaron las credenciales seguras
// de arranque, es preferible detener la API que publicar un sistema sin una
// vía administrativa controlada.
if (configuracion.esProduccion && !existeSuperAdministrador()) {
  db.close();
  throw new Error(
    'Producción requiere un SuperAdministrador activo. Restaura una base que ya lo contenga o define PARKCONTROL_SUPERADMIN_EMAIL y PARKCONTROL_SUPERADMIN_PASSWORD antes de iniciar.'
  );
}

// ============================================================
// RUTA PRINCIPAL
// ============================================================

// Endpoints operativos para el balanceador y la supervisión del VPS. No
// revelan rutas, usuarios ni datos comerciales y se registran antes de la
// autenticación de /api para que Nginx pueda comprobar la disponibilidad.
app.get('/healthz', (req, res) => {
  return res.status(200).json({ estado: 'ok' });
});

app.get('/readyz', (req, res) => {
  try {
    db.prepare('SELECT 1 AS listo').get();
    return res.status(200).json({ estado: 'listo' });
  } catch (_) {
    return res.status(503).json({ estado: 'no_listo' });
  }
});

app.get('/', (req, res) => {
  res.json({
    mensaje: 'API de ParkControl funcionando',
    estado: 'OK'
  });
});

// ============================================================
// CONFIGURACIÓN INICIAL DEL PROPIETARIO
// ============================================================

app.get('/api/setup/estado', (req, res) => {
  const requiereConfiguracion =
    !existeSuperAdministrador();

  return res.json({
    requiereConfiguracion,
    requiereCodigo: requiereConfiguracion,
    configuracionPermitida:
      configuracionInicialPermitida(req)
  });
});

app.post('/api/setup/superadmin', (req, res) => {
  try {
    if (!configuracionInicialPermitida(req)) {
      return res.status(403).json({
        codigo: 'CONFIGURACION_DESHABILITADA',
        mensaje: 'La configuración inicial solo está disponible localmente o mediante autorización del servidor'
      });
    }

    if (existeSuperAdministrador()) {
      return res.status(409).json({
        codigo: 'SUPERADMIN_YA_CONFIGURADO',
        mensaje: 'El SuperAdministrador ya fue configurado'
      });
    }

    const claveConfiguracion =
      normalizarClaveConfiguracion(
        req.body.claveConfiguracion ||
        req.body.setupKey ||
        req.get('x-parkcontrol-setup-key')
      );

    if (!compararValoresSeguros(
          claveConfiguracion,
          CLAVE_CONFIGURACION_INICIAL
        )) {
      return res.status(403).json({
        codigo: 'CLAVE_CONFIGURACION_INVALIDA',
        mensaje: 'El código no coincide. Usa el mostrado en el último inicio del servidor.'
      });
    }

    const nombre = String(req.body.nombre || '').trim();
    const email = normalizarEmail(req.body.email);
    const password = String(req.body.password || '');

    if (!nombre || !email || !password) {
      return res.status(400).json({
        mensaje: 'Nombre, correo y contraseña son obligatorios'
      });
    }

    if (!/^\S+@\S+\.\S+$/.test(email)) {
      return res.status(400).json({
        mensaje: 'Ingresa un correo electrónico válido'
      });
    }

    const errorPassword = mensajePasswordDemasiadoCorta(password, {
      rol: 'superadmin'
    });

    if (errorPassword) {
      return res.status(400).json({
        mensaje: errorPassword
      });
    }

    const usuario = crearSuperAdministrador({
      nombre,
      email,
      password
    });

    return res.status(201).json({
      mensaje: 'Cuenta propietaria configurada correctamente',
      usuario: {
        id: usuario.id,
        nombre: usuario.nombre,
        email: usuario.email,
        rol: usuario.rol
      }
    });
  } catch (error) {
    if (error.codigo === 'SUPERADMIN_YA_CONFIGURADO') {
      return res.status(409).json({
        codigo: error.codigo,
        mensaje: error.message
      });
    }

    if (String(error.code || '').startsWith('SQLITE_CONSTRAINT')) {
      return res.status(409).json({
        mensaje: 'Ese correo ya pertenece a otro usuario'
      });
    }

    console.error('ERROR CONFIGURAR SUPERADMIN:', error);

    return res.status(500).json({
      mensaje: 'No se pudo configurar la cuenta propietaria'
    });
  }
});

// ============================================================
// VERSIÓN Y ACTUALIZACIONES AUTOMÁTICAS (PÚBLICA)
// ============================================================

app.get('/api/version', (req, res) => {
  return res.json({
    version: '1.0.0',
    versionCode: 1,
    fecha: '2026-08-22',
    nombreApp: 'ParkControl',
    plataformas: {
      android: {
        url: 'https://api.neatspace.cl/downloads/parkcontrol.apk',
        nombreArchivo: 'parkcontrol.apk'
      },
      windows: {
        url: 'https://api.neatspace.cl/downloads/parkcontrol-windows.zip',
        nombreArchivo: 'parkcontrol-windows.zip'
      },
      web: {
        url: 'https://app.neatspace.cl'
      }
    },
    novedades: [
      'Módulo de Abonados y Clientes Mensuales',
      'Impresión Térmica ESC/POS directa (58mm y 80mm)',
      'Modo Offline-First con sincronización automática',
      'Panel SuperAdmin para control de estacionamientos'
    ]
  });
});

// ============================================================
// LOGIN
// ============================================================

app.post('/api/login', (req, res) => {
  try {
    const email = normalizarEmail(req.body.email);
    const password = String(req.body.password || '');

    if (!email || !password) {
      return res.status(400).json({
        mensaje: 'Email y contraseña son obligatorios'
      });
    }

    const claveIntentos = `${req.ip}|${email}`;
    const estadoIntentos = proteccionLogin.obtenerEstado(claveIntentos);

    if (!estadoIntentos.permitido) {
      res.setHeader(
        'Retry-After',
        String(estadoIntentos.reintentarEnSegundos)
      );

      return res.status(429).json({
        codigo: 'DEMASIADOS_INTENTOS_LOGIN',
        mensaje: 'Demasiados intentos. Espera antes de volver a ingresar.'
      });
    }

    const usuario = db
      .prepare(`
        SELECT
          u.id,
          u.nombre,
          u.email,
          u.password,
          u.rol,
          u.registrarEntradas,
          u.registrarSalidas,
          u.verReportes,
          u.sesionVersion,
          u.estacionamiento_id,
          u.activo,
          e.nombre AS estacionamiento_nombre,
          e.estado AS estacionamiento_estado,
          e.plan AS estacionamiento_plan
        FROM usuarios u
        LEFT JOIN estacionamientos e
          ON e.id = u.estacionamiento_id
        WHERE u.email = ?
      `)
      .get(email);

    if (!usuario ||
        !verificarPassword(
          password,
          usuario.password
        )) {
      const nuevoEstado = proteccionLogin.registrarFallo(claveIntentos);

      if (!nuevoEstado.permitido) {
        res.setHeader(
          'Retry-After',
          String(nuevoEstado.reintentarEnSegundos)
        );

        return res.status(429).json({
          codigo: 'DEMASIADOS_INTENTOS_LOGIN',
          mensaje: 'Demasiados intentos. Espera antes de volver a ingresar.'
        });
      }

      return res.status(401).json({
        mensaje: 'Correo o contraseña incorrectos'
      });
    }

    proteccionLogin.limpiar(claveIntentos);

    if (!Boolean(usuario.activo)) {
      return res.status(403).json({
        codigo: 'USUARIO_INACTIVO',
        mensaje: 'Esta cuenta de usuario está desactivada'
      });
    }

    if (usuario.rol !== 'superadmin' &&
        usuario.estacionamiento_estado !== 'activo') {
      return res.status(403).json({
        codigo: 'ESTACIONAMIENTO_SUSPENDIDO',
        mensaje: 'La cuenta del estacionamiento está suspendida. Contacta a ParkControl.'
      });
    }

    if (!esHashPassword(usuario.password)) {
      db.prepare(`
        UPDATE usuarios
        SET password = ?
        WHERE id = ?
      `).run(
        crearHashPassword(password),
        usuario.id
      );
    }

    const token = crearTokenSesion(usuario);

    return res.json({
      mensaje: 'Login exitoso',

      token,

      expiraEnSegundos:
        DURACION_SESION_SEGUNDOS,

      usuario: {
        id: usuario.id,
        nombre: usuario.nombre,
        email: usuario.email,
        rol: usuario.rol,
        estacionamientoId:
          usuario.estacionamiento_id == null
            ? null
            : Number(usuario.estacionamiento_id),
        estacionamientoNombre:
          usuario.estacionamiento_nombre || null,

        plan:
          usuario.estacionamiento_plan
            ? normalizarPlan(usuario.estacionamiento_plan)
            : null,

        capacidades:
          usuario.rol === 'superadmin'
            ? null
            : obtenerCapacidadesPlan(
                usuario.estacionamiento_plan
              ),

        registrarEntradas:
          Boolean(usuario.registrarEntradas),

        registrarSalidas:
          Boolean(usuario.registrarSalidas),

        verReportes:
          Boolean(usuario.verReportes)
      }
    });

  } catch (error) {
    console.error('ERROR LOGIN:', error);

    return res.status(500).json({
      mensaje: 'Error interno del servidor'
    });
  }
});

// ============================================================
// WEBHOOK MERCADO PAGO (BANDEJA SEGURA, SIN EFECTO COMERCIAL)
// ============================================================
// Esta ruta queda fuera de la autenticación de usuarios porque Mercado Pago
// no tiene una sesión ParkControl. La firma HMAC es obligatoria. Por ahora el
// evento sólo entra a la bandeja idempotente; ningún webhook extiende un plan
// hasta que el adaptador consulte el recurso servidor-a-servidor y valide sus
// datos comerciales.
app.post('/api/webhooks/mercadopago', (req, res) => {
  try {
    if (!configuracion.mercadoPago.webhookHabilitado) {
      return res.status(503).json({
        codigo: 'PASARELA_NO_CONFIGURADA',
        mensaje: 'La recepción de notificaciones de pago no está configurada'
      });
    }

    const verificacion = verificarFirmaWebhookMercadoPago(req);

    if (!verificacion.valida) {
      return res.status(401).json({
        codigo: 'FIRMA_WEBHOOK_INVALIDA',
        mensaje: 'La firma de la notificación no es válida'
      });
    }

    const huella = huellaSeguraEventoPasarela(req);
    const idNotificacion = textoSeguroPasarela(req.body?.id, 180);
    const idEventoExterno = idNotificacion
      ? `notificacion:${idNotificacion}`
      : `huella:${huella}`;
    const tipo = textoSeguroPasarela(
      req.body?.type || req.body?.topic || req.body?.action,
      120
    );
    const recibidoEn = new Date().toISOString();
    const resultado = db.prepare(`
      INSERT OR IGNORE INTO eventos_pasarela
      (
        proveedor,
        evento_externo_id,
        tipo,
        recurso_externo_id,
        estacionamiento_id,
        firma_valida,
        estado_procesamiento,
        hash_payload,
        recibido_en
      )
      VALUES (?, ?, ?, ?, NULL, 1, 'pendiente_verificacion', ?, ?)
    `).run(
      'mercadopago',
      idEventoExterno,
      tipo,
      verificacion.dataId,
      huella,
      recibidoEn
    );

    return res.status(resultado.changes > 0 ? 202 : 200).json({
      recibido: true,
      duplicado: resultado.changes === 0,
      procesado: false
    });
  } catch (error) {
    // No se registran headers ni payload de una pasarela: pueden contener
    // datos personales que no pertenecen al log de ParkControl.
    console.error('ERROR RECEPCIÓN WEBHOOK MERCADO PAGO:', error.message);

    return res.status(500).json({
      mensaje: 'No se pudo recibir la notificación de pago'
    });
  }
});

// Todas las rutas de la API, salvo login, requieren una sesión válida.
app.use('/api', requerirAutenticacion);

// ============================================================
// CAPACIDADES DEL PLAN VIGENTE
// ============================================================
// Este endpoint se consulta al abrir un dashboard. Así, un cambio de
// Lite a Pro (o viceversa) se refleja sin que el usuario tenga que volver
// a iniciar sesión, mientras las rutas siguen protegidas por el backend.
app.get('/api/cuenta/capacidades', (req, res) => {
  if (req.usuario.rol === 'superadmin') {
    return res.json({
      rol: 'superadmin',
      estacionamientoId: null,
      plan: null,
      capacidades: null
    });
  }

  const capacidades = obtenerCapacidadesPlan(
    req.usuario.estacionamientoPlan
  );
  const limites = obtenerLimitesUsuariosPlan(
    req.usuario.estacionamientoId
  );

  return res.json({
    rol: req.usuario.rol,
    estacionamientoId: req.usuario.estacionamientoId,
    plan: capacidades.plan,
    capacidades,
    limitesUsuarios: {
      maxAdministradores: limites.maxAdministradores,
      maxCajeros: limites.maxCajeros,
      administradoresActivos: limites.administradoresActivos,
      cajerosActivos: limites.cajerosActivos
    }
  });
});

// ============================================================
// SUSCRIPCIÓN DEL ESTACIONAMIENTO
// ============================================================
// La tarjeta nunca se guarda en ParkControl. Cuando exista un proveedor
// configurado, esta ruta expondrá sólo marca, últimos cuatro dígitos e
// identificadores externos que el proveedor entregue.
app.get('/api/cuenta/suscripcion', requerirAdministrador, (req, res) => {
  try {
    const cliente = db.prepare(`
      SELECT
        plan,
        estado,
        fecha_inicio,
        fecha_vencimiento,
        fecha_ultimo_pago
      FROM estacionamientos
      WHERE id = ?
    `).get(req.usuario.estacionamientoId);

    const ultimoPago = db.prepare(`
      SELECT metodo, fecha_pago, referencia, estado
      FROM pagos_suscripcion
      WHERE estacionamiento_id = ?
      ORDER BY id DESC
      LIMIT 1
    `).get(req.usuario.estacionamientoId);

    const suscripcionAutomatica = db.prepare(`
      SELECT
        proveedor,
        suscripcion_externa_id AS suscripcionExternaId,
        estado,
        renovacion_automatica AS renovacionAutomatica,
        tarjeta_marca AS tarjetaMarca,
        tarjeta_ultimos4 AS tarjetaUltimos4,
        proximo_cobro AS proximoCobro,
        ultima_sincronizacion AS ultimaSincronizacion
      FROM suscripciones_pago
      WHERE estacionamiento_id = ?
      LIMIT 1
    `).get(req.usuario.estacionamientoId);

    if (!cliente) {
      return res.status(404).json({
        mensaje: 'No se encontró la suscripción del estacionamiento'
      });
    }

    const estadoPagoAutomatico = suscripcionAutomatica?.estado ||
      (configuracion.mercadoPago.configuracionCompleta
        ? 'preparado'
        : 'no_configurado');
    const tarjeta = suscripcionAutomatica?.tarjetaMarca &&
        suscripcionAutomatica?.tarjetaUltimos4
      ? {
          marca: suscripcionAutomatica.tarjetaMarca,
          ultimos4: suscripcionAutomatica.tarjetaUltimos4
        }
      : null;

    return res.json({
      plan: normalizarPlan(cliente.plan),
      estado: cliente.estado,
      fechaInicio: cliente.fecha_inicio,
      fechaVencimiento: cliente.fecha_vencimiento,
      fechaUltimoPago: cliente.fecha_ultimo_pago,
      // Se conserva por compatibilidad visual. El último pago no representa
      // necesariamente una tarjeta asociada a una renovación automática.
      metodoActual: ultimoPago?.metodo || 'sin_configurar',
      metodoUltimoPago: ultimoPago?.metodo || 'sin_configurar',
      ultimoPago: ultimoPago
        ? {
            fecha: ultimoPago.fecha_pago,
            referencia: ultimoPago.referencia || '',
            estado: ultimoPago.estado
          }
        : null,
      pagoAutomaticoDisponible: false,
      proveedor: suscripcionAutomatica?.proveedor || 'mercadopago',
      estadoPagoAutomatico,
      renovacionAutomatica: Boolean(
        suscripcionAutomatica?.renovacionAutomatica
      ),
      suscripcionExternaId: suscripcionAutomatica?.suscripcionExternaId || null,
      proximoCobro: suscripcionAutomatica?.proximoCobro || null,
      ultimaSincronizacion:
        suscripcionAutomatica?.ultimaSincronizacion || null,
      tarjeta,
      checkoutUrl: null,
      integracionPasarelaConfigurada:
        configuracion.mercadoPago.configuracionCompleta,
      mensajeConfiguracion:
        configuracion.mercadoPago.configuracionCompleta
          ? 'Mercado Pago está preparado en el servidor. La activación comercial requiere terminar la prueba controlada de checkout y webhook.'
          : 'Mercado Pago aún no está configurado en el servidor. Puedes pagar por transferencia bancaria o efectivo.'
    });
  } catch (error) {
    console.error('ERROR SUSCRIPCIÓN CUENTA:', error);

    return res.status(500).json({
      mensaje: 'No se pudo obtener la información de suscripción'
    });
  }
});

// La creación real del checkout se conecta junto con la consulta directa a la
// API de Mercado Pago. Mientras esa fase no esté terminada, esta ruta falla de
// manera explícita y no crea una suscripción parcial ni una URL inventada.
app.post(
  '/api/cuenta/suscripcion/checkout',
  requerirAdministrador,
  requerirEstacionamientoActivo,
  (req, res) => {
    if (!configuracion.mercadoPago.configuracionCompleta) {
      return res.status(503).json({
        codigo: 'PASARELA_NO_CONFIGURADA',
        mensaje: 'Mercado Pago aún no está configurado para renovaciones automáticas'
      });
    }

    return res.status(501).json({
      codigo: 'CHECKOUT_AUN_NO_HABILITADO',
      mensaje: 'La renovación automática está en preparación. Puedes pagar por transferencia o efectivo mientras finaliza la prueba controlada.'
    });
  }
);

// ============================================================
// TURNOS Y CIERRE DE CAJA PRO
// ============================================================

function obtenerTurnoAbierto(estacionamientoId, usuarioId) {
  return db.prepare(`
    SELECT *
    FROM turnos_caja
    WHERE estacionamiento_id = ?
      AND cajero_usuario_id = ?
      AND estado = 'abierto'
    ORDER BY id DESC
    LIMIT 1
  `).get(estacionamientoId, usuarioId);
}

function obtenerTurnoAbiertoEstacionamiento(estacionamientoId) {
  return db.prepare(`
    SELECT *
    FROM turnos_caja
    WHERE estacionamiento_id = ?
      AND estado = 'abierto'
    ORDER BY id DESC
    LIMIT 1
  `).get(estacionamientoId);
}

function obtenerUltimoTurnoCerrado(estacionamientoId) {
  return db.prepare(`
    SELECT
      t.*,
      u.nombre AS cajero_nombre,
      u.email AS cajero_email
    FROM turnos_caja t
    JOIN usuarios u ON u.id = t.cajero_usuario_id
    WHERE t.estacionamiento_id = ?
      AND t.estado = 'cerrado'
    ORDER BY t.id DESC
    LIMIT 1
  `).get(estacionamientoId);
}

function registrarAuditoriaTurno({
  estacionamientoId,
  accion,
  usuario,
  fecha,
  descripcion
}) {
  db.prepare(`
    INSERT INTO auditoria
    (
      estacionamiento_id,
      accion,
      observacion_nueva,
      usuario_id,
      usuario_nombre,
      usuario_email,
      fecha
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(
    estacionamientoId,
    accion,
    descripcion,
    usuario.id,
    usuario.nombre || null,
    usuario.email || null,
    fecha
  );
}

function registrarAuditoriaAdministrativa({
  estacionamientoId,
  accion,
  usuario,
  descripcion,
  fecha = new Date().toISOString()
}) {
  db.prepare(`
    INSERT INTO auditoria
    (
      estacionamiento_id,
      accion,
      observacion_nueva,
      usuario_id,
      usuario_nombre,
      usuario_email,
      fecha
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(
    estacionamientoId,
    accion,
    textoOpcional(descripcion),
    usuario.id,
    usuario.nombre || null,
    usuario.email || null,
    fecha
  );
}

function resumenCobrosTurno(turno, hasta) {
  const usaVinculoInmutable = Number(
    turno.version_conciliacion || 1
  ) >= 2;
  const consultaBase = `
    SELECT
      COUNT(*) AS salidas,
      COALESCE(SUM(monto), 0) AS recaudado,
      COALESCE(SUM(CASE
        WHEN COALESCE(metodo_pago, 'efectivo') = 'efectivo' THEN monto
        ELSE 0
      END), 0) AS efectivo,
      COALESCE(SUM(CASE
        WHEN metodo_pago = 'transferencia' THEN monto
        ELSE 0
      END), 0) AS transferencia,
      COALESCE(SUM(CASE
        WHEN metodo_pago = 'tarjeta' THEN monto
        ELSE 0
      END), 0) AS tarjeta,
      COALESCE(SUM(CASE
        WHEN metodo_pago = 'otro' THEN monto
        ELSE 0
      END), 0) AS otros
    FROM movimientos
    WHERE estacionamiento_id = ?
      AND estado = 'salio'
  `;
  const resumen = usaVinculoInmutable
    ? db.prepare(`
      ${consultaBase}
        AND turno_caja_id = ?
    `).get(
      turno.estacionamiento_id,
      turno.id
    )
    // Compatibilidad de un turno que ya estaba abierto antes de la migración
    // v2. Al cerrarlo se conserva exactamente la regla histórica, sin
    // inventar vínculos retroactivos. Los turnos nuevos no usan esta rama.
    : db.prepare(`
      ${consultaBase}
        AND usuario_salida_id = ?
        AND hora_salida >= ?
        AND hora_salida <= ?
    `).get(
      turno.estacionamiento_id,
      turno.cajero_usuario_id,
      turno.abierto_en,
      hasta
    );

  return {
    salidas: Number(resumen?.salidas || 0),
    recaudado: Number(resumen?.recaudado || 0),
    efectivo: Number(resumen?.efectivo || 0),
    transferencia: Number(resumen?.transferencia || 0),
    tarjeta: Number(resumen?.tarjeta || 0),
    otros: Number(resumen?.otros || 0)
  };
}

function mapearTurno(turno, resumen = null) {
  if (!turno) return null;

  return {
    id: Number(turno.id),
    versionConciliacion: Number(turno.version_conciliacion || 1),
    cajeroUsuarioId: Number(turno.cajero_usuario_id),
    abiertoEn: turno.abierto_en,
    cerradoEn: turno.cerrado_en || null,
    montoInicial: Number(turno.monto_inicial || 0),
    montoRecaudado: resumen
      ? Number(resumen.recaudado || 0)
      : Number(turno.monto_recaudado || 0),
    montoEfectivo: resumen
      ? Number(resumen.efectivo || 0)
      : Number(
          turno.monto_efectivo == null
            ? (turno.monto_recaudado || 0)
            : turno.monto_efectivo
        ),
    montoTransferencia: resumen
      ? Number(resumen.transferencia || 0)
      : Number(turno.monto_transferencia || 0),
    montoTarjeta: resumen
      ? Number(resumen.tarjeta || 0)
      : Number(turno.monto_tarjeta || 0),
    montoOtros: resumen
      ? Number(resumen.otros || 0)
      : Number(turno.monto_otros || 0),
    montoEsperado: resumen
      ? Number(turno.monto_inicial || 0) + Number(resumen.efectivo || 0)
      : Number(turno.monto_esperado || 0),
    montoDeclarado: turno.monto_declarado == null
      ? null
      : Number(turno.monto_declarado),
    diferencia: turno.diferencia == null ? null : Number(turno.diferencia),
    novedadApertura: turno.novedad_apertura || '',
    novedadCierre: turno.novedad_cierre || '',
    vehiculosDentroAlCierre: Number(turno.vehiculos_dentro_cierre || 0),
    estadoRevision: turno.estado_revision || 'pendiente',
    revisadoEn: turno.revisado_en || null,
    revisadoPorUsuarioId: turno.revisado_por_usuario_id == null
      ? null
      : Number(turno.revisado_por_usuario_id),
    observacionRevision: turno.observacion_revision || '',
    estado: turno.estado,
    salidas: resumen?.salidas ?? null
  };
}

function mapearEntrega(turno) {
  if (!turno) return null;

  return {
    ...mapearTurno(turno),
    cajeroNombre: turno.cajero_nombre || null,
    cajeroEmail: turno.cajero_email || null
  };
}

function registrarAlertaDiferenciaCierre({
  estacionamientoId,
  turnoId,
  diferencia,
  ocurridaEn
}) {
  if (Math.abs(Number(diferencia || 0)) <= 0.009) {
    return false;
  }

  const montoAbsoluto = Math.abs(Number(diferencia)).toFixed(0);
  const tipoDiferencia = Number(diferencia) < 0
    ? 'faltante'
    : 'sobrante';
  const resultado = db.prepare(`
    INSERT OR IGNORE INTO alertas_administrativas
    (
      estacionamiento_id,
      tipo,
      severidad,
      estado,
      entidad_tipo,
      entidad_id,
      clave_deduplicacion,
      titulo,
      detalle,
      monto_diferencia,
      ocurrida_en
    )
    VALUES (?, ?, 'alta', 'pendiente', ?, ?, ?, ?, ?, ?, ?)
  `).run(
    estacionamientoId,
    'CIERRE_CON_DIFERENCIA',
    'turno_caja',
    turnoId,
    `cierre-diferencia:${turnoId}`,
    'Cierre de caja con diferencia',
    `El cierre registra un ${tipoDiferencia} de $${montoAbsoluto} y requiere revisión administrativa.`,
    diferencia,
    ocurridaEn
  );

  return resultado.changes === 1;
}

function actualizarAlertaAlRevisarCierre({
  estacionamientoId,
  turnoId,
  estadoRevision,
  usuarioId,
  observacion,
  revisadoEn
}) {
  if (estadoRevision === 'revisado') {
    return db.prepare(`
      UPDATE alertas_administrativas
      SET
        estado = 'resuelta',
        revisada_en = ?,
        revisada_por_usuario_id = ?,
        observacion_revision = ?,
        resuelta_en = ?,
        resuelta_por_usuario_id = ?
      WHERE estacionamiento_id = ?
        AND entidad_tipo = 'turno_caja'
        AND entidad_id = ?
        AND estado = 'pendiente'
    `).run(
      revisadoEn,
      usuarioId,
      observacion,
      revisadoEn,
      usuarioId,
      estacionamientoId,
      turnoId
    ).changes === 1;
  }

  return db.prepare(`
    UPDATE alertas_administrativas
    SET
      estado = 'revisada',
      revisada_en = ?,
      revisada_por_usuario_id = ?,
      observacion_revision = ?
    WHERE estacionamiento_id = ?
      AND entidad_tipo = 'turno_caja'
      AND entidad_id = ?
      AND estado = 'pendiente'
  `).run(
    revisadoEn,
    usuarioId,
    observacion,
    estacionamientoId,
    turnoId
  ).changes === 1;
}

function mapearAlertaAdministrativa(alerta) {
  return {
    id: Number(alerta.id),
    tipo: alerta.tipo,
    severidad: alerta.severidad,
    estado: alerta.estado,
    entidadTipo: alerta.entidad_tipo,
    entidadId: Number(alerta.entidad_id),
    titulo: alerta.titulo,
    detalle: alerta.detalle,
    montoDiferencia: alerta.monto_diferencia == null
      ? null
      : Number(alerta.monto_diferencia),
    ocurridaEn: alerta.ocurrida_en,
    revisadaEn: alerta.revisada_en || null,
    revisadaPorUsuarioId: alerta.revisada_por_usuario_id == null
      ? null
      : Number(alerta.revisada_por_usuario_id),
    observacionRevision: alerta.observacion_revision || '',
    resueltaEn: alerta.resuelta_en || null,
    resueltaPorUsuarioId: alerta.resuelta_por_usuario_id == null
      ? null
      : Number(alerta.resuelta_por_usuario_id)
  };
}

function requerirCajero(req, res, next) {
  if (req.usuario?.rol === 'cajero') return next();

  return res.status(403).json({
    codigo: 'SOLO_CAJERO',
    mensaje: 'Esta operación está disponible para cajeros'
  });
}

app.get(
  '/api/turnos/actual',
  requerirEstacionamientoActivo,
  requerirCajero,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const turno = obtenerTurnoAbierto(
        req.usuario.estacionamientoId,
        req.usuario.id
      );
      const ahora = new Date().toISOString();

      return res.json({
        turno: turno
          ? mapearTurno(turno, resumenCobrosTurno(turno, ahora))
          : null,
        entregaAnterior: mapearEntrega(
          obtenerUltimoTurnoCerrado(req.usuario.estacionamientoId)
        ),
        consultadoEn: ahora
      });
    } catch (error) {
      console.error('ERROR TURNO ACTUAL:', error);
      return res.status(500).json({
        mensaje: 'No se pudo obtener el turno actual'
      });
    }
  }
);

app.post(
  '/api/turnos/iniciar',
  requerirEstacionamientoActivo,
  requerirCajero,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const montoInicial = Number(req.body.montoInicial ?? 0);
      const novedad = textoOpcional(req.body.novedad);

      if (!Number.isFinite(montoInicial) || montoInicial < 0) {
        return res.status(400).json({
          mensaje: 'El monto inicial no es válido'
        });
      }

      const iniciarTurno = db.transaction(() => {
        const existente = obtenerTurnoAbiertoEstacionamiento(
          req.usuario.estacionamientoId
        );

        if (existente) {
          return { existente };
        }

        const abiertoEn = new Date().toISOString();
        const resultado = db.prepare(`
          INSERT INTO turnos_caja
          (
            estacionamiento_id,
            cajero_usuario_id,
            abierto_en,
            monto_inicial,
            novedad_apertura,
            version_conciliacion,
            estado
          )
          VALUES (?, ?, ?, ?, ?, 2, 'abierto')
        `).run(
          req.usuario.estacionamientoId,
          req.usuario.id,
          abiertoEn,
          montoInicial,
          novedad
        );
        const turno = db.prepare(`
          SELECT * FROM turnos_caja WHERE id = ?
        `).get(resultado.lastInsertRowid);

        registrarAuditoriaTurno({
          estacionamientoId: req.usuario.estacionamientoId,
          accion: 'TURNO_INICIADO',
          usuario: req.usuario,
          fecha: abiertoEn,
          descripcion: `Turno ${turno.id} iniciado con fondo de caja ${montoInicial}`
        });

        return {
          turno,
          entregaAnterior: obtenerUltimoTurnoCerrado(
            req.usuario.estacionamientoId
          )
        };
      });

      const resultadoInicio = iniciarTurno();

      if (resultadoInicio.existente) {
        const existente = resultadoInicio.existente;
        return res.status(409).json({
          codigo: existente.cajero_usuario_id === req.usuario.id
            ? 'TURNO_ABIERTO_EXISTENTE'
            : 'TURNO_ESTACIONAMIENTO_ABIERTO',
          mensaje: existente.cajero_usuario_id === req.usuario.id
            ? 'Ya tienes un turno de caja abierto'
            : 'Otro cajero mantiene un turno de caja abierto',
          turno: mapearTurno(
            existente,
            resumenCobrosTurno(existente, new Date().toISOString())
          )
        });
      }

      return res.status(201).json({
        mensaje: 'Turno iniciado correctamente',
        turno: mapearTurno(resultadoInicio.turno, {
          salidas: 0,
          recaudado: 0
        }),
        entregaAnterior: mapearEntrega(resultadoInicio.entregaAnterior)
      });
    } catch (error) {
      console.error('ERROR INICIAR TURNO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo iniciar el turno'
      });
    }
  }
);

app.post(
  '/api/turnos/:id/cerrar',
  requerirEstacionamientoActivo,
  requerirCajero,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const montoDeclarado = Number(req.body.montoDeclarado);
      const novedad = textoOpcional(req.body.novedad);

      if (!Number.isInteger(id) || !Number.isFinite(montoDeclarado) ||
          montoDeclarado < 0) {
        return res.status(400).json({
          mensaje: 'Revisa el turno y el monto declarado'
        });
      }

      const cerrarTurno = db.transaction(() => {
        const turno = db.prepare(`
          SELECT *
          FROM turnos_caja
          WHERE id = ?
            AND estacionamiento_id = ?
            AND cajero_usuario_id = ?
            AND estado = 'abierto'
        `).get(id, req.usuario.estacionamientoId, req.usuario.id);

        if (!turno) {
          return null;
        }

        const cerradoEn = new Date().toISOString();
        const resumen = resumenCobrosTurno(turno, cerradoEn);
        const esperado = Number(turno.monto_inicial || 0) + resumen.efectivo;
        const diferencia = montoDeclarado - esperado;
        const vehiculosDentro = db.prepare(`
          SELECT id, patente, tipo, color, hora_entrada
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND estado = 'dentro'
          ORDER BY hora_entrada ASC, id ASC
        `).all(req.usuario.estacionamientoId);

        db.prepare(`
          UPDATE turnos_caja
          SET
            cerrado_en = ?,
            monto_recaudado = ?,
            monto_efectivo = ?,
            monto_transferencia = ?,
            monto_tarjeta = ?,
            monto_otros = ?,
            monto_esperado = ?,
            monto_declarado = ?,
            diferencia = ?,
            novedad_cierre = ?,
            vehiculos_dentro_cierre = ?,
            estado = 'cerrado'
          WHERE id = ?
            AND estado = 'abierto'
        `).run(
          cerradoEn,
          resumen.recaudado,
          resumen.efectivo,
          resumen.transferencia,
          resumen.tarjeta,
          resumen.otros,
          esperado,
          montoDeclarado,
          diferencia,
          novedad,
          vehiculosDentro.length,
          id
        );

        const insertarVehiculoAbierto = db.prepare(`
          INSERT OR IGNORE INTO turnos_caja_vehiculos_abiertos
          (
            turno_caja_id,
            movimiento_id,
            patente,
            tipo,
            color,
            hora_entrada
          )
          VALUES (?, ?, ?, ?, ?, ?)
        `);

        for (const vehiculo of vehiculosDentro) {
          insertarVehiculoAbierto.run(
            id,
            vehiculo.id,
            vehiculo.patente,
            vehiculo.tipo,
            vehiculo.color,
            vehiculo.hora_entrada
          );
        }

        const alertaCreada = registrarAlertaDiferenciaCierre({
          estacionamientoId: req.usuario.estacionamientoId,
          turnoId: id,
          diferencia,
          ocurridaEn: cerradoEn
        });

        registrarAuditoriaTurno({
          estacionamientoId: req.usuario.estacionamientoId,
          accion: 'CIERRE_CAJA',
          usuario: req.usuario,
          fecha: cerradoEn,
          descripcion: `Turno ${id} cerrado. Efectivo esperado: ${esperado}; declarado: ${montoDeclarado}; diferencia: ${diferencia}; transferencia: ${resumen.transferencia}; tarjeta: ${resumen.tarjeta}; vehículos dentro: ${vehiculosDentro.length}`
        });

        if (alertaCreada) {
          registrarAuditoriaTurno({
            estacionamientoId: req.usuario.estacionamientoId,
            accion: 'ALERTA_CIERRE_DIFERENCIA_CREADA',
            usuario: req.usuario,
            fecha: cerradoEn,
            descripcion: `Alerta creada para el turno ${id} por diferencia de caja ${diferencia}.`
          });
        }

        return db.prepare(`
          SELECT * FROM turnos_caja WHERE id = ?
        `).get(id);
      });

      const turnoCerrado = cerrarTurno();

      if (!turnoCerrado) {
        return res.status(404).json({
          mensaje: 'No se encontró un turno abierto para cerrar'
        });
      }

      return res.json({
        mensaje: 'Cierre de caja registrado correctamente',
        turno: mapearTurno(turnoCerrado)
      });
    } catch (error) {
      console.error('ERROR CERRAR TURNO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo cerrar el turno'
      });
    }
  }
);

app.get(
  '/api/pro/alertas',
  requerirEstacionamientoActivo,
  requerirAdministrador,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const estacionamientoId = req.usuario.estacionamientoId;
      const resumen = db.prepare(`
        SELECT
          COALESCE(SUM(CASE WHEN estado = 'pendiente' THEN 1 ELSE 0 END), 0)
            AS pendientes,
          COALESCE(SUM(CASE
            WHEN estado = 'pendiente' AND severidad = 'alta' THEN 1
            ELSE 0
          END), 0) AS criticas,
          COALESCE(SUM(CASE WHEN estado = 'revisada' THEN 1 ELSE 0 END), 0)
            AS revisadas,
          COALESCE(SUM(CASE WHEN estado = 'resuelta' THEN 1 ELSE 0 END), 0)
            AS resueltas
        FROM alertas_administrativas
        WHERE estacionamiento_id = ?
      `).get(estacionamientoId);
      const alertas = db.prepare(`
        SELECT *
        FROM alertas_administrativas
        WHERE estacionamiento_id = ?
        ORDER BY
          CASE estado
            WHEN 'pendiente' THEN 0
            WHEN 'revisada' THEN 1
            ELSE 2
          END ASC,
          ocurrida_en DESC,
          id DESC
        LIMIT 50
      `).all(estacionamientoId).map(mapearAlertaAdministrativa);

      return res.json({
        actualizadoEn: new Date().toISOString(),
        resumen: {
          pendientes: Number(resumen?.pendientes || 0),
          criticas: Number(resumen?.criticas || 0),
          revisadas: Number(resumen?.revisadas || 0),
          resueltas: Number(resumen?.resueltas || 0)
        },
        alertas
      });
    } catch (error) {
      console.error('ERROR LISTAR ALERTAS PRO:', error);
      return res.status(500).json({
        mensaje: 'No se pudieron obtener las alertas administrativas'
      });
    }
  }
);

app.get(
  '/api/pro/turnos',
  requerirEstacionamientoActivo,
  requerirAdministrador,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const ahora = new Date().toISOString();
      const turnos = db.prepare(`
        SELECT
          t.*,
          u.nombre AS cajero_nombre,
          u.email AS cajero_email,
          revisor.nombre AS revisor_nombre,
          revisor.email AS revisor_email
        FROM turnos_caja t
        JOIN usuarios u ON u.id = t.cajero_usuario_id
        LEFT JOIN usuarios revisor ON revisor.id = t.revisado_por_usuario_id
        WHERE t.estacionamiento_id = ?
        ORDER BY t.id DESC
      `).all(req.usuario.estacionamientoId).map(turno => ({
        ...mapearTurno(
          turno,
          turno.estado === 'abierto'
            ? resumenCobrosTurno(turno, ahora)
            : null
        ),
        cajeroNombre: turno.cajero_nombre,
        cajeroEmail: turno.cajero_email,
        revisorNombre: turno.revisor_nombre || null,
        revisorEmail: turno.revisor_email || null
      }));

      return res.json({ turnos });
    } catch (error) {
      console.error('ERROR LISTAR TURNOS PRO:', error);
      return res.status(500).json({
        mensaje: 'No se pudieron obtener los turnos'
      });
    }
  }
);

app.get(
  '/api/pro/turnos/:id/vehiculos-abiertos',
  requerirEstacionamientoActivo,
  requerirAdministrador,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const turnoId = Number(req.params.id);
      if (!Number.isInteger(turnoId) || turnoId < 1) {
        return res.status(400).json({
          mensaje: 'El identificador de turno no es válido'
        });
      }

      const turno = db.prepare(`
        SELECT id
        FROM turnos_caja
        WHERE id = ?
          AND estacionamiento_id = ?
      `).get(turnoId, req.usuario.estacionamientoId);

      if (!turno) {
        return res.status(404).json({
          mensaje: 'El turno no pertenece a este estacionamiento'
        });
      }

      const vehiculos = db.prepare(`
        SELECT
          movimiento_id AS movimientoId,
          patente,
          tipo,
          color,
          hora_entrada AS horaEntrada
        FROM turnos_caja_vehiculos_abiertos
        WHERE turno_caja_id = ?
        ORDER BY hora_entrada ASC, id ASC
      `).all(turnoId);

      return res.json({ vehiculos });
    } catch (error) {
      console.error('ERROR VEHÍCULOS ABIERTOS DEL TURNO:', error);
      return res.status(500).json({
        mensaje: 'No se pudieron obtener los vehículos del cierre'
      });
    }
  }
);

app.post(
  '/api/pro/turnos/:id/revision',
  requerirEstacionamientoActivo,
  requerirAdministrador,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const turnoId = Number(req.params.id);
      const estadoRevision = String(req.body.estadoRevision || '')
        .trim()
        .toLowerCase();
      const observacion = textoOpcional(req.body.observacion);

      if (!Number.isInteger(turnoId) || turnoId < 1) {
        return res.status(400).json({
          mensaje: 'El identificador de turno no es válido'
        });
      }

      if (!['revisado', 'observado'].includes(estadoRevision)) {
        return res.status(400).json({
          mensaje: 'La revisión debe ser revisado u observado'
        });
      }

      if (estadoRevision === 'observado' && !observacion) {
        return res.status(400).json({
          mensaje: 'Describe la observación del cierre antes de registrarla'
        });
      }

      const revisar = db.transaction(() => {
        const turno = db.prepare(`
          SELECT *
          FROM turnos_caja
          WHERE id = ?
            AND estacionamiento_id = ?
            AND estado = 'cerrado'
        `).get(turnoId, req.usuario.estacionamientoId);

        if (!turno) return { tipo: 'no_encontrado' };

        if ((turno.estado_revision || 'pendiente') !== 'pendiente') {
          return { tipo: 'ya_revisado' };
        }

        const revisadoEn = new Date().toISOString();
        db.prepare(`
          UPDATE turnos_caja
          SET
            estado_revision = ?,
            revisado_en = ?,
            revisado_por_usuario_id = ?,
            observacion_revision = ?
          WHERE id = ?
            AND estado_revision = 'pendiente'
        `).run(
          estadoRevision,
          revisadoEn,
          req.usuario.id,
          observacion,
          turnoId
        );

        const alertaActualizada = actualizarAlertaAlRevisarCierre({
          estacionamientoId: req.usuario.estacionamientoId,
          turnoId,
          estadoRevision,
          usuarioId: req.usuario.id,
          observacion,
          revisadoEn
        });

        registrarAuditoriaTurno({
          estacionamientoId: req.usuario.estacionamientoId,
          accion: 'REVISION_CIERRE_CAJA',
          usuario: req.usuario,
          fecha: revisadoEn,
          descripcion: `Turno ${turnoId} ${estadoRevision}. ${observacion || 'Sin observaciones.'}`
        });

        if (alertaActualizada) {
          registrarAuditoriaTurno({
            estacionamientoId: req.usuario.estacionamientoId,
            accion: estadoRevision === 'revisado'
              ? 'ALERTA_CIERRE_RESUELTA'
              : 'ALERTA_CIERRE_REVISADA',
            usuario: req.usuario,
            fecha: revisadoEn,
            descripcion: `Alerta del turno ${turnoId} actualizada a ${estadoRevision === 'revisado' ? 'resuelta' : 'revisada'}.`
          });
        }

        return {
          tipo: 'ok',
          turno: db.prepare(`
            SELECT * FROM turnos_caja WHERE id = ?
          `).get(turnoId)
        };
      });

      const resultado = revisar();
      if (resultado.tipo === 'no_encontrado') {
        return res.status(404).json({
          mensaje: 'No se encontró un cierre de caja para revisar'
        });
      }
      if (resultado.tipo === 'ya_revisado') {
        return res.status(409).json({
          codigo: 'CIERRE_YA_REVISADO',
          mensaje: 'Este cierre ya fue revisado y no puede modificarse'
        });
      }

      return res.json({
        mensaje: estadoRevision === 'revisado'
          ? 'Cierre confirmado correctamente'
          : 'Cierre observado correctamente',
        turno: mapearTurno(resultado.turno)
      });
    } catch (error) {
      console.error('ERROR REVISAR CIERRE DE CAJA:', error);
      return res.status(500).json({
        mensaje: 'No se pudo registrar la revisión del cierre'
      });
    }
  }
);

app.get(
  '/api/pro/turnos/:id/pdf',
  requerirEstacionamientoActivo,
  requerirAdministrador,
  requerirCapacidad('cierreCaja'),
  (req, res) => {
    try {
      const turnoId = Number(req.params.id);
      if (!Number.isInteger(turnoId) || turnoId < 1) {
        return res.status(400).json({
          mensaje: 'El identificador de turno no es válido'
        });
      }

      const turno = db.prepare(`
        SELECT
          t.*,
          cajero.nombre AS cajero_nombre,
          cajero.email AS cajero_email,
          revisor.nombre AS revisor_nombre
        FROM turnos_caja t
        JOIN usuarios cajero ON cajero.id = t.cajero_usuario_id
        LEFT JOIN usuarios revisor ON revisor.id = t.revisado_por_usuario_id
        WHERE t.id = ?
          AND t.estacionamiento_id = ?
          AND t.estado = 'cerrado'
      `).get(turnoId, req.usuario.estacionamientoId);

      if (!turno) {
        return res.status(404).json({
          mensaje: 'No se encontró un cierre de caja para descargar'
        });
      }

      const vehiculos = db.prepare(`
        SELECT patente, tipo, color, hora_entrada
        FROM turnos_caja_vehiculos_abiertos
        WHERE turno_caja_id = ?
        ORDER BY hora_entrada ASC, id ASC
      `).all(turnoId);
      const estacionamiento = db.prepare(`
        SELECT zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(req.usuario.estacionamientoId);
      const zonaHoraria = resolverZonaHoraria(
        estacionamiento?.zona_horaria
      );

      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader(
        'Content-Disposition',
        `inline; filename="cierre-caja-${turnoId}.pdf"`
      );

      const doc = new PDFDocument({ size: 'A4', margin: 48 });
      doc.pipe(res);
      const detalle = (etiqueta, valor) => {
        doc.fontSize(10).font('Helvetica-Bold').text(`${etiqueta}: `, {
          continued: true
        });
        doc.font('Helvetica').text(String(valor));
        doc.moveDown(0.45);
      };
      const medio = (etiqueta, monto) => detalle(
        etiqueta,
        formatearPesos(Number(monto || 0))
      );

      doc.font('Helvetica-Bold').fontSize(23).text('PARKCONTROL', {
        align: 'center'
      });
      doc.moveDown(0.35);
      doc.fontSize(16).text(`CIERRE DE CAJA N° ${turnoId}`, {
        align: 'center'
      });
      doc.moveDown(0.4);
      doc.font('Helvetica').fontSize(9).text(
        'Documento operativo de conciliación interna · No tributario',
        { align: 'center' }
      );
      doc.moveDown(1.4);
      detalle('Cajero', `${turno.cajero_nombre} (${turno.cajero_email})`);
      detalle('Inicio', formatearFechaPDF(turno.abierto_en, zonaHoraria));
      detalle('Cierre', formatearFechaPDF(turno.cerrado_en, zonaHoraria));
      detalle('Fondo inicial', formatearPesos(Number(turno.monto_inicial || 0)));
      doc.moveDown(0.5);
      doc.font('Helvetica-Bold').fontSize(13).text('Cobros registrados');
      doc.moveDown(0.6);
      medio('Total cobrado', turno.monto_recaudado);
      medio('Efectivo', turno.monto_efectivo == null
        ? turno.monto_recaudado
        : turno.monto_efectivo);
      medio('Transferencias', turno.monto_transferencia);
      medio('Tarjetas', turno.monto_tarjeta);
      medio('Otros medios', turno.monto_otros);
      doc.moveDown(0.4);
      doc.font('Helvetica-Bold').fontSize(13).text('Conciliación de efectivo');
      doc.moveDown(0.6);
      medio('Efectivo esperado', turno.monto_esperado);
      medio('Efectivo declarado', turno.monto_declarado);
      const diferencia = Number(turno.diferencia || 0);
      detalle(
        'Diferencia',
        `${formatearPesos(diferencia)} ${diferencia === 0 ? '(cuadrada)' : '(requiere revisión)'}`
      );
      if (turno.novedad_apertura) {
        detalle('Novedad de apertura', turno.novedad_apertura);
      }
      if (turno.novedad_cierre) {
        detalle('Novedad de cierre', turno.novedad_cierre);
      }
      doc.moveDown(0.4);
      doc.font('Helvetica-Bold').fontSize(13).text('Revisión administrativa');
      doc.moveDown(0.6);
      detalle(
        'Estado',
        turno.estado_revision === 'observado'
          ? 'Observado'
          : turno.estado_revision === 'revisado'
            ? 'Confirmado'
            : 'Pendiente'
      );
      if (turno.revisado_en) detalle(
        'Fecha de revisión',
        formatearFechaPDF(turno.revisado_en, zonaHoraria)
      );
      if (turno.revisor_nombre) detalle('Revisado por', turno.revisor_nombre);
      if (turno.observacion_revision) detalle('Comentario', turno.observacion_revision);
      doc.moveDown(0.4);
      doc.font('Helvetica-Bold').fontSize(13).text(
        `Vehículos dentro al cierre (${vehiculos.length})`
      );
      doc.moveDown(0.55);
      if (vehiculos.length === 0) {
        doc.font('Helvetica').fontSize(10).text('No había vehículos dentro.');
      } else {
        for (const vehiculo of vehiculos) {
          doc.font('Helvetica').fontSize(10).text(
            `${vehiculo.patente} · ${vehiculo.tipo} · ${vehiculo.color} · entrada ${formatearFechaPDF(vehiculo.hora_entrada, zonaHoraria)}`
          );
        }
      }
      doc.moveDown(2);
      doc.font('Helvetica').fontSize(8).text(
        `Generado por ParkControl el ${formatearFechaPDF(new Date().toISOString(), zonaHoraria)}`,
        { align: 'center' }
      );
      doc.end();
    } catch (error) {
      console.error('ERROR PDF CIERRE DE CAJA:', error);
      if (!res.headersSent) {
        return res.status(500).json({
          mensaje: 'No se pudo generar el PDF del cierre'
        });
      }
    }
  }
);

// ============================================================
// AUDITORÍA PRO POR CAJERO
// ============================================================
//
// Consolida exclusivamente datos operativos persistidos: cobros asociados a
// usuario_salida_id, cambios registrados en auditoría y cierres reales. No se
// derivan montos desde el cliente ni se usan contadores de interfaz.
// ============================================================

app.get(
  '/api/pro/auditoria-cajeros',
  requerirEstacionamientoActivo,
  requerirAdministrador,
  requerirCapacidad('graficosAvanzados'),
  (req, res) => {
    try {
      const estacionamientoId = req.usuario.estacionamientoId;
      const estacionamiento = db.prepare(`
        SELECT zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(estacionamientoId);
      const periodo = crearPeriodoAnalitica(
        req.query.periodo,
        estacionamiento?.zona_horaria || 'America/Santiago'
      );

      if (!periodo) {
        return res.status(400).json({
          mensaje: 'El periodo debe ser dia, semana, mes, semestre o ano'
        });
      }

      const fechaBase =
        periodo.periodo === 'semestre' || periodo.periodo === 'ano'
          ? `${periodo.primeraClave}-01`
          : periodo.primeraClave.slice(0, 10);
      const fechaMinima = `${fechaBase}T00:00:00.000Z`;
      const porClave = new Map(
        periodo.puntos.map(punto => [punto.clave, {
          ...punto,
          recaudado: 0,
          turnosCerrados: 0
        }])
      );
      const cajeros = new Map();
      const asegurarCajero = (id, nombre, email) => {
        if (!Number.isInteger(Number(id))) return null;

        const clave = Number(id);
        if (!cajeros.has(clave)) {
          cajeros.set(clave, {
            usuarioId: clave,
            nombre: nombre || 'Cajero sin nombre',
            email: email || null,
            turnosCerrados: 0,
            cobros: 0,
            recaudado: 0,
            modificaciones: 0,
            eliminaciones: 0,
            diferenciaAcumulada: 0
          });
        }

        return cajeros.get(clave);
      };

      const usuariosCajero = db.prepare(`
        SELECT id, nombre, email
        FROM usuarios
        WHERE estacionamiento_id = ?
          AND rol = 'cajero'
      `).all(estacionamientoId);

      for (const usuario of usuariosCajero) {
        asegurarCajero(usuario.id, usuario.nombre, usuario.email);
      }

      const movimientos = db.prepare(`
        SELECT
          m.usuario_salida_id,
          m.hora_salida,
          m.monto,
          u.nombre AS cajero_nombre,
          u.email AS cajero_email
        FROM movimientos m
        JOIN usuarios u ON u.id = m.usuario_salida_id
        WHERE m.estacionamiento_id = ?
          AND m.estado = 'salio'
          AND m.hora_salida >= ?
          AND u.rol = 'cajero'
      `).all(estacionamientoId, fechaMinima);

      for (const movimiento of movimientos) {
        const cajero = asegurarCajero(
          movimiento.usuario_salida_id,
          movimiento.cajero_nombre,
          movimiento.cajero_email
        );
        const punto = porClave.get(
          periodo.claveParaFecha(movimiento.hora_salida)
        );

        if (!cajero || !punto || !punto.disponible) continue;

        const monto = Number(movimiento.monto || 0);
        cajero.cobros += 1;
        cajero.recaudado += monto;
        punto.salidas += 1;
        punto.recaudado += monto;
      }

      const auditorias = db.prepare(`
        SELECT
          a.accion,
          a.fecha,
          a.usuario_id,
          a.usuario_nombre,
          a.usuario_email
        FROM auditoria a
        JOIN usuarios u ON u.id = a.usuario_id
        WHERE a.estacionamiento_id = ?
          AND a.fecha >= ?
          AND a.accion IN ('MODIFICACION', 'ELIMINACION')
          AND u.rol = 'cajero'
      `).all(estacionamientoId, fechaMinima);

      for (const auditoria of auditorias) {
        const cajero = asegurarCajero(
          auditoria.usuario_id,
          auditoria.usuario_nombre,
          auditoria.usuario_email
        );
        const punto = porClave.get(
          periodo.claveParaFecha(auditoria.fecha)
        );

        if (!cajero || !punto || !punto.disponible) continue;

        if (auditoria.accion === 'MODIFICACION') {
          cajero.modificaciones += 1;
          punto.modificaciones += 1;
        } else {
          cajero.eliminaciones += 1;
          punto.eliminaciones += 1;
        }
      }

      const turnos = db.prepare(`
        SELECT
          t.*,
          u.nombre AS cajero_nombre,
          u.email AS cajero_email
        FROM turnos_caja t
        JOIN usuarios u ON u.id = t.cajero_usuario_id
        WHERE t.estacionamiento_id = ?
          AND t.estado = 'cerrado'
          AND t.cerrado_en >= ?
          AND u.rol = 'cajero'
      `).all(estacionamientoId, fechaMinima);

      for (const turno of turnos) {
        const cajero = asegurarCajero(
          turno.cajero_usuario_id,
          turno.cajero_nombre,
          turno.cajero_email
        );
        const punto = porClave.get(
          periodo.claveParaFecha(turno.cerrado_en)
        );

        if (!cajero || !punto || !punto.disponible) continue;

        cajero.turnosCerrados += 1;
        cajero.diferenciaAcumulada += Number(turno.diferencia || 0);
        punto.turnosCerrados += 1;
      }

      const puntos = [...porClave.values()].map(punto => ({
        ...punto,
        recaudado: Number(punto.recaudado.toFixed(2))
      }));
      const resumen = puntos.reduce((acumulado, punto) => ({
        recaudado: acumulado.recaudado + punto.recaudado,
        cobros: acumulado.cobros + punto.salidas,
        modificaciones: acumulado.modificaciones + punto.modificaciones,
        eliminaciones: acumulado.eliminaciones + punto.eliminaciones,
        turnosCerrados: acumulado.turnosCerrados + punto.turnosCerrados
      }), {
        recaudado: 0,
        cobros: 0,
        modificaciones: 0,
        eliminaciones: 0,
        turnosCerrados: 0
      });
      const cajerosOrdenados = [...cajeros.values()]
        .map(cajero => ({
          ...cajero,
          recaudado: Number(cajero.recaudado.toFixed(2)),
          diferenciaAcumulada: Number(
            cajero.diferenciaAcumulada.toFixed(2)
          )
        }))
        .sort((a, b) =>
          b.recaudado - a.recaudado ||
          b.turnosCerrados - a.turnosCerrados ||
          a.nombre.localeCompare(b.nombre, 'es')
        );

      return res.json({
        periodo: periodo.periodo,
        actualizadoEn: new Date().toISOString(),
        puntos,
        resumen: {
          ...resumen,
          recaudado: Number(resumen.recaudado.toFixed(2))
        },
        cajeros: cajerosOrdenados
      });
    } catch (error) {
      console.error('ERROR AUDITORÍA PRO CAJEROS:', error);
      return res.status(500).json({
        mensaje: 'No se pudo obtener la auditoría Pro de cajeros'
      });
    }
  }
);

// ============================================================
// CERRAR SESIÓN
// ============================================================

app.post('/api/logout', (req, res) => {
  try {
    db.prepare(`
      UPDATE usuarios
      SET sesionVersion = sesionVersion + 1
      WHERE id = ?
    `).run(req.usuario.id);

    return res.json({
      mensaje: 'Sesión cerrada correctamente'
    });
  } catch (error) {
    console.error('ERROR CERRAR SESIÓN:', error);

    return res.status(500).json({
      mensaje: 'No se pudo cerrar la sesión'
    });
  }
});

// ============================================================
// CUENTA - CAMBIAR CONTRASEÑA PROPIA
// ============================================================

app.patch('/api/cuenta/password', (req, res) => {
  try {
    const passwordActual = String(
      req.body.passwordActual || ''
    );
    const passwordNueva = String(
      req.body.passwordNueva || ''
    );

    if (!passwordActual || !passwordNueva) {
      return res.status(400).json({
        mensaje: 'La contraseña actual y la nueva son obligatorias'
      });
    }

    const errorPassword = mensajePasswordDemasiadoCorta(passwordNueva, {
      rol: req.usuario.rol,
      etiqueta: 'La nueva contraseña'
    });

    if (errorPassword) {
      return res.status(400).json({
        mensaje: errorPassword
      });
    }

    if (passwordNueva === passwordActual) {
      return res.status(400).json({
        mensaje: 'La nueva contraseña debe ser diferente de la actual'
      });
    }

    const usuario = db.prepare(`
      SELECT password
      FROM usuarios
      WHERE id = ?
        AND activo = 1
    `).get(req.usuario.id);

    if (!usuario ||
        !verificarPassword(
          passwordActual,
          usuario.password
        )) {
      return res.status(401).json({
        mensaje: 'La contraseña actual no es correcta'
      });
    }

    db.prepare(`
      UPDATE usuarios
      SET
        password = ?,
        sesionVersion = sesionVersion + 1
      WHERE id = ?
    `).run(
      crearHashPassword(passwordNueva),
      req.usuario.id
    );

    if (req.usuario.rol === 'superadmin') {
      registrarAuditoriaSistema({
        superadminId: req.usuario.id,
        accion: 'PASSWORD_PROPIA_CAMBIADA',
        entidad: 'superadmin',
        entidadId: req.usuario.id
      });
    }

    return res.json({
      mensaje: 'Contraseña actualizada. Inicia sesión nuevamente.'
    });
  } catch (error) {
    console.error('ERROR CAMBIAR PASSWORD PROPIA:', error);

    return res.status(500).json({
      mensaje: 'No se pudo cambiar la contraseña'
    });
  }
});

// ============================================================
// SUPERADMIN - RESUMEN GLOBAL
// ============================================================

app.get(
  '/api/superadmin/resumen',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const clientes = db
        .prepare(`
          SELECT id
          FROM estacionamientos
          WHERE visible_superadmin = 1
          ORDER BY id ASC
        `)
        .all()
        .map(({ id }) =>
          mapearCliente(consultarClientePorId(id))
        );

      const clientesActivos = clientes.filter(
        cliente => cliente.estado === 'activo'
      ).length;

      const clientesSuspendidos = clientes.filter(
        cliente => cliente.estado === 'suspendido'
      ).length;

      const clientesVencidos = clientes.filter(
        cliente => cliente.estadoComercial === 'vencido'
      ).length;

      const clientesPorVencer = clientes.filter(
        cliente => cliente.estadoComercial === 'por_vencer'
      ).length;

      const inicioMes = new Date();
      inicioMes.setDate(1);
      inicioMes.setHours(0, 0, 0, 0);

      const ingresosMes = db.prepare(`
        SELECT COALESCE(SUM(monto), 0) AS total
        FROM pagos_suscripcion
        WHERE estado = 'confirmado'
          AND fecha_pago >= ?
      `).get(inicioMes.toISOString());

      const vencimientosProximos = clientes
        .filter(cliente =>
          cliente.estadoComercial === 'por_vencer' ||
          cliente.estadoComercial === 'vencido'
        )
        .sort((a, b) =>
          String(a.fechaVencimiento)
            .localeCompare(String(b.fechaVencimiento))
        )
        .slice(0, 8);

      return res.json({
        totalClientes: clientes.length,
        clientesActivos,
        clientesSuspendidos,
        clientesVencidos,
        clientesPorVencer,
        ingresosMes: Number(ingresosMes.total || 0),
        vencimientosProximos
      });
    } catch (error) {
      console.error('ERROR RESUMEN SUPERADMIN:', error);

      return res.status(500).json({
        mensaje: 'No se pudo obtener el resumen general'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - LISTADO DE CLIENTES
// ============================================================

app.get(
  '/api/superadmin/clientes',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const buscar = String(req.query.buscar || '')
        .trim()
        .toLowerCase();
      const estado = String(req.query.estado || '')
        .trim()
        .toLowerCase();

      let clientes = db
        .prepare(`
          SELECT id
          FROM estacionamientos
          WHERE visible_superadmin = 1
          ORDER BY nombre COLLATE NOCASE ASC, id ASC
        `)
        .all()
        .map(({ id }) =>
          mapearCliente(consultarClientePorId(id))
        );

      if (buscar) {
        clientes = clientes.filter(cliente =>
          [
            cliente.nombre,
            cliente.razonSocial,
            cliente.rut,
            cliente.emailContacto,
            cliente.administradorPrincipal?.email
          ]
            .filter(Boolean)
            .some(valor =>
              String(valor).toLowerCase().includes(buscar)
            )
        );
      }

      if (estado && estado !== 'todos') {
        clientes = clientes.filter(cliente =>
          cliente.estado === estado ||
          cliente.estadoComercial === estado
        );
      }

      return res.json({ clientes });
    } catch (error) {
      console.error('ERROR LISTAR CLIENTES:', error);

      return res.status(500).json({
        mensaje: 'No se pudo obtener la lista de clientes'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - CREAR CLIENTE Y ADMINISTRADOR INICIAL
// ============================================================

app.post(
  '/api/superadmin/clientes',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const nombre = String(req.body.nombre || '').trim();
      const razonSocial = textoOpcional(req.body.razonSocial);
      const rut = textoOpcional(req.body.rut);
      const emailContacto = normalizarEmail(
        req.body.emailContacto
      ) || null;
      const telefono = textoOpcional(req.body.telefono);
      const direccion = textoOpcional(req.body.direccion);
      const plan = String(req.body.plan || 'LITE')
        .trim()
        .toUpperCase();
      const zonaHoraria = normalizarZonaHorariaIana(
        Object.prototype.hasOwnProperty.call(
          req.body,
          'zonaHoraria'
        )
          ? req.body.zonaHoraria
          : ZONA_HORARIA_POR_DEFECTO
      );
      const estado = String(req.body.estado || 'activo')
        .trim()
        .toLowerCase();
      const motivoSuspension =
        textoOpcional(req.body.motivoSuspension);

      const administrador = req.body.administrador || {};
      const administradorNombre = String(
        administrador.nombre ||
        req.body.administradorNombre ||
        ''
      ).trim();
      const administradorEmail = normalizarEmail(
        administrador.email ||
        req.body.administradorEmail
      );
      const administradorPassword = String(
        administrador.password ||
        req.body.administradorPassword ||
        ''
      );

      const fechaInicioTexto =
        textoOpcional(req.body.fechaInicio);
      const fechaVencimientoTexto =
        textoOpcional(req.body.fechaVencimiento);
      const fechaInicio = fechaInicioTexto
        ? fechaIsoValida(fechaInicioTexto)
        : new Date().toISOString();
      const fechaVencimiento = fechaVencimientoTexto
        ? fechaIsoValida(fechaVencimientoTexto)
        : null;
      const tarifaPorMinuto = Number(
        req.body.tarifaPorMinuto ?? 48
      );

      if (!nombre ||
          !administradorNombre ||
          !administradorEmail ||
          !administradorPassword) {
        return res.status(400).json({
          mensaje: 'Completa el cliente y su administrador inicial'
        });
      }

      if (!/^\S+@\S+\.\S+$/.test(administradorEmail)) {
        return res.status(400).json({
          mensaje: 'El correo del administrador no es válido'
        });
      }

      const errorPasswordAdministrador = mensajePasswordDemasiadoCorta(
        administradorPassword,
        {
          rol: 'admin',
          etiqueta: 'La contraseña del administrador'
        }
      );

      if (errorPasswordAdministrador) {
        return res.status(400).json({
          mensaje: errorPasswordAdministrador
        });
      }

      if (!['activo', 'suspendido'].includes(estado)) {
        return res.status(400).json({
          mensaje: 'El estado del cliente no es válido'
        });
      }

      if (!['LITE', 'PRO'].includes(plan)) {
        return res.status(400).json({
          mensaje: 'El plan debe ser Lite o Pro'
        });
      }

      if (!zonaHoraria) {
        return res.status(400).json({
          mensaje: 'La zona horaria debe ser un identificador IANA válido, por ejemplo America/Santiago'
        });
      }

      if (estado === 'suspendido' && !motivoSuspension) {
        return res.status(400).json({
          mensaje: 'Indica el motivo de la suspensión'
        });
      }

      if (!fechaInicio ||
          (fechaVencimientoTexto && !fechaVencimiento)) {
        return res.status(400).json({
          mensaje: 'Revisa las fechas de la suscripción'
        });
      }

      if (!Number.isFinite(tarifaPorMinuto) ||
          tarifaPorMinuto < 0) {
        return res.status(400).json({
          mensaje: 'La tarifa inicial no es válida'
        });
      }

      if (db.prepare(`
        SELECT id FROM usuarios WHERE email = ?
      `).get(administradorEmail)) {
        return res.status(409).json({
          mensaje: 'Ya existe un usuario con el correo del administrador'
        });
      }

      if (rut && db.prepare(`
        SELECT id FROM estacionamientos WHERE rut = ?
      `).get(rut)) {
        return res.status(409).json({
          mensaje: 'Ya existe un cliente con ese RUT'
        });
      }

      const crearCliente = db.transaction(() => {
        const ahora = new Date().toISOString();
        const codigo = crearCodigoCliente(nombre);

        const resultadoCliente = db.prepare(`
          INSERT INTO estacionamientos
          (
            codigo,
            nombre,
            razon_social,
            rut,
            email_contacto,
            telefono,
            direccion,
            plan,
            estado,
            zona_horaria,
            fecha_inicio,
            fecha_vencimiento,
            motivo_suspension,
            suspendido_en,
            suspendido_por,
            creado_en,
            actualizado_en
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          codigo,
          nombre,
          razonSocial,
          rut,
          emailContacto,
          telefono,
          direccion,
          plan || 'LITE',
          estado,
          zonaHoraria,
          fechaInicio,
          fechaVencimiento,
          estado === 'suspendido'
            ? motivoSuspension
            : null,
          estado === 'suspendido' ? ahora : null,
          estado === 'suspendido'
            ? req.usuario.id
            : null,
          ahora,
          ahora
        );

        const clienteId = Number(
          resultadoCliente.lastInsertRowid
        );

        db.prepare(`
          INSERT INTO usuarios
          (
            nombre,
            email,
            password,
            rol,
            registrarEntradas,
            registrarSalidas,
            verReportes,
            sesionVersion,
            estacionamiento_id,
            activo
          )
          VALUES (?, ?, ?, 'admin', 1, 1, 1, 0, ?, 1)
        `).run(
          administradorNombre,
          administradorEmail,
          crearHashPassword(administradorPassword),
          clienteId
        );

        db.prepare(`
          INSERT INTO tarifas
          (
            estacionamiento_id,
            tarifa_por_minuto,
            activa
          )
          VALUES (?, ?, 1)
        `).run(clienteId, tarifaPorMinuto);

        registrarAuditoriaSistema({
          superadminId: req.usuario.id,
          accion: 'CLIENTE_CREADO',
          entidad: 'estacionamiento',
          entidadId: clienteId,
          nuevo: {
            nombre,
            rut,
            plan,
            estado,
            administradorEmail
          }
        });

        return clienteId;
      });

      const clienteId = crearCliente();

      return res.status(201).json({
        mensaje: 'Cliente y administrador creados correctamente',
        cliente: mapearCliente(
          consultarClientePorId(clienteId)
        )
      });
    } catch (error) {
      console.error('ERROR CREAR CLIENTE:', error);

      if (String(error.code || '').startsWith('SQLITE_CONSTRAINT')) {
        return res.status(409).json({
          mensaje: 'No se pudo crear porque uno de los datos ya existe'
        });
      }

      return res.status(500).json({
        mensaje: 'No se pudo crear el cliente'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - DETALLE DE CLIENTE
// ============================================================

app.get(
  '/api/superadmin/clientes/:id',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje: 'ID de cliente no válido'
        });
      }

      const filaCliente = consultarClientePorId(id);

      if (!filaCliente) {
        return res.status(404).json({
          mensaje: 'Cliente no encontrado'
        });
      }

      const administradores = db.prepare(`
        SELECT
          id,
          nombre,
          email,
          rol,
          activo
        FROM usuarios
        WHERE estacionamiento_id = ?
          AND rol IN ('admin', 'admin_estacionamiento')
        ORDER BY activo DESC, id ASC
      `).all(id).map(usuario => ({
        id: Number(usuario.id),
        nombre: usuario.nombre,
        email: usuario.email,
        rol: usuario.rol,
        activo: Boolean(usuario.activo)
      }));

      const pagos = db.prepare(`
        SELECT
          id,
          monto,
          metodo,
          fecha_pago AS fechaPago,
          periodo_desde AS periodoDesde,
          periodo_hasta AS periodoHasta,
          referencia,
          observacion,
          estado,
          motivo_anulacion AS motivoAnulacion,
          creado_en AS creadoEn
        FROM pagos_suscripcion
        WHERE estacionamiento_id = ?
        ORDER BY fecha_pago DESC, id DESC
      `).all(id).map(pago => ({
        ...pago,
        id: Number(pago.id),
        monto: Number(pago.monto)
      }));

      const suscripcionAutomatica = db.prepare(`
        SELECT
          proveedor,
          suscripcion_externa_id AS suscripcionExternaId,
          estado,
          renovacion_automatica AS renovacionAutomatica,
          tarjeta_marca AS tarjetaMarca,
          tarjeta_ultimos4 AS tarjetaUltimos4,
          proximo_cobro AS proximoCobro,
          ultima_sincronizacion AS ultimaSincronizacion
        FROM suscripciones_pago
        WHERE estacionamiento_id = ?
        LIMIT 1
      `).get(id);

      return res.json({
        cliente: {
          ...mapearCliente(filaCliente),
          suscripcionAutomatica: suscripcionAutomatica || null
        },
        administradores,
        pagos,
        suscripcionAutomatica: suscripcionAutomatica || null
      });
    } catch (error) {
      console.error('ERROR DETALLE CLIENTE:', error);

      return res.status(500).json({
        mensaje: 'No se pudo obtener el detalle del cliente'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - EDITAR DATOS COMERCIALES
// ============================================================

app.put(
  '/api/superadmin/clientes/:id',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const anterior = consultarClientePorId(id);

      if (!Number.isInteger(id) || !anterior) {
        return res.status(404).json({
          mensaje: 'Cliente no encontrado'
        });
      }

      const tiene = campo =>
        Object.prototype.hasOwnProperty.call(req.body, campo);
      const nombre = tiene('nombre')
        ? String(req.body.nombre || '').trim()
        : anterior.nombre;
      const razonSocial = tiene('razonSocial')
        ? textoOpcional(req.body.razonSocial)
        : anterior.razon_social;
      const rut = tiene('rut')
        ? textoOpcional(req.body.rut)
        : anterior.rut;
      const emailContacto = tiene('emailContacto')
        ? normalizarEmail(req.body.emailContacto) || null
        : anterior.email_contacto;
      const telefono = tiene('telefono')
        ? textoOpcional(req.body.telefono)
        : anterior.telefono;
      const direccion = tiene('direccion')
        ? textoOpcional(req.body.direccion)
        : anterior.direccion;
      const plan = tiene('plan')
        ? String(req.body.plan || '').trim().toUpperCase()
        : anterior.plan;
      const zonaHoraria = tiene('zonaHoraria')
        ? normalizarZonaHorariaIana(req.body.zonaHoraria)
        : (textoOpcional(anterior.zona_horaria) ||
          ZONA_HORARIA_POR_DEFECTO);

      if (!['LITE', 'PRO'].includes(plan) &&
          plan !== anterior.plan) {
        return res.status(400).json({
          mensaje: 'El plan debe ser Lite o Pro'
        });
      }

      if (tiene('zonaHoraria') && !zonaHoraria) {
        return res.status(400).json({
          mensaje: 'La zona horaria debe ser un identificador IANA válido, por ejemplo America/Santiago'
        });
      }

      let fechaInicio = anterior.fecha_inicio;
      let fechaVencimiento = anterior.fecha_vencimiento;

      if (tiene('fechaInicio')) {
        fechaInicio = fechaIsoValida(req.body.fechaInicio, true);
      }

      if (tiene('fechaVencimiento')) {
        const texto = textoOpcional(req.body.fechaVencimiento);
        fechaVencimiento = texto
          ? fechaIsoValida(texto)
          : null;

        if (texto && !fechaVencimiento) {
          return res.status(400).json({
            mensaje: 'La fecha de vencimiento no es válida'
          });
        }
      }

      if (!nombre || !plan || !zonaHoraria || !fechaInicio) {
        return res.status(400).json({
          mensaje: 'Nombre, plan, zona horaria y fecha de inicio son obligatorios'
        });
      }

      // Al bajar de plan nunca se desactivan personas de forma automática.
      // Primero se debe regularizar el equipo para no perder acceso ni datos
      // de usuarios existentes.
      if (plan !== anterior.plan) {
        const limiteDestino = obtenerCapacidadesPlan(plan);
        const usuariosActuales = obtenerLimitesUsuariosPlan(id);

        if (usuariosActuales.administradoresActivos >
              limiteDestino.maxAdministradores ||
            usuariosActuales.cajerosActivos >
              limiteDestino.maxCajeros) {
          return res.status(409).json({
            codigo: 'LIMITE_USUARIOS_PLAN',
            mensaje: `No se puede cambiar a ${limiteDestino.plan} mientras existan más usuarios activos que los permitidos por ese plan`,
            planDestino: limiteDestino.plan,
            limites: {
              maxAdministradores:
                limiteDestino.maxAdministradores,
              maxCajeros: limiteDestino.maxCajeros,
              administradoresActivos:
                usuariosActuales.administradoresActivos,
              cajerosActivos:
                usuariosActuales.cajerosActivos
            }
          });
        }
      }

      if (rut && db.prepare(`
        SELECT id
        FROM estacionamientos
        WHERE rut = ? AND id != ?
      `).get(rut, id)) {
        return res.status(409).json({
          mensaje: 'Ese RUT ya pertenece a otro cliente'
        });
      }

      db.prepare(`
        UPDATE estacionamientos
        SET
          nombre = ?,
          razon_social = ?,
          rut = ?,
          email_contacto = ?,
          telefono = ?,
          direccion = ?,
          plan = ?,
          zona_horaria = ?,
          fecha_inicio = ?,
          fecha_vencimiento = ?,
          actualizado_en = ?
        WHERE id = ?
      `).run(
        nombre,
        razonSocial,
        rut,
        emailContacto,
        telefono,
        direccion,
        plan,
        zonaHoraria,
        fechaInicio,
        fechaVencimiento,
        new Date().toISOString(),
        id
      );

      const nuevo = consultarClientePorId(id);

      registrarAuditoriaSistema({
        superadminId: req.usuario.id,
        accion: 'CLIENTE_EDITADO',
        entidad: 'estacionamiento',
        entidadId: id,
        anterior: mapearCliente(anterior),
        nuevo: mapearCliente(nuevo)
      });

      return res.json({
        mensaje: 'Cliente actualizado correctamente',
        cliente: mapearCliente(nuevo)
      });
    } catch (error) {
      console.error('ERROR EDITAR CLIENTE:', error);

      return res.status(500).json({
        mensaje: 'No se pudo actualizar el cliente'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - SUSPENDER O REACTIVAR CLIENTE
// ============================================================

app.patch(
  '/api/superadmin/clientes/:id/estado',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const estado = String(req.body.estado || '')
        .trim()
        .toLowerCase();
      const motivo = textoOpcional(req.body.motivo);

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje: 'ID de cliente no válido'
        });
      }

      if (!['activo', 'suspendido'].includes(estado)) {
        return res.status(400).json({
          mensaje: 'El estado debe ser activo o suspendido'
        });
      }

      if (estado === 'suspendido' && !motivo) {
        return res.status(400).json({
          mensaje: 'Indica el motivo de la suspensión'
        });
      }

      const anterior = consultarClientePorId(id);

      if (!anterior) {
        return res.status(404).json({
          mensaje: 'Cliente no encontrado'
        });
      }

      const actualizarEstado = db.transaction(() => {
        const ahora = new Date().toISOString();

        db.prepare(`
          UPDATE estacionamientos
          SET
            estado = ?,
            motivo_suspension = ?,
            suspendido_en = ?,
            suspendido_por = ?,
            actualizado_en = ?
          WHERE id = ?
        `).run(
          estado,
          estado === 'suspendido' ? motivo : null,
          estado === 'suspendido' ? ahora : null,
          estado === 'suspendido'
            ? req.usuario.id
            : null,
          ahora,
          id
        );

        // Invalida de inmediato todas las sesiones abiertas del cliente.
        db.prepare(`
          UPDATE usuarios
          SET sesionVersion = sesionVersion + 1
          WHERE estacionamiento_id = ?
        `).run(id);

        const nuevo = consultarClientePorId(id);

        registrarAuditoriaSistema({
          superadminId: req.usuario.id,
          accion: estado === 'suspendido'
            ? 'CLIENTE_SUSPENDIDO'
            : 'CLIENTE_REACTIVADO',
          entidad: 'estacionamiento',
          entidadId: id,
          anterior: mapearCliente(anterior),
          nuevo: mapearCliente(nuevo),
          motivo
        });
      });

      actualizarEstado();

      return res.json({
        mensaje: estado === 'suspendido'
          ? 'Cliente suspendido correctamente'
          : 'Cliente reactivado correctamente',
        cliente: mapearCliente(
          consultarClientePorId(id)
        )
      });
    } catch (error) {
      console.error('ERROR CAMBIAR ESTADO CLIENTE:', error);

      return res.status(500).json({
        mensaje: 'No se pudo cambiar el estado del cliente'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - REGISTRAR PAGO MANUAL
// ============================================================

app.post(
  '/api/superadmin/clientes/:id/pagos',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const monto = Math.round(Number(req.body.monto));
      const metodo = String(req.body.metodo || '')
        .trim()
        .toLowerCase();
      const referencia = textoOpcional(req.body.referencia);
      const observacion = textoOpcional(req.body.observacion);
      const reactivar = req.body.reactivar !== false;

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje: 'ID de cliente no válido'
        });
      }

      const anterior = consultarClientePorId(id);

      if (!anterior) {
        return res.status(404).json({
          mensaje: 'Cliente no encontrado'
        });
      }

      if (!Number.isFinite(monto) || monto <= 0) {
        return res.status(400).json({
          mensaje: 'El monto debe ser mayor que cero'
        });
      }

      if (!['transferencia', 'efectivo', 'otro'].includes(metodo)) {
        return res.status(400).json({
          mensaje: 'Selecciona transferencia, efectivo u otro medio'
        });
      }

      const fechaPagoTexto = textoOpcional(req.body.fechaPago);
      const periodoDesdeTexto = textoOpcional(req.body.periodoDesde);
      const periodoHastaTexto = textoOpcional(req.body.periodoHasta);
      const fechaPago = fechaPagoTexto
        ? fechaIsoValida(fechaPagoTexto)
        : new Date().toISOString();
      const periodoDesde = periodoDesdeTexto
        ? fechaIsoValida(periodoDesdeTexto)
        : null;
      const periodoHasta = periodoHastaTexto
        ? fechaIsoValida(periodoHastaTexto)
        : null;

      if (!fechaPago ||
          (periodoDesdeTexto && !periodoDesde) ||
          (periodoHastaTexto && !periodoHasta)) {
        return res.status(400).json({
          mensaje: 'Revisa las fechas del pago'
        });
      }

      if (periodoDesde && periodoHasta &&
          periodoDesde > periodoHasta) {
        return res.status(400).json({
          mensaje: 'El inicio del período no puede ser posterior al vencimiento'
        });
      }

      const registrarPago = db.transaction(() => {
        const ahora = new Date().toISOString();

        const resultado = db.prepare(`
          INSERT INTO pagos_suscripcion
          (
            estacionamiento_id,
            monto,
            metodo,
            fecha_pago,
            periodo_desde,
            periodo_hasta,
            referencia,
            observacion,
            fecha_vencimiento_anterior,
            fecha_ultimo_pago_anterior,
            estado_cliente_anterior,
            motivo_suspension_anterior,
            suspendido_en_anterior,
            suspendido_por_anterior,
            reactivar_solicitado,
            estado,
            registrado_por_usuario_id,
            creado_en
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'confirmado', ?, ?)
        `).run(
          id,
          monto,
          metodo,
          fechaPago,
          periodoDesde,
          periodoHasta,
          referencia,
          observacion,
          anterior.fecha_vencimiento,
          anterior.fecha_ultimo_pago,
          anterior.estado,
          anterior.motivo_suspension,
          anterior.suspendido_en,
          anterior.suspendido_por,
          reactivar ? 1 : 0,
          req.usuario.id,
          ahora
        );

        db.prepare(`
          UPDATE estacionamientos
          SET
            fecha_ultimo_pago = ?,
            fecha_vencimiento = COALESCE(?, fecha_vencimiento),
            estado = CASE WHEN ? = 1 THEN 'activo' ELSE estado END,
            motivo_suspension = CASE WHEN ? = 1 THEN NULL ELSE motivo_suspension END,
            suspendido_en = CASE WHEN ? = 1 THEN NULL ELSE suspendido_en END,
            suspendido_por = CASE WHEN ? = 1 THEN NULL ELSE suspendido_por END,
            actualizado_en = ?
          WHERE id = ?
        `).run(
          fechaPago,
          periodoHasta,
          reactivar ? 1 : 0,
          reactivar ? 1 : 0,
          reactivar ? 1 : 0,
          reactivar ? 1 : 0,
          ahora,
          id
        );

        if (reactivar && anterior.estado === 'suspendido') {
          db.prepare(`
            UPDATE usuarios
            SET sesionVersion = sesionVersion + 1
            WHERE estacionamiento_id = ?
          `).run(id);
        }

        registrarAuditoriaSistema({
          superadminId: req.usuario.id,
          accion: 'PAGO_REGISTRADO',
          entidad: 'pago_suscripcion',
          entidadId: Number(resultado.lastInsertRowid),
          nuevo: {
            estacionamientoId: id,
            monto,
            metodo,
            fechaPago,
            periodoDesde,
            periodoHasta,
            referencia,
            reactivar
          }
        });

        return Number(resultado.lastInsertRowid);
      });

      const pagoId = registrarPago();
      const pago = db.prepare(`
        SELECT
          id,
          monto,
          metodo,
          fecha_pago AS fechaPago,
          periodo_desde AS periodoDesde,
          periodo_hasta AS periodoHasta,
          referencia,
          observacion,
          estado,
          creado_en AS creadoEn
        FROM pagos_suscripcion
        WHERE id = ? AND estacionamiento_id = ?
      `).get(pagoId, id);

      const fueReactivado =
        reactivar && anterior.estado === 'suspendido';

      return res.status(201).json({
        mensaje: fueReactivado
          ? 'Pago registrado y cliente habilitado'
          : 'Pago registrado correctamente',
        pago: {
          ...pago,
          id: Number(pago.id),
          monto: Number(pago.monto)
        },
        cliente: mapearCliente(
          consultarClientePorId(id)
        )
      });
    } catch (error) {
      console.error('ERROR REGISTRAR PAGO:', error);

      return res.status(500).json({
        mensaje: 'No se pudo registrar el pago'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - ANULAR PAGO MANUAL
// ============================================================

app.post(
  '/api/superadmin/clientes/:id/pagos/:pagoId/anular',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const pagoId = Number(req.params.pagoId);
      const motivo = textoOpcional(req.body.motivo);

      if (!Number.isInteger(id) ||
          !Number.isInteger(pagoId)) {
        return res.status(400).json({
          mensaje: 'Identificador de pago no válido'
        });
      }

      if (!motivo) {
        return res.status(400).json({
          mensaje: 'Indica por qué se anula el pago'
        });
      }

      const pago = db.prepare(`
        SELECT *
        FROM pagos_suscripcion
        WHERE id = ?
          AND estacionamiento_id = ?
      `).get(pagoId, id);

      if (!pago) {
        return res.status(404).json({
          mensaje: 'Pago no encontrado'
        });
      }

      if (pago.estado === 'anulado') {
        return res.status(409).json({
          mensaje: 'El pago ya se encuentra anulado'
        });
      }

      const pagoPosterior = db.prepare(`
        SELECT id
        FROM pagos_suscripcion
        WHERE estacionamiento_id = ?
          AND estado = 'confirmado'
          AND id > ?
        LIMIT 1
      `).get(id, pagoId);

      if (pagoPosterior) {
        return res.status(409).json({
          mensaje: 'Anula primero el pago confirmado más reciente'
        });
      }

      const clienteActual = consultarClientePorId(id);

      const anularPago = db.transaction(() => {
        const valorComparable = valor =>
          valor == null ? null : String(valor);
        const esperabaEstado = pago.reactivar_solicitado
          ? 'activo'
          : pago.estado_cliente_anterior;
        const esperabaVencimiento =
          pago.periodo_hasta || pago.fecha_vencimiento_anterior;
        const esperabaMotivo = pago.reactivar_solicitado
          ? null
          : pago.motivo_suspension_anterior;
        const esperabaSuspendidoEn = pago.reactivar_solicitado
          ? null
          : pago.suspendido_en_anterior;
        const esperabaSuspendidoPor = pago.reactivar_solicitado
          ? null
          : pago.suspendido_por_anterior;

        const efectoSigueActual =
          valorComparable(clienteActual.fecha_ultimo_pago) ===
            valorComparable(pago.fecha_pago) &&
          valorComparable(clienteActual.fecha_vencimiento) ===
            valorComparable(esperabaVencimiento) &&
          valorComparable(clienteActual.estado) ===
            valorComparable(esperabaEstado) &&
          valorComparable(clienteActual.motivo_suspension) ===
            valorComparable(esperabaMotivo) &&
          valorComparable(clienteActual.suspendido_en) ===
            valorComparable(esperabaSuspendidoEn) &&
          valorComparable(clienteActual.suspendido_por) ===
            valorComparable(esperabaSuspendidoPor);
        const efectosComercialesRestaurados =
          pago.estado_cliente_anterior != null &&
          efectoSigueActual;

        db.prepare(`
          UPDATE pagos_suscripcion
          SET
            estado = 'anulado',
            motivo_anulacion = ?
          WHERE id = ?
            AND estacionamiento_id = ?
            AND estado = 'confirmado'
        `).run(motivo, pagoId, id);

        if (efectosComercialesRestaurados) {
          db.prepare(`
            UPDATE estacionamientos
            SET
              fecha_vencimiento = ?,
              fecha_ultimo_pago = ?,
              estado = ?,
              motivo_suspension = ?,
              suspendido_en = ?,
              suspendido_por = ?,
              actualizado_en = ?
            WHERE id = ?
          `).run(
            pago.fecha_vencimiento_anterior,
            pago.fecha_ultimo_pago_anterior,
            pago.estado_cliente_anterior,
            pago.motivo_suspension_anterior,
            pago.suspendido_en_anterior,
            pago.suspendido_por_anterior,
            new Date().toISOString(),
            id
          );

          if (clienteActual.estado !== pago.estado_cliente_anterior) {
            db.prepare(`
              UPDATE usuarios
              SET sesionVersion = sesionVersion + 1
              WHERE estacionamiento_id = ?
            `).run(id);
          }
        }

        registrarAuditoriaSistema({
          superadminId: req.usuario.id,
          accion: 'PAGO_ANULADO',
          entidad: 'pago_suscripcion',
          entidadId: pagoId,
          anterior: {
            estado: pago.estado,
            monto: Number(pago.monto),
            estacionamientoId: id
          },
          nuevo: {
            estado: 'anulado',
            motivo,
            efectosComercialesRestaurados
          },
          motivo
        });

        return efectosComercialesRestaurados;
      });

      const efectosComercialesRestaurados = anularPago();

      return res.json({
        mensaje: efectosComercialesRestaurados
          ? 'Pago anulado y estado comercial anterior restaurado.'
          : 'Pago anulado. El cliente tuvo cambios posteriores; revisa su vencimiento y acceso.',
        efectosComercialesRestaurados,
        cliente: mapearCliente(consultarClientePorId(id))
      });
    } catch (error) {
      console.error('ERROR ANULAR PAGO:', error);

      return res.status(500).json({
        mensaje: 'No se pudo anular el pago'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - AGREGAR ADMINISTRADOR DE CLIENTE
// ============================================================

app.post(
  '/api/superadmin/clientes/:id/administradores',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const nombre = String(req.body.nombre || '').trim();
      const email = normalizarEmail(req.body.email);
      const password = String(req.body.password || '');

      if (!Number.isInteger(id) || !consultarClientePorId(id)) {
        return res.status(404).json({
          mensaje: 'Cliente no encontrado'
        });
      }

      if (!nombre || !email || !password) {
        return res.status(400).json({
          mensaje: 'Nombre, correo y contraseña son obligatorios'
        });
      }

      if (!/^\S+@\S+\.\S+$/.test(email)) {
        return res.status(400).json({
          mensaje: 'El correo no es válido'
        });
      }

      const errorPassword = mensajePasswordDemasiadoCorta(password, {
        rol: 'admin'
      });

      if (errorPassword) {
        return res.status(400).json({
          mensaje: errorPassword
        });
      }

      if (db.prepare(`
        SELECT id FROM usuarios WHERE email = ?
      `).get(email)) {
        return res.status(409).json({
          mensaje: 'Ya existe un usuario con ese correo'
        });
      }

      const cupo = validarCupoUsuario({
        estacionamientoId: id,
        rol: 'admin'
      });

      if (!cupo.permitido) {
        return res.status(409).json({
          codigo: 'LIMITE_USUARIOS_PLAN',
          mensaje: cupo.mensaje,
          plan: cupo.limites.plan,
          limites: cupo.limites
        });
      }

      const resultado = db.prepare(`
        INSERT INTO usuarios
        (
          nombre,
          email,
          password,
          rol,
          registrarEntradas,
          registrarSalidas,
          verReportes,
          sesionVersion,
          estacionamiento_id,
          activo
        )
        VALUES (?, ?, ?, 'admin', 1, 1, 1, 0, ?, 1)
      `).run(
        nombre,
        email,
        crearHashPassword(password),
        id
      );

      const usuarioId = Number(resultado.lastInsertRowid);

      registrarAuditoriaSistema({
        superadminId: req.usuario.id,
        accion: 'ADMINISTRADOR_CREADO',
        entidad: 'usuario',
        entidadId: usuarioId,
        nuevo: {
          estacionamientoId: id,
          nombre,
          email,
          rol: 'admin'
        }
      });

      return res.status(201).json({
        mensaje: 'Administrador creado correctamente',
        administrador: {
          id: usuarioId,
          nombre,
          email,
          rol: 'admin',
          activo: true
        }
      });
    } catch (error) {
      console.error('ERROR CREAR ADMINISTRADOR:', error);

      return res.status(500).json({
        mensaje: 'No se pudo crear el administrador'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - RESTABLECER CONTRASEÑA DE ADMINISTRADOR
// ============================================================

app.patch(
  '/api/superadmin/clientes/:id/administradores/:usuarioId/password',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const usuarioId = Number(req.params.usuarioId);
      const password = String(req.body.password || '');

      if (!Number.isInteger(id) ||
          !Number.isInteger(usuarioId)) {
        return res.status(400).json({
          mensaje: 'Identificador no válido'
        });
      }

      const errorPassword = mensajePasswordDemasiadoCorta(password, {
        rol: 'admin',
        etiqueta: 'La nueva contraseña'
      });

      if (errorPassword) {
        return res.status(400).json({
          mensaje: errorPassword
        });
      }

      const administrador = db.prepare(`
        SELECT id, nombre, email
        FROM usuarios
        WHERE id = ?
          AND estacionamiento_id = ?
          AND rol IN ('admin', 'admin_estacionamiento')
          AND activo = 1
      `).get(usuarioId, id);

      if (!administrador) {
        return res.status(404).json({
          mensaje: 'Administrador no encontrado'
        });
      }

      db.prepare(`
        UPDATE usuarios
        SET
          password = ?,
          sesionVersion = sesionVersion + 1
        WHERE id = ?
          AND estacionamiento_id = ?
      `).run(
        crearHashPassword(password),
        usuarioId,
        id
      );

      registrarAuditoriaSistema({
        superadminId: req.usuario.id,
        accion: 'PASSWORD_ADMIN_RESTABLECIDA',
        entidad: 'usuario',
        entidadId: usuarioId,
        nuevo: {
          estacionamientoId: id,
          email: administrador.email
        }
      });

      return res.json({
        mensaje: 'Contraseña restablecida; las sesiones anteriores quedaron cerradas'
      });
    } catch (error) {
      console.error('ERROR RESTABLECER PASSWORD ADMIN:', error);

      return res.status(500).json({
        mensaje: 'No se pudo restablecer la contraseña'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - AUDITORÍA GLOBAL
// ============================================================

app.get(
  '/api/superadmin/auditoria',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const auditoria = db.prepare(`
        SELECT
          a.id,
          a.accion,
          a.entidad,
          a.entidad_id AS entidadId,
          a.datos_anteriores AS datosAnteriores,
          a.datos_nuevos AS datosNuevos,
          a.motivo,
          a.fecha,
          u.nombre AS superadminNombre,
          u.email AS superadminEmail
        FROM auditoria_sistema a
        INNER JOIN usuarios u
          ON u.id = a.superadmin_id
        ORDER BY a.id DESC
        LIMIT 500
      `).all().map(registro => ({
        ...registro,
        datosAnteriores: registro.datosAnteriores
          ? JSON.parse(registro.datosAnteriores)
          : null,
        datosNuevos: registro.datosNuevos
          ? JSON.parse(registro.datosNuevos)
          : null
      }));

      return res.json({ auditoria });
    } catch (error) {
      console.error('ERROR AUDITORIA SUPERADMIN:', error);

      return res.status(500).json({
        mensaje: 'No se pudo obtener la auditoría general'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - ACCESO DELEGADO MODO SOPORTE / AUDITORÍA
// ============================================================

app.post(
  '/api/superadmin/clientes/:id/entrar-soporte',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const clienteId = Number(req.params.id);
      const motivo = String(req.body?.motivo || '').trim();

      if (!Number.isInteger(clienteId) || clienteId < 1) {
        return res.status(400).json({
          mensaje: 'Identificador de cliente inválido'
        });
      }

      if (motivo.length < 5 || motivo.length > 500) {
        return res.status(400).json({
          mensaje: 'Debes indicar un motivo de soporte entre 5 y 500 caracteres'
        });
      }

      const cliente = db.prepare(`
        SELECT id, nombre, plan, estado, zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(clienteId);

      if (!cliente) {
        return res.status(404).json({
          mensaje: 'El estacionamiento seleccionado no existe'
        });
      }

      // Registrar acceso en auditoría global de sistema
      registrarAuditoriaSistema({
        superadminId: req.usuario.id,
        accion: 'SOPORTE_ACCESO_ESTACIONAMIENTO',
        entidad: 'estacionamiento',
        entidadId: cliente.id,
        motivo,
        nuevo: {
          estacionamientoId: cliente.id,
          nombre: cliente.nombre,
          plan: cliente.plan,
          estado: cliente.estado
        }
      });

      // Crear token de sesión delegada de soporte (duración: 2 horas)
      const tokenSoporte = crearTokenSesion(req.usuario, {
        estacionamientoId: cliente.id,
        motivo,
        duracionSegundos: 7200
      });

      return res.json({
        token: tokenSoporte,
        estacionamiento: {
          id: cliente.id,
          nombre: cliente.nombre,
          plan: normalizarPlan(cliente.plan),
          estado: cliente.estado
        },
        usuario: {
          id: req.usuario.id,
          nombre: req.usuario.nombre,
          email: req.usuario.email,
          rol: 'admin',
          rolReal: 'superadmin',
          esSuperadminDelegado: true,
          motivoSoporte: motivo
        },
        mensaje: 'Acceso en modo soporte autorizado exitosamente.'
      });
    } catch (error) {
      console.error('ERROR ACCESO SOPORTE SUPERADMIN:', error);
      return res.status(500).json({
        mensaje: 'No se pudo iniciar el modo soporte para el estacionamiento'
      });
    }
  }
);

// ============================================================
// SUPERADMIN - CONTABILIDAD SAAS Y RECAUDACIÓN DE SUSCRIPCIONES
// ============================================================

app.get(
  '/api/superadmin/contabilidad',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const pagos = db.prepare(`
        SELECT
          p.id,
          p.estacionamiento_id AS estacionamientoId,
          e.nombre AS estacionamientoNombre,
          e.plan AS estacionamientoPlan,
          e.estado AS estacionamientoEstado,
          p.monto,
          p.metodo,
          p.fecha_pago AS fechaPago,
          p.periodo_desde AS periodoDesde,
          p.periodo_hasta AS periodoHasta,
          p.referencia,
          p.observacion,
          p.estado,
          p.creado_en AS creadoEn
        FROM pagos_suscripcion p
        JOIN estacionamientos e ON e.id = p.estacionamiento_id
        WHERE p.estado = 'confirmado'
        ORDER BY p.fecha_pago DESC, p.id DESC
      `).all();

      const totalHistorico = pagos.reduce((acc, p) => acc + (Number(p.monto) || 0), 0);

      const ingresosPorMesMap = {};
      for (const p of pagos) {
        const mes = String(p.fechaPago || p.creadoEn || '').slice(0, 7);
        if (mes) {
          ingresosPorMesMap[mes] = (ingresosPorMesMap[mes] || 0) + (Number(p.monto) || 0);
        }
      }

      const ingresosPorMes = Object.entries(ingresosPorMesMap)
        .map(([mes, total]) => ({ mes, total }))
        .sort((a, b) => b.mes.localeCompare(a.mes));

      const mesActual = new Date().toISOString().slice(0, 7);
      const ingresosMesActual = ingresosPorMesMap[mesActual] || 0;

      const clientes = db.prepare(`
        SELECT id, nombre, plan, estado, precio_mensual, fecha_vencimiento
        FROM estacionamientos
        WHERE visible_superadmin = 1
      `).all();

      const mrrEstimado = clientes
        .filter(c => c.estado === 'activo')
        .reduce((acc, c) => acc + (Number(c.precio_mensual) || 0), 0);

      return res.json({
        totalHistorico,
        ingresosMesActual,
        mrrEstimado,
        ingresosPorMes,
        totalPagos: pagos.length,
        pagos,
        resumenPlanes: {
          total: clientes.length,
          activos: clientes.filter(c => c.estado === 'activo').length,
          suspendidos: clientes.filter(c => c.estado === 'suspendido').length,
          vencidos: clientes.filter(c => c.estado === 'vencido').length,
        }
      });
    } catch (error) {
      console.error('ERROR CONTABILIDAD SUPERADMIN:', error);
      return res.status(500).json({ mensaje: 'No se pudo cargar la contabilidad de la plataforma' });
    }
  }
);

// ============================================================
// SUPERADMIN - COMUNICADOS MASIVOS POR CORREO
// ============================================================

app.post(
  '/api/superadmin/comunicados/enviar',
  requerirSuperAdministrador,
  async (req, res) => {
    try {
      const asunto = textoSeguro(req.body.asunto, 180);
      const mensaje = String(req.body.mensaje || '').trim();
      const destinatariosTipo = String(req.body.destinatariosTipo || 'todos').toLowerCase();

      if (!asunto || !mensaje) {
        return res.status(400).json({ mensaje: 'El asunto y el mensaje son requeridos' });
      }

      let filtroSql = 'WHERE u.activo = 1 AND u.rol IN (\'admin\', \'admin_estacionamiento\')';
      if (destinatariosTipo === 'activos') {
        filtroSql += ' AND e.estado = \'activo\'';
      } else if (destinatariosTipo === 'suspendidos') {
        filtroSql += ' AND e.estado = \'suspendido\'';
      }

      const administradores = db.prepare(`
        SELECT u.id, u.nombre, u.email, e.nombre AS estacionamientoNombre, e.estado AS estacionamientoEstado
        FROM usuarios u
        JOIN estacionamientos e ON e.id = u.estacionamiento_id
        ${filtroSql}
      `).all();

      let enviados = 0;
      for (const admin of administradores) {
        try {
          const html = `<!doctype html>
<html>
<body style="font-family:Arial,sans-serif;color:#172B4D;line-height:1.6;padding:24px;">
  <div style="background:#0F2B52;color:#ffffff;padding:16px 20px;border-radius:8px 8px 0 0;">
    <h2 style="margin:0;color:#ffffff;">ParkControl · Comunicado Oficial</h2>
  </div>
  <div style="background:#ffffff;border:1px solid #E0E8F5;border-top:none;padding:20px;border-radius:0 0 8px 8px;">
    <p>Estimado(a) <strong>${admin.nombre || 'Administrador'}</strong> (${admin.estacionamientoNombre}):</p>
    <div style="margin:20px 0;font-size:15px;white-space:pre-line;color:#253858;">
      ${mensaje}
    </div>
    <hr style="border:none;border-top:1px solid #E0E8F5;margin:24px 0;" />
    <p style="color:#617181;font-size:12px;margin:0;">
      Emitido por la Administración General de ParkControl · Contacto: <strong>neatspacespa@gmail.com</strong>
    </p>
  </div>
</body>
</html>`;

          if (transporteCorreo.disponible) {
            await transporteCorreo.enviar({
              para: admin.email,
              asunto: `[ParkControl] ${asunto}`,
              html,
              texto: `Estimado(a) ${admin.nombre || 'Administrador'}:\n\n${mensaje}\n\nParkControl (neatspacespa@gmail.com)`
            });
          }
          enviados++;
        } catch (_) {}
      }

      db.prepare(`
        INSERT INTO superadmin_comunicados
        (asunto, mensaje, destinatarios_tipo, total_enviados, creado_por, creado_en)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(asunto, mensaje, destinatariosTipo, enviados, req.usuario.id, new Date().toISOString());

      return res.json({
        mensaje: `Comunicado enviado a ${enviados} administradores de estacionamientos.`,
        totalEnviados: enviados,
        destinatariosTipo
      });
    } catch (error) {
      console.error('ERROR ENVIAR COMUNICADO SUPERADMIN:', error);
      return res.status(500).json({ mensaje: 'No se pudo enviar el comunicado' });
    }
  }
);

app.get(
  '/api/superadmin/comunicados',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const lista = db.prepare(`
        SELECT id, asunto, mensaje, destinatarios_tipo AS destinatariosTipo, total_enviados AS totalEnviados, creado_en AS creadoEn
        FROM superadmin_comunicados
        ORDER BY id DESC
        LIMIT 50
      `).all();
      return res.json({ comunicados: lista });
    } catch (error) {
      return res.status(500).json({ mensaje: 'No se pudieron consultar los comunicados' });
    }
  }
);

// ============================================================
// SUPERADMIN - DESBLOQUEO REMOTO DE TURNOS Y CONFLICTOS
// ============================================================

app.post(
  '/api/superadmin/estacionamientos/:id/desbloquear-cajas',
  requerirSuperAdministrador,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      if (!Number.isInteger(id)) {
        return res.status(400).json({ mensaje: 'ID no válido' });
      }

      const resAlertas = db.prepare(`
        UPDATE alertas_administrativas
        SET estado = 'resuelta', resuelta_en = ?, resuelta_por_usuario_id = ?, nota_resolucion = 'Desbloqueado remotamente por SuperAdmin'
        WHERE estacionamiento_id = ? AND estado = 'pendiente'
      `).run(new Date().toISOString(), req.usuario.id, id);

      registrarAuditoriaAdministrativa({
        estacionamientoId: id,
        accion: 'DESBLOQUEO_REMOTO_SUPERADMIN',
        usuario: req.usuario,
        descripcion: `SuperAdmin desbloqueó remotamente cajas y resolvió ${resAlertas.changes} alertas`
      });

      return res.json({
        mensaje: `Cajas y alertas desbloqueadas exitosamente para el estacionamiento ID ${id}.`,
        alertasResueltas: resAlertas.changes
      });
    } catch (error) {
      return res.status(500).json({ mensaje: 'No se pudo realizar el desbloqueo remoto' });
    }
  }
);

// Las rutas que siguen pertenecen a la operación de un estacionamiento.
// El SuperAdministrador no las usa y las cuentas suspendidas quedan
// bloqueadas aquí incluso si conservan un token emitido anteriormente.
app.use('/api', requerirEstacionamientoActivo);

// ============================================================
// TARIFA
// ============================================================

app.get('/api/tarifa', (req, res) => {
  try {
    const tarifa = obtenerTarifaActiva(
      req.usuario.estacionamientoId
    );

    return res.json({
      tarifaId:
        tarifa.id,

      tarifaPorMinuto:
        tarifa.tarifaPorMinuto
    });

  } catch (error) {
    console.error('ERROR TARIFA:', error);

    return res.status(500).json({
      mensaje: 'Error al obtener la tarifa'
    });
  }
});

// ============================================================
// ESTADO INICIAL PARA CACHE Y SINCRONIZACIÓN OFFLINE
// ============================================================

app.get('/api/sincronizacion/estado', (req, res) => {
  try {
    const estacionamientoId = req.usuario.estacionamientoId;
    const tarifa = obtenerTarifaActiva(estacionamientoId);
    const movimientos = db.prepare(`
      SELECT
        id,
        patente,
        tipo,
        color,
        observacion,
        hora_entrada AS horaEntrada,
        version
      FROM movimientos
      WHERE estacionamiento_id = ?
        AND estado = 'dentro'
      ORDER BY hora_entrada ASC, id ASC
    `).all(estacionamientoId).map(movimiento => ({
      ...movimiento,
      id: Number(movimiento.id),
      version: Number(movimiento.version)
    }));

    return res.json({
      versionFormato: 1,
      servidorFecha: new Date().toISOString(),
      estacionamientoId,
      tarifa,
      tarifaPorMinuto: tarifa.tarifaPorMinuto,
      movimientos
    });
  } catch (error) {
    console.error('ERROR ESTADO SINCRONIZACION:', error);

    return res.status(500).json({
      mensaje: 'No se pudo preparar el estado de sincronización'
    });
  }
});

app.post(
  '/api/sincronizacion/conflictos/resolver',
  requerirPermiso('registrarEntradas', 'registrarSalidas'),
  (req, res) => {
    try {
      const estacionamientoId = req.usuario.estacionamientoId;
      const usuarioId = req.usuario.id;
      const usuarioNombre = req.usuario.nombre;
      const usuarioEmail = req.usuario.email;

      const claveOperacion = textoOpcional(
        req.body.claveOperacion ?? req.body.clave
      );
      const accion = String(
        req.body.accion || 'descartar_operacion_local'
      ).trim();
      const tipo = String(req.body.tipo || '').trim().toLowerCase();
      const estado = String(req.body.estado || '').trim().toLowerCase();
      const metodo = String(req.body.metodo || '').trim().toUpperCase();
      const ruta = textoOpcional(req.body.ruta);
      const patente = normalizarPatente(req.body.patente);
      const ultimoError = textoOpcional(req.body.ultimoError);
      const motivo = textoOpcional(req.body.motivo);

      const tiposPermitidos = new Set([
        'entrada',
        'salida',
        'modificacion',
        'eliminacion'
      ]);
      const metodosPermitidos = new Set(['POST', 'PUT', 'DELETE']);

      if (!claveOperacion ||
          !/^[A-Za-z0-9._:-]{8,128}$/.test(claveOperacion)) {
        return res.status(400).json({
          codigo: 'CLAVE_OPERACION_INVALIDA',
          mensaje: 'La clave de la operación offline no es válida'
        });
      }

      if (accion !== 'descartar_operacion_local') {
        return res.status(400).json({
          codigo: 'ACCION_RESOLUCION_INVALIDA',
          mensaje: 'La acción de resolución no es válida'
        });
      }

      if (!tiposPermitidos.has(tipo)) {
        return res.status(400).json({
          codigo: 'TIPO_OPERACION_INVALIDO',
          mensaje: 'El tipo de operación offline no es válido'
        });
      }

      // Una salida pendiente afecta dinero y, en Pro, puede involucrar un
      // cierre de caja. Un cajero no puede descartarla por su cuenta: queda
      // visible como conflicto hasta que un administrador la revise y deje el
      // motivo en la auditoría del estacionamiento.
      if (tipo === 'salida' &&
          obtenerCapacidadesPlan(
            req.usuario.estacionamientoPlan
          ).cierreCaja === true &&
          req.usuario.rol === 'cajero') {
        return res.status(403).json({
          codigo: 'REVISION_ADMINISTRATIVA_REQUERIDA',
          mensaje: 'Un administrador debe revisar una salida Pro en conflicto'
        });
      }

      if (estado !== 'conflicto') {
        return res.status(400).json({
          codigo: 'ESTADO_CONFLICTO_REQUERIDO',
          mensaje: 'Sólo se pueden resolver operaciones en conflicto'
        });
      }

      if (!metodosPermitidos.has(metodo)) {
        return res.status(400).json({
          codigo: 'METODO_OPERACION_INVALIDO',
          mensaje: 'El método de la operación offline no es válido'
        });
      }

      if (!ruta || !ruta.startsWith('/api/') || ruta.length > 200) {
        return res.status(400).json({
          codigo: 'RUTA_OPERACION_INVALIDA',
          mensaje: 'La ruta de la operación offline no es válida'
        });
      }

      if (!motivo || motivo.length < 5 || motivo.length > 500) {
        return res.status(400).json({
          codigo: 'MOTIVO_RESOLUCION_INVALIDO',
          mensaje: 'Indica un motivo de resolución entre 5 y 500 caracteres'
        });
      }

      if (ultimoError && ultimoError.length > 1000) {
        return res.status(400).json({
          codigo: 'DETALLE_CONFLICTO_INVALIDO',
          mensaje: 'El detalle del conflicto es demasiado largo'
        });
      }

      const datosOperacion = {
        claveOperacion,
        accion,
        tipo,
        estado,
        metodo,
        ruta,
        patente: patente || null,
        ultimoError,
        motivo
      };

      const resultadoOperacion = ejecutarOperacionIdempotente({
        req,
        tipo: 'resolucion_conflicto_offline',
        datos: datosOperacion,
        operacion: () => {
          const fecha = new Date().toISOString();

          db.prepare(`
            INSERT INTO auditoria
            (
              estacionamiento_id,
              accion,
              movimiento_id,
              patente_anterior,
              patente_nueva,
              tipo_anterior,
              tipo_nuevo,
              color_anterior,
              color_nuevo,
              observacion_anterior,
              observacion_nueva,
              usuario_id,
              usuario_nombre,
              usuario_email,
              fecha
            )
            VALUES (?, ?, NULL, ?, NULL, ?, NULL, NULL, NULL, ?, ?, ?, ?, ?, ?)
          `).run(
            estacionamientoId,
            'CONFLICTO_OFFLINE_DESCARTADO',
            patente || null,
            tipo,
            ultimoError,
            motivo,
            usuarioId,
            usuarioNombre,
            usuarioEmail,
            fecha
          );

          // Esta acción ya queda registrada con el actor real en auditoria.
          // No se escribe en auditoria_sistema porque su columna histórica
          // superadmin_id no representa a un cajero o administrador local.
          return {
            estadoHttp: 200,
            cuerpo: {
              mensaje: 'Conflicto offline auditado correctamente',
              resolucion: {
                claveOperacion,
                accion,
                estado: 'auditado',
                fecha
              }
            }
          };
        }
      });

      return responderOperacionIdempotente(res, resultadoOperacion);
    } catch (error) {
      console.error('ERROR RESOLVER CONFLICTO OFFLINE:', error);

      return res.status(500).json({
        mensaje: 'No se pudo auditar la resolución del conflicto offline'
      });
    }
  }
);

// ============================================================
// ACTUALIZAR TARIFA
// ============================================================

app.put('/api/tarifa', requerirAdministrador, (req, res) => {
  try {
    const nuevaTarifa =
      Number(req.body.tarifaPorMinuto);

    if (
      !Number.isFinite(nuevaTarifa) ||
      nuevaTarifa < 0
    ) {
      return res.status(400).json({
        mensaje: 'La tarifa no es válida'
      });
    }

    const actualizarTarifa =
      db.transaction(() => {

        db.prepare(`
          UPDATE tarifas
          SET activa = 0
          WHERE estacionamiento_id = ?
            AND activa = 1
        `).run(req.usuario.estacionamientoId);

        db.prepare(`
          INSERT INTO tarifas
          (
            estacionamiento_id,
            tarifa_por_minuto,
            activa
          )
          VALUES (?, ?, 1)
        `).run(
          req.usuario.estacionamientoId,
          nuevaTarifa
        );

      });

    actualizarTarifa();

    return res.json({
      mensaje:
        'Tarifa actualizada correctamente',

      tarifaPorMinuto:
        nuevaTarifa
    });

  } catch (error) {
    console.error(
      'ERROR ACTUALIZAR TARIFA:',
      error
    );

    return res.status(500).json({
      mensaje:
        'Error al actualizar la tarifa'
    });
  }
});

// ============================================================
// REGISTRAR ENTRADA
// ============================================================

app.post(
  '/api/entradas',
  requerirPermiso('registrarEntradas'),
  (req, res) => {
  try {
    const patente =
      normalizarPatente(
        req.body.patente
      );

    const tipo =
      String(
        req.body.tipo || 'Auto'
      ).trim();

    const color =
      String(
        req.body.color ||
        'No especificado'
      ).trim();

    const observacion =
      String(
        req.body.observacion || ''
      ).trim();

    const fechaEntradaReportada =
      fechaOperacionReportadaValida(
        req.body.horaEntradaCliente,
        'horaEntradaCliente'
      );

    if (!patente) {
      return res.status(400).json({
        mensaje:
          'La patente es obligatoria'
      });
    }

    if (!fechaEntradaReportada.ok) {
      return res.status(400).json({
        mensaje:
          fechaEntradaReportada.mensaje
      });
    }

    const datosOperacion = {
      patente,
      tipo,
      color,
      observacion
    };

    if (fechaEntradaReportada.iso) {
      datosOperacion.horaEntradaCliente =
        fechaEntradaReportada.iso;
    }

    const resultadoOperacion = ejecutarOperacionIdempotente({
      req,
      tipo: 'entrada',
      datos: datosOperacion,
      operacion: () => {
        const vehiculoDentro = db.prepare(`
          SELECT id
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND patente = ?
            AND estado = 'dentro'
          ORDER BY id DESC
          LIMIT 1
        `).get(
          req.usuario.estacionamientoId,
          patente
        );

        if (vehiculoDentro) {
          return {
            estadoHttp: 409,
            cuerpo: {
              mensaje:
                'Esta patente ya se encuentra dentro del estacionamiento'
            }
          };
        }

        const tiempoOperacion = crearHoraOperacionOficial(
          fechaEntradaReportada.iso
        );
        const horaEntrada = tiempoOperacion.oficial;

        db.prepare(`
          INSERT INTO vehiculos_estacionamiento
          (
            estacionamiento_id,
            patente,
            tipo,
            color,
            observacion,
            horaEntrada
          )
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT (estacionamiento_id, patente)
          DO UPDATE SET
            tipo = excluded.tipo,
            color = excluded.color,
            observacion = excluded.observacion,
            horaEntrada = excluded.horaEntrada
        `).run(
          req.usuario.estacionamientoId,
          patente,
          tipo,
          color,
          observacion,
          horaEntrada
        );

        const abonado = db.prepare(`
          SELECT id, nombre_titular, fecha_vencimiento, estado
          FROM abonados
          WHERE estacionamiento_id = ? AND patente = ?
        `).get(req.usuario.estacionamientoId, patente);

        const hoy = new Date().toISOString().slice(0, 10);
        const esAbonadoVigente = Boolean(
          abonado && abonado.estado === 'activo' && abonado.fecha_vencimiento >= hoy
        );

        const resultado = db.prepare(`
          INSERT INTO movimientos
          (
            estacionamiento_id,
            patente,
            tipo,
            color,
            observacion,
            hora_entrada,
            hora_entrada_reportada,
            entrada_recibida_en,
            usuario_entrada_id,
            es_abonado,
            abonado_id,
            version,
            estado
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'dentro')
        `).run(
          req.usuario.estacionamientoId,
          patente,
          tipo,
          color,
          observacion,
          horaEntrada,
          tiempoOperacion.reportada,
          tiempoOperacion.recibidaEn,
          req.usuario.id,
          esAbonadoVigente ? 1 : 0,
          abonado ? abonado.id : null
        );

        return {
          estadoHttp: 201,
          cuerpo: {
            mensaje: esAbonadoVigente
              ? `Entrada registrada para ABONADO ${patente} (${abonado.nombre_titular})`
              : `Entrada registrada para ${patente}`,
            esAbonado: esAbonadoVigente,
            abonado: abonado ? {
              id: abonado.id,
              titular: abonado.nombre_titular,
              vencimiento: abonado.fecha_vencimiento,
              estado: abonado.estado,
              vigente: esAbonadoVigente
            } : null,
            movimiento: {
              id: resultado.lastInsertRowid,
              patente,
              tipo,
              color,
              observacion,
              horaEntrada,
              horaEntradaReportada: tiempoOperacion.reportada,
              entradaRecibidaEn: tiempoOperacion.recibidaEn,
              esAbonado: esAbonadoVigente,
              version: 1
            }
          }
        };
      }
    });

    return responderOperacionIdempotente(
      res,
      resultadoOperacion
    );

  } catch (error) {
    console.error(
      'ERROR ENTRADA:',
      error
    );

    return res.status(500).json({
      mensaje:
        'Error al registrar la entrada'
    });
  }
  }
);

// ============================================================
// BUSCAR VEHÍCULO DENTRO
// ============================================================

app.get(
  '/api/vehiculos/:patente',
  (req, res) => {

    try {

      const patente =
        normalizarPatente(
          req.params.patente
        );

      if (!patente) {
        return res.status(400).json({
          mensaje:
            'La patente es obligatoria'
        });
      }

      const movimiento =
        db.prepare(`
          SELECT
            id,
            patente,
            tipo,
            color,
            observacion,
            hora_entrada,
            estado
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND patente = ?
            AND estado = 'dentro'
          ORDER BY id DESC
          LIMIT 1
        `).get(
          req.usuario.estacionamientoId,
          patente
        );

      if (!movimiento) {
        return res.status(404).json({
          mensaje:
            'No se encontró el vehículo dentro del estacionamiento'
        });
      }

      return res.json({
        encontrado: true,

        vehiculo: {
          id:
            movimiento.id,

          patente:
            movimiento.patente,

          tipo:
            movimiento.tipo,

          color:
            movimiento.color,

          observacion:
            movimiento.observacion || '',

          horaEntrada:
            movimiento.hora_entrada,

          version:
            Number(movimiento.version),

          estado:
            movimiento.estado
        }
      });

    } catch (error) {

      console.error(
        'ERROR BUSCAR VEHÍCULO:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al buscar el vehículo'
      });
    }
  }
);

// ============================================================
// BUSCAR REGISTRO PARA MODIFICAR
// ============================================================

app.get(
  '/api/modificar/:patente',
  requerirPermiso(
    'registrarEntradas',
    'registrarSalidas'
  ),
  (req, res) => {

    try {

      const patente =
        normalizarPatente(
          req.params.patente
        );

      if (!patente) {
        return res.status(400).json({
          mensaje:
            'La patente es obligatoria'
        });
      }

      const movimiento =
        db.prepare(`
          SELECT
            id,
            patente,
            tipo,
            color,
            observacion,
            hora_entrada AS horaEntrada,
            hora_salida AS horaSalida,
            minutos,
            tarifa_por_minuto AS tarifaPorMinuto,
            monto,
            version,
            estado
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND patente = ?
            AND estado = 'dentro'
          ORDER BY id DESC
          LIMIT 1
        `).get(
          req.usuario.estacionamientoId,
          patente
        );

      if (!movimiento) {
        return res.status(404).json({
          mensaje:
            `No se encontró la patente ${patente} dentro del estacionamiento`
        });
      }

      return res.json({
        registro:
          movimiento
      });

    } catch (error) {

      console.error(
        'ERROR BUSCAR MODIFICAR:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al buscar el registro'
      });
    }
  }
);

// ============================================================
// MODIFICAR REGISTRO
// ============================================================

app.put(
  '/api/modificar/:patente',
  requerirPermiso(
    'registrarEntradas',
    'registrarSalidas'
  ),
  (req, res) => {

    try {

      const patenteOriginal =
        normalizarPatente(
          req.params.patente
        );

      const patenteNueva =
        normalizarPatente(
          req.body.patente
        );

      const tipo =
        String(
          req.body.tipo || ''
        ).trim();

      const color =
        String(
          req.body.color || ''
        ).trim();

      const observacion =
        String(
          req.body.observacion || ''
        ).trim();

      const versionRecibida = req.body.versionEsperada;
      const versionEsperada = versionRecibida == null
        ? null
        : Number(versionRecibida);

      const usuarioId = req.usuario.id;
      const usuarioNombre = req.usuario.nombre;
      const usuarioEmail = req.usuario.email;
      const estacionamientoId =
        req.usuario.estacionamientoId;

      // --------------------------------------------------------
      // VALIDACIONES
      // --------------------------------------------------------

      if (!patenteOriginal) {
        return res.status(400).json({
          mensaje:
            'La patente original es obligatoria'
        });
      }

      if (!patenteNueva) {
        return res.status(400).json({
          mensaje:
            'La nueva patente es obligatoria'
        });
      }

      if (!tipo) {
        return res.status(400).json({
          mensaje:
            'El tipo de vehículo es obligatorio'
        });
      }

      if (!color) {
        return res.status(400).json({
          mensaje:
            'El color es obligatorio'
        });
      }

      if (versionEsperada != null &&
          (!Number.isInteger(versionEsperada) || versionEsperada < 1)) {
        return res.status(400).json({
          mensaje: 'La versión esperada del movimiento no es válida'
        });
      }

      const datosOperacion = {
        patenteOriginal,
        patenteNueva,
        tipo,
        color,
        observacion,
        versionEsperada
      };
      const operacionExistente = consultarOperacionIdempotente({
        req,
        tipo: 'modificacion',
        datos: datosOperacion
      });

      if (operacionExistente) {
        return responderOperacionIdempotente(
          res,
          operacionExistente
        );
      }

      // --------------------------------------------------------
      // BUSCAR MOVIMIENTO ACTIVO
      // --------------------------------------------------------

      const movimiento =
        db.prepare(`
          SELECT *
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND patente = ?
            AND estado = 'dentro'
          ORDER BY id DESC
          LIMIT 1
        `).get(
          estacionamientoId,
          patenteOriginal
        );

      if (!movimiento) {
        return res.status(404).json({
          mensaje:
            'No se encontró el registro dentro del estacionamiento'
        });
      }

      if (versionEsperada != null &&
          Number(movimiento.version) !== versionEsperada) {
        return res.status(409).json({
          codigo: 'MOVIMIENTO_DESACTUALIZADO',
          mensaje:
            'El movimiento cambió desde la última sincronización',
          versionActual: Number(movimiento.version)
        });
      }

      // --------------------------------------------------------
      // COMPROBAR PATENTE NUEVA
      // --------------------------------------------------------

      if (
        patenteNueva !== patenteOriginal
      ) {

        const patenteOcupada =
          db.prepare(`
            SELECT id
            FROM movimientos
            WHERE estacionamiento_id = ?
              AND patente = ?
              AND estado = 'dentro'
              AND id != ?
            LIMIT 1
          `).get(
            estacionamientoId,
            patenteNueva,
            movimiento.id
          );

        if (patenteOcupada) {
          return res.status(409).json({
            mensaje:
              `La patente ${patenteNueva} ya se encuentra dentro del estacionamiento`
          });
        }

        // También verificamos la ficha de vehículos.
        // Esto evita problemas con UNIQUE(patente).

        const fichaNueva =
          db.prepare(`
            SELECT id
            FROM vehiculos_estacionamiento
            WHERE estacionamiento_id = ?
              AND patente = ?
          `).get(
            estacionamientoId,
            patenteNueva
          );

        if (fichaNueva) {

          // Si existe una ficha histórica con la nueva patente,
          // la conservaremos y posteriormente actualizaremos
          // sus datos.
        }
      }

      const fecha =
        new Date().toISOString();

      // --------------------------------------------------------
      // TRANSACCIÓN COMPLETA
      // --------------------------------------------------------

      const ejecutarModificacion =
        db.transaction(() => {

          // ----------------------------------------------------
          // 1. AUDITORÍA
          // ----------------------------------------------------

          db.prepare(`
            INSERT INTO auditoria
            (
              estacionamiento_id,
              accion,
              movimiento_id,

              patente_anterior,
              patente_nueva,

              tipo_anterior,
              tipo_nuevo,

              color_anterior,
              color_nuevo,

              observacion_anterior,
              observacion_nueva,

              usuario_id,
              usuario_nombre,
              usuario_email,

              fecha
            )
            VALUES (
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?
            )
          `).run(

            estacionamientoId,

            'MODIFICACION',

            movimiento.id,

            movimiento.patente,
            patenteNueva,

            movimiento.tipo,
            tipo,

            movimiento.color,
            color,

            movimiento.observacion || '',
            observacion,

            Number.isInteger(usuarioId)
              ? usuarioId
              : null,

            usuarioNombre,
            usuarioEmail,

            fecha
          );

          // ----------------------------------------------------
          // 2. ACTUALIZAR MOVIMIENTO
          // ----------------------------------------------------

          const resultadoActualizacion = db.prepare(`
            UPDATE movimientos
            SET
              patente = ?,
              tipo = ?,
              color = ?,
              observacion = ?,
              version = version + 1
            WHERE id = ?
              AND estacionamiento_id = ?
              AND estado = 'dentro'
              AND (? IS NULL OR version = ?)
          `).run(
            patenteNueva,
            tipo,
            color,
            observacion,
            movimiento.id,
            estacionamientoId,
            versionEsperada,
            versionEsperada
          );

          if (resultadoActualizacion.changes !== 1) {
            const errorVersion = new Error(
              'El movimiento cambió antes de aplicar la modificación'
            );
            errorVersion.codigo = 'MOVIMIENTO_DESACTUALIZADO';
            throw errorVersion;
          }

          // ----------------------------------------------------
          // 3. BUSCAR FICHA ANTIGUA
          // ----------------------------------------------------

          const vehiculoAnterior =
            db.prepare(`
              SELECT *
              FROM vehiculos_estacionamiento
              WHERE estacionamiento_id = ?
                AND patente = ?
              LIMIT 1
            `).get(
              estacionamientoId,
              patenteOriginal
            );

          // ----------------------------------------------------
          // 4. SI EXISTE FICHA ANTIGUA
          // ----------------------------------------------------

          if (vehiculoAnterior) {

            // Si la patente cambió y ya existe una ficha con
            // la nueva patente, no podemos hacer UPDATE directo
            // debido al UNIQUE de patente.

            if (
              patenteNueva !== patenteOriginal
            ) {

              const vehiculoNuevo =
                db.prepare(`
                  SELECT *
                  FROM vehiculos_estacionamiento
                  WHERE estacionamiento_id = ?
                    AND patente = ?
                  LIMIT 1
                `).get(
                  estacionamientoId,
                  patenteNueva
                );

              if (
                vehiculoNuevo &&
                vehiculoNuevo.id !== vehiculoAnterior.id
              ) {

                // Eliminamos la ficha antigua.
                db.prepare(`
                  DELETE FROM vehiculos_estacionamiento
                  WHERE id = ?
                    AND estacionamiento_id = ?
                `).run(
                  vehiculoAnterior.id,
                  estacionamientoId
                );

                // Actualizamos la ficha existente.
                db.prepare(`
                  UPDATE vehiculos_estacionamiento
                  SET
                    tipo = ?,
                    color = ?,
                    observacion = ?,
                    horaEntrada = ?
                  WHERE id = ?
                    AND estacionamiento_id = ?
                `).run(
                  tipo,
                  color,
                  observacion,
                  movimiento.hora_entrada,
                  vehiculoNuevo.id,
                  estacionamientoId
                );

              } else {

                db.prepare(`
                  UPDATE vehiculos_estacionamiento
                  SET
                    patente = ?,
                    tipo = ?,
                    color = ?,
                    observacion = ?,
                    horaEntrada = ?
                  WHERE id = ?
                    AND estacionamiento_id = ?
                `).run(
                  patenteNueva,
                  tipo,
                  color,
                  observacion,
                  movimiento.hora_entrada,
                  vehiculoAnterior.id,
                  estacionamientoId
                );
              }

            } else {

              db.prepare(`
                UPDATE vehiculos_estacionamiento
                SET
                  tipo = ?,
                  color = ?,
                  observacion = ?,
                  horaEntrada = ?
                WHERE id = ?
                  AND estacionamiento_id = ?
              `).run(
                tipo,
                color,
                observacion,
                movimiento.hora_entrada,
                vehiculoAnterior.id,
                estacionamientoId
              );
            }

          } else {

            // --------------------------------------------------
            // 5. SI NO EXISTE FICHA, CREARLA
            // --------------------------------------------------

            db.prepare(`
              INSERT INTO vehiculos_estacionamiento
              (
                estacionamiento_id,
                patente,
                tipo,
                color,
                observacion,
                horaEntrada
              )
              VALUES (?, ?, ?, ?, ?, ?)
            `).run(
              estacionamientoId,
              patenteNueva,
              tipo,
              color,
              observacion,
              movimiento.hora_entrada
            );
          }
        });

      const resultadoOperacion = ejecutarOperacionIdempotente({
        req,
        tipo: 'modificacion',
        datos: datosOperacion,
        operacion: () => {
          ejecutarModificacion();

          const actualizado = db.prepare(`
            SELECT
              id,
              patente,
              tipo,
              color,
              observacion,
              hora_entrada AS horaEntrada,
              hora_salida AS horaSalida,
              minutos,
              tarifa_por_minuto AS tarifaPorMinuto,
              monto,
              estado,
              version
            FROM movimientos
            WHERE id = ?
              AND estacionamiento_id = ?
          `).get(
            movimiento.id,
            estacionamientoId
          );

          return {
            estadoHttp: 200,
            cuerpo: {
              mensaje: 'Registro modificado correctamente',
              registro: actualizado
            }
          };
        }
      });

      return responderOperacionIdempotente(
        res,
        resultadoOperacion
      );

    } catch (error) {

      if (error.codigo === 'MOVIMIENTO_DESACTUALIZADO') {
        return res.status(409).json({
          codigo: error.codigo,
          mensaje:
            'El movimiento cambió desde la última sincronización'
        });
      }

      console.error(
        '=================================================='
      );

      console.error(
        'ERROR PUT /api/modificar/:patente'
      );

      console.error(
        error
      );

      console.error(
        '=================================================='
      );

      return res.status(500).json({
        mensaje:
          'Error al modificar el registro'
      });
    }
  }
);

// ============================================================
// ELIMINAR REGISTRO
// ============================================================

app.delete(
  '/api/modificar/:patente',
  requerirPermiso(
    'registrarEntradas',
    'registrarSalidas'
  ),
  (req, res) => {

    try {

      const patente =
        normalizarPatente(
          req.params.patente
        );

      const versionRecibida = req.body?.versionEsperada;
      const versionEsperada = versionRecibida == null
        ? null
        : Number(versionRecibida);

      const usuarioId = req.usuario.id;
      const usuarioNombre = req.usuario.nombre;
      const usuarioEmail = req.usuario.email;
      const estacionamientoId =
        req.usuario.estacionamientoId;

      if (!patente) {
        return res.status(400).json({
          mensaje:
            'La patente es obligatoria'
        });
      }

      if (versionEsperada != null &&
          (!Number.isInteger(versionEsperada) || versionEsperada < 1)) {
        return res.status(400).json({
          mensaje: 'La versión esperada del movimiento no es válida'
        });
      }

      const datosOperacion = { patente, versionEsperada };
      const operacionExistente = consultarOperacionIdempotente({
        req,
        tipo: 'eliminacion',
        datos: datosOperacion
      });

      if (operacionExistente) {
        return responderOperacionIdempotente(
          res,
          operacionExistente
        );
      }

      // --------------------------------------------------------
      // BUSCAR MOVIMIENTO ACTIVO
      // --------------------------------------------------------

      const movimiento =
        db.prepare(`
          SELECT *
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND patente = ?
            AND estado = 'dentro'
          ORDER BY id DESC
          LIMIT 1
        `).get(
          estacionamientoId,
          patente
        );

      if (!movimiento) {
        return res.status(404).json({
          mensaje:
            'No se encontró el registro dentro del estacionamiento'
        });
      }

      if (versionEsperada != null &&
          Number(movimiento.version) !== versionEsperada) {
        return res.status(409).json({
          codigo: 'MOVIMIENTO_DESACTUALIZADO',
          mensaje:
            'El movimiento cambió desde la última sincronización',
          versionActual: Number(movimiento.version)
        });
      }

      const fecha =
        new Date().toISOString();

      // --------------------------------------------------------
      // TRANSACCIÓN
      // --------------------------------------------------------

      const ejecutarEliminacion =
        db.transaction(() => {

          // ----------------------------------------------------
          // 1. AUDITORÍA
          // ----------------------------------------------------

          db.prepare(`
            INSERT INTO auditoria
            (
              estacionamiento_id,
              accion,
              movimiento_id,

              patente_anterior,
              patente_nueva,

              tipo_anterior,
              tipo_nuevo,

              color_anterior,
              color_nuevo,

              observacion_anterior,
              observacion_nueva,

              usuario_id,
              usuario_nombre,
              usuario_email,

              fecha
            )
            VALUES (
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?,
              ?
            )
          `).run(

            estacionamientoId,

            'ELIMINACION',

            movimiento.id,

            movimiento.patente,
            null,

            movimiento.tipo,
            null,

            movimiento.color,
            null,

            movimiento.observacion || '',
            null,

            Number.isInteger(usuarioId)
              ? usuarioId
              : null,

            usuarioNombre,
            usuarioEmail,

            fecha
          );

          // ----------------------------------------------------
          // 2. ELIMINACIÓN LÓGICA DEL MOVIMIENTO ACTIVO
          // ----------------------------------------------------
          //
          // auditoria.movimiento_id puede tener una clave foránea
          // hacia movimientos.id. Por eso este registro no se borra:
          // se conserva para auditoría y se marca como eliminado.
          // Al anular una entrada no corresponde cobrar una salida.
          // ----------------------------------------------------

          const resultadoMovimiento =
            db.prepare(`
              UPDATE movimientos
              SET
                estado = 'eliminado',
                hora_salida = NULL,
                minutos = NULL,
                tarifa_por_minuto = NULL,
                monto = NULL,
                version = version + 1
              WHERE id = ?
                AND estacionamiento_id = ?
                AND estado = 'dentro'
                AND (? IS NULL OR version = ?)
            `).run(
              movimiento.id,
              estacionamientoId,
              versionEsperada,
              versionEsperada
            );

          if (
            resultadoMovimiento.changes !== 1
          ) {
            const errorVersion = new Error(
              'No fue posible eliminar el movimiento activo'
            );
            errorVersion.codigo = 'MOVIMIENTO_DESACTUALIZADO';
            throw errorVersion;
          }

          // ----------------------------------------------------
          // 3. COMPROBAR OTROS MOVIMIENTOS QUE REQUIERAN LA FICHA
          // ----------------------------------------------------
          //
          // Sólo se elimina la ficha operativa cuando no exista
          // otro movimiento activo o histórico cobrable para esa
          // patente. El movimiento recién eliminado se omite.
          // ----------------------------------------------------

          const movimientosRelacionados =
            db.prepare(`
              SELECT COUNT(*) AS total
              FROM movimientos
              WHERE estacionamiento_id = ?
                AND patente = ?
                AND id != ?
                AND estado IN ('dentro', 'salio')
            `).get(
              estacionamientoId,
              patente,
              movimiento.id
            );

          // ----------------------------------------------------
          // 4. ELIMINAR FICHA SI YA NO SE DEBE CONSERVAR
          // ----------------------------------------------------

          if (
            Number(
              movimientosRelacionados.total
            ) === 0
          ) {

            db.prepare(`
              DELETE FROM vehiculos_estacionamiento
              WHERE estacionamiento_id = ?
                AND patente = ?
            `).run(
              estacionamientoId,
              patente
            );
          }
        });

      const resultadoOperacion = ejecutarOperacionIdempotente({
        req,
        tipo: 'eliminacion',
        datos: datosOperacion,
        operacion: () => {
          ejecutarEliminacion();

          return {
            estadoHttp: 200,
            cuerpo: {
              mensaje:
                `Registro de ${patente} eliminado correctamente`,
              patente
            }
          };
        }
      });

      return responderOperacionIdempotente(
        res,
        resultadoOperacion
      );

    } catch (error) {

      if (error.codigo === 'MOVIMIENTO_DESACTUALIZADO') {
        return res.status(409).json({
          codigo: error.codigo,
          mensaje:
            'El movimiento cambió desde la última sincronización'
        });
      }

      console.error(
        '=================================================='
      );

      console.error(
        'ERROR DELETE /api/modificar/:patente'
      );

      console.error(
        error
      );

      console.error(
        '=================================================='
      );

      return res.status(500).json({
        mensaje:
          'Error al eliminar el registro'
      });
    }
  }
);

// ============================================================
// AUDITORÍA
// ============================================================

app.get(
  '/api/auditoria',
  requerirAdministrador,
  (req, res) => {

    try {

      const registros =
        db.prepare(`
          SELECT
            id,
            accion,
            movimiento_id,

            patente_anterior AS patenteAnterior,
            patente_nueva AS patenteNueva,

            tipo_anterior AS tipoAnterior,
            tipo_nuevo AS tipoNuevo,

            color_anterior AS colorAnterior,
            color_nuevo AS colorNuevo,

            observacion_anterior AS observacionAnterior,
            observacion_nueva AS observacionNueva,

            usuario_id AS usuarioId,
            usuario_nombre AS usuarioNombre,
            usuario_email AS usuarioEmail,

            fecha

          FROM auditoria

          WHERE estacionamiento_id = ?

          ORDER BY id DESC
        `).all(req.usuario.estacionamientoId);

      return res.json({
        auditoria:
          registros
      });

    } catch (error) {

      console.error(
        'ERROR AUDITORIA:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener la auditoría'
      });
    }
  }
);

// ============================================================
// REGISTRAR SALIDA
// ============================================================

app.post(
  '/api/salidas',
  requerirPermiso('registrarSalidas'),
  (req, res) => {

    try {

      const patente =
        normalizarPatente(
          req.body.patente
        );

      const movimientoIdRecibido = req.body.movimientoId;
      const movimientoId = movimientoIdRecibido == null
        ? null
        : Number(movimientoIdRecibido);
      const versionRecibida = req.body.versionEsperada;
      const versionEsperada = versionRecibida == null
        ? null
        : Number(versionRecibida);
      const tarifaIdRecibida = req.body.tarifaIdEsperada;
      const tarifaIdEsperada = tarifaIdRecibida == null
        ? null
        : Number(tarifaIdRecibida);
      const metodoPago = normalizarMetodoPagoEstacionamiento(
        req.body.metodoPago
      );
      const fechaSalidaReportada =
        fechaOperacionReportadaValida(
          req.body.horaSalidaCliente,
          'horaSalidaCliente'
        );
      const origenOperacion = String(
        req.body.origenOperacion || ''
      ).trim().toLowerCase();

      if (!patente) {
        return res.status(400).json({
          mensaje:
            'La patente es obligatoria'
        });
      }

      if (movimientoId != null &&
          (!Number.isInteger(movimientoId) || movimientoId < 1)) {
        return res.status(400).json({
          mensaje: 'El identificador del movimiento no es válido'
        });
      }

      if (versionEsperada != null &&
          (!Number.isInteger(versionEsperada) || versionEsperada < 1)) {
        return res.status(400).json({
          mensaje: 'La versión esperada del movimiento no es válida'
        });
      }

      if (tarifaIdEsperada != null &&
          (!Number.isInteger(tarifaIdEsperada) || tarifaIdEsperada < 1)) {
        return res.status(400).json({
          mensaje: 'La tarifa esperada no es válida'
        });
      }

      if (!metodoPago) {
        return res.status(400).json({
          mensaje: 'El medio de pago debe ser efectivo, transferencia, tarjeta u otro'
        });
      }

      if (origenOperacion &&
          !['online', 'offline_v1'].includes(origenOperacion)) {
        return res.status(400).json({
          codigo: 'ORIGEN_OPERACION_INVALIDO',
          mensaje: 'El origen de la operación no es válido'
        });
      }

      if (!fechaSalidaReportada.ok) {
        return res.status(400).json({
          mensaje:
            fechaSalidaReportada.mensaje
        });
      }

      const datosOperacion = {
        patente,
        movimientoId,
        versionEsperada,
        tarifaIdEsperada,
        metodoPago,
        origenOperacion: origenOperacion || null
      };

      if (fechaSalidaReportada.iso) {
        datosOperacion.horaSalidaCliente =
          fechaSalidaReportada.iso;
      }

      const resultadoOperacion = ejecutarOperacionIdempotente({
        req,
        tipo: 'salida',
        datos: datosOperacion,
        operacion: () => {
          const requiereTurnoCaja = obtenerCapacidadesPlan(
            req.usuario.estacionamientoPlan
          ).cierreCaja === true;
          const turnoCaja = requiereTurnoCaja
            ? obtenerTurnoAbiertoEstacionamiento(
              req.usuario.estacionamientoId
            )
            : null;

          let turnoCajaIdAsignado = null;
          if (turnoCaja) {
            turnoCajaIdAsignado = Number(turnoCaja.id);
          } else if (requiereTurnoCaja) {
            const ultimoTurno = db.prepare(`
              SELECT id FROM turnos_caja
              WHERE estacionamiento_id = ? AND cajero_usuario_id = ?
              ORDER BY id DESC LIMIT 1
            `).get(req.usuario.estacionamientoId, req.usuario.id);
            if (ultimoTurno) {
              turnoCajaIdAsignado = Number(ultimoTurno.id);
            }
          }

          const movimiento = db.prepare(`
            SELECT *
            FROM movimientos
            WHERE estacionamiento_id = ?
              AND patente = ?
              AND estado = 'dentro'
              AND (? IS NULL OR id = ?)
            ORDER BY id DESC
            LIMIT 1
          `).get(
            req.usuario.estacionamientoId,
            patente,
            movimientoId,
            movimientoId
          );

          if (!movimiento) {
            return {
              estadoHttp: 404,
              cuerpo: {
                mensaje:
                  'No se encontró el vehículo dentro del estacionamiento'
              }
            };
          }

          if (versionEsperada != null &&
              Number(movimiento.version) !== versionEsperada) {
            return {
              estadoHttp: 409,
              cuerpo: {
                codigo: 'MOVIMIENTO_DESACTUALIZADO',
                mensaje:
                  'El movimiento cambió desde la última sincronización',
                versionActual: Number(movimiento.version)
              }
            };
          }

          const tarifaActiva = obtenerTarifaActiva(
            req.usuario.estacionamientoId
          );

          if (tarifaIdEsperada != null &&
              tarifaActiva.id !== tarifaIdEsperada) {
            return {
              estadoHttp: 409,
              cuerpo: {
                codigo: 'TARIFA_DESACTUALIZADA',
                mensaje:
                  'La tarifa cambió desde la última sincronización',
                tarifaActual: tarifaActiva
              }
            };
          }

          const tiempoOperacion = crearHoraOperacionOficial(
            fechaSalidaReportada.iso
          );
          const horaSalida = new Date(tiempoOperacion.oficial);
          const horaEntrada = new Date(movimiento.hora_entrada);

          if (horaSalida.getTime() < horaEntrada.getTime()) {
            return {
              estadoHttp: 409,
              cuerpo: {
                codigo: 'HORA_OPERACION_INCONSISTENTE',
                mensaje:
                  'La hora de salida no puede ser anterior a la entrada'
              }
            };
          }

          let minutos = Math.ceil(
            (
              horaSalida.getTime() -
              horaEntrada.getTime()
            ) / 60000
          );

          if (minutos < 1) {
            minutos = 1;
          }

          const abonado = db.prepare(`
            SELECT id, nombre_titular, fecha_vencimiento, estado
            FROM abonados
            WHERE estacionamiento_id = ? AND patente = ?
          `).get(req.usuario.estacionamientoId, patente);

          const hoy = new Date().toISOString().slice(0, 10);
          const esAbonadoVigente = Boolean(
            (movimiento.es_abonado === 1 || abonado) &&
            abonado &&
            abonado.estado === 'activo' &&
            abonado.fecha_vencimiento >= hoy
          );

          const tarifaPorMinuto = esAbonadoVigente ? 0 : tarifaActiva.tarifaPorMinuto;
          const monto = esAbonadoVigente ? 0 : (minutos * tarifaPorMinuto);
          const metodoPagoFinal = esAbonadoVigente ? 'abonado' : metodoPago;

          const resultadoActualizacion = db.prepare(`
            UPDATE movimientos
            SET
              hora_salida = ?,
              hora_salida_reportada = ?,
              salida_recibida_en = ?,
              origen_salida = ?,
              minutos = ?,
              tarifa_por_minuto = ?,
              monto = ?,
              metodo_pago = ?,
              usuario_salida_id = ?,
              turno_caja_id = ?,
              estado = 'salio',
              version = version + 1
            WHERE id = ?
              AND estacionamiento_id = ?
              AND estado = 'dentro'
              AND (? IS NULL OR version = ?)
          `).run(
            horaSalida.toISOString(),
            tiempoOperacion.reportada,
            tiempoOperacion.recibidaEn,
            origenOperacion || 'online',
            minutos,
            tarifaPorMinuto,
            monto,
            metodoPagoFinal,
            req.usuario.id,
            turnoCajaIdAsignado ? Number(turnoCajaIdAsignado) : null,
            movimiento.id,
            req.usuario.estacionamientoId,
            versionEsperada,
            versionEsperada
          );

          if (resultadoActualizacion.changes !== 1) {
            return {
              estadoHttp: 409,
              cuerpo: {
                codigo: 'MOVIMIENTO_YA_CERRADO',
                mensaje:
                  'El movimiento ya fue cerrado por otra operación'
              }
            };
          }

          if (metodoPagoFinal === 'no_pago') {
            const configMulta = db.prepare(`
              SELECT multa_monto FROM configuracion_multas WHERE estacionamiento_id = ?
            `).get(req.usuario.estacionamientoId);
            const montoMulta = configMulta ? Number(configMulta.multa_monto) : 15000;

            db.prepare(`
              INSERT INTO morosidad_patentes (
                estacionamiento_id, patente, movimiento_id, monto_adeudado, monto_multa, estado, motivo, registrado_por_usuario_id, creado_en
              ) VALUES (?, ?, ?, ?, ?, 'pendiente', 'Salida sin pago / Fuga de vehículo', ?, datetime('now'))
            `).run(
              req.usuario.estacionamientoId,
              patente,
              movimiento.id,
              monto,
              montoMulta,
              req.usuario.id
            );

            try {
              db.prepare(`
                INSERT INTO alertas_administrativas (
                  estacionamiento_id, tipo, severidad, estado, entidad_tipo, entidad_id, clave_deduplicacion, titulo, detalle, monto_diferencia, ocurrida_en
                ) VALUES (?, 'FUGA_VEHICULO_NO_PAGO', 'alta', 'pendiente', 'movimiento', ?, ?, ?, ?, ?, datetime('now'))
              `).run(
                req.usuario.estacionamientoId,
                movimiento.id,
                `fuga-${movimiento.id}-${Date.now()}`,
                `Fuga / No Pago: Patente ${patente}`,
                `Vehículo ${patente} salió sin pagar. Monto adeudado: $${monto}. Multa asignada: $${montoMulta}.`,
                monto
              );
            } catch (_) {}

            try {
              db.prepare(`
                INSERT INTO auditoria (
                  estacionamiento_id, accion, movimiento_id, patente_anterior, patente_nueva, usuario_id, observacion_nueva, fecha
                ) VALUES (?, 'SALIDA_NO_PAGO_FUGA', ?, ?, ?, ?, ?, datetime('now'))
              `).run(
                req.usuario.estacionamientoId,
                movimiento.id,
                patente,
                patente,
                req.usuario.id,
                `Salida sin pagar. Deuda: $${monto} - Multa: $${montoMulta}`
              );
            } catch (_) {}
          }

          return {
            estadoHttp: 200,
            cuerpo: {
              mensaje: esAbonadoVigente
                ? `Salida registrada para ABONADO ${patente} ($0 CLP)`
                : (metodoPagoFinal === 'no_pago' ? `Salida registrada como MOROSA / NO PAGO para ${patente}` : 'Salida registrada correctamente'),
              esAbonado: esAbonadoVigente,
              abonado: abonado ? {
                id: abonado.id,
                titular: abonado.nombre_titular,
                vencimiento: abonado.fecha_vencimiento
              } : null,
              salida: {
                id: movimiento.id,
                patente: movimiento.patente,
                tipo: movimiento.tipo,
                color: movimiento.color,
                observacion: movimiento.observacion || '',
                horaEntrada: movimiento.hora_entrada,
                horaSalida: horaSalida.toISOString(),
                horaSalidaReportada: tiempoOperacion.reportada,
                salidaRecibidaEn: tiempoOperacion.recibidaEn,
                origenSalida: origenOperacion || 'online',
                minutos,
                tarifaPorMinuto,
                monto,
                metodoPago: metodoPagoFinal,
                esAbonado: esAbonadoVigente,
                turnoCajaId: turnoCaja ? Number(turnoCaja.id) : null,
                version: Number(movimiento.version) + 1
              }
            }
          };
        }
      });

      return responderOperacionIdempotente(
        res,
        resultadoOperacion
      );

    } catch (error) {

      console.error(
        'ERROR SALIDA:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al registrar la salida'
      });
    }
  }
);

// ============================================================
// MOROSIDAD Y GESTIÓN DE MULTAS
// ============================================================

app.get('/api/morosidad', (req, res) => {
  try {
    const estado = req.query.estado || 'todos';
    let query = `
      SELECT
        m.id,
        m.patente,
        m.movimiento_id AS movimientoId,
        m.monto_adeudado AS montoAdeudado,
        m.monto_multa AS montoMulta,
        m.monto_pagado AS montoPagado,
        m.estado,
        m.motivo,
        m.creado_en AS creadoEn,
        m.pagado_en AS pagadoEn,
        m.observaciones,
        u1.nombre AS registradoPor,
        u2.nombre AS cobradoPor
      FROM morosidad_patentes m
      LEFT JOIN usuarios u1 ON u1.id = m.registrado_por_usuario_id
      LEFT JOIN usuarios u2 ON u2.id = m.cobrado_por_usuario_id
      WHERE m.estacionamiento_id = ?
    `;
    const params = [req.usuario.estacionamientoId];
    if (estado !== 'todos') {
      query += ' AND m.estado = ?';
      params.push(estado);
    }
    query += ' ORDER BY m.id DESC';

    const registros = db.prepare(query).all(...params);
    return res.json({ morosidad: registros });
  } catch (error) {
    console.error('ERROR GET /api/morosidad:', error);
    return res.status(500).json({ mensaje: 'Error al consultar morosidad' });
  }
});

app.get('/api/morosidad/patente/:patente', (req, res) => {
  try {
    const patente = String(req.params.patente || '').trim().toUpperCase();
    const morosidad = db.prepare(`
      SELECT
        id,
        patente,
        movimiento_id AS movimientoId,
        monto_adeudado AS montoAdeudado,
        monto_multa AS montoMulta,
        monto_pagado AS montoPagado,
        estado,
        motivo,
        creado_en AS creadoEn,
        observaciones
      FROM morosidad_patentes
      WHERE estacionamiento_id = ? AND patente = ? AND estado = 'pendiente'
      ORDER BY id DESC
      LIMIT 1
    `).get(req.usuario.estacionamientoId, patente);

    return res.json({
      esMoroso: Boolean(morosidad),
      morosidad: morosidad || null
    });
  } catch (error) {
    console.error('ERROR GET /api/morosidad/patente:', error);
    return res.status(500).json({ mensaje: 'Error al verificar patente' });
  }
});

app.post('/api/morosidad', requerirAdministrador, (req, res) => {
  try {
    const { patente, montoAdeudado, montoMulta, motivo, observaciones } = req.body;
    const patLimpia = String(patente || '').trim().toUpperCase();
    if (!patLimpia) {
      return res.status(400).json({ mensaje: 'La patente es obligatoria' });
    }

    const resultado = db.prepare(`
      INSERT INTO morosidad_patentes (
        estacionamiento_id, patente, monto_adeudado, monto_multa, estado, motivo, registrado_por_usuario_id, observaciones, creado_en
      ) VALUES (?, ?, ?, ?, 'pendiente', ?, ?, ?, datetime('now'))
    `).run(
      req.usuario.estacionamientoId,
      patLimpia,
      Number(montoAdeudado) || 0,
      Number(montoMulta) || 15000,
      motivo || 'Ingreso manual de multa / morosidad',
      req.usuario.id,
      observaciones || ''
    );

    return res.status(201).json({
      mensaje: 'Patente agregada a lista de morosos y multas',
      id: resultado.lastInsertRowid
    });
  } catch (error) {
    console.error('ERROR POST /api/morosidad:', error);
    return res.status(500).json({ mensaje: 'Error al registrar morosidad' });
  }
});

app.post('/api/morosidad/:id/pagar', (req, res) => {
  try {
    const id = Number(req.params.id);
    const { montoPagado, metodoPago } = req.body;

    const registro = db.prepare(`
      SELECT * FROM morosidad_patentes WHERE id = ? AND estacionamiento_id = ?
    `).get(id, req.usuario.estacionamientoId);

    if (!registro) {
      return res.status(404).json({ mensaje: 'Registro de morosidad no encontrado' });
    }

    const totalDeuda = Number(registro.monto_adeudado) + Number(registro.monto_multa);
    const pagado = Number(montoPagado) || totalDeuda;

    db.prepare(`
      UPDATE morosidad_patentes
      SET estado = 'pagada', monto_pagado = ?, pagado_en = datetime('now'), cobrado_por_usuario_id = ?
      WHERE id = ?
    `).run(pagado, req.usuario.id, id);

    try {
      db.prepare(`
        INSERT INTO auditoria (
          estacionamiento_id, accion, usuario_id, observacion_nueva, fecha
        ) VALUES (?, 'PAGO_MULTA_MOROSIDAD', ?, ?, datetime('now'))
      `).run(
        req.usuario.estacionamientoId,
        req.usuario.id,
        `Pago de multa/deuda para patente ${registro.patente}: $${pagado} (${metodoPago || 'efectivo'})`
      );
    } catch (_) {}

    return res.json({ mensaje: `Multa y deuda de ${registro.patente} pagadas con éxito ($${pagado})` });
  } catch (error) {
    console.error('ERROR POST /api/morosidad/:id/pagar:', error);
    return res.status(500).json({ mensaje: 'Error al procesar pago de multa' });
  }
});

app.post('/api/morosidad/:id/condonar', requerirAdministrador, (req, res) => {
  try {
    const id = Number(req.params.id);
    const { motivo } = req.body;

    const registro = db.prepare(`
      SELECT * FROM morosidad_patentes WHERE id = ? AND estacionamiento_id = ?
    `).get(id, req.usuario.estacionamientoId);

    if (!registro) {
      return res.status(404).json({ mensaje: 'Registro no encontrado' });
    }

    db.prepare(`
      UPDATE morosidad_patentes
      SET estado = 'condonada', observaciones = ?, pagado_en = datetime('now')
      WHERE id = ?
    `).run(`Condonada por administrador: ${motivo || 'Sin motivo'}`, id);

    return res.json({ mensaje: `Multa condonada para la patente ${registro.patente}` });
  } catch (error) {
    console.error('ERROR POST /api/morosidad/:id/condonar:', error);
    return res.status(500).json({ mensaje: 'Error al condonar multa' });
  }
});

app.get('/api/configuracion/multas', (req, res) => {
  try {
    const config = db.prepare(`
      SELECT multa_monto AS multaMonto, motivo_predeterminado AS motivoPredeterminado
      FROM configuracion_multas
      WHERE estacionamiento_id = ?
    `).get(req.usuario.estacionamientoId);

    return res.json({
      multaMonto: config ? Number(config.multaMonto) : 15000,
      motivoPredeterminado: config ? config.motivoPredeterminado : 'Salida sin pago / Fuga de vehículo'
    });
  } catch (error) {
    return res.status(500).json({ mensaje: 'Error al obtener configuración de multas' });
  }
});

app.post('/api/configuracion/multas', requerirAdministrador, (req, res) => {
  try {
    const { multaMonto, motivoPredeterminado } = req.body;
    const monto = Number(multaMonto) || 15000;
    const motivo = motivoPredeterminado || 'Salida sin pago / Fuga de vehículo';

    db.prepare(`
      INSERT INTO configuracion_multas (estacionamiento_id, multa_monto, motivo_predeterminado, actualizado_en)
      VALUES (?, ?, ?, datetime('now'))
      ON CONFLICT(estacionamiento_id) DO UPDATE SET
        multa_monto = excluded.multa_monto,
        motivo_predeterminado = excluded.motivo_predeterminado,
        actualizado_en = datetime('now')
    `).run(req.usuario.estacionamientoId, monto, motivo);

    return res.json({
      mensaje: 'Configuración de multas actualizada correctamente',
      multaMonto: monto,
      motivoPredeterminado: motivo
    });
  } catch (error) {
    return res.status(500).json({ mensaje: 'Error al actualizar configuración de multas' });
  }
});

app.get(
  '/api/historial',
  (req, res) => {

    try {

      const historial =
        db.prepare(`
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
            COALESCE(metodo_pago, 'efectivo') AS metodoPago,
            monto AS totalCobrado,
            estado
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND estado = 'salio'
          ORDER BY id DESC
        `).all(req.usuario.estacionamientoId);

      return res.json(
        historial
      );

    } catch (error) {

      console.error(
        'ERROR HISTORIAL:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener el historial'
      });
    }
  }
);

// ============================================================
// BOLETAS
// ============================================================

app.get(
  '/api/boletas',
  requerirCapacidad('boletasPdf'),
  (req, res) => {

    try {

      const boletas =
        db.prepare(`
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
            COALESCE(metodo_pago, 'efectivo') AS metodoPago,
            monto AS totalCobrado,
            estado
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND estado = 'salio'
          ORDER BY
            hora_salida DESC,
            id DESC
        `).all(req.usuario.estacionamientoId);

      return res.json({
        boletas
      });

    } catch (error) {

      console.error(
        'ERROR BOLETAS:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener las boletas'
      });
    }
  }
);

// ============================================================
// BOLETA INDIVIDUAL
// ============================================================

app.get(
  '/api/boletas/:id',
  requerirCapacidad('boletasPdf'),
  (req, res) => {

    try {

      const id =
        Number(
          req.params.id
        );

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje:
          'ID de comprobante no válido'
        });
      }

      const boleta =
        db.prepare(`
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
            COALESCE(metodo_pago, 'efectivo') AS metodoPago,
            monto AS totalCobrado,
            estado
          FROM movimientos
          WHERE id = ?
            AND estacionamiento_id = ?
            AND estado = 'salio'
        `).get(
          id,
          req.usuario.estacionamientoId
        );

      if (!boleta) {
        return res.status(404).json({
          mensaje:
          'Comprobante no encontrado'
        });
      }

      return res.json(
        boleta
      );

    } catch (error) {

      console.error(
        'ERROR OBTENER BOLETA:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener el comprobante'
      });
    }
  }
);

// ============================================================
// PDF BOLETA
// ============================================================

app.get(
  '/api/boletas/:id/pdf',
  requerirCapacidad('boletasPdf'),
  (req, res) => {

    try {

      const id =
        Number(
          req.params.id
        );

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje:
          'ID de comprobante no válido'
        });
      }

      const boleta =
        db.prepare(`
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
            COALESCE(metodo_pago, 'efectivo') AS metodoPago,
            estado
          FROM movimientos
          WHERE id = ?
            AND estacionamiento_id = ?
            AND estado = 'salio'
        `).get(
          id,
          req.usuario.estacionamientoId
        );

      if (!boleta) {
        return res.status(404).json({
          mensaje:
          'Comprobante no encontrado'
        });
      }

      const estacionamiento = db.prepare(`
        SELECT zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(req.usuario.estacionamientoId);
      const zonaHoraria = resolverZonaHoraria(
        estacionamiento?.zona_horaria
      );

      res.setHeader(
        'Content-Type',
        'application/pdf'
      );

      res.setHeader(
        'Content-Disposition',
        `inline; filename="comprobante-${boleta.folio}.pdf"`
      );

      const doc =
        new PDFDocument({
          size: 'A4',
          margin: 50
        });

      doc.pipe(res);

      doc
        .fontSize(24)
        .font('Helvetica-Bold')
        .text(
          'PARKCONTROL',
          {
            align: 'center'
          }
        );

      doc.moveDown(0.5);

      doc
        .fontSize(18)
        .font('Helvetica-Bold')
        .text(
          `COMPROBANTE N° ${boleta.folio}`,
          {
            align: 'center'
          }
        );

      doc.moveDown(1);

      doc
        .fontSize(10)
        .font('Helvetica')
        .text(
          'Comprobante de estacionamiento · No tributario',
          {
            align: 'center'
          }
        );

      doc.moveDown(2);

      doc
        .moveTo(50, doc.y)
        .lineTo(545, doc.y)
        .stroke();

      doc.moveDown(1.5);

      function datoPDF(
        titulo,
        valor
      ) {

        doc
          .fontSize(11)
          .font('Helvetica-Bold')
          .text(
            `${titulo}:`,
            {
              continued: true
            }
          );

        doc
          .font('Helvetica')
          .text(
            ` ${valor}`
          );

        doc.moveDown(0.5);
      }

      datoPDF(
        'Patente',
        boleta.patente || '-'
      );

      datoPDF(
        'Tipo',
        boleta.tipo || '-'
      );

      datoPDF(
        'Color',
        boleta.color || '-'
      );

      datoPDF(
        'Entrada',
        formatearFechaPDF(
          boleta.horaEntrada,
          zonaHoraria
        )
      );

      datoPDF(
        'Salida',
        formatearFechaPDF(
          boleta.horaSalida,
          zonaHoraria
        )
      );

      datoPDF(
        'Tiempo estacionado',
        `${boleta.minutos || 0} minutos`
      );

      datoPDF(
        'Tarifa',
        `${formatearPesos(
          boleta.tarifaPorMinuto
        )} por minuto`
      );

      datoPDF(
        'Medio de pago',
        boleta.metodoPago === 'transferencia'
          ? 'Transferencia'
          : boleta.metodoPago === 'tarjeta'
            ? 'Tarjeta'
            : boleta.metodoPago === 'otro'
              ? 'Otro medio'
              : 'Efectivo'
      );

      if (
        boleta.observacion &&
        String(
          boleta.observacion
        ).trim() !== ''
      ) {

        doc.moveDown(0.5);

        datoPDF(
          'Observación',
          boleta.observacion
        );
      }

      doc.moveDown(1);

      doc
        .moveTo(50, doc.y)
        .lineTo(545, doc.y)
        .stroke();

      doc.moveDown(1);

      doc
        .fontSize(14)
        .font('Helvetica-Bold')
        .text(
          'TOTAL'
        );

      doc.moveDown(0.5);

      doc
        .fontSize(28)
        .font('Helvetica-Bold')
        .text(
          formatearPesos(
            boleta.monto
          ),
          {
            align: 'right'
          }
        );

      doc.moveDown(3);

      doc
        .fontSize(9)
        .font('Helvetica')
        .text(
          'Documento generado por ParkControl',
          {
            align: 'center'
          }
        );

      doc.moveDown(0.5);

      doc.text(
        `Comprobante ${boleta.folio} · No tributario`,
        {
          align: 'center'
        }
      );

      doc.end();

    } catch (error) {

      console.error(
        'ERROR GENERAR PDF:',
        error
      );

      if (!res.headersSent) {
        return res.status(500).json({
          mensaje:
            'Error al generar el PDF'
        });
      }
    }
  }
);

// ============================================================
// CONTABILIDAD PRO
// ============================================================

app.get(
  '/api/contabilidad',
  requerirAdministrador,
  requerirCapacidad('contabilidadAvanzada'),
  (req, res) => {

    try {

      const fechaInicio =
        req.query.fechaInicio
          ? String(
              req.query.fechaInicio
            ).trim()
          : '';

      const fechaFin =
        req.query.fechaFin
          ? String(
              req.query.fechaFin
            ).trim()
          : '';

      if (
        fechaInicio &&
        !fechaCalendarioValida(fechaInicio)
      ) {
        return res.status(400).json({
          mensaje:
            'La fechaInicio debe ser una fecha válida con formato YYYY-MM-DD'
        });
      }

      if (
        fechaFin &&
        !fechaCalendarioValida(fechaFin)
      ) {
        return res.status(400).json({
          mensaje:
            'La fechaFin debe ser una fecha válida con formato YYYY-MM-DD'
        });
      }

      if (
        fechaInicio &&
        fechaFin &&
        fechaInicio > fechaFin
      ) {
        return res.status(400).json({
          mensaje:
            'La fechaInicio no puede ser posterior a la fechaFin'
        });
      }

      const estacionamiento = db.prepare(`
        SELECT zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(req.usuario.estacionamientoId);
      const zonaHoraria = resolverZonaHoraria(
        estacionamiento?.zona_horaria
      );
      const informe = servicioInformesPro.obtenerContabilidad({
        estacionamientoId: req.usuario.estacionamientoId,
        zonaHoraria,
        fechaInicio,
        fechaFin
      });

      return res.json(informe);

    } catch (error) {

      console.error(
        'ERROR CONTABILIDAD:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener la información contable'
      });
    }
  }
);

// ============================================================
// INFORMES PROGRAMADOS POR CORREO PRO
// ============================================================
// El correo destino siempre se deriva de una cuenta administradora autenticada.
// Así no se transforma esta función en un canal para extraer información del
// estacionamiento hacia direcciones arbitrarias. El transportador externo se
// mantiene opcional y el estado se informa sin exponer claves ni detalles del
// proveedor.

const GUARDIAS_INFORMES_CORREO_PRO = [
  requerirEstacionamientoActivo,
  requerirAdministrador,
  requerirCapacidad('reportesPorCorreo')
];

function respuestaInformesCorreo(req) {
  return {
    transporte: {
      disponible: colaInformesCorreo.transporteDisponible,
      proveedor: colaInformesCorreo.proveedor,
      mensaje: colaInformesCorreo.transporteDisponible
        ? 'Los informes se envían desde el servidor de ParkControl.'
        : 'El correo programado está preparado, pero falta configurar un remitente verificado en el servidor.'
    },
    programaciones: colaInformesCorreo.listarProgramaciones(
      req.usuario.estacionamientoId
    ),
    envios: colaInformesCorreo.listarEnvios(
      req.usuario.estacionamientoId
    )
  };
}

app.get(
  '/api/pro/informes-correo',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  (req, res) => {
    try {
      return res.json(respuestaInformesCorreo(req));
    } catch (error) {
      console.error('ERROR LISTAR INFORMES POR CORREO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo consultar la configuración de informes por correo'
      });
    }
  }
);

app.post(
  '/api/pro/informes-correo',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  (req, res) => {
    try {
      const datos = req.body && typeof req.body === 'object'
        ? req.body
        : {};
      const frecuencia = String(datos.frecuencia || '').trim().toLowerCase();
      const horaLocal = String(datos.horaLocal || '').trim();

      if (datos.activo != null && typeof datos.activo !== 'boolean') {
        return res.status(400).json({
          mensaje: 'activo debe ser verdadero o falso'
        });
      }

      const resultado = colaInformesCorreo.guardarProgramacion({
        estacionamientoId: req.usuario.estacionamientoId,
        usuarioId: req.usuario.id,
        correoDestino: req.usuario.email,
        frecuencia,
        horaLocal,
        activo: datos.activo !== false
      });

      if (resultado.error) {
        return res.status(400).json({ mensaje: resultado.error });
      }

      registrarAuditoriaAdministrativa({
        estacionamientoId: req.usuario.estacionamientoId,
        accion: 'INFORME_CORREO_PROGRAMADO',
        usuario: req.usuario,
        descripcion: `Programación ${frecuencia} configurada para ${horaLocal}`
      });

      const programacion = colaInformesCorreo
        .listarProgramaciones(req.usuario.estacionamientoId)
        .find(item => Number(item.id) === Number(resultado.id));

      return res.status(201).json({
        mensaje: colaInformesCorreo.transporteDisponible
          ? 'Informe programado correctamente'
          : 'Programación guardada. El envío se activará cuando ParkControl configure el remitente verificado.',
        programacion,
        transporteDisponible: colaInformesCorreo.transporteDisponible
      });
    } catch (error) {
      console.error('ERROR CREAR INFORME POR CORREO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo guardar la programación del informe'
      });
    }
  }
);

app.patch(
  '/api/pro/informes-correo/:id',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  (req, res) => {
    try {
      const id = Number(req.params.id);
      const datos = req.body && typeof req.body === 'object'
        ? req.body
        : {};

      if (!Number.isInteger(id) || id < 1) {
        return res.status(400).json({ mensaje: 'La programación no es válida' });
      }

      if (datos.activo != null && typeof datos.activo !== 'boolean') {
        return res.status(400).json({
          mensaje: 'activo debe ser verdadero o falso'
        });
      }

      if (datos.usarMiCorreo != null && typeof datos.usarMiCorreo !== 'boolean') {
        return res.status(400).json({
          mensaje: 'usarMiCorreo debe ser verdadero o falso'
        });
      }

      const resultado = colaInformesCorreo.actualizarProgramacion({
        estacionamientoId: req.usuario.estacionamientoId,
        programacionId: id,
        usuarioId: req.usuario.id,
        correoDestino: datos.usarMiCorreo === true ? req.usuario.email : null,
        horaLocal: datos.horaLocal == null ? null : String(datos.horaLocal),
        activo: datos.activo
      });

      if (resultado.noEncontrada) {
        return res.status(404).json({ mensaje: 'No se encontró la programación' });
      }

      if (resultado.error) {
        return res.status(400).json({ mensaje: resultado.error });
      }

      registrarAuditoriaAdministrativa({
        estacionamientoId: req.usuario.estacionamientoId,
        accion: 'INFORME_CORREO_ACTUALIZADO',
        usuario: req.usuario,
        descripcion: `Programación ${id} actualizada`
      });

      const programacion = colaInformesCorreo
        .listarProgramaciones(req.usuario.estacionamientoId)
        .find(item => Number(item.id) === id);

      return res.json({
        mensaje: 'Programación actualizada correctamente',
        programacion
      });
    } catch (error) {
      console.error('ERROR ACTUALIZAR INFORME POR CORREO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo actualizar la programación del informe'
      });
    }
  }
);

app.delete(
  '/api/pro/informes-correo/:id',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  (req, res) => {
    try {
      const id = Number(req.params.id);

      if (!Number.isInteger(id) || id < 1) {
        return res.status(400).json({ mensaje: 'La programación no es válida' });
      }

      const resultado = colaInformesCorreo.desactivarProgramacion({
        estacionamientoId: req.usuario.estacionamientoId,
        programacionId: id
      });

      if (resultado.noEncontrada) {
        return res.status(404).json({ mensaje: 'No se encontró la programación' });
      }

      registrarAuditoriaAdministrativa({
        estacionamientoId: req.usuario.estacionamientoId,
        accion: 'INFORME_CORREO_DESACTIVADO',
        usuario: req.usuario,
        descripcion: `Programación ${id} desactivada`
      });

      return res.json({
        mensaje: resultado.yaDesactivada
          ? 'La programación ya estaba desactivada'
          : 'Programación desactivada correctamente'
      });
    } catch (error) {
      console.error('ERROR DESACTIVAR INFORME POR CORREO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo desactivar la programación del informe'
      });
    }
  }
);

app.post(
  '/api/pro/informes-correo/:id/envio-prueba',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  (req, res) => {
    try {
      const programacionId = Number(req.params.id);
      const datos = req.body && typeof req.body === 'object'
        ? req.body
        : {};
      const fechaInicio = textoOpcional(datos.fechaInicio) || '';
      const fechaFin = textoOpcional(datos.fechaFin) || '';

      if (!Number.isInteger(programacionId) || programacionId < 1) {
        return res.status(400).json({ mensaje: 'La programación no es válida' });
      }

      if ((fechaInicio && !fechaCalendarioValida(fechaInicio)) ||
          (fechaFin && !fechaCalendarioValida(fechaFin)) ||
          (fechaInicio && fechaFin && fechaInicio > fechaFin)) {
        return res.status(400).json({
          mensaje: 'Revisa el rango de fechas del informe'
        });
      }

      const existe = colaInformesCorreo
        .listarProgramaciones(req.usuario.estacionamientoId)
        .some(item => Number(item.id) === programacionId);

      if (!existe) {
        return res.status(404).json({ mensaje: 'No se encontró la programación' });
      }

      const clave = claveIdempotenciaSolicitud(req);
      const resultadoIdempotente = ejecutarOperacionIdempotente({
        req,
        tipo: 'informe_correo_manual',
        datos: { programacionId, fechaInicio, fechaFin },
        operacion: () => {
          const resultado = colaInformesCorreo.encolarEnvioManual({
            estacionamientoId: req.usuario.estacionamientoId,
            usuarioId: req.usuario.id,
            correoDestino: req.usuario.email,
            fechaInicio,
            fechaFin,
            claveIdempotencia: clave
          });

          if (resultado.correoNoConfigurado) {
            return {
              estadoHttp: 503,
              cuerpo: {
                codigo: 'CORREO_NO_CONFIGURADO',
                mensaje: 'El envío de informes todavía no está configurado en el servidor'
              }
            };
          }

          if (resultado.noDisponible) {
            return {
              estadoHttp: 403,
              cuerpo: {
                codigo: 'INFORME_NO_DISPONIBLE',
                mensaje: 'Los informes por correo no están disponibles para esta cuenta'
              }
            };
          }

          if (resultado.error) {
            return {
              estadoHttp: 400,
              cuerpo: { mensaje: resultado.error }
            };
          }

          registrarAuditoriaAdministrativa({
            estacionamientoId: req.usuario.estacionamientoId,
            accion: 'INFORME_CORREO_SOLICITADO',
            usuario: req.usuario,
            descripcion: `Informe manual encolado (${fechaInicio || 'mes actual'} a ${fechaFin || 'hoy'})`
          });

          return {
            estadoHttp: 202,
            cuerpo: {
              mensaje: 'Informe encolado para envío',
              envioId: resultado.envioId
            }
          };
        }
      });

      return responderOperacionIdempotente(res, resultadoIdempotente);
    } catch (error) {
      console.error('ERROR SOLICITAR INFORME POR CORREO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo solicitar el informe por correo'
      });
    }
  }
);

app.get(
  '/api/pro/informes-correo/envios',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  (req, res) => {
    try {
      return res.json({
        envios: colaInformesCorreo.listarEnvios(
          req.usuario.estacionamientoId,
          req.query.limite
        )
      });
    } catch (error) {
      console.error('ERROR LISTAR ENVÍOS DE INFORME:', error);
      return res.status(500).json({
        mensaje: 'No se pudo consultar los envíos de informes'
      });
    }
  }
);

app.post(
  '/api/pro/informes-correo/envios/:id/reintentar',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  (req, res) => {
    try {
      if (!colaInformesCorreo.transporteDisponible) {
        return res.status(503).json({
          codigo: 'CORREO_NO_CONFIGURADO',
          mensaje: 'El envío de informes todavía no está configurado en el servidor'
        });
      }

      const id = Number(req.params.id);

      if (!Number.isInteger(id) || id < 1) {
        return res.status(400).json({ mensaje: 'El envío no es válido' });
      }

      const resultado = colaInformesCorreo.reintentarEnvio({
        estacionamientoId: req.usuario.estacionamientoId,
        envioId: id
      });

      if (resultado.noEncontrada) {
        return res.status(404).json({ mensaje: 'No se encontró el envío' });
      }

      if (resultado.noReintentable) {
        return res.status(409).json({
          mensaje: 'El envío todavía no puede reintentarse'
        });
      }

      registrarAuditoriaAdministrativa({
        estacionamientoId: req.usuario.estacionamientoId,
        accion: 'INFORME_CORREO_REINTENTADO',
        usuario: req.usuario,
        descripcion: `Se solicitó reintentar el envío ${id}`
      });

      return res.status(202).json({
        mensaje: 'El informe quedó en cola para reintento'
      });
    } catch (error) {
      console.error('ERROR REINTENTAR INFORME POR CORREO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo reintentar el informe'
      });
    }
  }
);

app.post(
  '/api/pro/informes-correo/enviar-inmediato',
  ...GUARDIAS_INFORMES_CORREO_PRO,
  async (req, res) => {
    try {
      const datos = req.body || {};
      const correoDestino = textoOpcional(datos.correoDestino) || req.usuario.email;
      const nombreEncargado = textoOpcional(datos.nombreEncargado) || req.usuario.nombre || 'Administrador';
      const fechaInicio = textoOpcional(datos.fechaInicio) || '';
      const fechaFin = textoOpcional(datos.fechaFin) || '';

      const estacionamiento = db.prepare(`
        SELECT id, nombre, plan, zona_horaria, estado
        FROM estacionamientos
        WHERE id = ?
      `).get(req.usuario.estacionamientoId);

      if (!estacionamiento) {
        return res.status(404).json({ mensaje: 'Estacionamiento no encontrado' });
      }

      const informe = servicioInformesPro.obtenerContabilidad({
        estacionamientoId: req.usuario.estacionamientoId,
        zonaHoraria: estacionamiento.zona_horaria,
        fechaInicio,
        fechaFin
      });

      const csv = servicioInformesPro.crearCsvContabilidad({ informe });
      const pdf = await servicioInformesPro.crearPdfResumenContable({
        nombreEstacionamiento: estacionamiento.nombre,
        informe
      });

      const periodoTexto = fechaInicio || fechaFin ? `${fechaInicio || 'inicio'} a ${fechaFin || 'hoy'}` : 'Período completo';

      const asunto = `ParkControl · Informe Contable y Auditoría (${estacionamiento.nombre})`;
      const html = `<!doctype html>
<html>
<body style="font-family:Arial,sans-serif;color:#172B4D;line-height:1.6;padding:20px;">
  <h2 style="color:#0F2B52;margin-bottom:6px;">Hola ${nombreEncargado},</h2>
  <p>Aquí está el <strong>informe contable y de auditoría</strong> que solicitaste para <strong>${estacionamiento.nombre}</strong>.</p>
  <div style="background:#F4F6F9;border-left:4px solid #1565FF;padding:14px 18px;border-radius:6px;margin:18px 0;">
    <p style="margin:4px 0;"><strong>Período:</strong> ${periodoTexto}</p>
    <p style="margin:4px 0;"><strong>Vehículos cobrados:</strong> ${informe.resumen.cantidadVehiculos}</p>
    <p style="margin:4px 0;"><strong>Ingresos totales:</strong> $${informe.resumen.ingresosTotales.toLocaleString('es-CL')} CLP</p>
    <p style="margin:4px 0;"><strong>Minutos totales:</strong> ${informe.resumen.minutosTotales} min</p>
  </div>
  <p>Adjuntamos el documento PDF oficial y la planilla de datos para que puedas descargarla y archivarla.</p>
  <p style="color:#617181;font-size:12px;margin-top:24px;">Enviado automáticamente por ParkControl desde <strong>neatspacespa@gmail.com</strong>.</p>
</body>
</html>`;

      const texto = `Hola ${nombreEncargado},\n\nAquí está tu informe contable y de auditoría de ${estacionamiento.nombre} (${periodoTexto}).\n\nVehículos cobrados: ${informe.resumen.cantidadVehiculos}\nIngresos: $${informe.resumen.ingresosTotales} CLP\n\nSe adjuntan los archivos correspondientes.\n\nEquipo ParkControl (neatspacespa@gmail.com)`;

      if (transporteCorreo.disponible) {
        await transporteCorreo.enviar({
          para: correoDestino,
          asunto,
          html,
          texto,
          adjuntos: [
            {
              nombre: `informe_contable_parkcontrol_${fechaInicio || 'inicio'}_${fechaFin || 'hoy'}.pdf`,
              contenido: pdf
            },
            {
              nombre: `movimientos_parkcontrol_${fechaInicio || 'inicio'}_${fechaFin || 'hoy'}.csv`,
              contenido: Buffer.from(csv.contenido, 'utf8')
            }
          ]
        });
      }

      registrarAuditoriaAdministrativa({
        estacionamientoId: req.usuario.estacionamientoId,
        accion: 'INFORME_CORREO_INMEDIATO',
        usuario: req.usuario,
        descripcion: `Informe inmediato enviado a ${correoDestino} (${periodoTexto})`
      });

      return res.status(200).json({
        mensaje: `¡Informe enviado exitosamente a ${correoDestino}!`,
        destinatario: correoDestino,
        simulado: !transporteCorreo.disponible
      });
    } catch (error) {
      console.error('ERROR ENVIAR INFORME INMEDIATO:', error);
      return res.status(500).json({
        mensaje: 'No se pudo enviar el informe por correo: ' + (error.message || 'Error del servidor')
      });
    }
  }
);

// ============================================================
// ANALÍTICA PRO: DATOS REALES PARA GRÁFICOS Y EXPORTACIONES
// ============================================================

app.get(
  '/api/pro/analitica',
  requerirAdministrador,
  requerirCapacidad('graficosAvanzados'),
  (req, res) => {
    try {
      const estacionamientoId = req.usuario.estacionamientoId;
      const estacionamiento = db.prepare(`
        SELECT zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(estacionamientoId);
      const zonaHoraria = resolverZonaHoraria(
        estacionamiento?.zona_horaria
      );
      const periodo = crearPeriodoAnalitica(
        req.query.periodo,
        zonaHoraria
      );

      if (!periodo) {
        return res.status(400).json({
          mensaje: 'El periodo debe ser dia, semana, mes, semestre o ano'
        });
      }

      const porClave = new Map(
        periodo.puntos.map(punto => [punto.clave, punto])
      );
      const fechaBase =
        periodo.periodo === 'semestre' || periodo.periodo === 'ano'
          ? `${periodo.primeraClave}-01`
          : periodo.primeraClave.slice(0, 10);
      const fechaMinima = `${fechaBase}T00:00:00.000Z`;

      const movimientos = db.prepare(`
        SELECT
          hora_entrada,
          hora_salida,
          monto,
          estado
        FROM movimientos
        WHERE estacionamiento_id = ?
          AND (
            hora_entrada >= ?
            OR hora_salida >= ?
          )
      `).all(estacionamientoId, fechaMinima, fechaMinima);

      for (const movimiento of movimientos) {
        const claveEntrada = periodo.claveParaFecha(
          movimiento.hora_entrada
        );
        const puntoEntrada = porClave.get(claveEntrada);

        if (puntoEntrada && puntoEntrada.disponible) {
          puntoEntrada.entradas += 1;
        }

        if (movimiento.estado === 'salio' && movimiento.hora_salida) {
          const claveSalida = periodo.claveParaFecha(
            movimiento.hora_salida
          );
          const puntoSalida = porClave.get(claveSalida);

          if (puntoSalida && puntoSalida.disponible) {
            puntoSalida.salidas += 1;
            puntoSalida.ingresos += Number(movimiento.monto || 0);
          }
        }
      }

      const auditorias = db.prepare(`
        SELECT accion, fecha
        FROM auditoria
        WHERE estacionamiento_id = ?
          AND fecha >= ?
          AND accion IN ('MODIFICACION', 'ELIMINACION')
      `).all(estacionamientoId, fechaMinima);

      for (const auditoria of auditorias) {
        const punto = porClave.get(
          periodo.claveParaFecha(auditoria.fecha)
        );

        if (!punto || !punto.disponible) continue;

        if (auditoria.accion === 'MODIFICACION') {
          punto.modificaciones += 1;
        } else if (auditoria.accion === 'ELIMINACION') {
          punto.eliminaciones += 1;
        }
      }

      const puntos = periodo.puntos.map(punto => ({
        ...punto,
        ingresos: Number(punto.ingresos.toFixed(2))
      }));
      const resumen = puntos.reduce((acumulado, punto) => ({
        ingresosBrutos: acumulado.ingresosBrutos + punto.ingresos,
        entradas: acumulado.entradas + punto.entradas,
        salidas: acumulado.salidas + punto.salidas,
        modificaciones: acumulado.modificaciones + punto.modificaciones,
        eliminaciones: acumulado.eliminaciones + punto.eliminaciones
      }), {
        ingresosBrutos: 0,
        entradas: 0,
        salidas: 0,
        modificaciones: 0,
        eliminaciones: 0
      });
      const ventaNetaEstimada = resumen.ingresosBrutos / 1.19;
      const ivaDebitoEstimado =
        resumen.ingresosBrutos - ventaNetaEstimada;

      return res.json({
        periodo: periodo.periodo,
        zonaHoraria,
        actualizadoEn: new Date().toISOString(),
        puntos,
        resumen: {
          ...resumen,
          ingresosBrutos: Number(resumen.ingresosBrutos.toFixed(2)),
          ventaNetaEstimada: Number(ventaNetaEstimada.toFixed(2)),
          ivaDebitoEstimado: Number(ivaDebitoEstimado.toFixed(2)),
          tasaIva: 19,
          promedioPorSalida: resumen.salidas > 0
            ? Number((resumen.ingresosBrutos / resumen.salidas).toFixed(2))
            : 0
        },
        advertenciaTributaria: 'Estimación referencial: considera que los cobros incluyen IVA al 19%. No descuenta crédito fiscal ni reemplaza la declaración ante el SII.'
      });
    } catch (error) {
      console.error('ERROR ANALÍTICA PRO:', error);

      return res.status(500).json({
        mensaje: 'No se pudo obtener la analítica del estacionamiento'
      });
    }
  }
);

// ============================================================
// ANALÍTICA COMPARATIVA PRO: DÍAS Y HORAS CON DATOS REALES
// ============================================================
//
// Se calculan dos cortes de la misma ventana: uno por día de la semana y
// otro por hora local. La actividad es entradas + salidas; los ingresos se
// atribuyen únicamente a una salida persistida. Un movimiento eliminado no
// representa actividad operativa y por eso queda excluido.
// ============================================================

const DIAS_COMPARATIVA_PERMITIDOS = new Set([30, 90, 365]);
const ETIQUETAS_DIAS_COMPARATIVA = [
  'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'
];

function resolverDiasComparativa(diasSolicitados) {
  if (diasSolicitados === undefined) return 90;

  const texto = typeof diasSolicitados === 'string' ||
    typeof diasSolicitados === 'number'
    ? String(diasSolicitados).trim()
    : '';
  const dias = Number(texto);

  if (!/^(30|90|365)$/.test(texto) ||
      !DIAS_COMPARATIVA_PERMITIDOS.has(dias)) {
    return null;
  }

  return dias;
}

function crearGruposComparativa() {
  const crearGrupo = datos => ({
    ...datos,
    entradas: 0,
    salidas: 0,
    ingresos: 0,
    actividad: 0
  });

  return {
    diasSemana: ETIQUETAS_DIAS_COMPARATIVA.map(
      (etiqueta, diaSemana) => crearGrupo({
        diaSemana,
        etiqueta
      })
    ),
    horas: Array.from({ length: 24 }, (_, hora) => crearGrupo({
      hora,
      etiqueta: `${String(hora).padStart(2, '0')}:00`
    }))
  };
}

function indiceDiaSemanaZona(partes) {
  if (!partes) return null;

  // La fecha UTC construida con el calendario local conserva su día de la
  // semana, sin depender de la zona del servidor.
  const diaDomingoCero = new Date(Date.UTC(
    partes.year,
    partes.month - 1,
    partes.day
  )).getUTCDay();

  return (diaDomingoCero + 6) % 7;
}

function normalizarGrupoComparativa(grupo) {
  return {
    ...grupo,
    ingresos: Number(grupo.ingresos.toFixed(2))
  };
}

function seleccionarDestacadoComparativa(grupos, comparar) {
  const gruposConActividad = grupos.filter(
    grupo => grupo.actividad > 0
  );

  if (gruposConActividad.length === 0) return null;

  return gruposConActividad.reduce((seleccionado, grupo) =>
    comparar(grupo, seleccionado) ? grupo : seleccionado
  );
}

app.get(
  '/api/pro/analitica/comparativa',
  requerirAdministrador,
  requerirCapacidad('graficosAvanzados'),
  (req, res) => {
    try {
      const dias = resolverDiasComparativa(req.query.dias);

      if (!dias) {
        return res.status(400).json({
          codigo: 'DIAS_COMPARATIVA_INVALIDO',
          mensaje: 'El parámetro dias debe ser 30, 90 o 365'
        });
      }

      const estacionamientoId = req.usuario.estacionamientoId;
      const estacionamiento = db.prepare(`
        SELECT zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(estacionamientoId);
      const zonaHoraria = resolverZonaHoraria(
        estacionamiento?.zona_horaria
      );
      const hasta = new Date();
      const desde = new Date(
        hasta.getTime() - dias * 24 * 60 * 60 * 1000
      );
      const desdeIso = desde.toISOString();
      const hastaIso = hasta.toISOString();
      const grupos = crearGruposComparativa();
      const resumen = {
        entradas: 0,
        salidas: 0,
        ingresos: 0,
        actividad: 0
      };
      const movimientos = db.prepare(`
        SELECT
          hora_entrada,
          hora_salida,
          monto,
          estado
        FROM movimientos
        WHERE estacionamiento_id = ?
          AND estado IN ('dentro', 'salio')
          AND (
            (
              hora_entrada >= ?
              AND hora_entrada <= ?
            )
            OR (
              estado = 'salio'
              AND hora_salida >= ?
              AND hora_salida <= ?
            )
          )
      `).all(
        estacionamientoId,
        desdeIso,
        hastaIso,
        desdeIso,
        hastaIso
      );

      const registrarEvento = ({ fecha, tipo, monto = 0 }) => {
        const partes = partesFechaZona(fecha, zonaHoraria);
        const diaSemana = indiceDiaSemanaZona(partes);
        const hora = partes?.hour;

        if (!Number.isInteger(diaSemana) ||
            !Number.isInteger(hora) ||
            hora < 0 || hora > 23) {
          return;
        }

        const montoNumerico = Number(monto || 0);
        const ingreso = tipo === 'salida' &&
          Number.isFinite(montoNumerico)
          ? montoNumerico
          : 0;
        const gruposEvento = [
          grupos.diasSemana[diaSemana],
          grupos.horas[hora]
        ];

        for (const grupo of gruposEvento) {
          grupo.actividad += 1;
          grupo.ingresos += ingreso;

          if (tipo === 'entrada') {
            grupo.entradas += 1;
          } else {
            grupo.salidas += 1;
          }
        }

        resumen.actividad += 1;
        resumen.ingresos += ingreso;

        if (tipo === 'entrada') {
          resumen.entradas += 1;
        } else {
          resumen.salidas += 1;
        }
      };

      for (const movimiento of movimientos) {
        if (movimiento.hora_entrada >= desdeIso &&
            movimiento.hora_entrada <= hastaIso) {
          registrarEvento({
            fecha: movimiento.hora_entrada,
            tipo: 'entrada'
          });
        }

        if (movimiento.estado === 'salio' &&
            movimiento.hora_salida >= desdeIso &&
            movimiento.hora_salida <= hastaIso) {
          registrarEvento({
            fecha: movimiento.hora_salida,
            tipo: 'salida',
            monto: movimiento.monto
          });
        }
      }

      const diasSemana = grupos.diasSemana.map(
        normalizarGrupoComparativa
      );
      const horas = grupos.horas.map(normalizarGrupoComparativa);
      const destacados = {
        diaConMayorActividad: seleccionarDestacadoComparativa(
          diasSemana,
          (actual, seleccionado) =>
            actual.actividad > seleccionado.actividad
        ),
        diaConMenorActividadRegistrada:
          seleccionarDestacadoComparativa(
            diasSemana,
            (actual, seleccionado) =>
              actual.actividad < seleccionado.actividad
          ),
        horaConMayorActividad: seleccionarDestacadoComparativa(
          horas,
          (actual, seleccionado) =>
            actual.actividad > seleccionado.actividad
        ),
        horaConMenorActividadRegistrada:
          seleccionarDestacadoComparativa(
            horas,
            (actual, seleccionado) =>
              actual.actividad < seleccionado.actividad
          )
      };

      return res.json({
        dias,
        ventanaDias: dias,
        zonaHoraria,
        desde: desdeIso,
        hasta: hastaIso,
        actualizadoEn: new Date().toISOString(),
        resumen: {
          ...resumen,
          ingresos: Number(resumen.ingresos.toFixed(2))
        },
        diasSemana,
        horas,
        destacados: {
          ...destacados,
          // Compatibilidad de interfaz: siguen siendo null cuando no hay
          // actividad, por lo que un tramo vacío no se presenta como fuerte
          // ni lento.
          diaFuerte: destacados.diaConMayorActividad,
          diaLento: destacados.diaConMenorActividadRegistrada,
          horaFuerte: destacados.horaConMayorActividad,
          horaLenta: destacados.horaConMenorActividadRegistrada
        }
      });
    } catch (error) {
      console.error('ERROR ANALÍTICA COMPARATIVA PRO:', error);

      return res.status(500).json({
        mensaje: 'No se pudo obtener la analítica comparativa del estacionamiento'
      });
    }
  }
);

// ============================================================
// VEHÍCULOS DENTRO
// ============================================================

app.get(
  '/api/vehiculos-dentro',
  (req, res) => {

    try {

      const vehiculos =
        db.prepare(`
          SELECT
            id,
            patente,
            tipo,
            color,
            observacion,
            hora_entrada AS horaEntrada,
            estado
          FROM movimientos
          WHERE estacionamiento_id = ?
            AND estado = 'dentro'
          ORDER BY id DESC
        `).all(req.usuario.estacionamientoId);

      return res.json(
        vehiculos
      );

    } catch (error) {

      console.error(
        'ERROR VEHÍCULOS DENTRO:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener vehículos dentro'
      });
    }
  }
);

// ============================================================
// RESUMEN DASHBOARD
// ============================================================

app.get(
  '/api/resumen',
  (req, res) => {

    try {
      const estacionamiento = db.prepare(`
        SELECT zona_horaria
        FROM estacionamientos
        WHERE id = ?
      `).get(req.usuario.estacionamientoId);
      const resumen = servicioResumenDiario.obtenerResumen({
        estacionamientoId: req.usuario.estacionamientoId,
        zonaHoraria: estacionamiento?.zona_horaria
      });

      return res.json(resumen);

    } catch (error) {

      console.error(
        'ERROR RESUMEN:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener el resumen'
      });
    }
  }
);

// ============================================================
// USUARIOS - OBTENER TODOS
// ============================================================

app.get(
  '/api/usuarios',
  requerirAdministrador,
  (req, res) => {

    try {

      const usuarios =
        db.prepare(`
          SELECT
            id,
            nombre,
            email,
            rol,
            registrarEntradas,
            registrarSalidas,
            verReportes
          FROM usuarios
          WHERE estacionamiento_id = ?
            AND activo = 1
          ORDER BY id ASC
        `).all(req.usuario.estacionamientoId);

      const resultado =
        usuarios.map(
          usuario => ({

            id:
              usuario.id,

            nombre:
              usuario.nombre,

            email:
              usuario.email,

            rol:
              usuario.rol,

            registrarEntradas:
              Boolean(
                usuario.registrarEntradas
              ),

            registrarSalidas:
              Boolean(
                usuario.registrarSalidas
              ),

            verReportes:
              Boolean(
                usuario.verReportes
              )
          })
        );

      return res.json(
        resultado
      );

    } catch (error) {

      console.error(
        'ERROR OBTENER USUARIOS:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener los usuarios'
      });
    }
  }
);

// ============================================================
// USUARIO - OBTENER UNO
// ============================================================

app.get(
  '/api/usuarios/:id',
  requerirAdministrador,
  (req, res) => {

    try {

      const id =
        Number(
          req.params.id
        );

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje:
            'ID de usuario no válido'
        });
      }

      const usuario =
        db.prepare(`
          SELECT
            id,
            nombre,
            email,
            rol,
            registrarEntradas,
            registrarSalidas,
            verReportes
          FROM usuarios
          WHERE id = ?
            AND estacionamiento_id = ?
            AND activo = 1
        `).get(
          id,
          req.usuario.estacionamientoId
        );

      if (!usuario) {
        return res.status(404).json({
          mensaje:
            'Usuario no encontrado'
        });
      }

      return res.json({

        id:
          usuario.id,

        nombre:
          usuario.nombre,

        email:
          usuario.email,

        rol:
          usuario.rol,

        registrarEntradas:
          Boolean(
            usuario.registrarEntradas
          ),

        registrarSalidas:
          Boolean(
            usuario.registrarSalidas
          ),

        verReportes:
          Boolean(
            usuario.verReportes
          )
      });

    } catch (error) {

      console.error(
        'ERROR OBTENER USUARIO:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al obtener el usuario'
      });
    }
  }
);

// ============================================================
// CREAR USUARIO
// ============================================================

app.post(
  '/api/usuarios',
  requerirAdministrador,
  (req, res) => {

    try {

      const nombre =
        String(
          req.body.nombre || ''
        ).trim();

      const email =
        normalizarEmail(
          req.body.email
        );

      const password =
        String(
          req.body.password || ''
        );

      const rol =
        String(
          req.body.rol || 'cajero'
        )
          .trim()
          .toLowerCase();

      const registrarEntradas =
        convertirBooleano(
          req.body.registrarEntradas,
          true
        );

      const registrarSalidas =
        convertirBooleano(
          req.body.registrarSalidas,
          true
        );

      const verReportes =
        convertirBooleano(
          req.body.verReportes,
          false
        );

      if (
        !nombre ||
        !email ||
        !password
      ) {
        return res.status(400).json({
          mensaje:
            'Nombre, email y contraseña son obligatorios'
        });
      }

      const errorPassword = mensajePasswordDemasiadoCorta(password, {
        rol
      });

      if (errorPassword) {
        return res.status(400).json({
          mensaje: errorPassword
        });
      }

      if (
        rol !== 'admin' &&
        rol !== 'cajero'
      ) {
        return res.status(400).json({
          mensaje:
            'El rol no es válido'
        });
      }

      const existe =
        db.prepare(`
          SELECT id
          FROM usuarios
          WHERE email = ?
        `).get(email);

      if (existe) {
        return res.status(409).json({
          mensaje:
            'Ya existe un usuario con ese correo'
        });
      }

      const cupo = validarCupoUsuario({
        estacionamientoId: req.usuario.estacionamientoId,
        rol
      });

      if (!cupo.permitido) {
        return res.status(409).json({
          codigo: 'LIMITE_USUARIOS_PLAN',
          mensaje: cupo.mensaje,
          plan: cupo.limites.plan,
          limites: cupo.limites
        });
      }

      const resultado =
        db.prepare(`
          INSERT INTO usuarios
          (
            nombre,
            email,
            password,
            rol,
            registrarEntradas,
            registrarSalidas,
            verReportes,
            estacionamiento_id,
            activo
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
        `).run(
          nombre,
          email,
          crearHashPassword(password),
          rol,
          registrarEntradas,
          registrarSalidas,
          verReportes,
          req.usuario.estacionamientoId
        );

      const usuario =
        db.prepare(`
          SELECT
            id,
            nombre,
            email,
            rol,
            registrarEntradas,
            registrarSalidas,
            verReportes
          FROM usuarios
          WHERE id = ?
            AND estacionamiento_id = ?
        `).get(
          resultado.lastInsertRowid,
          req.usuario.estacionamientoId
        );

      return res.status(201).json({

        mensaje:
          'Usuario creado correctamente',

        usuario: {

          id:
            usuario.id,

          nombre:
            usuario.nombre,

          email:
            usuario.email,

          rol:
            usuario.rol,

          registrarEntradas:
            Boolean(
              usuario.registrarEntradas
            ),

          registrarSalidas:
            Boolean(
              usuario.registrarSalidas
            ),

          verReportes:
            Boolean(
              usuario.verReportes
            )
        }
      });

    } catch (error) {

      console.error(
        'ERROR CREAR USUARIO:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al crear el usuario'
      });
    }
  }
);

// ============================================================
// MODIFICAR USUARIO
// ============================================================

app.put(
  '/api/usuarios/:id',
  requerirAdministrador,
  (req, res) => {

    try {

      const id =
        Number(
          req.params.id
        );

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje:
            'ID de usuario no válido'
        });
      }

      const nombre =
        String(
          req.body.nombre || ''
        ).trim();

      const email =
        normalizarEmail(
          req.body.email
        );

      const password =
        req.body.password != null
          ? String(
              req.body.password
            )
          : '';

      const rol =
        String(
          req.body.rol || ''
        )
          .trim()
          .toLowerCase();

      const registrarEntradas =
        convertirBooleano(
          req.body.registrarEntradas,
          true
        );

      const registrarSalidas =
        convertirBooleano(
          req.body.registrarSalidas,
          true
        );

      const verReportes =
        convertirBooleano(
          req.body.verReportes,
          false
        );

      if (
        !nombre ||
        !email ||
        !rol
      ) {
        return res.status(400).json({
          mensaje:
            'Nombre, email y rol son obligatorios'
        });
      }

      const errorPassword = password.trim() === ''
        ? null
        : mensajePasswordDemasiadoCorta(password, { rol });

      if (errorPassword) {
        return res.status(400).json({
          mensaje: errorPassword
        });
      }

      if (
        rol !== 'admin' &&
        rol !== 'cajero'
      ) {
        return res.status(400).json({
          mensaje:
            'El rol no es válido'
        });
      }

      const usuarioExiste =
        db.prepare(`
          SELECT id, rol
          FROM usuarios
          WHERE id = ?
            AND estacionamiento_id = ?
            AND activo = 1
        `).get(
          id,
          req.usuario.estacionamientoId
        );

      if (!usuarioExiste) {
        return res.status(404).json({
          mensaje:
            'Usuario no encontrado'
        });
      }

      if (
        (usuarioExiste.rol === 'admin' ||
          usuarioExiste.rol === 'admin_estacionamiento') &&
        rol === 'cajero'
      ) {
        const administradoresActivos = db.prepare(`
          SELECT COUNT(*) AS total
          FROM usuarios
          WHERE estacionamiento_id = ?
            AND rol IN ('admin', 'admin_estacionamiento')
            AND activo = 1
        `).get(req.usuario.estacionamientoId);

        if (Number(administradoresActivos.total) <= 1) {
          return res.status(403).json({
            mensaje: 'El estacionamiento debe conservar al menos un administrador activo'
          });
        }
      }

      const eraAdministrador =
        usuarioExiste.rol === 'admin' ||
        usuarioExiste.rol === 'admin_estacionamiento';
      const seraAdministrador = rol === 'admin';

      if (eraAdministrador !== seraAdministrador) {
        const cupo = validarCupoUsuario({
          estacionamientoId: req.usuario.estacionamientoId,
          rol
        });

        if (!cupo.permitido) {
          return res.status(409).json({
            codigo: 'LIMITE_USUARIOS_PLAN',
            mensaje: cupo.mensaje,
            plan: cupo.limites.plan,
            limites: cupo.limites
          });
        }
      }

      const emailExiste =
        db.prepare(`
          SELECT id
          FROM usuarios
          WHERE email = ?
            AND id != ?
        `).get(
          email,
          id
        );

      if (emailExiste) {
        return res.status(409).json({
          mensaje:
            'Ese correo ya pertenece a otro usuario'
        });
      }

      if (
        password.trim() !== ''
      ) {

        db.prepare(`
          UPDATE usuarios
          SET
            nombre = ?,
            email = ?,
            password = ?,
            rol = ?,
            registrarEntradas = ?,
            registrarSalidas = ?,
            verReportes = ?,
            sesionVersion = sesionVersion + 1
          WHERE id = ?
            AND estacionamiento_id = ?
            AND activo = 1
        `).run(
          nombre,
          email,
          crearHashPassword(password),
          rol,
          registrarEntradas,
          registrarSalidas,
          verReportes,
          id,
          req.usuario.estacionamientoId
        );

      } else {

        db.prepare(`
          UPDATE usuarios
          SET
            nombre = ?,
            email = ?,
            rol = ?,
            registrarEntradas = ?,
            registrarSalidas = ?,
            verReportes = ?,
            sesionVersion = sesionVersion + 1
          WHERE id = ?
            AND estacionamiento_id = ?
            AND activo = 1
        `).run(
          nombre,
          email,
          rol,
          registrarEntradas,
          registrarSalidas,
          verReportes,
          id,
          req.usuario.estacionamientoId
        );
      }

      const usuario =
        db.prepare(`
          SELECT
            id,
            nombre,
            email,
            rol,
            registrarEntradas,
            registrarSalidas,
            verReportes
          FROM usuarios
          WHERE id = ?
            AND estacionamiento_id = ?
            AND activo = 1
        `).get(
          id,
          req.usuario.estacionamientoId
        );

      return res.json({

        mensaje:
          'Usuario actualizado correctamente',

        usuario: {

          id:
            usuario.id,

          nombre:
            usuario.nombre,

          email:
            usuario.email,

          rol:
            usuario.rol,

          registrarEntradas:
            Boolean(
              usuario.registrarEntradas
            ),

          registrarSalidas:
            Boolean(
              usuario.registrarSalidas
            ),

          verReportes:
            Boolean(
              usuario.verReportes
            )
        }
      });

    } catch (error) {

      console.error(
        'ERROR ACTUALIZAR USUARIO:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al actualizar el usuario'
      });
    }
  }
);

// ============================================================
// ============================================================
// ELIMINAR USUARIO
// ============================================================

app.delete(
  '/api/usuarios/:id',
  requerirAdministrador,
  (req, res) => {

    try {

      const id =
        Number(
          req.params.id
        );

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          mensaje:
            'ID de usuario no válido'
        });
      }

      const usuario =
        db.prepare(`
          SELECT
            id,
            nombre,
            email,
            rol
          FROM usuarios
          WHERE id = ?
            AND estacionamiento_id = ?
            AND activo = 1
        `).get(
          id,
          req.usuario.estacionamientoId
        );

      if (!usuario) {
        return res.status(404).json({
          mensaje:
            'Usuario no encontrado'
        });
      }

      if (
        usuario.id === req.usuario.id
      ) {
        return res.status(403).json({
          mensaje:
            'No puedes desactivar tu propia cuenta'
        });
      }

      if (
        usuario.rol === 'admin' ||
        usuario.rol === 'admin_estacionamiento'
      ) {
        const administradoresActivos = db.prepare(`
          SELECT COUNT(*) AS total
          FROM usuarios
          WHERE estacionamiento_id = ?
            AND rol IN ('admin', 'admin_estacionamiento')
            AND activo = 1
        `).get(req.usuario.estacionamientoId);

        if (Number(administradoresActivos.total) <= 1) {
          return res.status(403).json({
            mensaje: 'El estacionamiento debe conservar al menos un administrador activo'
          });
        }
      }

      db.prepare(`
        UPDATE usuarios
        SET
          activo = 0,
          sesionVersion = sesionVersion + 1
        WHERE id = ?
          AND estacionamiento_id = ?
      `).run(
        id,
        req.usuario.estacionamientoId
      );

      return res.json({
        mensaje:
          'Usuario desactivado correctamente'
      });

    } catch (error) {

      console.error(
        'ERROR ELIMINAR USUARIO:',
        error
      );

      return res.status(500).json({
        mensaje:
          'Error al eliminar el usuario'
      });
    }
  }
);

// ============================================================
// ABONADOS Y CONVENIOS MENSUALES
// ============================================================

app.get('/api/abonados', (req, res) => {
  try {
    const buscar = String(req.query.buscar || '').trim().toLowerCase();
    const estado = String(req.query.estado || '').trim().toLowerCase();

    let query = `
      SELECT
        id,
        nombre_titular AS nombreTitular,
        rut,
        telefono,
        email,
        patente,
        tipo_vehiculo AS tipoVehiculo,
        monto_mensual AS montoMensual,
        fecha_inicio AS fechaInicio,
        fecha_vencimiento AS fechaVencimiento,
        estado,
        observacion,
        creado_en AS creadoEn,
        actualizado_en AS actualizadoEn
      FROM abonados
      WHERE estacionamiento_id = ?
    `;
    const params = [req.usuario.estacionamientoId];

    if (buscar) {
      query += ` AND (
        LOWER(nombre_titular) LIKE ? OR
        LOWER(patente) LIKE ? OR
        LOWER(COALESCE(rut, '')) LIKE ? OR
        LOWER(COALESCE(email, '')) LIKE ?
      )`;
      const pattern = `%${buscar}%`;
      params.push(pattern, pattern, pattern, pattern);
    }

    if (estado && estado !== 'todos') {
      query += ` AND estado = ?`;
      params.push(estado);
    }

    query += ` ORDER BY id DESC`;

    const hoy = new Date().toISOString().slice(0, 10);

    const abonados = db.prepare(query).all(...params).map(a => {
      let estadoComercial = a.estado;
      if (a.estado === 'activo') {
        if (a.fechaVencimiento < hoy) {
          estadoComercial = 'vencido';
        } else {
          const diffDays = Math.ceil(
            (new Date(a.fechaVencimiento).getTime() - new Date(hoy).getTime()) / (1000 * 3600 * 24)
          );
          if (diffDays <= 7) {
            estadoComercial = 'por_vencer';
          } else {
            estadoComercial = 'al_dia';
          }
        }
      }
      return {
        ...a,
        montoMensual: Number(a.montoMensual),
        estadoComercial
      };
    });

    return res.json({ abonados });
  } catch (error) {
    console.error('ERROR LISTAR ABONADOS:', error);
    return res.status(500).json({ mensaje: 'No se pudieron listar los abonados' });
  }
});

app.get('/api/abonados/verificar/:patente', (req, res) => {
  try {
    const patente = normalizarPatente(req.params.patente);
    if (!patente) {
      return res.status(400).json({ mensaje: 'Patente inválida' });
    }

    const abonado = db.prepare(`
      SELECT
        id,
        nombre_titular AS nombreTitular,
        rut,
        telefono,
        email,
        patente,
        tipo_vehiculo AS tipoVehiculo,
        monto_mensual AS montoMensual,
        fecha_inicio AS fechaInicio,
        fecha_vencimiento AS fechaVencimiento,
        estado,
        observacion
      FROM abonados
      WHERE estacionamiento_id = ? AND patente = ?
    `).get(req.usuario.estacionamientoId, patente);

    if (!abonado) {
      return res.json({ esAbonado: false, abonado: null });
    }

    const hoy = new Date().toISOString().slice(0, 10);
    const vigente = abonado.estado === 'activo' && abonado.fechaVencimiento >= hoy;

    return res.json({
      esAbonado: true,
      vigente,
      abonado: {
        ...abonado,
        montoMensual: Number(abonado.montoMensual),
        vigente
      }
    });
  } catch (error) {
    console.error('ERROR VERIFICAR ABONADO:', error);
    return res.status(500).json({ mensaje: 'Error al verificar abonado' });
  }
});

app.post('/api/abonados', requerirAdministrador, (req, res) => {
  try {
    const nombreTitular = String(req.body.nombreTitular || '').trim();
    const patente = normalizarPatente(req.body.patente);
    const rut = String(req.body.rut || '').trim();
    const telefono = String(req.body.telefono || '').trim();
    const email = String(req.body.email || '').trim().toLowerCase();
    const tipoVehiculo = String(req.body.tipoVehiculo || 'Auto').trim();
    const montoMensual = Number(req.body.montoMensual || 0);
    const fechaInicio = String(req.body.fechaInicio || '').slice(0, 10);
    const fechaVencimiento = String(req.body.fechaVencimiento || '').slice(0, 10);
    const observacion = String(req.body.observacion || '').trim();

    if (!nombreTitular || nombreTitular.length < 2) {
      return res.status(400).json({ mensaje: 'El nombre del titular es obligatorio' });
    }
    if (!patente) {
      return res.status(400).json({ mensaje: 'La patente es obligatoria y debe ser válida' });
    }
    if (!fechaInicio || !fechaVencimiento) {
      return res.status(400).json({ mensaje: 'Las fechas de inicio y vencimiento son obligatorias' });
    }
    if (fechaVencimiento < fechaInicio) {
      return res.status(400).json({ mensaje: 'La fecha de vencimiento no puede ser anterior al inicio' });
    }

    const existente = db.prepare(`
      SELECT id, nombre_titular
      FROM abonados
      WHERE estacionamiento_id = ? AND patente = ?
    `).get(req.usuario.estacionamientoId, patente);

    if (existente) {
      return res.status(409).json({
        mensaje: `La patente ${patente} ya está registrada como abonado a nombre de ${existente.nombre_titular}`
      });
    }

    const ahora = new Date().toISOString();
    const resultado = db.prepare(`
      INSERT INTO abonados
      (
        estacionamiento_id,
        nombre_titular,
        rut,
        telefono,
        email,
        patente,
        tipo_vehiculo,
        monto_mensual,
        fecha_inicio,
        fecha_vencimiento,
        estado,
        observacion,
        creado_en,
        actualizado_en
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'activo', ?, ?, ?)
    `).run(
      req.usuario.estacionamientoId,
      nombreTitular,
      rut || null,
      telefono || null,
      email || null,
      patente,
      tipoVehiculo,
      montoMensual >= 0 ? montoMensual : 0,
      fechaInicio,
      fechaVencimiento,
      observacion || null,
      ahora,
      ahora
    );

    return res.status(201).json({
      mensaje: `Abonado ${nombreTitular} registrado exitosamente para la patente ${patente}`,
      abonado: {
        id: resultado.lastInsertRowid,
        nombreTitular,
        patente,
        tipoVehiculo,
        montoMensual,
        fechaInicio,
        fechaVencimiento,
        estado: 'activo'
      }
    });
  } catch (error) {
    console.error('ERROR CREAR ABONADO:', error);
    return res.status(500).json({ mensaje: 'No se pudo registrar el abonado' });
  }
});

app.put('/api/abonados/:id', requerirAdministrador, (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ mensaje: 'ID de abonado inválido' });
    }

    const existente = db.prepare(`
      SELECT * FROM abonados
      WHERE id = ? AND estacionamiento_id = ?
    `).get(id, req.usuario.estacionamientoId);

    if (!existente) {
      return res.status(404).json({ mensaje: 'Abonado no encontrado' });
    }

    const nombreTitular = String(req.body.nombreTitular ?? existente.nombre_titular).trim();
    const rut = String(req.body.rut ?? existente.rut ?? '').trim();
    const telefono = String(req.body.telefono ?? existente.telefono ?? '').trim();
    const email = String(req.body.email ?? existente.email ?? '').trim().toLowerCase();
    const tipoVehiculo = String(req.body.tipoVehiculo ?? existente.tipo_vehiculo).trim();
    const montoMensual = req.body.montoMensual != null ? Number(req.body.montoMensual) : existente.monto_mensual;
    const fechaInicio = String(req.body.fechaInicio ?? existente.fecha_inicio).slice(0, 10);
    const fechaVencimiento = String(req.body.fechaVencimiento ?? existente.fecha_vencimiento).slice(0, 10);
    const estado = String(req.body.estado ?? existente.estado).trim().toLowerCase();
    const observacion = String(req.body.observacion ?? existente.observacion ?? '').trim();

    const ahora = new Date().toISOString();
    db.prepare(`
      UPDATE abonados
      SET
        nombre_titular = ?,
        rut = ?,
        telefono = ?,
        email = ?,
        tipo_vehiculo = ?,
        monto_mensual = ?,
        fecha_inicio = ?,
        fecha_vencimiento = ?,
        estado = ?,
        observacion = ?,
        actualizado_en = ?
      WHERE id = ? AND estacionamiento_id = ?
    `).run(
      nombreTitular,
      rut || null,
      telefono || null,
      email || null,
      tipoVehiculo,
      montoMensual,
      fechaInicio,
      fechaVencimiento,
      ['activo', 'suspendido'].includes(estado) ? estado : 'activo',
      observacion || null,
      ahora,
      id,
      req.usuario.estacionamientoId
    );

    return res.json({
      mensaje: 'Abonado actualizado correctamente',
      abonado: {
        id,
        nombreTitular,
        patente: existente.patente,
        fechaVencimiento,
        estado
      }
    });
  } catch (error) {
    console.error('ERROR ACTUALIZAR ABONADO:', error);
    return res.status(500).json({ mensaje: 'No se pudo actualizar el abonado' });
  }
});

app.delete('/api/abonados/:id', requerirAdministrador, (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ mensaje: 'ID de abonado inválido' });
    }

    db.prepare(`
      UPDATE movimientos
      SET abonado_id = NULL
      WHERE abonado_id = ? AND estacionamiento_id = ?
    `).run(id, req.usuario.estacionamientoId);

    const resultado = db.prepare(`
      DELETE FROM abonados
      WHERE id = ? AND estacionamiento_id = ?
    `).run(id, req.usuario.estacionamientoId);

    if (resultado.changes === 0) {
      return res.status(404).json({ mensaje: 'Abonado no encontrado' });
    }

    return res.json({ mensaje: 'Abonado eliminado correctamente' });
  } catch (error) {
    console.error('ERROR ELIMINAR ABONADO:', error);
    return res.status(500).json({ mensaje: 'No se pudo eliminar el abonado' });
  }
});

// ============================================================
// RUTA NO ENCONTRADA
// ============================================================

app.use(
  (req, res) => {

    res.status(404).json({
      mensaje:
        'Ruta no encontrada'
    });
  }
);

// ============================================================
// MANEJO GENERAL DE ERRORES
// ============================================================

app.use(
  (error, req, res, next) => {

    console.error(
      'ERROR GENERAL API:',
      error
    );

    if (res.headersSent) {
      return next(error);
    }

    if (error?.type === 'entity.parse.failed') {
      return res.status(400).json({
        mensaje: 'El contenido JSON no es válido'
      });
    }

    if (error?.type === 'entity.too.large' || error?.status === 413) {
      return res.status(413).json({
        mensaje: 'La solicitud supera el tamaño permitido'
      });
    }

    return res.status(500).json({
      mensaje: 'Error interno del servidor'
    });
  }
);

// ============================================================
// INICIAR SERVIDOR
// ============================================================

let intervaloInformesCorreo = null;

function iniciarProcesadorInformesCorreo() {
  if (!colaInformesCorreo.transporteDisponible || intervaloInformesCorreo) {
    return;
  }

  const procesar = () => {
    colaInformesCorreo.procesarDisponibles({ limite: 3 })
      .catch(error => {
        // Nunca se registra el error crudo del proveedor: puede incluir datos
        // de contacto o detalles que no pertenecen al log operativo.
        console.error(
          'ERROR PROCESADOR INFORMES POR CORREO:',
          error?.message || 'fallo no identificado'
        );
      });
  };

  procesar();
  intervaloInformesCorreo = setInterval(procesar, 60 * 1000);
  intervaloInformesCorreo.unref();
}

const servidorHttp = app.listen(
  PORT,
  configuracion.host,
  () => {

    console.log('');
    console.log('====================================');
    console.log('          PARKCONTROL API');
    console.log('====================================');

    console.log(
      `API ejecutándose en http://${configuracion.host.includes(':')
        ? `[${configuracion.host}]`
        : configuracion.host}:${PORT}`
    );

    console.log(
      `Base de datos: ${RUTA_BASE_DATOS}`
    );

    console.log(
      'Boletas: /api/boletas'
    );

    console.log(
      'PDF boleta: /api/boletas/:id/pdf'
    );

    console.log(
      'Contabilidad Pro: /api/contabilidad'
    );

    if (colaInformesCorreo.transporteDisponible) {
      console.log('Informes Pro por correo: procesador activo');
    } else {
      console.log('Informes Pro por correo: pendiente de configurar remitente');
    }

    console.log(
      'Modificar: /api/modificar/:patente'
    );

    console.log(
      'Auditoría: /api/auditoria'
    );

    if (!existeSuperAdministrador()) {
      const codigoVisible =
        CLAVE_CONFIGURACION_INICIAL
          .match(/.{1,4}/g)
          ?.join('-') ||
        CLAVE_CONFIGURACION_INICIAL;

      console.log('');
      console.log(
        `Código único para crear el SuperAdministrador: ${codigoVisible}`
      );
      console.log(
        'Este código deja de servir cuando se crea la cuenta propietaria.'
      );
      console.log('');
    }

    console.log(
      'Estado: FUNCIONANDO'
    );

    console.log('====================================');
    console.log('');

    iniciarProcesadorInformesCorreo();
  }
);

let apagandoServidor = false;

function apagarServidorDeFormaSegura(senal) {
  if (apagandoServidor) {
    return;
  }

  apagandoServidor = true;
  console.log(`Se recibió ${senal}; cerrando ParkControl de forma segura.`);

  // Evita que una conexión defectuosa impida indefinidamente que el gestor
  // del VPS reinicie el proceso. El temporizador no mantiene vivo al proceso.
  const salidaForzada = setTimeout(() => {
    console.error('El cierre ordenado superó el tiempo máximo.');
    process.exit(1);
  }, 10000);
  salidaForzada.unref();

  servidorHttp.close(errorHttp => {
    clearTimeout(salidaForzada);

    if (intervaloInformesCorreo) {
      clearInterval(intervaloInformesCorreo);
      intervaloInformesCorreo = null;
    }

    try {
      // PASSIVE no fuerza escrituras concurrentes; deja SQLite consistente
      // antes de ceder el proceso al gestor de servicio.
      db.pragma('wal_checkpoint(PASSIVE)');
      db.close();
    } catch (errorBaseDatos) {
      console.error(
        'No se pudo cerrar SQLite de forma ordenada:',
        errorBaseDatos.message
      );
      process.exit(1);
      return;
    }

    if (errorHttp) {
      console.error('No se pudo cerrar el servidor HTTP:', errorHttp.message);
      process.exit(1);
      return;
    }

    process.exit(0);
  });
}

process.once('SIGTERM', () => apagarServidorDeFormaSegura('SIGTERM'));
process.once('SIGINT', () => apagarServidorDeFormaSegura('SIGINT'));
