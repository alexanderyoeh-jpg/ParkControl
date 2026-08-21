import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'parkcontrol_local_database.g.dart';

class OperacionesPendientes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clave => text().unique()();
  IntColumn get estacionamientoId => integer()();
  IntColumn get usuarioId => integer()();
  TextColumn get tipo => text()();
  TextColumn get metodo => text()();
  TextColumn get ruta => text()();
  TextColumn get cuerpoJson => text().nullable()();
  IntColumn get versionFormato => integer().withDefault(const Constant(1))();
  TextColumn get estado => text().withDefault(const Constant('pendiente'))();
  IntColumn get intentos => integer().withDefault(const Constant(0))();
  TextColumn get ultimoError => text().nullable()();
  DateTimeColumn get proximoIntentoEn => dateTime().nullable()();
  DateTimeColumn get creadaEn => dateTime()();
  DateTimeColumn get actualizadaEn => dateTime()();
}

class TarifasLocales extends Table {
  IntColumn get estacionamientoId => integer()();
  IntColumn get tarifaServidorId => integer().nullable()();
  RealColumn get tarifaPorMinuto => real()();
  DateTimeColumn get servidorFecha => dateTime().nullable()();
  DateTimeColumn get sincronizadaEn => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {estacionamientoId};
}

class MovimientosLocales extends Table {
  TextColumn get claveLocal => text()();
  IntColumn get estacionamientoId => integer()();
  IntColumn get servidorId => integer().nullable()();
  TextColumn get patente => text()();
  TextColumn get tipo => text()();
  TextColumn get color => text()();
  TextColumn get observacion => text().withDefault(const Constant(''))();
  DateTimeColumn get horaEntrada => dateTime()();
  IntColumn get versionServidor => integer().nullable()();
  TextColumn get estado => text().withDefault(const Constant('dentro'))();
  TextColumn get estadoSincronizacion =>
      text().withDefault(const Constant('confirmado'))();
  DateTimeColumn get creadaEn => dateTime()();
  DateTimeColumn get actualizadaEn => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {claveLocal};
}

@DriftDatabase(
  tables: [OperacionesPendientes, TarifasLocales, MovimientosLocales],
)
class ParkControlLocalDatabase extends _$ParkControlLocalDatabase {
  ParkControlLocalDatabase(super.executor);

  ParkControlLocalDatabase.predeterminada()
    : super(
        driftDatabase(
          name: 'parkcontrol_offline',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement('''
            CREATE INDEX idx_cola_estacionamiento_estado
            ON operaciones_pendientes (
              estacionamiento_id,
              estado,
              proximo_intento_en,
              id
            )
          ''');
      await _crearIndicesCache();
    },
    onUpgrade: (migrator, desde, hasta) async {
      if (desde < 2) {
        await migrator.createTable(tarifasLocales);
        await migrator.createTable(movimientosLocales);
        await _crearIndicesCache();
      }
    },
    beforeOpen: (detalles) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _crearIndicesCache() async {
    await customStatement('''
      CREATE INDEX idx_movimientos_locales_estacionamiento_estado
      ON movimientos_locales (
        estacionamiento_id,
        estado,
        estado_sincronizacion,
        hora_entrada
      )
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX idx_movimientos_locales_servidor
      ON movimientos_locales (estacionamiento_id, servidor_id)
      WHERE servidor_id IS NOT NULL
    ''');
  }
}
