import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parkcontrol/offline/cache_operativo_repository.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';
import 'package:parkcontrol/offline/sincronizacion_inicial_service.dart';

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

  test('descarga y reconcilia el snapshot autenticado', () async {
    final servicio = SincronizacionInicialService(
      cache,
      obtener: (_) async => http.Response('''
        {
          "versionFormato": 1,
          "servidorFecha": "2026-08-18T15:00:00.000Z",
          "estacionamientoId": 23,
          "tarifa": {"id": 8, "tarifaPorMinuto": 55},
          "movimientos": [
            {
              "id": 91,
              "patente": "AB1234",
              "tipo": "Auto",
              "color": "Rojo",
              "observacion": "",
              "horaEntrada": "2026-08-18T14:00:00.000Z",
              "version": 2
            }
          ]
        }
      ''', 200),
    );

    final estado = await servicio.actualizar();

    expect(estado.estacionamientoId, 23);
    expect((await cache.obtenerTarifa(23))?.tarifaServidorId, 8);
    expect((await cache.listarDentro(23)).single.servidorId, 91);
  });

  test(
    'rechaza versiones de contrato desconocidas sin tocar la caché',
    () async {
      final servicio = SincronizacionInicialService(
        cache,
        obtener: (_) async => http.Response('''
        {
          "versionFormato": 99,
          "servidorFecha": "2026-08-18T15:00:00.000Z",
          "estacionamientoId": 23,
          "tarifa": {"id": 8, "tarifaPorMinuto": 55},
          "movimientos": []
        }
      ''', 200),
      );

      expect(servicio.actualizar, throwsA(isA<ErrorSincronizacionInicial>()));
      expect(await cache.obtenerTarifa(23), isNull);
    },
  );

  test(
    'propaga suspensión del servidor sin sobrescribir datos locales',
    () async {
      await cache.reconciliarEstadoServidor(
        estacionamientoId: 23,
        tarifaServidorId: 8,
        tarifaPorMinuto: 55,
        movimientos: const [],
      );
      final servicio = SincronizacionInicialService(
        cache,
        obtener: (_) async =>
            http.Response('{"mensaje":"Estacionamiento suspendido"}', 403),
      );

      try {
        await servicio.actualizar();
        fail('Debió rechazar la sincronización');
      } on ErrorSincronizacionInicial catch (error) {
        expect(error.codigoHttp, 403);
        expect(error.mensaje, 'Estacionamiento suspendido');
      }
      expect((await cache.obtenerTarifa(23))?.tarifaServidorId, 8);
    },
  );
}
