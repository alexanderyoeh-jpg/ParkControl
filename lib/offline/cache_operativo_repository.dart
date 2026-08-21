import 'package:drift/drift.dart';

import 'parkcontrol_local_database.dart';

class MovimientoServidorSnapshot {
  const MovimientoServidorSnapshot({
    required this.id,
    required this.patente,
    required this.tipo,
    required this.color,
    required this.observacion,
    required this.horaEntrada,
    required this.version,
  });

  final int id;
  final String patente;
  final String tipo;
  final String color;
  final String observacion;
  final DateTime horaEntrada;
  final int version;
}

class CacheOperativoRepository {
  CacheOperativoRepository(this._db);

  final ParkControlLocalDatabase _db;

  Future<void> reconciliarEstadoServidor({
    required int estacionamientoId,
    required int? tarifaServidorId,
    required double tarifaPorMinuto,
    required Iterable<MovimientoServidorSnapshot> movimientos,
    DateTime? servidorFecha,
    DateTime? ahora,
  }) async {
    if (estacionamientoId < 1) {
      throw ArgumentError.value(estacionamientoId, 'estacionamientoId');
    }
    if (tarifaServidorId != null && tarifaServidorId < 1) {
      throw ArgumentError.value(tarifaServidorId, 'tarifaServidorId');
    }
    if (!tarifaPorMinuto.isFinite || tarifaPorMinuto < 0) {
      throw ArgumentError.value(tarifaPorMinuto, 'tarifaPorMinuto');
    }

    final instante = (ahora ?? DateTime.now()).toUtc();
    final fechaServidor = servidorFecha?.toUtc();
    final snapshot = movimientos.toList(growable: false);
    final idsServidor = <int>{};

    for (final movimiento in snapshot) {
      if (movimiento.id < 1 || movimiento.version < 1) {
        throw ArgumentError('El movimiento del servidor no es válido');
      }
      if (!idsServidor.add(movimiento.id)) {
        throw ArgumentError('El snapshot contiene movimientos duplicados');
      }
    }

    await _db.transaction(() async {
      await _db
          .into(_db.tarifasLocales)
          .insertOnConflictUpdate(
            TarifasLocalesCompanion(
              estacionamientoId: Value(estacionamientoId),
              tarifaServidorId: Value(tarifaServidorId),
              tarifaPorMinuto: Value(tarifaPorMinuto),
              servidorFecha: Value(fechaServidor),
              sincronizadaEn: Value(instante),
            ),
          );

      for (final movimiento in snapshot) {
        final existente =
            await (_db.select(_db.movimientosLocales)..where(
                  (tabla) =>
                      tabla.estacionamientoId.equals(estacionamientoId) &
                      tabla.servidorId.equals(movimiento.id),
                ))
                .getSingleOrNull();

        // Una operación offline puede haber cambiado localmente el vehículo
        // después del último snapshot (por ejemplo, una salida pendiente).
        // El servidor todavía mostrará su estado anterior hasta confirmar esa
        // cola, por lo que no se debe pisar la proyección local ni revivirlo
        // como "dentro". Sólo se promueve a confirmado si ya representa el
        // mismo movimiento que entregó el servidor.
        if (existente != null &&
            existente.estadoSincronizacion != 'confirmado' &&
            !_representaSnapshotServidor(existente, movimiento)) {
          continue;
        }

        final companion = MovimientosLocalesCompanion(
          claveLocal: existente == null
              ? Value('servidor:$estacionamientoId:${movimiento.id}')
              : const Value.absent(),
          estacionamientoId: existente == null
              ? Value(estacionamientoId)
              : const Value.absent(),
          servidorId: Value(movimiento.id),
          patente: Value(movimiento.patente.trim().toUpperCase()),
          tipo: Value(movimiento.tipo.trim()),
          color: Value(movimiento.color.trim()),
          observacion: Value(movimiento.observacion.trim()),
          horaEntrada: Value(movimiento.horaEntrada.toUtc()),
          versionServidor: Value(movimiento.version),
          estado: const Value('dentro'),
          estadoSincronizacion: const Value('confirmado'),
          creadaEn: existente == null ? Value(instante) : const Value.absent(),
          actualizadaEn: Value(instante),
        );

        if (existente == null) {
          await _db.into(_db.movimientosLocales).insert(companion);
        } else {
          await (_db.update(_db.movimientosLocales)..where(
                (tabla) => tabla.claveLocal.equals(existente.claveLocal),
              ))
              .write(companion);
        }
      }

      final confirmados =
          await (_db.select(_db.movimientosLocales)..where(
                (tabla) =>
                    tabla.estacionamientoId.equals(estacionamientoId) &
                    tabla.estadoSincronizacion.equals('confirmado') &
                    tabla.servidorId.isNotNull(),
              ))
              .get();

      for (final local in confirmados) {
        if (!idsServidor.contains(local.servidorId)) {
          await (_db.delete(
            _db.movimientosLocales,
          )..where((tabla) => tabla.claveLocal.equals(local.claveLocal))).go();
        }
      }
    });
  }

