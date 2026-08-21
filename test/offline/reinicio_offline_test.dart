import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parkcontrol/offline/cola_sincronizacion_repository.dart';
import 'package:parkcontrol/offline/coordinador_sincronizacion.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';

void main() {
  test('recupera una operación enviando después de reiniciar la app', () async {
    final ahora = DateTime.utc(2026, 8, 18, 12);
    final temporal = await Directory.systemTemp.createTemp(
      'parkcontrol-reinicio-offline-',
    );
    final archivo = File(
      '${temporal.path}${Platform.pathSeparator}offline.sqlite',
    );

    ParkControlLocalDatabase? dbInicial;
    ParkControlLocalDatabase? dbReiniciada;

    try {
      dbInicial = ParkControlLocalDatabase(NativeDatabase(archivo));
      final colaInicial = ColaSincronizacionRepository(dbInicial);

      await colaInicial.encolar(
        clave: 'offline-reinicio-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        tipo: 'entrada',
        metodo: 'POST',
        ruta: '/api/entradas',
        cuerpoJson: '{"patente":"REINI1"}',
        ahora: ahora,
      );
      await colaInicial.encolar(
        clave: 'offline-reinicio-0002',
        estacionamientoId: 1,
        usuarioId: 10,
        tipo: 'salida',
        metodo: 'POST',
        ruta: '/api/salidas',
        cuerpoJson: '{"patente":"REINI1"}',
        ahora: ahora.add(const Duration(seconds: 1)),
      );

      final reservada = await colaInicial.reservarSiguiente(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      );
      expect(reservada?.clave, 'offline-reinicio-0001');
      expect(reservada?.estado, 'enviando');

      await dbInicial.close();
      dbInicial = null;

      dbReiniciada = ParkControlLocalDatabase(NativeDatabase(archivo));
      final colaReiniciada = ColaSincronizacionRepository(dbReiniciada);
      final recuperadas = await colaReiniciada.restablecerEnviosInterrumpidos(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora.add(const Duration(minutes: 1)),
      );
      expect(recuperadas, 1);

      final enviadas = <String>[];
      final coordinador = CoordinadorSincronizacion(
        colaReiniciada,
        enviar: (operacion) async {
          enviadas.add(operacion.clave);
          return http.Response('{"mensaje":"ok"}', 200);
        },
      );

      expect(
        await coordinador.procesarUna(
          estacionamientoId: 1,
          usuarioId: 10,
          ahora: ahora.add(const Duration(minutes: 1)),
        ),
        ResultadoProcesamientoOffline.completada,
      );
      expect(enviadas, ['offline-reinicio-0001']);
      expect(
        (await colaReiniciada.siguiente(
          estacionamientoId: 1,
          usuarioId: 10,
          ahora: ahora.add(const Duration(minutes: 1)),
        ))?.clave,
        'offline-reinicio-0002',
      );
    } finally {
      await dbInicial?.close();
      await dbReiniciada?.close();
      await temporal.delete(recursive: true);
    }
  });
}
