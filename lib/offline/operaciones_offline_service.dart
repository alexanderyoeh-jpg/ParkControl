import 'dart:convert';

import 'package:drift/drift.dart';

import 'cola_sincronizacion_repository.dart';
import 'parkcontrol_local_database.dart';

class ErrorOperacionOffline implements Exception {
  const ErrorOperacionOffline(this.codigo, this.mensaje);

  final String codigo;
  final String mensaje;

  @override
  String toString() => mensaje;
}

class OperacionesOfflineService {
  OperacionesOfflineService(this._db);

  final ParkControlLocalDatabase _db;

  Future<MovimientosLocale> registrarEntrada({
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String patente,
    required String tipo,
    required String color,
    String observacion = '',
    DateTime? horaEntrada,
    DateTime? ahora,
  }) {
    final datos = _normalizarVehiculo(
      patente: patente,
      tipo: tipo,
      color: color,
      observacion: observacion,
    );
    final instante = (ahora ?? DateTime.now()).toUtc();
    final hora = (horaEntrada ?? instante).toUtc();
    final claveLimpia = _validarClave(clave);
    _validarIdentidad(estacionamientoId, usuarioId);

    final cuerpo = jsonEncode({
      'patente': datos.patente,
      'tipo': datos.tipo,
      'color': datos.color,
      'observacion': datos.observacion,
      'horaEntradaCliente': hora.toIso8601String(),
      'origenOperacion': 'offline_v1',
    });
    final claveLocal = 'offline:$claveLimpia';

    return _db.transaction(() async {
      final repetida = await _operacionYaExiste(
        clave: claveLimpia,
        estacionamientoId: estacionamientoId,
        usuarioId: usuarioId,
        tipo: 'entrada',
        metodo: 'POST',
        ruta: '/api/entradas',
        cuerpoJson: cuerpo,
      );

      if (repetida) {
        final existente =
            await (_db.select(_db.movimientosLocales)
                  ..where((tabla) => tabla.claveLocal.equals(claveLocal)))
                .getSingleOrNull();
        if (existente != null) {
          return existente;
        }
      }

      await _rechazarPatenteActiva(
        estacionamientoId,
        datos.patente,
        ignorarClaveLocal: claveLocal,
      );

      await _insertarOperacionPendiente(
        clave: claveLimpia,
        estacionamientoId: estacionamientoId,
        usuarioId: usuarioId,
        tipo: 'entrada',
        metodo: 'POST',
        ruta: '/api/entradas',
        cuerpoJson: cuerpo,
        instante: instante,
      );

      await _db
          .into(_db.movimientosLocales)
          .insert(
            MovimientosLocalesCompanion.insert(
              claveLocal: claveLocal,
              estacionamientoId: estacionamientoId,
              patente: datos.patente,
              tipo: datos.tipo,
              color: datos.color,
              observacion: Value(datos.observacion),
              horaEntrada: hora,
              estadoSincronizacion: const Value('pendiente'),
              creadaEn: instante,
              actualizadaEn: instante,
            ),
          );

      return (_db.select(
        _db.movimientosLocales,
      )..where((tabla) => tabla.claveLocal.equals(claveLocal))).getSingle();
    });
  }

  Future<MovimientosLocale> modificarVehiculo({
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String patenteActual,
    required String patenteNueva,
    required String tipo,
    required String color,
    String observacion = '',
    DateTime? ahora,
  }) async {
    final actual = _normalizarPatente(patenteActual);
    final datos = _normalizarVehiculo(
      patente: patenteNueva,
      tipo: tipo,
      color: color,
      observacion: observacion,
    );
    final instante = (ahora ?? DateTime.now()).toUtc();
    final claveLimpia = _validarClave(clave);
    _validarIdentidad(estacionamientoId, usuarioId);

    if (actual.isEmpty) {
      throw const ErrorOperacionOffline(
        'PATENTE_INVALIDA',
        'La patente actual es obligatoria',
      );
    }

    return _db.transaction(() async {
      final movimiento = await _buscarDentro(estacionamientoId, actual);
      if (movimiento == null) {
        throw const ErrorOperacionOffline(
          'VEHICULO_NO_ENCONTRADO',
          'No se encontró el vehículo dentro de la caché local',
        );
      }

      if (datos.patente != actual) {
        await _rechazarPatenteActiva(
          estacionamientoId,
          datos.patente,
          ignorarClaveLocal: movimiento.claveLocal,
        );
      }

      final cuerpo = <String, Object?>{
        'patente': datos.patente,
        'tipo': datos.tipo,
        'color': datos.color,
        'observacion': datos.observacion,
      };

      if (movimiento.versionServidor != null) {
        cuerpo['versionEsperada'] = movimiento.versionServidor;
      }

      await _insertarOperacionPendiente(
        clave: claveLimpia,
        estacionamientoId: estacionamientoId,
        usuarioId: usuarioId,
        tipo: 'modificacion',
        metodo: 'PUT',
        ruta: '/api/modificar/${Uri.encodeComponent(actual)}',
        cuerpoJson: jsonEncode(cuerpo),
        instante: instante,
      );

      await (_db.update(_db.movimientosLocales)
            ..where((tabla) => tabla.claveLocal.equals(movimiento.claveLocal)))
          .write(
            MovimientosLocalesCompanion(
              patente: Value(datos.patente),
              tipo: Value(datos.tipo),
              color: Value(datos.color),
              observacion: Value(datos.observacion),
              estadoSincronizacion: const Value('pendiente'),
              actualizadaEn: Value(instante),
            ),
          );

      return (_db.select(_db.movimientosLocales)
            ..where((tabla) => tabla.claveLocal.equals(movimiento.claveLocal)))
          .getSingle();
    });
  }

