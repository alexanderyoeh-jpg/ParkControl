import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkcontrol/offline/parkcontrol_local_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('migra la cola v1 a caché v2 sin perder operaciones', () async {
    final temporal = await Directory.systemTemp.createTemp(
      'parkcontrol-migracion-',
    );
    final archivo = File('${temporal.path}/offline.sqlite');

    try {
      final antigua = sqlite.sqlite3.open(archivo.path);
      antigua.execute('''
        CREATE TABLE operaciones_pendientes (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          clave TEXT NOT NULL UNIQUE,
          estacionamiento_id INTEGER NOT NULL,
          usuario_id INTEGER NOT NULL,
          tipo TEXT NOT NULL,
          metodo TEXT NOT NULL,
          ruta TEXT NOT NULL,
          cuerpo_json TEXT NULL,
          version_formato INTEGER NOT NULL DEFAULT 1,
          estado TEXT NOT NULL DEFAULT 'pendiente',
          intentos INTEGER NOT NULL DEFAULT 0,
          ultimo_error TEXT NULL,
          proximo_intento_en INTEGER NULL,
          creada_en INTEGER NOT NULL,
          actualizada_en INTEGER NOT NULL
        )
      ''');
      antigua.execute('''
        CREATE INDEX idx_cola_estacionamiento_estado
        ON operaciones_pendientes (
          estacionamiento_id,
          estado,
          proximo_intento_en,
          id
        )
      ''');
      antigua.execute(
        '''
        INSERT INTO operaciones_pendientes (
          clave,
          estacionamiento_id,
          usuario_id,
          tipo,
          metodo,
          ruta,
          creada_en,
          actualizada_en
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          'offline-entrada-migrada-0001',
          12,
          5,
          'entrada',
          'POST',
          '/api/entradas',
          1787068800,
          1787068800,
        ],
      );
      antigua.execute('PRAGMA user_version = 1');
      antigua.close();

      final db = ParkControlLocalDatabase(NativeDatabase(archivo));
      final operaciones = await db.select(db.operacionesPendientes).get();
      final tablas = await db.customSelect('''
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
              AND name IN ('tarifas_locales', 'movimientos_locales')
            ORDER BY name
          ''').get();

      expect(operaciones, hasLength(1));
      expect(operaciones.single.clave, 'offline-entrada-migrada-0001');
      expect(tablas.map((fila) => fila.read<String>('name')).toList(), [
        'movimientos_locales',
        'tarifas_locales',
      ]);

      await db.close();
    } finally {
      await temporal.delete(recursive: true);
    }
  });
}
