const assert = require('node:assert/strict');
const Database = require('better-sqlite3');

const {
  crearColaInformesCorreo
} = require('../servicios/cola_informes_correo');

async function ejecutar() {
  const db = new Database(':memory:');
  db.pragma('foreign_keys = ON');
  db.exec(`
    CREATE TABLE estacionamientos (
      id INTEGER PRIMARY KEY,
      nombre TEXT NOT NULL,
      estado TEXT NOT NULL,
      plan TEXT NOT NULL,
      zona_horaria TEXT NOT NULL
    );
    CREATE TABLE usuarios (
      id INTEGER PRIMARY KEY,
      estacionamiento_id INTEGER NOT NULL,
      email TEXT NOT NULL,
      rol TEXT NOT NULL,
      activo INTEGER NOT NULL
    );
    CREATE TABLE informes_correo_programados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      estacionamiento_id INTEGER NOT NULL,
      creado_por_usuario_id INTEGER NOT NULL,
      destinatario_usuario_id INTEGER NOT NULL,
      frecuencia TEXT NOT NULL,
      hora_local TEXT NOT NULL,
      zona_horaria TEXT NOT NULL,
      correo_destino TEXT NOT NULL,
      activo INTEGER NOT NULL,
      ultima_clave_periodo TEXT,
      ultima_ejecucion_en TEXT,
      creado_en TEXT NOT NULL,
      actualizado_en TEXT NOT NULL,
      UNIQUE (estacionamiento_id, frecuencia)
    );
    CREATE TABLE informes_correo_envios (
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
      estado TEXT NOT NULL,
      intentos INTEGER NOT NULL,
      disponible_en TEXT NOT NULL,
      reservado_hasta TEXT,
      error_publico TEXT,
      proveedor TEXT,
      proveedor_mensaje_id TEXT,
      clave_deduplicacion TEXT NOT NULL,
      creado_en TEXT NOT NULL,
      enviado_en TEXT,
      actualizado_en TEXT NOT NULL,
      UNIQUE (estacionamiento_id, clave_deduplicacion)
    );
    CREATE TABLE informes_correo_eventos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      estacionamiento_id INTEGER NOT NULL,
      envio_id INTEGER NOT NULL,
      tipo TEXT NOT NULL,
      mensaje TEXT,
      creado_en TEXT NOT NULL
    );
  `);
  db.prepare(`
    INSERT INTO estacionamientos (id, nombre, estado, plan, zona_horaria)
    VALUES (?, ?, ?, ?, ?)
  `).run(1, 'Parking Norte', 'activo', 'PRO', 'America/Santiago');
  db.prepare(`
    INSERT INTO estacionamientos (id, nombre, estado, plan, zona_horaria)
    VALUES (?, ?, ?, ?, ?)
  `).run(2, 'Parking Sur', 'activo', 'PRO', 'America/Santiago');
  db.prepare(`
    INSERT INTO usuarios (id, estacionamiento_id, email, rol, activo)
    VALUES (?, ?, ?, ?, ?)
  `).run(10, 1, 'admin.norte@prueba.cl', 'admin', 1);
  db.prepare(`
    INSERT INTO usuarios (id, estacionamiento_id, email, rol, activo)
    VALUES (?, ?, ?, ?, ?)
  `).run(20, 2, 'admin.sur@prueba.cl', 'admin', 1);

  let fechaActual = new Date('2026-08-20T12:00:00.000Z');
  const enviados = [];
  const cola = crearColaInformesCorreo({
    db,
    transporte: {
      disponible: true,
      proveedor: 'prueba',
      async enviar(datos) {
        enviados.push(datos);
        return { mensajeId: `prueba-${enviados.length}` };
      }
    },
    servicioInformes: {
      obtenerContabilidad({ fechaInicio, fechaFin, zonaHoraria }) {
        return {
          fechaInicio,
          fechaFin,
          zonaHoraria,
          resumen: {
            cantidadVehiculos: 1,
            ingresosTotales: 1200,
            promedioPorVehiculo: 1200,
            minutosTotales: 30
          },
          registros: []
        };
      },
      crearCsvContabilidad() {
        return { contenido: 'Folio\n', registrosIncluidos: 0, registrosOmitidos: 0 };
      },
      crearPdfResumenContable() {
        return Promise.resolve(Buffer.from('pdf-prueba'));
      },
      crearHtmlResumenContable() {
        return '<html><body>Informe</body></html>';
      },
      crearTextoResumenContable() {
        return 'Informe';
      }
    },
    obtenerCapacidadesPlan(plan) {
      return { reportesPorCorreo: plan === 'PRO' };
    },
    partesFechaZona(fecha) {
      return {
        year: fecha.getUTCFullYear(),
        month: fecha.getUTCMonth() + 1,
        day: fecha.getUTCDate(),
        hour: fecha.getUTCHours(),
        minute: fecha.getUTCMinutes()
      };
    },
    resolverZonaHoraria(zona) {
      return zona;
    },
    ahora: () => fechaActual
  });

  const programacion = cola.guardarProgramacion({
    estacionamientoId: 1,
    usuarioId: 10,
    correoDestino: 'admin.norte@prueba.cl',
    frecuencia: 'diario',
    horaLocal: '08:30',
    activo: true
  });
  assert.ok(programacion.id > 0);
  assert.equal(cola.listarProgramaciones(1).length, 1);
  assert.equal(cola.listarProgramaciones(2).length, 0);

  assert.equal(cola.programarInformesVencidos(), 1);
  assert.equal(cola.programarInformesVencidos(), 0);
  assert.equal(cola.listarEnvios(1).length, 1);
  assert.equal(cola.listarEnvios(2).length, 0);

  const procesado = await cola.procesarDisponibles({
    limite: 1,
    incluirProgramacion: false
  });
  assert.equal(procesado.procesados, 1);
  assert.equal(enviados.length, 1);
  assert.equal(enviados[0].para, 'admin.norte@prueba.cl');
  assert.equal(enviados[0].claveIdempotencia, 'informe-correo/1');
  assert.equal(cola.listarEnvios(1)[0].estado, 'enviado');
  assert.equal(cola.listarEnvios(1)[0].proveedorMensajeId, 'registrado');

  db.prepare(`UPDATE estacionamientos SET plan = 'LITE' WHERE id = 1`).run();
  const manualBloqueado = cola.encolarEnvioManual({
    estacionamientoId: 1,
    usuarioId: 10,
    correoDestino: 'admin.norte@prueba.cl',
    claveIdempotencia: 'manual-prueba-0001'
  });
  assert.equal(manualBloqueado.noDisponible, true);

  fechaActual = new Date('2026-08-20T12:01:00.000Z');
  assert.equal(cola.programarInformesVencidos(), 0);

  db.prepare(`UPDATE estacionamientos SET plan = 'PRO' WHERE id = 1`).run();

  // Un reinicio después del lunes recupera el último período semanal cerrado
  // en vez de perderlo por no ocurrir exactamente el lunes.
  const semanal = cola.guardarProgramacion({
    estacionamientoId: 1,
    usuarioId: 10,
    correoDestino: 'admin.norte@prueba.cl',
    frecuencia: 'semanal',
    horaLocal: '08:30',
    activo: true
  });
  assert.ok(semanal.id > 0);

  fechaActual = new Date('2026-09-08T12:00:00.000Z'); // martes
  assert.equal(cola.programarInformesVencidos(), 2);
  const envioSemanal = cola.listarEnvios(1).find(
    envio => envio.frecuencia === 'semanal'
  );
  assert.ok(envioSemanal);
  assert.equal(envioSemanal.periodoInicio, '2026-08-31');
  assert.equal(envioSemanal.periodoFin, '2026-09-06');

  // El mismo criterio evita perder el informe mensual tras una caída el día
  // uno: el día dos se encola el mes que ya terminó.
  const mensual = cola.guardarProgramacion({
    estacionamientoId: 1,
    usuarioId: 10,
    correoDestino: 'admin.norte@prueba.cl',
    frecuencia: 'mensual',
    horaLocal: '08:30',
    activo: true
  });
  assert.ok(mensual.id > 0);

  fechaActual = new Date('2026-10-02T12:00:00.000Z');
  assert.equal(cola.programarInformesVencidos(), 3);
  const envioMensual = cola.listarEnvios(1).find(
    envio => envio.frecuencia === 'mensual'
  );
  assert.ok(envioMensual);
  assert.equal(envioMensual.periodoInicio, '2026-09-01');
  assert.equal(envioMensual.periodoFin, '2026-09-30');

  // Los ticks repetidos no duplican envíos gracias a la clave de período.
  assert.equal(cola.programarInformesVencidos(), 0);

  db.close();
  console.log('Cola de informes por correo verificada con SQLite en memoria.');
}

ejecutar().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