  Future<void> registrarSalida({
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String patente,
    DateTime? horaSalida,
    DateTime? ahora,
    String metodoPago = 'efectivo',
  }) async {
    final patenteLimpia = _normalizarPatente(patente);
    final instante = (ahora ?? DateTime.now()).toUtc();
    final hora = (horaSalida ?? instante).toUtc();
    final claveLimpia = _validarClave(clave);
    _validarIdentidad(estacionamientoId, usuarioId);

    if (patenteLimpia.isEmpty) {
      throw const ErrorOperacionOffline(
        'PATENTE_INVALIDA',
        'La patente es obligatoria',
      );
    }

    await _db.transaction(() async {
      final movimiento = await _buscarDentro(estacionamientoId, patenteLimpia);
      if (movimiento == null) {
        throw const ErrorOperacionOffline(
          'VEHICULO_NO_ENCONTRADO',
          'No se encontró el vehículo dentro de la caché local',
        );
      }

      if (hora.isBefore(movimiento.horaEntrada.toUtc())) {
        throw const ErrorOperacionOffline(
          'HORA_OPERACION_INCONSISTENTE',
          'La salida no puede ser anterior a la entrada',
        );
      }

      final tarifa =
          await (_db.select(_db.tarifasLocales)..where(
                (tabla) => tabla.estacionamientoId.equals(estacionamientoId),
              ))
              .getSingleOrNull();

      if (tarifa == null) {
        throw const ErrorOperacionOffline(
          'TARIFA_NO_SINCRONIZADA',
          'No hay tarifa local sincronizada para registrar la salida',
        );
      }

      final cuerpo = <String, Object?>{
        'patente': patenteLimpia,
        'horaSalidaCliente': hora.toIso8601String(),
        'metodoPago': metodoPago,
        'origenOperacion': 'offline_v1',
      };

      if (movimiento.servidorId != null) {
        cuerpo['movimientoId'] = movimiento.servidorId;
      }
      if (movimiento.versionServidor != null) {
        cuerpo['versionEsperada'] = movimiento.versionServidor;
      }
      if (tarifa.tarifaServidorId != null) {
        cuerpo['tarifaIdEsperada'] = tarifa.tarifaServidorId;
      }

      await _insertarOperacionPendiente(
        clave: claveLimpia,
        estacionamientoId: estacionamientoId,
        usuarioId: usuarioId,
        tipo: 'salida',
        metodo: 'POST',
        ruta: '/api/salidas',
        cuerpoJson: jsonEncode(cuerpo),
        instante: instante,
      );

      await (_db.update(_db.movimientosLocales)
            ..where((tabla) => tabla.claveLocal.equals(movimiento.claveLocal)))
          .write(
            MovimientosLocalesCompanion(
              estado: const Value('salio'),
              estadoSincronizacion: const Value('pendiente'),
              actualizadaEn: Value(instante),
            ),
          );
    });
  }

  Future<void> eliminarVehiculo({
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String patente,
    DateTime? ahora,
  }) async {
    final patenteLimpia = _normalizarPatente(patente);
    final instante = (ahora ?? DateTime.now()).toUtc();
    final claveLimpia = _validarClave(clave);
    _validarIdentidad(estacionamientoId, usuarioId);

    if (patenteLimpia.isEmpty) {
      throw const ErrorOperacionOffline(
        'PATENTE_INVALIDA',
        'La patente es obligatoria',
      );
    }

    await _db.transaction(() async {
      final movimiento = await _buscarDentro(estacionamientoId, patenteLimpia);
      if (movimiento == null) {
        throw const ErrorOperacionOffline(
          'VEHICULO_NO_ENCONTRADO',
          'No se encontró el vehículo dentro de la caché local',
        );
      }

      final cuerpo = <String, Object?>{};
      if (movimiento.versionServidor != null) {
        cuerpo['versionEsperada'] = movimiento.versionServidor;
      }

      await _insertarOperacionPendiente(
        clave: claveLimpia,
        estacionamientoId: estacionamientoId,
        usuarioId: usuarioId,
        tipo: 'eliminacion',
        metodo: 'DELETE',
        ruta: '/api/modificar/${Uri.encodeComponent(patenteLimpia)}',
        cuerpoJson: jsonEncode(cuerpo),
        instante: instante,
      );

      await (_db.update(_db.movimientosLocales)
            ..where((tabla) => tabla.claveLocal.equals(movimiento.claveLocal)))
          .write(
            MovimientosLocalesCompanion(
              estado: const Value('eliminado'),
              estadoSincronizacion: const Value('pendiente'),
              actualizadaEn: Value(instante),
            ),
          );
    });
  }

