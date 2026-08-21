import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkcontrol/offline/cache_operativo_repository.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';

void main() {
  late ParkControlLocalDatabase db;
  late CacheOperativoRepository cache;

  setUp(() {
    db = ParkControlLocalDatabase(NativeDatabase.memory());
    cache = CacheOperativoRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  MovimientoServidorSnapshot movimiento(
    int id,
    String patente, {
    int version = 1,
  }) {
    return MovimientoServidorSnapshot(
      id: id,
      patente: patente,
      tipo: 'Auto',
      color: 'Rojo',
      observacion: '',
      horaEntrada: DateTime.utc(2026, 8, 18, 12),
      version: version,
    );
  }

  test('guarda tarifa y movimientos confirmados del servidor', () async {
    final servidorFecha = DateTime.utc(2026, 8, 18, 13);
    await cache.reconciliarEstadoServidor(
      estacionamientoId: 1,
      tarifaServidorId: 7,
      tarifaPorMinuto: 48,
      movimientos: [movimiento(10, 'aa1111')],
      servidorFecha: servidorFecha,
    );

    final tarifa = await cache.obtenerTarifa(1);
    final dentro = await cache.listarDentro(1);

    expect(tarifa?.tarifaServidorId, 7);
    expect(tarifa?.tarifaPorMinuto, 48);
    expect(tarifa?.servidorFecha?.toUtc(), servidorFecha);
    expect(dentro.single.patente, 'AA1111');
    expect(dentro.single.versionServidor, 1);
    expect(dentro.single.estadoSincronizacion, 'confirmado');
  });

  test('actualiza y retira confirmados ausentes en el snapshot', () async {
    await cache.reconciliarEstadoServidor(
      estacionamientoId: 1,
      tarifaServidorId: 7,
      tarifaPorMinuto: 48,
      movimientos: [movimiento(10, 'AA1111'), movimiento(11, 'BB2222')],
    );

    await cache.reconciliarEstadoServidor(
      estacionamientoId: 1,
      tarifaServidorId: 8,
      tarifaPorMinuto: 55,
      movimientos: [movimiento(10, 'AA1111', version: 2)],
    );

    final dentro = await cache.listarDentro(1);
    expect(dentro, hasLength(1));
    expect(dentro.single.servidorId, 10);
    expect(dentro.single.versionServidor, 2);
    expect((await cache.obtenerTarifa(1))?.tarifaServidorId, 8);
  });

  test('no mezcla datos entre estacionamientos', () async {
    await cache.reconciliarEstadoServidor(
      estacionamientoId: 1,
      tarifaServidorId: 7,
      tarifaPorMinuto: 48,
      movimientos: [movimiento(10, 'MISMA1')],
    );
    await cache.reconciliarEstadoServidor(
      estacionamientoId: 2,
      tarifaServidorId: 9,
      tarifaPorMinuto: 60,
      movimientos: [movimiento(10, 'MISMA1')],
    );
    await cache.reconciliarEstadoServidor(
      estacionamientoId: 1,
      tarifaServidorId: 7,
      tarifaPorMinuto: 48,
      movimientos: const [],
    );

    expect(await cache.listarDentro(1), isEmpty);
    expect(await cache.listarDentro(2), hasLength(1));
    expect((await cache.obtenerTarifa(2))?.tarifaPorMinuto, 60);
  });

  test(
    'conserva movimientos locales pendientes durante conciliación',
    () async {
      final ahora = DateTime.utc(2026, 8, 18, 12);
      await db
          .into(db.movimientosLocales)
          .insert(
            MovimientosLocalesCompanion.insert(
              claveLocal: 'offline-entrada-0001',
              estacionamientoId: 1,
              patente: 'LOCAL1',
              tipo: 'Auto',
              color: 'Azul',
              horaEntrada: ahora,
              estadoSincronizacion: const Value('pendiente'),
              creadaEn: ahora,
              actualizadaEn: ahora,
            ),
          );

      await cache.reconciliarEstadoServidor(
        estacionamientoId: 1,
        tarifaServidorId: 7,
        tarifaPorMinuto: 48,
        movimientos: const [],
      );

      final dentro = await cache.listarDentro(1);
      expect(dentro, hasLength(1));
      expect(dentro.single.estadoSincronizacion, 'pendiente');
    },
  );

  test(
    'vincula una entrada offline confirmada sin duplicarla al conciliar',
    () async {
      final ahora = DateTime.utc(2026, 8, 18, 12);
      await db
          .into(db.movimientosLocales)
          .insert(
            MovimientosLocalesCompanion.insert(
              claveLocal: 'offline:entrada-confirmada-0001',
              estacionamientoId: 1,
              patente: 'AA1111',
              tipo: 'Auto',
              color: 'Rojo',
              horaEntrada: ahora,
              estadoSincronizacion: const Value('pendiente'),
              creadaEn: ahora,
              actualizadaEn: ahora,
            ),
          );

      await cache.vincularEntradaConfirmada(
        estacionamientoId: 1,
        claveOperacion: 'entrada-confirmada-0001',
        servidorId: 10,
        versionServidor: 1,
        ahora: ahora,
      );
      await cache.reconciliarEstadoServidor(
        estacionamientoId: 1,
        tarifaServidorId: 7,
        tarifaPorMinuto: 48,
        movimientos: [movimiento(10, 'AA1111')],
        ahora: ahora.add(const Duration(seconds: 1)),
      );

      final locales = await db.select(db.movimientosLocales).get();
      expect(locales, hasLength(1));
      expect(locales.single.claveLocal, 'offline:entrada-confirmada-0001');
      expect(locales.single.servidorId, 10);
      expect(locales.single.versionServidor, 1);
      expect(locales.single.estadoSincronizacion, 'confirmado');
    },
  );

  test(
    'conserva una salida pendiente ante el snapshot anterior del servidor',
    () async {
      final ahora = DateTime.utc(2026, 8, 18, 12);
      await db
          .into(db.movimientosLocales)
          .insert(
            MovimientosLocalesCompanion.insert(
              claveLocal: 'offline:entrada-con-salida-0001',
              estacionamientoId: 1,
              patente: 'AA1111',
              tipo: 'Auto',
              color: 'Rojo',
              horaEntrada: ahora,
              estado: const Value('salio'),
              estadoSincronizacion: const Value('pendiente'),
              creadaEn: ahora,
              actualizadaEn: ahora,
            ),
          );

      await cache.vincularEntradaConfirmada(
        estacionamientoId: 1,
        claveOperacion: 'entrada-con-salida-0001',
        servidorId: 10,
        versionServidor: 1,
        ahora: ahora,
      );
      await cache.reconciliarEstadoServidor(
        estacionamientoId: 1,
        tarifaServidorId: 7,
        tarifaPorMinuto: 48,
        movimientos: [movimiento(10, 'AA1111')],
        ahora: ahora.add(const Duration(seconds: 1)),
      );

      final locales = await db.select(db.movimientosLocales).get();
      expect(locales, hasLength(1));
      expect(locales.single.estado, 'salio');
      expect(locales.single.estadoSincronizacion, 'pendiente');
      expect(locales.single.servidorId, 10);
      expect(await cache.listarDentro(1), isEmpty);
    },
  );

  test(
    'no revierte una modificación local pendiente con datos del snapshot',
    () async {
      final ahora = DateTime.utc(2026, 8, 18, 12);
      await db
          .into(db.movimientosLocales)
          .insert(
            MovimientosLocalesCompanion.insert(
              claveLocal: 'servidor:1:10',
              estacionamientoId: 1,
              servidorId: const Value(10),
              patente: 'AA1111',
              tipo: 'Auto',
              color: 'Azul',
              horaEntrada: ahora,
              versionServidor: const Value(1),
              estadoSincronizacion: const Value('pendiente'),
              creadaEn: ahora,
              actualizadaEn: ahora,
            ),
          );

      await cache.reconciliarEstadoServidor(
        estacionamientoId: 1,
        tarifaServidorId: 7,
        tarifaPorMinuto: 48,
        movimientos: [movimiento(10, 'AA1111')],
        ahora: ahora.add(const Duration(seconds: 1)),
      );

      final local = (await db.select(db.movimientosLocales).get()).single;
      expect(local.color, 'Azul');
      expect(local.estadoSincronizacion, 'pendiente');
    },
  );

  test(
    'fusiona un duplicado de snapshot al vincular la entrada confirmada',
    () async {
      final ahora = DateTime.utc(2026, 8, 18, 12);
      await db
          .into(db.movimientosLocales)
          .insert(
            MovimientosLocalesCompanion.insert(
              claveLocal: 'offline:entrada-duplicada-0001',
              estacionamientoId: 1,
              patente: 'AA1111',
              tipo: 'Auto',
              color: 'Rojo',
              horaEntrada: ahora,
              estadoSincronizacion: const Value('pendiente'),
              creadaEn: ahora,
              actualizadaEn: ahora,
            ),
          );
      await db
          .into(db.movimientosLocales)
          .insert(
            MovimientosLocalesCompanion.insert(
              claveLocal: 'servidor:1:10',
              estacionamientoId: 1,
              servidorId: const Value(10),
              patente: 'AA1111',
              tipo: 'Auto',
              color: 'Rojo',
              horaEntrada: ahora,
              versionServidor: const Value(1),
              creadaEn: ahora,
              actualizadaEn: ahora,
            ),
          );

      await cache.vincularEntradaConfirmada(
        estacionamientoId: 1,
        claveOperacion: 'entrada-duplicada-0001',
        servidorId: 10,
        versionServidor: 1,
        ahora: ahora,
      );

      final locales = await db.select(db.movimientosLocales).get();
      expect(locales, hasLength(1));
      expect(locales.single.claveLocal, 'offline:entrada-duplicada-0001');
      expect(locales.single.servidorId, 10);
    },
  );

  test('busca patente solo dentro del cliente indicado', () async {
    await cache.reconciliarEstadoServidor(
      estacionamientoId: 1,
      tarifaServidorId: 7,
      tarifaPorMinuto: 48,
      movimientos: [movimiento(10, 'aa1111')],
    );

    expect(await cache.buscarPatenteDentro(1, 'Aa1111'), isNotNull);
    expect(await cache.buscarPatenteDentro(2, 'AA1111'), isNull);
  });
}
