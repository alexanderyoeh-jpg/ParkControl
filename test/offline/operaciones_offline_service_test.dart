import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkcontrol/offline/cache_operativo_repository.dart';
import 'package:parkcontrol/offline/cola_sincronizacion_repository.dart';
import 'package:parkcontrol/offline/operaciones_offline_service.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';

void main() {
  late ParkControlLocalDatabase db;
  late CacheOperativoRepository cache;
  late OperacionesOfflineService operaciones;
  final ahora = DateTime.utc(2026, 8, 19, 12);

  setUp(() {
    db = ParkControlLocalDatabase(NativeDatabase.memory());
    cache = CacheOperativoRepository(db);
    operaciones = OperacionesOfflineService(db);
  });

  tearDown(() async {
    await db.close();
  });

  MovimientoServidorSnapshot movimientoServidor(
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
      horaEntrada: ahora.subtract(const Duration(minutes: 40)),
      version: version,
    );
  }

  Future<void> prepararSnapshot({int estacionamientoId = 1}) {
    return cache.reconciliarEstadoServidor(
      estacionamientoId: estacionamientoId,
      tarifaServidorId: 7,
      tarifaPorMinuto: 50,
      movimientos: [movimientoServidor(101, 'AB1234', version: 3)],
      ahora: ahora,
    );
  }

  test('registra una entrada offline y la deja visible en la cache', () async {
    final entrada = await operaciones.registrarEntrada(
      clave: 'offline-entrada-1001',
      estacionamientoId: 1,
      usuarioId: 10,
      patente: ' aa1111 ',
      tipo: 'Auto',
      color: 'Azul',
      observacion: 'Cliente frecuente',
      horaEntrada: ahora,
      ahora: ahora,
    );

    final pendientes = await db.select(db.operacionesPendientes).get();
    final cuerpo = jsonDecode(pendientes.single.cuerpoJson!);

    expect(entrada.claveLocal, 'offline:offline-entrada-1001');
    expect(entrada.patente, 'AA1111');
    expect(entrada.estado, 'dentro');
    expect(entrada.estadoSincronizacion, 'pendiente');
    expect(cuerpo['horaEntradaCliente'], ahora.toIso8601String());
    expect((await cache.listarDentro(1)).single.patente, 'AA1111');
  });

  test('repetir la misma entrada no duplica cola ni movimiento', () async {
    Future<void> registrar() => operaciones.registrarEntrada(
      clave: 'offline-entrada-1001',
      estacionamientoId: 1,
      usuarioId: 10,
      patente: 'AA1111',
      tipo: 'Auto',
      color: 'Azul',
      horaEntrada: ahora,
      ahora: ahora,
    );

    await registrar();
    await registrar();

    expect(await db.select(db.operacionesPendientes).get(), hasLength(1));
    expect(await db.select(db.movimientosLocales).get(), hasLength(1));
  });

  test('rechaza una segunda entrada activa de la misma patente', () async {
    await operaciones.registrarEntrada(
      clave: 'offline-entrada-1001',
      estacionamientoId: 1,
      usuarioId: 10,
      patente: 'AA1111',
      tipo: 'Auto',
      color: 'Azul',
      ahora: ahora,
    );

    expect(
      () => operaciones.registrarEntrada(
        clave: 'offline-entrada-1002',
        estacionamientoId: 1,
        usuarioId: 10,
        patente: 'AA1111',
        tipo: 'Auto',
        color: 'Rojo',
        ahora: ahora,
      ),
      throwsA(
        isA<ErrorOperacionOffline>().having(
          (error) => error.codigo,
          'codigo',
          'PATENTE_YA_DENTRO',
        ),
      ),
    );
  });

  test('salida offline usa version, movimiento y tarifa esperada', () async {
    await prepararSnapshot();

    await operaciones.registrarSalida(
      clave: 'offline-salida-1001',
      estacionamientoId: 1,
      usuarioId: 10,
      patente: 'AB1234',
      horaSalida: ahora,
      ahora: ahora,
    );

    final pendientes = await db.select(db.operacionesPendientes).get();
    final cuerpo = jsonDecode(pendientes.single.cuerpoJson!);
    final movimiento = (await db.select(db.movimientosLocales).get()).single;

    expect(pendientes.single.tipo, 'salida');
    expect(cuerpo['movimientoId'], 101);
    expect(cuerpo['versionEsperada'], 3);
    expect(cuerpo['tarifaIdEsperada'], 7);
    expect(cuerpo['horaSalidaCliente'], ahora.toIso8601String());
    expect(movimiento.estado, 'salio');
    expect(movimiento.estadoSincronizacion, 'pendiente');
    expect(await cache.listarDentro(1), isEmpty);
  });

  test(
    'modificacion offline actualiza la patente y conserva aislamiento',
    () async {
      await prepararSnapshot(estacionamientoId: 1);
      await prepararSnapshot(estacionamientoId: 2);

      final modificado = await operaciones.modificarVehiculo(
        clave: 'offline-modificar-1001',
        estacionamientoId: 1,
        usuarioId: 10,
        patenteActual: 'AB1234',
        patenteNueva: 'CD5678',
        tipo: 'Moto',
        color: 'Negro',
        observacion: 'Cambio local',
        ahora: ahora,
      );

      final pendientes = await db.select(db.operacionesPendientes).get();
      final cuerpo = jsonDecode(pendientes.single.cuerpoJson!);

      expect(modificado.patente, 'CD5678');
      expect(modificado.tipo, 'Moto');
      expect(pendientes.single.ruta, '/api/modificar/AB1234');
      expect(cuerpo['versionEsperada'], 3);
      expect((await cache.buscarPatenteDentro(2, 'AB1234')), isNotNull);
    },
  );

  test('eliminacion offline marca eliminado sin borrar fisicamente', () async {
    await prepararSnapshot();

    await operaciones.eliminarVehiculo(
      clave: 'offline-eliminar-1001',
      estacionamientoId: 1,
      usuarioId: 10,
      patente: 'AB1234',
      ahora: ahora,
    );

    final pendientes = await db.select(db.operacionesPendientes).get();
    final cuerpo = jsonDecode(pendientes.single.cuerpoJson!);
    final movimiento = (await db.select(db.movimientosLocales).get()).single;

    expect(pendientes.single.tipo, 'eliminacion');
    expect(cuerpo['versionEsperada'], 3);
    expect(movimiento.estado, 'eliminado');
    expect(movimiento.estadoSincronizacion, 'pendiente');
    expect(await cache.listarDentro(1), isEmpty);
  });

  test('rechaza reutilizar una clave con otros datos', () async {
    await operaciones.registrarEntrada(
      clave: 'offline-entrada-1001',
      estacionamientoId: 1,
      usuarioId: 10,
      patente: 'AA1111',
      tipo: 'Auto',
      color: 'Azul',
      horaEntrada: ahora,
      ahora: ahora,
    );

    expect(
      () => operaciones.registrarEntrada(
        clave: 'offline-entrada-1001',
        estacionamientoId: 1,
        usuarioId: 10,
        patente: 'BB2222',
        tipo: 'Auto',
        color: 'Azul',
        horaEntrada: ahora,
        ahora: ahora,
      ),
      throwsA(isA<ConflictoClaveOffline>()),
    );
  });
}
