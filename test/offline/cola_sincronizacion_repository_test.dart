import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkcontrol/offline/cola_sincronizacion_repository.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';

void main() {
  late ParkControlLocalDatabase db;
  late ColaSincronizacionRepository cola;

  setUp(() {
    db = ParkControlLocalDatabase(NativeDatabase.memory());
    cola = ColaSincronizacionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('mantiene orden e aislamiento entre estacionamientos', () async {
    final ahora = DateTime.utc(2026, 8, 18, 12);

    await cola.encolar(
      clave: 'offline-entrada-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
      cuerpoJson: '{"patente":"AA1111"}',
      ahora: ahora,
    );
    await cola.encolar(
      clave: 'offline-salida-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'salida',
      metodo: 'POST',
      ruta: '/api/salidas',
      cuerpoJson: '{"patente":"AA1111"}',
      ahora: ahora.add(const Duration(seconds: 1)),
    );
    await cola.encolar(
      clave: 'offline-entrada-0002',
      estacionamientoId: 2,
      usuarioId: 20,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
      cuerpoJson: '{"patente":"BB2222"}',
      ahora: ahora,
    );

    expect(
      (await cola.siguiente(estacionamientoId: 1, usuarioId: 10))?.clave,
      'offline-entrada-0001',
    );
    expect(
      (await cola.siguiente(estacionamientoId: 2, usuarioId: 20))?.clave,
      'offline-entrada-0002',
    );
  });

  test('repetir la misma operación no duplica la cola', () async {
    Future<void> encolar() => cola.encolar(
      clave: 'offline-entrada-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
      cuerpoJson: '{"patente":"AA1111"}',
    );

    await encolar();
    await encolar();

    expect((await cola.listar()).length, 1);
  });

  test('rechaza una clave reutilizada con otros datos', () async {
    await cola.encolar(
      clave: 'offline-entrada-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
      cuerpoJson: '{"patente":"AA1111"}',
    );

    expect(
      () => cola.encolar(
        clave: 'offline-entrada-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        tipo: 'entrada',
        metodo: 'POST',
        ruta: '/api/entradas',
        cuerpoJson: '{"patente":"DISTINTA"}',
      ),
      throwsA(isA<ConflictoClaveOffline>()),
    );
  });

  test('programa reintentos y excluye estados terminales', () async {
    final ahora = DateTime.utc(2026, 8, 18, 12);

    await cola.encolar(
      clave: 'offline-salida-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'salida',
      metodo: 'POST',
      ruta: '/api/salidas',
      cuerpoJson: '{"patente":"AA1111"}',
      ahora: ahora,
    );
    await cola.encolar(
      clave: 'offline-modificar-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'modificacion',
      metodo: 'PUT',
      ruta: '/api/modificar/AA1111',
      cuerpoJson: '{"color":"Azul"}',
      ahora: ahora.add(const Duration(seconds: 1)),
    );
    await cola.marcarEnviando(
      'offline-salida-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      ahora: ahora,
    );
    await cola.registrarFallo(
      'offline-salida-0001',
      'Sin conexión',
      estacionamientoId: 1,
      usuarioId: 10,
      ahora: ahora,
    );

    expect(
      await cola.siguiente(estacionamientoId: 1, usuarioId: 10, ahora: ahora),
      isNull,
    );
    expect(
      (await cola.siguiente(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora.add(const Duration(seconds: 5)),
      ))?.clave,
      'offline-salida-0001',
    );

    await cola.marcarConflicto(
      'offline-salida-0001',
      'Patente ya cerrada',
      estacionamientoId: 1,
      usuarioId: 10,
    );
    expect(await cola.siguiente(estacionamientoId: 1, usuarioId: 10), isNull);

    await cola.marcarCompletada(
      'offline-salida-0001',
      estacionamientoId: 1,
      usuarioId: 10,
    );
    expect(
      (await cola.siguiente(estacionamientoId: 1, usuarioId: 10))?.clave,
      'offline-modificar-0001',
    );
  });

  test('recupera envíos que quedaron interrumpidos', () async {
    await cola.encolar(
      clave: 'offline-eliminar-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'eliminacion',
      metodo: 'DELETE',
      ruta: '/api/modificar/AA1111',
    );
    await cola.marcarEnviando(
      'offline-eliminar-0001',
      estacionamientoId: 1,
      usuarioId: 10,
    );

    expect(
      await cola.restablecerEnviosInterrumpidos(
        estacionamientoId: 1,
        usuarioId: 10,
      ),
      1,
    );
    expect(
      (await cola.siguiente(estacionamientoId: 1, usuarioId: 10))?.estado,
      'pendiente',
    );
  });

  test('reanuda bloqueadas solo para el estacionamiento autenticado', () async {
    await cola.encolar(
      clave: 'offline-bloqueada-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
    );
    await cola.encolar(
      clave: 'offline-bloqueada-0002',
      estacionamientoId: 2,
      usuarioId: 20,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
    );
    await cola.marcarBloqueada(
      'offline-bloqueada-0001',
      'Sesión vencida',
      estacionamientoId: 1,
      usuarioId: 10,
    );
    await cola.marcarBloqueada(
      'offline-bloqueada-0002',
      'Suspendido',
      estacionamientoId: 2,
      usuarioId: 20,
    );

    expect(
      await cola.reanudarBloqueadas(estacionamientoId: 1, usuarioId: 10),
      1,
    );
    expect(
      (await cola.listar(estacionamientoId: 1)).single.estado,
      'pendiente',
    );
    expect(
      (await cola.listar(estacionamientoId: 2)).single.estado,
      'bloqueada',
    );
  });

  test('aísla la cola entre cajeros del mismo estacionamiento', () async {
    await cola.encolar(
      clave: 'offline-cajero-uno-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
    );
    await cola.encolar(
      clave: 'offline-cajero-dos-0001',
      estacionamientoId: 1,
      usuarioId: 20,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
    );

    expect(
      (await cola.siguiente(estacionamientoId: 1, usuarioId: 10))?.clave,
      'offline-cajero-uno-0001',
    );
    expect(
      (await cola.siguiente(estacionamientoId: 1, usuarioId: 20))?.clave,
      'offline-cajero-dos-0001',
    );
    expect(
      (await cola.listarActivas(
        estacionamientoId: 1,
        usuarioId: 10,
      )).map((operacion) => operacion.clave),
      ['offline-cajero-uno-0001'],
    );

    await cola.marcarBloqueada(
      'offline-cajero-uno-0001',
      'Sesión vencida',
      estacionamientoId: 1,
      usuarioId: 10,
    );

    expect(
      await cola.reanudarBloqueadas(estacionamientoId: 1, usuarioId: 20),
      0,
    );
    expect(
      (await cola.listar(
        estacionamientoId: 1,
      )).firstWhere((operacion) => operacion.usuarioId == 10).estado,
      'bloqueada',
    );
  });

  test(
    'lista activas y permite reintento manual por estacionamiento',
    () async {
      final ahora = DateTime.utc(2026, 8, 18, 12);

      await cola.encolar(
        clave: 'offline-reintento-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        tipo: 'entrada',
        metodo: 'POST',
        ruta: '/api/entradas',
        ahora: ahora,
      );
      await cola.encolar(
        clave: 'offline-completada-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        tipo: 'salida',
        metodo: 'POST',
        ruta: '/api/salidas',
        ahora: ahora.add(const Duration(seconds: 1)),
      );
      await cola.encolar(
        clave: 'offline-reintento-0002',
        estacionamientoId: 2,
        usuarioId: 20,
        tipo: 'entrada',
        metodo: 'POST',
        ruta: '/api/entradas',
        ahora: ahora,
      );

      await cola.marcarEnviando(
        'offline-reintento-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      );
      await cola.registrarFallo(
        'offline-reintento-0001',
        'Sin conexión',
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      );
      await cola.marcarCompletada(
        'offline-completada-0001',
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      );

      expect(
        (await cola.listarActivas(
          estacionamientoId: 1,
          usuarioId: 10,
        )).map((op) => op.clave),
        ['offline-reintento-0001'],
      );
      expect(
        await cola.siguiente(estacionamientoId: 1, usuarioId: 10, ahora: ahora),
        isNull,
      );

      expect(
        await cola.reintentarPendientesAhora(
          estacionamientoId: 1,
          usuarioId: 10,
          ahora: ahora,
        ),
        1,
      );
      expect(
        (await cola.siguiente(
          estacionamientoId: 1,
          usuarioId: 10,
          ahora: ahora,
        ))?.clave,
        'offline-reintento-0001',
      );
      expect(
        (await cola.siguiente(
          estacionamientoId: 2,
          usuarioId: 20,
          ahora: ahora,
        ))?.clave,
        'offline-reintento-0002',
      );
    },
  );

  test('descarta conflictos y permite continuar la cola del cliente', () async {
    final ahora = DateTime.utc(2026, 8, 18, 12);

    await cola.encolar(
      clave: 'offline-conflicto-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'salida',
      metodo: 'POST',
      ruta: '/api/salidas',
      ahora: ahora,
    );
    await cola.encolar(
      clave: 'offline-posterior-0001',
      estacionamientoId: 1,
      usuarioId: 10,
      tipo: 'entrada',
      metodo: 'POST',
      ruta: '/api/entradas',
      ahora: ahora.add(const Duration(seconds: 1)),
    );
    await cola.encolar(
      clave: 'offline-conflicto-0002',
      estacionamientoId: 2,
      usuarioId: 20,
      tipo: 'salida',
      metodo: 'POST',
      ruta: '/api/salidas',
      ahora: ahora,
    );

    await cola.marcarConflicto(
      'offline-conflicto-0001',
      'Tarifa desactualizada',
      estacionamientoId: 1,
      usuarioId: 10,
      ahora: ahora,
    );
    await cola.marcarConflicto(
      'offline-conflicto-0002',
      'Tarifa desactualizada',
      estacionamientoId: 2,
      usuarioId: 20,
      ahora: ahora,
    );

    expect(
      await cola.siguiente(estacionamientoId: 1, usuarioId: 10, ahora: ahora),
      isNull,
    );

    expect(
      await cola.descartarConflicto(
        estacionamientoId: 1,
        usuarioId: 10,
        clave: 'offline-conflicto-0001',
        motivo: 'Se recalculará con la tarifa vigente',
        ahora: ahora,
      ),
      1,
    );

    expect(
      (await cola.siguiente(
        estacionamientoId: 1,
        usuarioId: 10,
        ahora: ahora,
      ))?.clave,
      'offline-posterior-0001',
    );
    expect(
      (await cola.listarActivas(
        estacionamientoId: 1,
        usuarioId: 10,
      )).map((op) => op.clave),
      ['offline-posterior-0001'],
    );
    expect(
      (await cola.listar(estacionamientoId: 2)).single.estado,
      'conflicto',
    );
  });
}
