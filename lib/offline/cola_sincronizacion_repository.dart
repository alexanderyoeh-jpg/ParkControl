import 'package:drift/drift.dart';

import 'parkcontrol_local_database.dart';

class ConflictoClaveOffline implements Exception {
  const ConflictoClaveOffline(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

class ColaSincronizacionRepository {
  ColaSincronizacionRepository(this._db);

  static const estadosTerminales = {'completada', 'conflicto', 'bloqueada'};
  static const tiposPermitidos = {
    'entrada',
    'salida',
    'modificacion',
    'eliminacion',
  };
  static const metodosPermitidos = {'POST', 'PUT', 'DELETE'};

  final ParkControlLocalDatabase _db;

  Future<void> encolar({
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String tipo,
    required String metodo,
    required String ruta,
    String? cuerpoJson,
    DateTime? ahora,
  }) async {
    final claveLimpia = clave.trim();
    final tipoLimpio = tipo.trim().toLowerCase();
    final metodoLimpio = metodo.trim().toUpperCase();
    final rutaLimpia = ruta.trim();
    final instante = (ahora ?? DateTime.now()).toUtc();

    if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(claveLimpia)) {
      throw ArgumentError.value(clave, 'clave', 'Clave offline inválida');
    }
    if (estacionamientoId < 1 || usuarioId < 1) {
      throw ArgumentError('Estacionamiento y usuario son obligatorios');
    }
    if (!tiposPermitidos.contains(tipoLimpio)) {
      throw ArgumentError.value(tipo, 'tipo', 'Operación offline no admitida');
    }
    if (!metodosPermitidos.contains(metodoLimpio)) {
      throw ArgumentError.value(metodo, 'metodo', 'Método offline no admitido');
    }
    if (!rutaLimpia.startsWith('/api/')) {
      throw ArgumentError.value(ruta, 'ruta', 'La ruta debe ser relativa');
    }

    await _db.transaction(() async {
      final existente = await (_db.select(
        _db.operacionesPendientes,
      )..where((tabla) => tabla.clave.equals(claveLimpia))).getSingleOrNull();

      if (existente != null) {
        final coincide =
            existente.estacionamientoId == estacionamientoId &&
            existente.usuarioId == usuarioId &&
            existente.tipo == tipoLimpio &&
            existente.metodo == metodoLimpio &&
            existente.ruta == rutaLimpia &&
            existente.cuerpoJson == cuerpoJson;

        if (!coincide) {
          throw const ConflictoClaveOffline(
            'La clave offline ya existe con una operación diferente',
          );
        }

        return;
      }

      await _db
          .into(_db.operacionesPendientes)
          .insert(
            OperacionesPendientesCompanion.insert(
              clave: claveLimpia,
              estacionamientoId: estacionamientoId,
              usuarioId: usuarioId,
              tipo: tipoLimpio,
              metodo: metodoLimpio,
              ruta: rutaLimpia,
              cuerpoJson: Value(cuerpoJson),
              creadaEn: instante,
              actualizadaEn: instante,
            ),
          );
    });
  }

  Future<OperacionesPendiente?> siguiente({
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) async {
    final instante = (ahora ?? DateTime.now()).toUtc();
    final consulta = _db.select(_db.operacionesPendientes)
      ..where(
        (tabla) =>
            tabla.estacionamientoId.equals(estacionamientoId) &
            tabla.usuarioId.equals(usuarioId) &
            tabla.estado.equals('completada').not(),
      )
      ..orderBy([(tabla) => OrderingTerm.asc(tabla.id)])
      ..limit(1);

    final primera = await consulta.getSingleOrNull();

    if (primera == null || primera.estado != 'pendiente') {
      return null;
    }

    if (primera.proximoIntentoEn?.isAfter(instante) ?? false) {
      return null;
    }

    return primera;
  }

  /// Reserva de forma atómica la primera operación disponible del cliente.
  /// Dos coordinadores concurrentes no pueden incrementar ni enviar la misma
  /// fila desde una misma base local.
  Future<OperacionesPendiente?> reservarSiguiente({
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) async {
    final instante = (ahora ?? DateTime.now()).toUtc();

    return _db.transaction(() async {
      final tabla = _db.operacionesPendientes;
      final consulta = _db.select(tabla)
        ..where(
          (fila) =>
              fila.estacionamientoId.equals(estacionamientoId) &
              fila.usuarioId.equals(usuarioId) &
              fila.estado.equals('completada').not(),
        )
        ..orderBy([(fila) => OrderingTerm.asc(fila.id)])
        ..limit(1);
      final primera = await consulta.getSingleOrNull();

      if (primera == null || primera.estado != 'pendiente') {
        return null;
      }
      if (primera.proximoIntentoEn?.isAfter(instante) ?? false) {
        return null;
      }

      final actualizadas =
          await (_db.update(tabla)..where(
                (fila) =>
                    fila.id.equals(primera.id) &
                    fila.estacionamientoId.equals(estacionamientoId) &
                    fila.usuarioId.equals(usuarioId) &
                    fila.estado.equals('pendiente'),
              ))
              .write(
                OperacionesPendientesCompanion.custom(
                  estado: const Constant('enviando'),
                  intentos: tabla.intentos + const Constant(1),
                  ultimoError: const Constant(null),
                  proximoIntentoEn: const Constant(null),
                  actualizadaEn: Variable(instante),
                ),
              );

      if (actualizadas != 1) {
        return null;
      }

      return (_db.select(
        tabla,
      )..where((fila) => fila.id.equals(primera.id))).getSingle();
    });
  }

  Future<void> marcarEnviando(
    String clave, {
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) async {
    final instante = (ahora ?? DateTime.now()).toUtc();
    final tabla = _db.operacionesPendientes;

    await (_db.update(tabla)..where(
          (fila) =>
              fila.clave.equals(clave) &
              fila.estacionamientoId.equals(estacionamientoId) &
              fila.usuarioId.equals(usuarioId),
        ))
        .write(
          OperacionesPendientesCompanion.custom(
            estado: const Constant('enviando'),
            intentos: tabla.intentos + const Constant(1),
            ultimoError: const Constant(null),
            actualizadaEn: Variable(instante),
          ),
        );
  }

  Future<void> registrarFallo(
    String clave,
    String error, {
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) async {
    final instante = (ahora ?? DateTime.now()).toUtc();
    final operacion =
        await (_db.select(_db.operacionesPendientes)..where(
              (tabla) =>
                  tabla.clave.equals(clave) &
                  tabla.estacionamientoId.equals(estacionamientoId) &
                  tabla.usuarioId.equals(usuarioId),
            ))
            .getSingle();
    final exponente = (operacion.intentos - 1).clamp(0, 6);
    final espera = Duration(seconds: 5 * (1 << exponente));

    await (_db.update(_db.operacionesPendientes)..where(
          (tabla) =>
              tabla.clave.equals(clave) &
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.usuarioId.equals(usuarioId),
        ))
        .write(
          OperacionesPendientesCompanion(
            estado: const Value('pendiente'),
            ultimoError: Value(error.trim()),
            proximoIntentoEn: Value(instante.add(espera)),
            actualizadaEn: Value(instante),
          ),
        );
  }

  Future<void> marcarConflicto(
    String clave,
    String motivo, {
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) {
    return _marcarTerminal(
      clave,
      estacionamientoId: estacionamientoId,
      usuarioId: usuarioId,
      estado: 'conflicto',
      detalle: motivo,
      ahora: ahora,
    );
  }

  Future<void> marcarBloqueada(
    String clave,
    String motivo, {
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) {
    return _marcarTerminal(
      clave,
      estacionamientoId: estacionamientoId,
      usuarioId: usuarioId,
      estado: 'bloqueada',
      detalle: motivo,
      ahora: ahora,
    );
  }

  Future<void> marcarCompletada(
    String clave, {
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) {
    return _marcarTerminal(
      clave,
      estacionamientoId: estacionamientoId,
      usuarioId: usuarioId,
      estado: 'completada',
      detalle: null,
      ahora: ahora,
    );
  }

  Future<int> descartarConflicto({
    required int estacionamientoId,
    required int usuarioId,
    required String clave,
    required String motivo,
    DateTime? ahora,
  }) {
    final instante = (ahora ?? DateTime.now()).toUtc();
    return (_db.update(_db.operacionesPendientes)..where(
          (tabla) =>
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.usuarioId.equals(usuarioId) &
              tabla.clave.equals(clave.trim()) &
              tabla.estado.equals('conflicto'),
        ))
        .write(
          OperacionesPendientesCompanion(
            estado: const Value('completada'),
            ultimoError: Value('Conflicto descartado localmente: $motivo'),
            proximoIntentoEn: const Value(null),
            actualizadaEn: Value(instante),
          ),
        );
  }

  Future<void> _marcarTerminal(
    String clave, {
    required int estacionamientoId,
    required int usuarioId,
    required String estado,
    required String? detalle,
    DateTime? ahora,
  }) async {
    if (!estadosTerminales.contains(estado)) {
      throw ArgumentError.value(estado, 'estado');
    }

    final instante = (ahora ?? DateTime.now()).toUtc();
    await (_db.update(_db.operacionesPendientes)..where(
          (tabla) =>
              tabla.clave.equals(clave) &
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.usuarioId.equals(usuarioId),
        ))
        .write(
          OperacionesPendientesCompanion(
            estado: Value(estado),
            ultimoError: Value(detalle?.trim()),
            proximoIntentoEn: const Value(null),
            actualizadaEn: Value(instante),
          ),
        );
  }

  Future<int> restablecerEnviosInterrumpidos({
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) {
    final instante = (ahora ?? DateTime.now()).toUtc();
    return (_db.update(_db.operacionesPendientes)..where(
          (tabla) =>
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.usuarioId.equals(usuarioId) &
              tabla.estado.equals('enviando'),
        ))
        .write(
          OperacionesPendientesCompanion(
            estado: const Value('pendiente'),
            ultimoError: const Value('Envío interrumpido antes de confirmarse'),
            proximoIntentoEn: Value(instante),
            actualizadaEn: Value(instante),
          ),
        );
  }

  Future<int> reanudarBloqueadas({
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) {
    final instante = (ahora ?? DateTime.now()).toUtc();
    return (_db.update(_db.operacionesPendientes)..where(
          (tabla) =>
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.usuarioId.equals(usuarioId) &
              tabla.estado.equals('bloqueada'),
        ))
        .write(
          OperacionesPendientesCompanion(
            estado: const Value('pendiente'),
            ultimoError: const Value(null),
            proximoIntentoEn: Value(instante),
            actualizadaEn: Value(instante),
          ),
        );
  }

  Future<int> reintentarPendientesAhora({
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) {
    final instante = (ahora ?? DateTime.now()).toUtc();
    return (_db.update(_db.operacionesPendientes)..where(
          (tabla) =>
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.usuarioId.equals(usuarioId) &
              tabla.estado.equals('pendiente'),
        ))
        .write(
          OperacionesPendientesCompanion(
            proximoIntentoEn: Value(instante),
            actualizadaEn: Value(instante),
          ),
        );
  }

  Future<List<OperacionesPendiente>> listar({int? estacionamientoId}) {
    final consulta = _db.select(_db.operacionesPendientes);

    if (estacionamientoId != null) {
      consulta.where(
        (tabla) => tabla.estacionamientoId.equals(estacionamientoId),
      );
    }

    consulta.orderBy([(tabla) => OrderingTerm.asc(tabla.id)]);
    return consulta.get();
  }

  Future<List<OperacionesPendiente>> listarActivas({
    required int estacionamientoId,
    required int usuarioId,
  }) {
    final consulta = _consultaActivas(estacionamientoId, usuarioId);
    return consulta.get();
  }

  Stream<List<OperacionesPendiente>> observarActivas({
    required int estacionamientoId,
    required int usuarioId,
  }) {
    final consulta = _consultaActivas(estacionamientoId, usuarioId);
    return consulta.watch();
  }

  SimpleSelectStatement<$OperacionesPendientesTable, OperacionesPendiente>
  _consultaActivas(int estacionamientoId, int usuarioId) {
    final consulta = _db.select(_db.operacionesPendientes)
      ..where(
        (tabla) =>
            tabla.estacionamientoId.equals(estacionamientoId) &
            tabla.usuarioId.equals(usuarioId) &
            tabla.estado.equals('completada').not(),
      )
      ..orderBy([(tabla) => OrderingTerm.asc(tabla.id)]);

    return consulta;
  }
}
