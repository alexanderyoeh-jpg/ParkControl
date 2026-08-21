import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parkcontrol/offline/cola_sincronizacion_repository.dart';
import 'package:parkcontrol/offline/coordinador_sincronizacion.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';

void main() {
  late ParkControlLocalDatabase db;
  late ColaSincronizacionRepository cola;
  final ahora = DateTime.utc(2026, 8, 18, 12);

  setUp(() {
    db = ParkControlLocalDatabase(NativeDatabase.memory());
    cola = ColaSincronizacionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> encolar(
    String clave, {
    int estacionamientoId = 1,
    int usuarioId = 10,
  }) {
    return cola.encolar(
      clave: clave,
      estacionamientoId: estacionamientoId,
      usuarioId: usuarioId,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
      cuerpoJson: '{"patente":"AA1111"}',
      ahora: ahora,
    );
  }

  test('confirma una operación y refresca la caché una sola vez', () async {
    await encolar('offline-coordinador-0001');
    var envios = 0;
    var refrescos = 0;
    var resultados = 0;
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (operacion) async {
        envios++;
        expect(operacion.estado, 'enviando');
        expect(operacion.intentos, 1);
        return http.Response('{"mensaje":"ok"}', 201);
      },
      refrescarCache: () async => refrescos++,
      registrarResultado: (operacion, respuesta) async {
        resultados++;
        expect(operacion.clave, 'offline-coordinador-0001');
        expect(respuesta.statusCode, 201);
      },
    );

    expect(
      await coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      ResultadoProcesamientoOffline.completada,
    );
    expect(envios, 1);
    expect(refrescos, 1);
    expect(resultados, 1);
    expect((await cola.listar()).single.estado, 'completada');
  });

  test('programa reintento ante red o error temporal', () async {
    await encolar('offline-coordinador-0001');
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (_) async => throw const SocketExceptionPrueba(),
    );

    expect(
      await coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      ResultadoProcesamientoOffline.reintentoProgramado,
    );
    final operacion = (await cola.listar()).single;
    expect(operacion.estado, 'pendiente');
    expect(operacion.intentos, 1);
    expect(
      operacion.proximoIntentoEn?.toUtc(),
      ahora.add(const Duration(seconds: 5)),
    );
  });

  test('un 409 bloquea el orden como conflicto visible', () async {
    await encolar('offline-coordinador-0001');
    await encolar('offline-coordinador-0002');
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (_) async =>
          http.Response('{"codigo":"MOVIMIENTO_DESACTUALIZADO"}', 409),
    );

    expect(
      await coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      ResultadoProcesamientoOffline.conflicto,
    );
    expect(await cola.siguiente(estacionamientoId: 1, usuarioId: 10), isNull);
    final operaciones = await cola.listar();
    expect(operaciones.first.estado, 'conflicto');
    expect(operaciones.first.ultimoError, 'MOVIMIENTO_DESACTUALIZADO');
    expect(operaciones.last.estado, 'pendiente');
  });

  test('un 403 deja la operación bloqueada sin reintentar', () async {
    await encolar('offline-coordinador-0001');
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (_) async =>
          http.Response('{"mensaje":"Estacionamiento suspendido"}', 403),
    );

    expect(
      await coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      ResultadoProcesamientoOffline.bloqueada,
    );
    final operacion = (await cola.listar()).single;
    expect(operacion.estado, 'bloqueada');
    expect(operacion.ultimoError, 'Estacionamiento suspendido');
  });

  test('un 429 programa reintento en vez de crear un conflicto', () async {
    await encolar('offline-coordinador-0001');
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (_) async =>
          http.Response('{"mensaje":"Intenta más tarde"}', 429),
    );

    expect(
      await coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      ResultadoProcesamientoOffline.reintentoProgramado,
    );
    final operacion = (await cola.listar()).single;
    expect(operacion.estado, 'pendiente');
    expect(operacion.proximoIntentoEn, isNotNull);
  });

  test('impide dos procesamientos simultáneos del mismo cliente', () async {
    await encolar('offline-coordinador-0001');
    final respuestaPendiente = Completer<http.Response>();
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (_) => respuestaPendiente.future,
    );

    final primero = coordinador.procesarUna(
      estacionamientoId: 1,
      usuarioId: 10,
      ahora: ahora,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      await coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      ResultadoProcesamientoOffline.yaProcesando,
    );

    respuestaPendiente.complete(http.Response('{}', 200));
    expect(await primero, ResultadoProcesamientoOffline.completada);
  });

  test('procesa clientes distintos sin compartir sus operaciones', () async {
    await encolar('offline-coordinador-0001', estacionamientoId: 1);
    await encolar('offline-coordinador-0002', estacionamientoId: 2);
    final clientesEnviados = <int>[];
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (operacion) async {
        clientesEnviados.add(operacion.estacionamientoId);
        return http.Response('{}', 200);
      },
    );

    await Future.wait([
      coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      coordinador.procesarUna(
        estacionamientoId: 2,
        usuarioId: 10,
        ahora: ahora,
      ),
    ]);

    expect(clientesEnviados.toSet(), {1, 2});
    expect(
      (await cola.listar()).every((item) => item.estado == 'completada'),
      isTrue,
    );
  });

  test('procesa sólo la cola del cajero autenticado', () async {
    await encolar('offline-cajero-uno-0001', usuarioId: 10);
    await encolar('offline-cajero-dos-0001', usuarioId: 20);
    final usuariosEnviados = <int>[];
    final coordinador = CoordinadorSincronizacion(
      cola,
      enviar: (operacion) async {
        usuariosEnviados.add(operacion.usuarioId);
        return http.Response('{}', 200);
      },
    );

    await Future.wait([
      coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ),
      coordinador.procesarUna(
        estacionamientoId: 1,
        usuarioId: 20,
        ahora: ahora,
      ),
    ]);

    expect(usuariosEnviados.toSet(), {10, 20});
    expect(
      await cola.listarActivas(estacionamientoId: 1, usuarioId: 10),
      isEmpty,
    );
    expect(
      await cola.listarActivas(estacionamientoId: 1, usuarioId: 20),
      isEmpty,
    );
  });
}

class SocketExceptionPrueba implements Exception {
  const SocketExceptionPrueba();

  @override
  String toString() => 'red no disponible';
}
