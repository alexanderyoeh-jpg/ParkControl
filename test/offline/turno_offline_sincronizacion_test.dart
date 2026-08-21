import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parkcontrol/offline/cache_operativo_repository.dart';
import 'package:parkcontrol/offline/cola_sincronizacion_repository.dart';
import 'package:parkcontrol/offline/coordinador_sincronizacion.dart';
import 'package:parkcontrol/offline/operaciones_offline_service.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';

void main() {
  late ParkControlLocalDatabase db;
  late CacheOperativoRepository cache;
  late ColaSincronizacionRepository cola;
  late OperacionesOfflineService operaciones;

  setUp(() {
    db = ParkControlLocalDatabase(NativeDatabase.memory());
    cache = CacheOperativoRepository(db);
    cola = ColaSincronizacionRepository(db);
    operaciones = OperacionesOfflineService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'sincroniza un turno corto offline respetando entrada antes de salida',
    () async {
      final ahora = DateTime.utc(2026, 8, 18, 12);
      final horaEntrada = ahora.subtract(const Duration(minutes: 45));
      final horaSalida = horaEntrada.add(const Duration(minutes: 30));

      await cache.reconciliarEstadoServidor(
        estacionamientoId: 1,
        tarifaServidorId: 7,
        tarifaPorMinuto: 50,
        movimientos: const [],
        servidorFecha: ahora,
        ahora: ahora,
      );

      await operaciones.registrarEntrada(
        clave: 'turno-offline-entrada-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        patente: 'TURN01',
        tipo: 'Auto',
        color: 'Blanco',
        observacion: 'Turno offline',
        horaEntrada: horaEntrada,
        ahora: ahora,
      );

      await operaciones.registrarSalida(
        clave: 'turno-offline-salida-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        patente: 'TURN01',
        horaSalida: horaSalida,
        ahora: ahora.add(const Duration(minutes: 30)),
      );

      final movimientoLocal = await db
          .select(db.movimientosLocales)
          .getSingle();
      expect(movimientoLocal.estado, 'salio');
      expect(movimientoLocal.estadoSincronizacion, 'pendiente');

      final enviadas = <String>[];
      final coordinador = CoordinadorSincronizacion(
        cola,
        enviar: (operacion) async {
          enviadas.add(operacion.clave);
          final cuerpo = jsonDecode(operacion.cuerpoJson ?? '{}');
          expect(cuerpo, isA<Map<String, dynamic>>());

          if (operacion.tipo == 'entrada') {
            expect(operacion.ruta, '/api/entradas');
            expect(cuerpo['patente'], 'TURN01');
            expect(cuerpo['horaEntradaCliente'], horaEntrada.toIso8601String());
            return http.Response(
              '{"movimiento":{"id":101,"patente":"TURN01","version":1}}',
              201,
            );
          }

          expect(operacion.tipo, 'salida');
          expect(operacion.ruta, '/api/salidas');
          expect(cuerpo['patente'], 'TURN01');
          expect(cuerpo['horaSalidaCliente'], horaSalida.toIso8601String());
          expect(cuerpo['movimientoId'], isNull);
          expect(cuerpo['versionEsperada'], isNull);
          expect(cuerpo['tarifaIdEsperada'], 7);
          return http.Response(
            '{"salida":{"id":101,"patente":"TURN01","monto":1500}}',
            200,
          );
        },
      );

      expect(
        await coordinador.procesarDisponibles(
          estacionamientoId: 1,
          usuarioId: 10,
          maximo: 2,
        ),
        2,
      );
      expect(enviadas, [
        'turno-offline-entrada-0001',
        'turno-offline-salida-0001',
      ]);
      expect(
        await cola.listarActivas(estacionamientoId: 1, usuarioId: 10),
        isEmpty,
      );
      expect((await cola.listar()).map((op) => op.estado).toSet(), {
        'completada',
      });
    },
  );
}