  Future<bool> _operacionYaExiste({
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String tipo,
    required String metodo,
    required String ruta,
    required String cuerpoJson,
  }) async {
    final existente = await (_db.select(
      _db.operacionesPendientes,
    )..where((tabla) => tabla.clave.equals(clave))).getSingleOrNull();

    if (existente == null) {
      return false;
    }

    final coincide =
        existente.estacionamientoId == estacionamientoId &&
        existente.usuarioId == usuarioId &&
        existente.tipo == tipo &&
        existente.metodo == metodo &&
        existente.ruta == ruta &&
        existente.cuerpoJson == cuerpoJson;

    if (!coincide) {
      throw const ConflictoClaveOffline(
        'La clave offline ya existe con una operación diferente',
      );
    }

    return true;
  }

  Future<void> _insertarOperacionPendiente({
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String tipo,
    required String metodo,
    required String ruta,
    required String cuerpoJson,
    required DateTime instante,
  }) async {
    if (await _operacionYaExiste(
      clave: clave,
      estacionamientoId: estacionamientoId,
      usuarioId: usuarioId,
      tipo: tipo,
      metodo: metodo,
      ruta: ruta,
      cuerpoJson: cuerpoJson,
    )) {
      return;
    }

    await _db
        .into(_db.operacionesPendientes)
        .insert(
          OperacionesPendientesCompanion.insert(
            clave: clave,
            estacionamientoId: estacionamientoId,
            usuarioId: usuarioId,
            tipo: tipo,
            metodo: metodo,
            ruta: ruta,
            cuerpoJson: Value(cuerpoJson),
            creadaEn: instante,
            actualizadaEn: instante,
          ),
        );
  }

  Future<MovimientosLocale?> _buscarDentro(
    int estacionamientoId,
    String patente,
  ) {
    return (_db.select(_db.movimientosLocales)..where(
          (tabla) =>
              tabla.estacionamientoId.equals(estacionamientoId) &
              tabla.patente.equals(patente) &
              tabla.estado.equals('dentro'),
        ))
        .getSingleOrNull();
  }

  Future<void> _rechazarPatenteActiva(
    int estacionamientoId,
    String patente, {
    required String ignorarClaveLocal,
  }) async {
    final existente = await _buscarDentro(estacionamientoId, patente);
    if (existente != null && existente.claveLocal != ignorarClaveLocal) {
      throw const ErrorOperacionOffline(
        'PATENTE_YA_DENTRO',
        'Esta patente ya se encuentra dentro del estacionamiento',
      );
    }
  }

  static String _validarClave(String clave) {
    final limpia = clave.trim();
    if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(limpia)) {
      throw ArgumentError.value(clave, 'clave', 'Clave offline inválida');
    }
    return limpia;
  }

  static void _validarIdentidad(int estacionamientoId, int usuarioId) {
    if (estacionamientoId < 1 || usuarioId < 1) {
      throw ArgumentError('Estacionamiento y usuario son obligatorios');
    }
  }

  static _DatosVehiculo _normalizarVehiculo({
    required String patente,
    required String tipo,
    required String color,
    required String observacion,
  }) {
    final patenteLimpia = _normalizarPatente(patente);
    final tipoLimpio = tipo.trim();
    final colorLimpio = color.trim();

    if (patenteLimpia.isEmpty || tipoLimpio.isEmpty || colorLimpio.isEmpty) {
      throw const ErrorOperacionOffline(
        'DATOS_VEHICULO_INVALIDOS',
        'Patente, tipo y color son obligatorios',
      );
    }

    return _DatosVehiculo(
      patente: patenteLimpia,
      tipo: tipoLimpio,
      color: colorLimpio,
      observacion: observacion.trim(),
    );
  }

  static String _normalizarPatente(String patente) {
    return patente.trim().toUpperCase();
  }
}

class _DatosVehiculo {
  const _DatosVehiculo({
    required this.patente,
    required this.tipo,
    required this.color,
    required this.observacion,
  });

  final String patente;
  final String tipo;
  final String color;
  final String observacion;
}