  /// Vincula la proyección creada por una entrada offline con el movimiento
  /// que el backend acaba de confirmar. La clave de idempotencia es estable,
  /// por lo que evita que el siguiente snapshot cree una segunda fila local
  /// para la misma patente.
  ///
  /// Esto sólo modifica la caché local; nunca elimina ni altera movimientos
  /// reales del backend.
  Future<void> vincularEntradaConfirmada({
    required int estacionamientoId,
    required String claveOperacion,
    required int servidorId,
    required int versionServidor,
    DateTime? ahora,
  }) async {
    final clave = claveOperacion.trim();

    if (estacionamientoId < 1 ||
        clave.isEmpty ||
        servidorId < 1 ||
        versionServidor < 1) {
      throw ArgumentError('La confirmación de entrada local no es válida');
    }

    final instante = (ahora ?? DateTime.now()).toUtc();
    final claveLocal = 'offline:$clave';

    await _db.transaction(() async {
      final local =
          await (_db.select(_db.movimientosLocales)..where(
                (tabla) =>
                    tabla.estacionamientoId.equals(estacionamientoId) &
                    tabla.claveLocal.equals(claveLocal),
              ))
              .getSingleOrNull();

      if (local == null) {
        // La caché puede haberse limpiado localmente; el próximo snapshot
        // autenticado volverá a materializar el movimiento del servidor.
        return;
      }

      // Un snapshot concurrente pudo haber creado una proyección temporal
      // con este servidorId. Se conserva la fila offline, que contiene la
      // superposición pendiente (salida, modificación o eliminación), y se
      // retira sólo la fila duplicada de caché.
      final duplicados =
          await (_db.select(_db.movimientosLocales)..where(
                (tabla) =>
                    tabla.estacionamientoId.equals(estacionamientoId) &
                    tabla.servidorId.equals(servidorId) &
                    tabla.claveLocal.equals(claveLocal).not(),
              ))
              .get();

      for (final duplicado in duplicados) {
        await (_db.delete(_db.movimientosLocales)
              ..where((tabla) => tabla.claveLocal.equals(duplicado.claveLocal)))
            .go();
      }

      await (_db.update(
        _db.movimientosLocales,
      )..where((tabla) => tabla.claveLocal.equals(claveLocal))).write(
        MovimientosLocalesCompanion(
          servidorId: Value(servidorId),
          versionServidor: Value(versionServidor),
          actualizadaEn: Value(instante),
        ),
      );
    });
  }

  Future<TarifasLocale?> obtenerTarifa(int estacionamientoId) {
    return (_db.select(_db.tarifasLocales)
          ..where((tabla) => tabla.estacionamientoId.equals(estacionamientoId)))
        .getSingleOrNull();
  }

  Future<List<MovimientosLocale>> listarDentro(int estacionamientoId) {
    final consulta = _db.select(_db.movimientosLocales)
      ..where(
        (tabla) =>
            tabla.estacionamientoId.equals(estacionamientoId) &
            tabla.estado.equals('dentro'),
      )
      ..orderBy([(tabla) => OrderingTerm.desc(tabla.horaEntrada)]);
    return consulta.get();
  }

  Future<MovimientosLocale?> buscarPatenteDentro(
    int estacionamientoId,
    String patente,
  ) {
    return (_db.select(_db.movimientosLocales)..where(
          (tabla) =>
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.patente.equals(patente.trim().toUpperCase()) &
              tabla.estado.equals('dentro'),
        ))
        .getSingleOrNull();
  }

  static bool _representaSnapshotServidor(
    MovimientosLocale local,
    MovimientoServidorSnapshot servidor,
  ) {
    return local.estado == 'dentro' &&
        local.patente.trim().toUpperCase() ==
            servidor.patente.trim().toUpperCase() &&
        local.tipo.trim() == servidor.tipo.trim() &&
        local.color.trim() == servidor.color.trim() &&
        local.observacion.trim() == servidor.observacion.trim() &&
        local.horaEntrada.toUtc().isAtSameMomentAs(
          servidor.horaEntrada.toUtc(),
        );
  }
}
