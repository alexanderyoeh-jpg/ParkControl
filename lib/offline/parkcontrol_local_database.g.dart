// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parkcontrol_local_database.dart';

// ignore_for_file: type=lint
class $OperacionesPendientesTable extends OperacionesPendientes
    with TableInfo<$OperacionesPendientesTable, OperacionesPendiente> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OperacionesPendientesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _claveMeta = const VerificationMeta('clave');
  @override
  late final GeneratedColumn<String> clave = GeneratedColumn<String>(
    'clave',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _estacionamientoIdMeta = const VerificationMeta(
    'estacionamientoId',
  );
  @override
  late final GeneratedColumn<int> estacionamientoId = GeneratedColumn<int>(
    'estacionamiento_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usuarioIdMeta = const VerificationMeta(
    'usuarioId',
  );
  @override
  late final GeneratedColumn<int> usuarioId = GeneratedColumn<int>(
    'usuario_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tipoMeta = const VerificationMeta('tipo');
  @override
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metodoMeta = const VerificationMeta('metodo');
  @override
  late final GeneratedColumn<String> metodo = GeneratedColumn<String>(
    'metodo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rutaMeta = const VerificationMeta('ruta');
  @override
  late final GeneratedColumn<String> ruta = GeneratedColumn<String>(
    'ruta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cuerpoJsonMeta = const VerificationMeta(
    'cuerpoJson',
  );
  @override
  late final GeneratedColumn<String> cuerpoJson = GeneratedColumn<String>(
    'cuerpo_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionFormatoMeta = const VerificationMeta(
    'versionFormato',
  );
  @override
  late final GeneratedColumn<int> versionFormato = GeneratedColumn<int>(
    'version_formato',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _estadoMeta = const VerificationMeta('estado');
  @override
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
    'estado',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pendiente'),
  );
  static const VerificationMeta _intentosMeta = const VerificationMeta(
    'intentos',
  );
  @override
  late final GeneratedColumn<int> intentos = GeneratedColumn<int>(
    'intentos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ultimoErrorMeta = const VerificationMeta(
    'ultimoError',
  );
  @override
  late final GeneratedColumn<String> ultimoError = GeneratedColumn<String>(
    'ultimo_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _proximoIntentoEnMeta = const VerificationMeta(
    'proximoIntentoEn',
  );
  @override
  late final GeneratedColumn<DateTime> proximoIntentoEn =
      GeneratedColumn<DateTime>(
        'proximo_intento_en',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _creadaEnMeta = const VerificationMeta(
    'creadaEn',
  );
  @override
  late final GeneratedColumn<DateTime> creadaEn = GeneratedColumn<DateTime>(
    'creada_en',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualizadaEnMeta = const VerificationMeta(
    'actualizadaEn',
  );
  @override
  late final GeneratedColumn<DateTime> actualizadaEn =
      GeneratedColumn<DateTime>(
        'actualizada_en',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clave,
    estacionamientoId,
    usuarioId,
    tipo,
    metodo,
    ruta,
    cuerpoJson,
    versionFormato,
    estado,
    intentos,
    ultimoError,
    proximoIntentoEn,
    creadaEn,
    actualizadaEn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'operaciones_pendientes';
  @override
  VerificationContext validateIntegrity(
    Insertable<OperacionesPendiente> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('clave')) {
      context.handle(
        _claveMeta,
        clave.isAcceptableOrUnknown(data['clave']!, _claveMeta),
      );
    } else if (isInserting) {
      context.missing(_claveMeta);
    }
    if (data.containsKey('estacionamiento_id')) {
      context.handle(
        _estacionamientoIdMeta,
        estacionamientoId.isAcceptableOrUnknown(
          data['estacionamiento_id']!,
          _estacionamientoIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_estacionamientoIdMeta);
    }
    if (data.containsKey('usuario_id')) {
      context.handle(
        _usuarioIdMeta,
        usuarioId.isAcceptableOrUnknown(data['usuario_id']!, _usuarioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_usuarioIdMeta);
    }
    if (data.containsKey('tipo')) {
      context.handle(
        _tipoMeta,
        tipo.isAcceptableOrUnknown(data['tipo']!, _tipoMeta),
      );
    } else if (isInserting) {
      context.missing(_tipoMeta);
    }
    if (data.containsKey('metodo')) {
      context.handle(
        _metodoMeta,
        metodo.isAcceptableOrUnknown(data['metodo']!, _metodoMeta),
      );
    } else if (isInserting) {
      context.missing(_metodoMeta);
    }
    if (data.containsKey('ruta')) {
      context.handle(
        _rutaMeta,
        ruta.isAcceptableOrUnknown(data['ruta']!, _rutaMeta),
      );
    } else if (isInserting) {
      context.missing(_rutaMeta);
    }
    if (data.containsKey('cuerpo_json')) {
      context.handle(
        _cuerpoJsonMeta,
        cuerpoJson.isAcceptableOrUnknown(data['cuerpo_json']!, _cuerpoJsonMeta),
      );
    }
    if (data.containsKey('version_formato')) {
      context.handle(
        _versionFormatoMeta,
        versionFormato.isAcceptableOrUnknown(
          data['version_formato']!,
          _versionFormatoMeta,
        ),
      );
    }
    if (data.containsKey('estado')) {
      context.handle(
        _estadoMeta,
        estado.isAcceptableOrUnknown(data['estado']!, _estadoMeta),
      );
    }
    if (data.containsKey('intentos')) {
      context.handle(
        _intentosMeta,
        intentos.isAcceptableOrUnknown(data['intentos']!, _intentosMeta),
      );
    }
    if (data.containsKey('ultimo_error')) {
      context.handle(
        _ultimoErrorMeta,
        ultimoError.isAcceptableOrUnknown(
          data['ultimo_error']!,
          _ultimoErrorMeta,
        ),
      );
    }
    if (data.containsKey('proximo_intento_en')) {
      context.handle(
        _proximoIntentoEnMeta,
        proximoIntentoEn.isAcceptableOrUnknown(
          data['proximo_intento_en']!,
          _proximoIntentoEnMeta,
        ),
      );
    }
    if (data.containsKey('creada_en')) {
      context.handle(
        _creadaEnMeta,
        creadaEn.isAcceptableOrUnknown(data['creada_en']!, _creadaEnMeta),
      );
    } else if (isInserting) {
      context.missing(_creadaEnMeta);
    }
    if (data.containsKey('actualizada_en')) {
      context.handle(
        _actualizadaEnMeta,
        actualizadaEn.isAcceptableOrUnknown(
          data['actualizada_en']!,
          _actualizadaEnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualizadaEnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OperacionesPendiente map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OperacionesPendiente(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      clave: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clave'],
      )!,
      estacionamientoId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estacionamiento_id'],
      )!,
      usuarioId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}usuario_id'],
      )!,
      tipo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tipo'],
      )!,
      metodo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metodo'],
      )!,
      ruta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ruta'],
      )!,
      cuerpoJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cuerpo_json'],
      ),
      versionFormato: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_formato'],
      )!,
      estado: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}estado'],
      )!,
      intentos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}intentos'],
      )!,
      ultimoError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ultimo_error'],
      ),
      proximoIntentoEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}proximo_intento_en'],
      ),
      creadaEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}creada_en'],
      )!,
      actualizadaEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actualizada_en'],
      )!,
    );
  }

  @override
  $OperacionesPendientesTable createAlias(String alias) {
    return $OperacionesPendientesTable(attachedDatabase, alias);
  }
}

class OperacionesPendiente extends DataClass
    implements Insertable<OperacionesPendiente> {
  final int id;
  final String clave;
  final int estacionamientoId;
  final int usuarioId;
  final String tipo;
  final String metodo;
  final String ruta;
  final String? cuerpoJson;
  final int versionFormato;
  final String estado;
  final int intentos;
  final String? ultimoError;
  final DateTime? proximoIntentoEn;
  final DateTime creadaEn;
  final DateTime actualizadaEn;
  const OperacionesPendiente({
    required this.id,
    required this.clave,
    required this.estacionamientoId,
    required this.usuarioId,
    required this.tipo,
    required this.metodo,
    required this.ruta,
    this.cuerpoJson,
    required this.versionFormato,
    required this.estado,
    required this.intentos,
    this.ultimoError,
    this.proximoIntentoEn,
    required this.creadaEn,
    required this.actualizadaEn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['clave'] = Variable<String>(clave);
    map['estacionamiento_id'] = Variable<int>(estacionamientoId);
    map['usuario_id'] = Variable<int>(usuarioId);
    map['tipo'] = Variable<String>(tipo);
    map['metodo'] = Variable<String>(metodo);
    map['ruta'] = Variable<String>(ruta);
    if (!nullToAbsent || cuerpoJson != null) {
      map['cuerpo_json'] = Variable<String>(cuerpoJson);
    }
    map['version_formato'] = Variable<int>(versionFormato);
    map['estado'] = Variable<String>(estado);
    map['intentos'] = Variable<int>(intentos);
    if (!nullToAbsent || ultimoError != null) {
      map['ultimo_error'] = Variable<String>(ultimoError);
    }
    if (!nullToAbsent || proximoIntentoEn != null) {
      map['proximo_intento_en'] = Variable<DateTime>(proximoIntentoEn);
    }
    map['creada_en'] = Variable<DateTime>(creadaEn);
    map['actualizada_en'] = Variable<DateTime>(actualizadaEn);
    return map;
  }

  OperacionesPendientesCompanion toCompanion(bool nullToAbsent) {
    return OperacionesPendientesCompanion(
      id: Value(id),
      clave: Value(clave),
      estacionamientoId: Value(estacionamientoId),
      usuarioId: Value(usuarioId),
      tipo: Value(tipo),
      metodo: Value(metodo),
      ruta: Value(ruta),
      cuerpoJson: cuerpoJson == null && nullToAbsent
          ? const Value.absent()
          : Value(cuerpoJson),
      versionFormato: Value(versionFormato),
      estado: Value(estado),
      intentos: Value(intentos),
      ultimoError: ultimoError == null && nullToAbsent
          ? const Value.absent()
          : Value(ultimoError),
      proximoIntentoEn: proximoIntentoEn == null && nullToAbsent
          ? const Value.absent()
          : Value(proximoIntentoEn),
      creadaEn: Value(creadaEn),
      actualizadaEn: Value(actualizadaEn),
    );
  }

  factory OperacionesPendiente.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OperacionesPendiente(
      id: serializer.fromJson<int>(json['id']),
      clave: serializer.fromJson<String>(json['clave']),
      estacionamientoId: serializer.fromJson<int>(json['estacionamientoId']),
      usuarioId: serializer.fromJson<int>(json['usuarioId']),
      tipo: serializer.fromJson<String>(json['tipo']),
      metodo: serializer.fromJson<String>(json['metodo']),
      ruta: serializer.fromJson<String>(json['ruta']),
      cuerpoJson: serializer.fromJson<String?>(json['cuerpoJson']),
      versionFormato: serializer.fromJson<int>(json['versionFormato']),
      estado: serializer.fromJson<String>(json['estado']),
      intentos: serializer.fromJson<int>(json['intentos']),
      ultimoError: serializer.fromJson<String?>(json['ultimoError']),
      proximoIntentoEn: serializer.fromJson<DateTime?>(
        json['proximoIntentoEn'],
      ),
      creadaEn: serializer.fromJson<DateTime>(json['creadaEn']),
      actualizadaEn: serializer.fromJson<DateTime>(json['actualizadaEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'clave': serializer.toJson<String>(clave),
      'estacionamientoId': serializer.toJson<int>(estacionamientoId),
      'usuarioId': serializer.toJson<int>(usuarioId),
      'tipo': serializer.toJson<String>(tipo),
      'metodo': serializer.toJson<String>(metodo),
      'ruta': serializer.toJson<String>(ruta),
      'cuerpoJson': serializer.toJson<String?>(cuerpoJson),
      'versionFormato': serializer.toJson<int>(versionFormato),
      'estado': serializer.toJson<String>(estado),
      'intentos': serializer.toJson<int>(intentos),
      'ultimoError': serializer.toJson<String?>(ultimoError),
      'proximoIntentoEn': serializer.toJson<DateTime?>(proximoIntentoEn),
      'creadaEn': serializer.toJson<DateTime>(creadaEn),
      'actualizadaEn': serializer.toJson<DateTime>(actualizadaEn),
    };
  }

  OperacionesPendiente copyWith({
    int? id,
    String? clave,
    int? estacionamientoId,
    int? usuarioId,
    String? tipo,
    String? metodo,
    String? ruta,
    Value<String?> cuerpoJson = const Value.absent(),
    int? versionFormato,
    String? estado,
    int? intentos,
    Value<String?> ultimoError = const Value.absent(),
    Value<DateTime?> proximoIntentoEn = const Value.absent(),
    DateTime? creadaEn,
    DateTime? actualizadaEn,
  }) => OperacionesPendiente(
    id: id ?? this.id,
    clave: clave ?? this.clave,
    estacionamientoId: estacionamientoId ?? this.estacionamientoId,
    usuarioId: usuarioId ?? this.usuarioId,
    tipo: tipo ?? this.tipo,
    metodo: metodo ?? this.metodo,
    ruta: ruta ?? this.ruta,
    cuerpoJson: cuerpoJson.present ? cuerpoJson.value : this.cuerpoJson,
    versionFormato: versionFormato ?? this.versionFormato,
    estado: estado ?? this.estado,
    intentos: intentos ?? this.intentos,
    ultimoError: ultimoError.present ? ultimoError.value : this.ultimoError,
    proximoIntentoEn: proximoIntentoEn.present
        ? proximoIntentoEn.value
        : this.proximoIntentoEn,
    creadaEn: creadaEn ?? this.creadaEn,
    actualizadaEn: actualizadaEn ?? this.actualizadaEn,
  );
  OperacionesPendiente copyWithCompanion(OperacionesPendientesCompanion data) {
    return OperacionesPendiente(
      id: data.id.present ? data.id.value : this.id,
      clave: data.clave.present ? data.clave.value : this.clave,
      estacionamientoId: data.estacionamientoId.present
          ? data.estacionamientoId.value
          : this.estacionamientoId,
      usuarioId: data.usuarioId.present ? data.usuarioId.value : this.usuarioId,
      tipo: data.tipo.present ? data.tipo.value : this.tipo,
      metodo: data.metodo.present ? data.metodo.value : this.metodo,
      ruta: data.ruta.present ? data.ruta.value : this.ruta,
      cuerpoJson: data.cuerpoJson.present
          ? data.cuerpoJson.value
          : this.cuerpoJson,
      versionFormato: data.versionFormato.present
          ? data.versionFormato.value
          : this.versionFormato,
      estado: data.estado.present ? data.estado.value : this.estado,
      intentos: data.intentos.present ? data.intentos.value : this.intentos,
      ultimoError: data.ultimoError.present
          ? data.ultimoError.value
          : this.ultimoError,
      proximoIntentoEn: data.proximoIntentoEn.present
          ? data.proximoIntentoEn.value
          : this.proximoIntentoEn,
      creadaEn: data.creadaEn.present ? data.creadaEn.value : this.creadaEn,
      actualizadaEn: data.actualizadaEn.present
          ? data.actualizadaEn.value
          : this.actualizadaEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OperacionesPendiente(')
          ..write('id: $id, ')
          ..write('clave: $clave, ')
          ..write('estacionamientoId: $estacionamientoId, ')
          ..write('usuarioId: $usuarioId, ')
          ..write('tipo: $tipo, ')
          ..write('metodo: $metodo, ')
          ..write('ruta: $ruta, ')
          ..write('cuerpoJson: $cuerpoJson, ')
          ..write('versionFormato: $versionFormato, ')
          ..write('estado: $estado, ')
          ..write('intentos: $intentos, ')
          ..write('ultimoError: $ultimoError, ')
          ..write('proximoIntentoEn: $proximoIntentoEn, ')
          ..write('creadaEn: $creadaEn, ')
          ..write('actualizadaEn: $actualizadaEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clave,
    estacionamientoId,
    usuarioId,
    tipo,
    metodo,
    ruta,
    cuerpoJson,
    versionFormato,
    estado,
    intentos,
    ultimoError,
    proximoIntentoEn,
    creadaEn,
    actualizadaEn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperacionesPendiente &&
          other.id == this.id &&
          other.clave == this.clave &&
          other.estacionamientoId == this.estacionamientoId &&
          other.usuarioId == this.usuarioId &&
          other.tipo == this.tipo &&
          other.metodo == this.metodo &&
          other.ruta == this.ruta &&
          other.cuerpoJson == this.cuerpoJson &&
          other.versionFormato == this.versionFormato &&
          other.estado == this.estado &&
          other.intentos == this.intentos &&
          other.ultimoError == this.ultimoError &&
          other.proximoIntentoEn == this.proximoIntentoEn &&
          other.creadaEn == this.creadaEn &&
          other.actualizadaEn == this.actualizadaEn);
}

class OperacionesPendientesCompanion
    extends UpdateCompanion<OperacionesPendiente> {
  final Value<int> id;
  final Value<String> clave;
  final Value<int> estacionamientoId;
  final Value<int> usuarioId;
  final Value<String> tipo;
  final Value<String> metodo;
  final Value<String> ruta;
  final Value<String?> cuerpoJson;
  final Value<int> versionFormato;
  final Value<String> estado;
  final Value<int> intentos;
  final Value<String?> ultimoError;
  final Value<DateTime?> proximoIntentoEn;
  final Value<DateTime> creadaEn;
  final Value<DateTime> actualizadaEn;
  const OperacionesPendientesCompanion({
    this.id = const Value.absent(),
    this.clave = const Value.absent(),
    this.estacionamientoId = const Value.absent(),
    this.usuarioId = const Value.absent(),
    this.tipo = const Value.absent(),
    this.metodo = const Value.absent(),
    this.ruta = const Value.absent(),
    this.cuerpoJson = const Value.absent(),
    this.versionFormato = const Value.absent(),
    this.estado = const Value.absent(),
    this.intentos = const Value.absent(),
    this.ultimoError = const Value.absent(),
    this.proximoIntentoEn = const Value.absent(),
    this.creadaEn = const Value.absent(),
    this.actualizadaEn = const Value.absent(),
  });
  OperacionesPendientesCompanion.insert({
    this.id = const Value.absent(),
    required String clave,
    required int estacionamientoId,
    required int usuarioId,
    required String tipo,
    required String metodo,
    required String ruta,
    this.cuerpoJson = const Value.absent(),
    this.versionFormato = const Value.absent(),
    this.estado = const Value.absent(),
    this.intentos = const Value.absent(),
    this.ultimoError = const Value.absent(),
    this.proximoIntentoEn = const Value.absent(),
    required DateTime creadaEn,
    required DateTime actualizadaEn,
  }) : clave = Value(clave),
       estacionamientoId = Value(estacionamientoId),
       usuarioId = Value(usuarioId),
       tipo = Value(tipo),
       metodo = Value(metodo),
       ruta = Value(ruta),
       creadaEn = Value(creadaEn),
       actualizadaEn = Value(actualizadaEn);
  static Insertable<OperacionesPendiente> custom({
    Expression<int>? id,
    Expression<String>? clave,
    Expression<int>? estacionamientoId,
    Expression<int>? usuarioId,
    Expression<String>? tipo,
    Expression<String>? metodo,
    Expression<String>? ruta,
    Expression<String>? cuerpoJson,
    Expression<int>? versionFormato,
    Expression<String>? estado,
    Expression<int>? intentos,
    Expression<String>? ultimoError,
    Expression<DateTime>? proximoIntentoEn,
    Expression<DateTime>? creadaEn,
    Expression<DateTime>? actualizadaEn,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clave != null) 'clave': clave,
      if (estacionamientoId != null) 'estacionamiento_id': estacionamientoId,
      if (usuarioId != null) 'usuario_id': usuarioId,
      if (tipo != null) 'tipo': tipo,
      if (metodo != null) 'metodo': metodo,
      if (ruta != null) 'ruta': ruta,
      if (cuerpoJson != null) 'cuerpo_json': cuerpoJson,
      if (versionFormato != null) 'version_formato': versionFormato,
      if (estado != null) 'estado': estado,
      if (intentos != null) 'intentos': intentos,
      if (ultimoError != null) 'ultimo_error': ultimoError,
      if (proximoIntentoEn != null) 'proximo_intento_en': proximoIntentoEn,
      if (creadaEn != null) 'creada_en': creadaEn,
      if (actualizadaEn != null) 'actualizada_en': actualizadaEn,
    });
  }

  OperacionesPendientesCompanion copyWith({
    Value<int>? id,
    Value<String>? clave,
    Value<int>? estacionamientoId,
    Value<int>? usuarioId,
    Value<String>? tipo,
    Value<String>? metodo,
    Value<String>? ruta,
    Value<String?>? cuerpoJson,
    Value<int>? versionFormato,
    Value<String>? estado,
    Value<int>? intentos,
    Value<String?>? ultimoError,
    Value<DateTime?>? proximoIntentoEn,
    Value<DateTime>? creadaEn,
    Value<DateTime>? actualizadaEn,
  }) {
    return OperacionesPendientesCompanion(
      id: id ?? this.id,
      clave: clave ?? this.clave,
      estacionamientoId: estacionamientoId ?? this.estacionamientoId,
      usuarioId: usuarioId ?? this.usuarioId,
      tipo: tipo ?? this.tipo,
      metodo: metodo ?? this.metodo,
      ruta: ruta ?? this.ruta,
      cuerpoJson: cuerpoJson ?? this.cuerpoJson,
      versionFormato: versionFormato ?? this.versionFormato,
      estado: estado ?? this.estado,
      intentos: intentos ?? this.intentos,
      ultimoError: ultimoError ?? this.ultimoError,
      proximoIntentoEn: proximoIntentoEn ?? this.proximoIntentoEn,
      creadaEn: creadaEn ?? this.creadaEn,
      actualizadaEn: actualizadaEn ?? this.actualizadaEn,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (clave.present) {
      map['clave'] = Variable<String>(clave.value);
    }
    if (estacionamientoId.present) {
      map['estacionamiento_id'] = Variable<int>(estacionamientoId.value);
    }
    if (usuarioId.present) {
      map['usuario_id'] = Variable<int>(usuarioId.value);
    }
    if (tipo.present) {
      map['tipo'] = Variable<String>(tipo.value);
    }
    if (metodo.present) {
      map['metodo'] = Variable<String>(metodo.value);
    }
    if (ruta.present) {
      map['ruta'] = Variable<String>(ruta.value);
    }
    if (cuerpoJson.present) {
      map['cuerpo_json'] = Variable<String>(cuerpoJson.value);
    }
    if (versionFormato.present) {
      map['version_formato'] = Variable<int>(versionFormato.value);
    }
    if (estado.present) {
      map['estado'] = Variable<String>(estado.value);
    }
    if (intentos.present) {
      map['intentos'] = Variable<int>(intentos.value);
    }
    if (ultimoError.present) {
      map['ultimo_error'] = Variable<String>(ultimoError.value);
    }
    if (proximoIntentoEn.present) {
      map['proximo_intento_en'] = Variable<DateTime>(proximoIntentoEn.value);
    }
    if (creadaEn.present) {
      map['creada_en'] = Variable<DateTime>(creadaEn.value);
    }
    if (actualizadaEn.present) {
      map['actualizada_en'] = Variable<DateTime>(actualizadaEn.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OperacionesPendientesCompanion(')
          ..write('id: $id, ')
          ..write('clave: $clave, ')
          ..write('estacionamientoId: $estacionamientoId, ')
          ..write('usuarioId: $usuarioId, ')
          ..write('tipo: $tipo, ')
          ..write('metodo: $metodo, ')
          ..write('ruta: $ruta, ')
          ..write('cuerpoJson: $cuerpoJson, ')
          ..write('versionFormato: $versionFormato, ')
          ..write('estado: $estado, ')
          ..write('intentos: $intentos, ')
          ..write('ultimoError: $ultimoError, ')
          ..write('proximoIntentoEn: $proximoIntentoEn, ')
          ..write('creadaEn: $creadaEn, ')
          ..write('actualizadaEn: $actualizadaEn')
          ..write(')'))
        .toString();
  }
}

class $TarifasLocalesTable extends TarifasLocales
    with TableInfo<$TarifasLocalesTable, TarifasLocale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TarifasLocalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _estacionamientoIdMeta = const VerificationMeta(
    'estacionamientoId',
  );
  @override
  late final GeneratedColumn<int> estacionamientoId = GeneratedColumn<int>(
    'estacionamiento_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tarifaServidorIdMeta = const VerificationMeta(
    'tarifaServidorId',
  );
  @override
  late final GeneratedColumn<int> tarifaServidorId = GeneratedColumn<int>(
    'tarifa_servidor_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tarifaPorMinutoMeta = const VerificationMeta(
    'tarifaPorMinuto',
  );
  @override
  late final GeneratedColumn<double> tarifaPorMinuto = GeneratedColumn<double>(
    'tarifa_por_minuto',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _servidorFechaMeta = const VerificationMeta(
    'servidorFecha',
  );
  @override
  late final GeneratedColumn<DateTime> servidorFecha =
      GeneratedColumn<DateTime>(
        'servidor_fecha',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sincronizadaEnMeta = const VerificationMeta(
    'sincronizadaEn',
  );
  @override
  late final GeneratedColumn<DateTime> sincronizadaEn =
      GeneratedColumn<DateTime>(
        'sincronizada_en',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    estacionamientoId,
    tarifaServidorId,
    tarifaPorMinuto,
    servidorFecha,
    sincronizadaEn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tarifas_locales';
  @override
  VerificationContext validateIntegrity(
    Insertable<TarifasLocale> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('estacionamiento_id')) {
      context.handle(
        _estacionamientoIdMeta,
        estacionamientoId.isAcceptableOrUnknown(
          data['estacionamiento_id']!,
          _estacionamientoIdMeta,
        ),
      );
    }
    if (data.containsKey('tarifa_servidor_id')) {
      context.handle(
        _tarifaServidorIdMeta,
        tarifaServidorId.isAcceptableOrUnknown(
          data['tarifa_servidor_id']!,
          _tarifaServidorIdMeta,
        ),
      );
    }
    if (data.containsKey('tarifa_por_minuto')) {
      context.handle(
        _tarifaPorMinutoMeta,
        tarifaPorMinuto.isAcceptableOrUnknown(
          data['tarifa_por_minuto']!,
          _tarifaPorMinutoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tarifaPorMinutoMeta);
    }
    if (data.containsKey('servidor_fecha')) {
      context.handle(
        _servidorFechaMeta,
        servidorFecha.isAcceptableOrUnknown(
          data['servidor_fecha']!,
          _servidorFechaMeta,
        ),
      );
    }
    if (data.containsKey('sincronizada_en')) {
      context.handle(
        _sincronizadaEnMeta,
        sincronizadaEn.isAcceptableOrUnknown(
          data['sincronizada_en']!,
          _sincronizadaEnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sincronizadaEnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {estacionamientoId};
  @override
  TarifasLocale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TarifasLocale(
      estacionamientoId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estacionamiento_id'],
      )!,
      tarifaServidorId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tarifa_servidor_id'],
      ),
      tarifaPorMinuto: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tarifa_por_minuto'],
      )!,
      servidorFecha: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}servidor_fecha'],
      ),
      sincronizadaEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sincronizada_en'],
      )!,
    );
  }

  @override
  $TarifasLocalesTable createAlias(String alias) {
    return $TarifasLocalesTable(attachedDatabase, alias);
  }
}

class TarifasLocale extends DataClass implements Insertable<TarifasLocale> {
  final int estacionamientoId;
  final int? tarifaServidorId;
  final double tarifaPorMinuto;
  final DateTime? servidorFecha;
  final DateTime sincronizadaEn;
  const TarifasLocale({
    required this.estacionamientoId,
    this.tarifaServidorId,
    required this.tarifaPorMinuto,
    this.servidorFecha,
    required this.sincronizadaEn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['estacionamiento_id'] = Variable<int>(estacionamientoId);
    if (!nullToAbsent || tarifaServidorId != null) {
      map['tarifa_servidor_id'] = Variable<int>(tarifaServidorId);
    }
    map['tarifa_por_minuto'] = Variable<double>(tarifaPorMinuto);
    if (!nullToAbsent || servidorFecha != null) {
      map['servidor_fecha'] = Variable<DateTime>(servidorFecha);
    }
    map['sincronizada_en'] = Variable<DateTime>(sincronizadaEn);
    return map;
  }

  TarifasLocalesCompanion toCompanion(bool nullToAbsent) {
    return TarifasLocalesCompanion(
      estacionamientoId: Value(estacionamientoId),
      tarifaServidorId: tarifaServidorId == null && nullToAbsent
          ? const Value.absent()
          : Value(tarifaServidorId),
      tarifaPorMinuto: Value(tarifaPorMinuto),
      servidorFecha: servidorFecha == null && nullToAbsent
          ? const Value.absent()
          : Value(servidorFecha),
      sincronizadaEn: Value(sincronizadaEn),
    );
  }

  factory TarifasLocale.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TarifasLocale(
      estacionamientoId: serializer.fromJson<int>(json['estacionamientoId']),
      tarifaServidorId: serializer.fromJson<int?>(json['tarifaServidorId']),
      tarifaPorMinuto: serializer.fromJson<double>(json['tarifaPorMinuto']),
      servidorFecha: serializer.fromJson<DateTime?>(json['servidorFecha']),
      sincronizadaEn: serializer.fromJson<DateTime>(json['sincronizadaEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'estacionamientoId': serializer.toJson<int>(estacionamientoId),
      'tarifaServidorId': serializer.toJson<int?>(tarifaServidorId),
      'tarifaPorMinuto': serializer.toJson<double>(tarifaPorMinuto),
      'servidorFecha': serializer.toJson<DateTime?>(servidorFecha),
      'sincronizadaEn': serializer.toJson<DateTime>(sincronizadaEn),
    };
  }

  TarifasLocale copyWith({
    int? estacionamientoId,
    Value<int?> tarifaServidorId = const Value.absent(),
    double? tarifaPorMinuto,
    Value<DateTime?> servidorFecha = const Value.absent(),
    DateTime? sincronizadaEn,
  }) => TarifasLocale(
    estacionamientoId: estacionamientoId ?? this.estacionamientoId,
    tarifaServidorId: tarifaServidorId.present
        ? tarifaServidorId.value
        : this.tarifaServidorId,
    tarifaPorMinuto: tarifaPorMinuto ?? this.tarifaPorMinuto,
    servidorFecha: servidorFecha.present
        ? servidorFecha.value
        : this.servidorFecha,
    sincronizadaEn: sincronizadaEn ?? this.sincronizadaEn,
  );
  TarifasLocale copyWithCompanion(TarifasLocalesCompanion data) {
    return TarifasLocale(
      estacionamientoId: data.estacionamientoId.present
          ? data.estacionamientoId.value
          : this.estacionamientoId,
      tarifaServidorId: data.tarifaServidorId.present
          ? data.tarifaServidorId.value
          : this.tarifaServidorId,
      tarifaPorMinuto: data.tarifaPorMinuto.present
          ? data.tarifaPorMinuto.value
          : this.tarifaPorMinuto,
      servidorFecha: data.servidorFecha.present
          ? data.servidorFecha.value
          : this.servidorFecha,
      sincronizadaEn: data.sincronizadaEn.present
          ? data.sincronizadaEn.value
          : this.sincronizadaEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TarifasLocale(')
          ..write('estacionamientoId: $estacionamientoId, ')
          ..write('tarifaServidorId: $tarifaServidorId, ')
          ..write('tarifaPorMinuto: $tarifaPorMinuto, ')
          ..write('servidorFecha: $servidorFecha, ')
          ..write('sincronizadaEn: $sincronizadaEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    estacionamientoId,
    tarifaServidorId,
    tarifaPorMinuto,
    servidorFecha,
    sincronizadaEn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TarifasLocale &&
          other.estacionamientoId == this.estacionamientoId &&
          other.tarifaServidorId == this.tarifaServidorId &&
          other.tarifaPorMinuto == this.tarifaPorMinuto &&
          other.servidorFecha == this.servidorFecha &&
          other.sincronizadaEn == this.sincronizadaEn);
}

class TarifasLocalesCompanion extends UpdateCompanion<TarifasLocale> {
  final Value<int> estacionamientoId;
  final Value<int?> tarifaServidorId;
  final Value<double> tarifaPorMinuto;
  final Value<DateTime?> servidorFecha;
  final Value<DateTime> sincronizadaEn;
  const TarifasLocalesCompanion({
    this.estacionamientoId = const Value.absent(),
    this.tarifaServidorId = const Value.absent(),
    this.tarifaPorMinuto = const Value.absent(),
    this.servidorFecha = const Value.absent(),
    this.sincronizadaEn = const Value.absent(),
  });
  TarifasLocalesCompanion.insert({
    this.estacionamientoId = const Value.absent(),
    this.tarifaServidorId = const Value.absent(),
    required double tarifaPorMinuto,
    this.servidorFecha = const Value.absent(),
    required DateTime sincronizadaEn,
  }) : tarifaPorMinuto = Value(tarifaPorMinuto),
       sincronizadaEn = Value(sincronizadaEn);
  static Insertable<TarifasLocale> custom({
    Expression<int>? estacionamientoId,
    Expression<int>? tarifaServidorId,
    Expression<double>? tarifaPorMinuto,
    Expression<DateTime>? servidorFecha,
    Expression<DateTime>? sincronizadaEn,
  }) {
    return RawValuesInsertable({
      if (estacionamientoId != null) 'estacionamiento_id': estacionamientoId,
      if (tarifaServidorId != null) 'tarifa_servidor_id': tarifaServidorId,
      if (tarifaPorMinuto != null) 'tarifa_por_minuto': tarifaPorMinuto,
      if (servidorFecha != null) 'servidor_fecha': servidorFecha,
      if (sincronizadaEn != null) 'sincronizada_en': sincronizadaEn,
    });
  }

  TarifasLocalesCompanion copyWith({
    Value<int>? estacionamientoId,
    Value<int?>? tarifaServidorId,
    Value<double>? tarifaPorMinuto,
    Value<DateTime?>? servidorFecha,
    Value<DateTime>? sincronizadaEn,
  }) {
    return TarifasLocalesCompanion(
      estacionamientoId: estacionamientoId ?? this.estacionamientoId,
      tarifaServidorId: tarifaServidorId ?? this.tarifaServidorId,
      tarifaPorMinuto: tarifaPorMinuto ?? this.tarifaPorMinuto,
      servidorFecha: servidorFecha ?? this.servidorFecha,
      sincronizadaEn: sincronizadaEn ?? this.sincronizadaEn,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (estacionamientoId.present) {
      map['estacionamiento_id'] = Variable<int>(estacionamientoId.value);
    }
    if (tarifaServidorId.present) {
      map['tarifa_servidor_id'] = Variable<int>(tarifaServidorId.value);
    }
    if (tarifaPorMinuto.present) {
      map['tarifa_por_minuto'] = Variable<double>(tarifaPorMinuto.value);
    }
    if (servidorFecha.present) {
      map['servidor_fecha'] = Variable<DateTime>(servidorFecha.value);
    }
    if (sincronizadaEn.present) {
      map['sincronizada_en'] = Variable<DateTime>(sincronizadaEn.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TarifasLocalesCompanion(')
          ..write('estacionamientoId: $estacionamientoId, ')
          ..write('tarifaServidorId: $tarifaServidorId, ')
          ..write('tarifaPorMinuto: $tarifaPorMinuto, ')
          ..write('servidorFecha: $servidorFecha, ')
          ..write('sincronizadaEn: $sincronizadaEn')
          ..write(')'))
        .toString();
  }
}

class $MovimientosLocalesTable extends MovimientosLocales
    with TableInfo<$MovimientosLocalesTable, MovimientosLocale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MovimientosLocalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _claveLocalMeta = const VerificationMeta(
    'claveLocal',
  );
  @override
  late final GeneratedColumn<String> claveLocal = GeneratedColumn<String>(
    'clave_local',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _estacionamientoIdMeta = const VerificationMeta(
    'estacionamientoId',
  );
  @override
  late final GeneratedColumn<int> estacionamientoId = GeneratedColumn<int>(
    'estacionamiento_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _servidorIdMeta = const VerificationMeta(
    'servidorId',
  );
  @override
  late final GeneratedColumn<int> servidorId = GeneratedColumn<int>(
    'servidor_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _patenteMeta = const VerificationMeta(
    'patente',
  );
  @override
  late final GeneratedColumn<String> patente = GeneratedColumn<String>(
    'patente',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tipoMeta = const VerificationMeta('tipo');
  @override
  late final GeneratedColumn<String> tipo = GeneratedColumn<String>(
    'tipo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observacionMeta = const VerificationMeta(
    'observacion',
  );
  @override
  late final GeneratedColumn<String> observacion = GeneratedColumn<String>(
    'observacion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _horaEntradaMeta = const VerificationMeta(
    'horaEntrada',
  );
  @override
  late final GeneratedColumn<DateTime> horaEntrada = GeneratedColumn<DateTime>(
    'hora_entrada',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionServidorMeta = const VerificationMeta(
    'versionServidor',
  );
  @override
  late final GeneratedColumn<int> versionServidor = GeneratedColumn<int>(
    'version_servidor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estadoMeta = const VerificationMeta('estado');
  @override
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
    'estado',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('dentro'),
  );
  static const VerificationMeta _estadoSincronizacionMeta =
      const VerificationMeta('estadoSincronizacion');
  @override
  late final GeneratedColumn<String> estadoSincronizacion =
      GeneratedColumn<String>(
        'estado_sincronizacion',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('confirmado'),
      );
  static const VerificationMeta _creadaEnMeta = const VerificationMeta(
    'creadaEn',
  );
  @override
  late final GeneratedColumn<DateTime> creadaEn = GeneratedColumn<DateTime>(
    'creada_en',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualizadaEnMeta = const VerificationMeta(
    'actualizadaEn',
  );
  @override
  late final GeneratedColumn<DateTime> actualizadaEn =
      GeneratedColumn<DateTime>(
        'actualizada_en',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    claveLocal,
    estacionamientoId,
    servidorId,
    patente,
    tipo,
    color,
    observacion,
    horaEntrada,
    versionServidor,
    estado,
    estadoSincronizacion,
    creadaEn,
    actualizadaEn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'movimientos_locales';
  @override
  VerificationContext validateIntegrity(
    Insertable<MovimientosLocale> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('clave_local')) {
      context.handle(
        _claveLocalMeta,
        claveLocal.isAcceptableOrUnknown(data['clave_local']!, _claveLocalMeta),
      );
    } else if (isInserting) {
      context.missing(_claveLocalMeta);
    }
    if (data.containsKey('estacionamiento_id')) {
      context.handle(
        _estacionamientoIdMeta,
        estacionamientoId.isAcceptableOrUnknown(
          data['estacionamiento_id']!,
          _estacionamientoIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_estacionamientoIdMeta);
    }
    if (data.containsKey('servidor_id')) {
      context.handle(
        _servidorIdMeta,
        servidorId.isAcceptableOrUnknown(data['servidor_id']!, _servidorIdMeta),
      );
    }
    if (data.containsKey('patente')) {
      context.handle(
        _patenteMeta,
        patente.isAcceptableOrUnknown(data['patente']!, _patenteMeta),
      );
    } else if (isInserting) {
      context.missing(_patenteMeta);
    }
    if (data.containsKey('tipo')) {
      context.handle(
        _tipoMeta,
        tipo.isAcceptableOrUnknown(data['tipo']!, _tipoMeta),
      );
    } else if (isInserting) {
      context.missing(_tipoMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('observacion')) {
      context.handle(
        _observacionMeta,
        observacion.isAcceptableOrUnknown(
          data['observacion']!,
          _observacionMeta,
        ),
      );
    }
    if (data.containsKey('hora_entrada')) {
      context.handle(
        _horaEntradaMeta,
        horaEntrada.isAcceptableOrUnknown(
          data['hora_entrada']!,
          _horaEntradaMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_horaEntradaMeta);
    }
    if (data.containsKey('version_servidor')) {
      context.handle(
        _versionServidorMeta,
        versionServidor.isAcceptableOrUnknown(
          data['version_servidor']!,
          _versionServidorMeta,
        ),
      );
    }
    if (data.containsKey('estado')) {
      context.handle(
        _estadoMeta,
        estado.isAcceptableOrUnknown(data['estado']!, _estadoMeta),
      );
    }
    if (data.containsKey('estado_sincronizacion')) {
      context.handle(
        _estadoSincronizacionMeta,
        estadoSincronizacion.isAcceptableOrUnknown(
          data['estado_sincronizacion']!,
          _estadoSincronizacionMeta,
        ),
      );
    }
    if (data.containsKey('creada_en')) {
      context.handle(
        _creadaEnMeta,
        creadaEn.isAcceptableOrUnknown(data['creada_en']!, _creadaEnMeta),
      );
    } else if (isInserting) {
      context.missing(_creadaEnMeta);
    }
    if (data.containsKey('actualizada_en')) {
      context.handle(
        _actualizadaEnMeta,
        actualizadaEn.isAcceptableOrUnknown(
          data['actualizada_en']!,
          _actualizadaEnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualizadaEnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {claveLocal};
  @override
  MovimientosLocale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MovimientosLocale(
      claveLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clave_local'],
      )!,
      estacionamientoId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estacionamiento_id'],
      )!,
      servidorId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}servidor_id'],
      ),
      patente: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patente'],
      )!,
      tipo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tipo'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      observacion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observacion'],
      )!,
      horaEntrada: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hora_entrada'],
      )!,
      versionServidor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_servidor'],
      ),
      estado: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}estado'],
      )!,
      estadoSincronizacion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}estado_sincronizacion'],
      )!,
      creadaEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}creada_en'],
      )!,
      actualizadaEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actualizada_en'],
      )!,
    );
  }

  @override
  $MovimientosLocalesTable createAlias(String alias) {
    return $MovimientosLocalesTable(attachedDatabase, alias);
  }
}

class MovimientosLocale extends DataClass
    implements Insertable<MovimientosLocale> {
  final String claveLocal;
  final int estacionamientoId;
  final int? servidorId;
  final String patente;
  final String tipo;
  final String color;
  final String observacion;
  final DateTime horaEntrada;
  final int? versionServidor;
  final String estado;
  final String estadoSincronizacion;
  final DateTime creadaEn;
  final DateTime actualizadaEn;
  const MovimientosLocale({
    required this.claveLocal,
    required this.estacionamientoId,
    this.servidorId,
    required this.patente,
    required this.tipo,
    required this.color,
    required this.observacion,
    required this.horaEntrada,
    this.versionServidor,
    required this.estado,
    required this.estadoSincronizacion,
    required this.creadaEn,
    required this.actualizadaEn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['clave_local'] = Variable<String>(claveLocal);
    map['estacionamiento_id'] = Variable<int>(estacionamientoId);
    if (!nullToAbsent || servidorId != null) {
      map['servidor_id'] = Variable<int>(servidorId);
    }
    map['patente'] = Variable<String>(patente);
    map['tipo'] = Variable<String>(tipo);
    map['color'] = Variable<String>(color);
    map['observacion'] = Variable<String>(observacion);
    map['hora_entrada'] = Variable<DateTime>(horaEntrada);
    if (!nullToAbsent || versionServidor != null) {
      map['version_servidor'] = Variable<int>(versionServidor);
    }
    map['estado'] = Variable<String>(estado);
    map['estado_sincronizacion'] = Variable<String>(estadoSincronizacion);
    map['creada_en'] = Variable<DateTime>(creadaEn);
    map['actualizada_en'] = Variable<DateTime>(actualizadaEn);
    return map;
  }

  MovimientosLocalesCompanion toCompanion(bool nullToAbsent) {
    return MovimientosLocalesCompanion(
      claveLocal: Value(claveLocal),
      estacionamientoId: Value(estacionamientoId),
      servidorId: servidorId == null && nullToAbsent
          ? const Value.absent()
          : Value(servidorId),
      patente: Value(patente),
      tipo: Value(tipo),
      color: Value(color),
      observacion: Value(observacion),
      horaEntrada: Value(horaEntrada),
      versionServidor: versionServidor == null && nullToAbsent
          ? const Value.absent()
          : Value(versionServidor),
      estado: Value(estado),
      estadoSincronizacion: Value(estadoSincronizacion),
      creadaEn: Value(creadaEn),
      actualizadaEn: Value(actualizadaEn),
    );
  }

  factory MovimientosLocale.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MovimientosLocale(
      claveLocal: serializer.fromJson<String>(json['claveLocal']),
      estacionamientoId: serializer.fromJson<int>(json['estacionamientoId']),
      servidorId: serializer.fromJson<int?>(json['servidorId']),
      patente: serializer.fromJson<String>(json['patente']),
      tipo: serializer.fromJson<String>(json['tipo']),
      color: serializer.fromJson<String>(json['color']),
      observacion: serializer.fromJson<String>(json['observacion']),
      horaEntrada: serializer.fromJson<DateTime>(json['horaEntrada']),
      versionServidor: serializer.fromJson<int?>(json['versionServidor']),
      estado: serializer.fromJson<String>(json['estado']),
      estadoSincronizacion: serializer.fromJson<String>(
        json['estadoSincronizacion'],
      ),
      creadaEn: serializer.fromJson<DateTime>(json['creadaEn']),
      actualizadaEn: serializer.fromJson<DateTime>(json['actualizadaEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'claveLocal': serializer.toJson<String>(claveLocal),
      'estacionamientoId': serializer.toJson<int>(estacionamientoId),
      'servidorId': serializer.toJson<int?>(servidorId),
      'patente': serializer.toJson<String>(patente),
      'tipo': serializer.toJson<String>(tipo),
      'color': serializer.toJson<String>(color),
      'observacion': serializer.toJson<String>(observacion),
      'horaEntrada': serializer.toJson<DateTime>(horaEntrada),
      'versionServidor': serializer.toJson<int?>(versionServidor),
      'estado': serializer.toJson<String>(estado),
      'estadoSincronizacion': serializer.toJson<String>(estadoSincronizacion),
      'creadaEn': serializer.toJson<DateTime>(creadaEn),
      'actualizadaEn': serializer.toJson<DateTime>(actualizadaEn),
    };
  }

  MovimientosLocale copyWith({
    String? claveLocal,
    int? estacionamientoId,
    Value<int?> servidorId = const Value.absent(),
    String? patente,
    String? tipo,
    String? color,
    String? observacion,
    DateTime? horaEntrada,
    Value<int?> versionServidor = const Value.absent(),
    String? estado,
    String? estadoSincronizacion,
    DateTime? creadaEn,
    DateTime? actualizadaEn,
  }) => MovimientosLocale(
    claveLocal: claveLocal ?? this.claveLocal,
    estacionamientoId: estacionamientoId ?? this.estacionamientoId,
    servidorId: servidorId.present ? servidorId.value : this.servidorId,
    patente: patente ?? this.patente,
    tipo: tipo ?? this.tipo,
    color: color ?? this.color,
    observacion: observacion ?? this.observacion,
    horaEntrada: horaEntrada ?? this.horaEntrada,
    versionServidor: versionServidor.present
        ? versionServidor.value
        : this.versionServidor,
    estado: estado ?? this.estado,
    estadoSincronizacion: estadoSincronizacion ?? this.estadoSincronizacion,
    creadaEn: creadaEn ?? this.creadaEn,
    actualizadaEn: actualizadaEn ?? this.actualizadaEn,
  );
  MovimientosLocale copyWithCompanion(MovimientosLocalesCompanion data) {
    return MovimientosLocale(
      claveLocal: data.claveLocal.present
          ? data.claveLocal.value
          : this.claveLocal,
      estacionamientoId: data.estacionamientoId.present
          ? data.estacionamientoId.value
          : this.estacionamientoId,
      servidorId: data.servidorId.present
          ? data.servidorId.value
          : this.servidorId,
      patente: data.patente.present ? data.patente.value : this.patente,
      tipo: data.tipo.present ? data.tipo.value : this.tipo,
      color: data.color.present ? data.color.value : this.color,
      observacion: data.observacion.present
          ? data.observacion.value
          : this.observacion,
      horaEntrada: data.horaEntrada.present
          ? data.horaEntrada.value
          : this.horaEntrada,
      versionServidor: data.versionServidor.present
          ? data.versionServidor.value
          : this.versionServidor,
      estado: data.estado.present ? data.estado.value : this.estado,
      estadoSincronizacion: data.estadoSincronizacion.present
          ? data.estadoSincronizacion.value
          : this.estadoSincronizacion,
      creadaEn: data.creadaEn.present ? data.creadaEn.value : this.creadaEn,
      actualizadaEn: data.actualizadaEn.present
          ? data.actualizadaEn.value
          : this.actualizadaEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MovimientosLocale(')
          ..write('claveLocal: $claveLocal, ')
          ..write('estacionamientoId: $estacionamientoId, ')
          ..write('servidorId: $servidorId, ')
          ..write('patente: $patente, ')
          ..write('tipo: $tipo, ')
          ..write('color: $color, ')
          ..write('observacion: $observacion, ')
          ..write('horaEntrada: $horaEntrada, ')
          ..write('versionServidor: $versionServidor, ')
          ..write('estado: $estado, ')
          ..write('estadoSincronizacion: $estadoSincronizacion, ')
          ..write('creadaEn: $creadaEn, ')
          ..write('actualizadaEn: $actualizadaEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    claveLocal,
    estacionamientoId,
    servidorId,
    patente,
    tipo,
    color,
    observacion,
    horaEntrada,
    versionServidor,
    estado,
    estadoSincronizacion,
    creadaEn,
    actualizadaEn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MovimientosLocale &&
          other.claveLocal == this.claveLocal &&
          other.estacionamientoId == this.estacionamientoId &&
          other.servidorId == this.servidorId &&
          other.patente == this.patente &&
          other.tipo == this.tipo &&
          other.color == this.color &&
          other.observacion == this.observacion &&
          other.horaEntrada == this.horaEntrada &&
          other.versionServidor == this.versionServidor &&
          other.estado == this.estado &&
          other.estadoSincronizacion == this.estadoSincronizacion &&
          other.creadaEn == this.creadaEn &&
          other.actualizadaEn == this.actualizadaEn);
}

class MovimientosLocalesCompanion extends UpdateCompanion<MovimientosLocale> {
  final Value<String> claveLocal;
  final Value<int> estacionamientoId;
  final Value<int?> servidorId;
  final Value<String> patente;
  final Value<String> tipo;
  final Value<String> color;
  final Value<String> observacion;
  final Value<DateTime> horaEntrada;
  final Value<int?> versionServidor;
  final Value<String> estado;
  final Value<String> estadoSincronizacion;
  final Value<DateTime> creadaEn;
  final Value<DateTime> actualizadaEn;
  final Value<int> rowid;
  const MovimientosLocalesCompanion({
    this.claveLocal = const Value.absent(),
    this.estacionamientoId = const Value.absent(),
    this.servidorId = const Value.absent(),
    this.patente = const Value.absent(),
    this.tipo = const Value.absent(),
    this.color = const Value.absent(),
    this.observacion = const Value.absent(),
    this.horaEntrada = const Value.absent(),
    this.versionServidor = const Value.absent(),
    this.estado = const Value.absent(),
    this.estadoSincronizacion = const Value.absent(),
    this.creadaEn = const Value.absent(),
    this.actualizadaEn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MovimientosLocalesCompanion.insert({
    required String claveLocal,
    required int estacionamientoId,
    this.servidorId = const Value.absent(),
    required String patente,
    required String tipo,
    required String color,
    this.observacion = const Value.absent(),
    required DateTime horaEntrada,
    this.versionServidor = const Value.absent(),
    this.estado = const Value.absent(),
    this.estadoSincronizacion = const Value.absent(),
    required DateTime creadaEn,
    required DateTime actualizadaEn,
    this.rowid = const Value.absent(),
  }) : claveLocal = Value(claveLocal),
       estacionamientoId = Value(estacionamientoId),
       patente = Value(patente),
       tipo = Value(tipo),
       color = Value(color),
       horaEntrada = Value(horaEntrada),
       creadaEn = Value(creadaEn),
       actualizadaEn = Value(actualizadaEn);
  static Insertable<MovimientosLocale> custom({
    Expression<String>? claveLocal,
    Expression<int>? estacionamientoId,
    Expression<int>? servidorId,
    Expression<String>? patente,
    Expression<String>? tipo,
    Expression<String>? color,
    Expression<String>? observacion,
    Expression<DateTime>? horaEntrada,
    Expression<int>? versionServidor,
    Expression<String>? estado,
    Expression<String>? estadoSincronizacion,
    Expression<DateTime>? creadaEn,
    Expression<DateTime>? actualizadaEn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (claveLocal != null) 'clave_local': claveLocal,
      if (estacionamientoId != null) 'estacionamiento_id': estacionamientoId,
      if (servidorId != null) 'servidor_id': servidorId,
      if (patente != null) 'patente': patente,
      if (tipo != null) 'tipo': tipo,
      if (color != null) 'color': color,
      if (observacion != null) 'observacion': observacion,
      if (horaEntrada != null) 'hora_entrada': horaEntrada,
      if (versionServidor != null) 'version_servidor': versionServidor,
      if (estado != null) 'estado': estado,
      if (estadoSincronizacion != null)
        'estado_sincronizacion': estadoSincronizacion,
      if (creadaEn != null) 'creada_en': creadaEn,
      if (actualizadaEn != null) 'actualizada_en': actualizadaEn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MovimientosLocalesCompanion copyWith({
    Value<String>? claveLocal,
    Value<int>? estacionamientoId,
    Value<int?>? servidorId,
    Value<String>? patente,
    Value<String>? tipo,
    Value<String>? color,
    Value<String>? observacion,
    Value<DateTime>? horaEntrada,
    Value<int?>? versionServidor,
    Value<String>? estado,
    Value<String>? estadoSincronizacion,
    Value<DateTime>? creadaEn,
    Value<DateTime>? actualizadaEn,
    Value<int>? rowid,
  }) {
    return MovimientosLocalesCompanion(
      claveLocal: claveLocal ?? this.claveLocal,
      estacionamientoId: estacionamientoId ?? this.estacionamientoId,
      servidorId: servidorId ?? this.servidorId,
      patente: patente ?? this.patente,
      tipo: tipo ?? this.tipo,
      color: color ?? this.color,
      observacion: observacion ?? this.observacion,
      horaEntrada: horaEntrada ?? this.horaEntrada,
      versionServidor: versionServidor ?? this.versionServidor,
      estado: estado ?? this.estado,
      estadoSincronizacion: estadoSincronizacion ?? this.estadoSincronizacion,
      creadaEn: creadaEn ?? this.creadaEn,
      actualizadaEn: actualizadaEn ?? this.actualizadaEn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (claveLocal.present) {
      map['clave_local'] = Variable<String>(claveLocal.value);
    }
    if (estacionamientoId.present) {
      map['estacionamiento_id'] = Variable<int>(estacionamientoId.value);
    }
    if (servidorId.present) {
      map['servidor_id'] = Variable<int>(servidorId.value);
    }
    if (patente.present) {
      map['patente'] = Variable<String>(patente.value);
    }
    if (tipo.present) {
      map['tipo'] = Variable<String>(tipo.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (observacion.present) {
      map['observacion'] = Variable<String>(observacion.value);
    }
    if (horaEntrada.present) {
      map['hora_entrada'] = Variable<DateTime>(horaEntrada.value);
    }
    if (versionServidor.present) {
      map['version_servidor'] = Variable<int>(versionServidor.value);
    }
    if (estado.present) {
      map['estado'] = Variable<String>(estado.value);
    }
    if (estadoSincronizacion.present) {
      map['estado_sincronizacion'] = Variable<String>(
        estadoSincronizacion.value,
      );
    }
    if (creadaEn.present) {
      map['creada_en'] = Variable<DateTime>(creadaEn.value);
    }
    if (actualizadaEn.present) {
      map['actualizada_en'] = Variable<DateTime>(actualizadaEn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MovimientosLocalesCompanion(')
          ..write('claveLocal: $claveLocal, ')
          ..write('estacionamientoId: $estacionamientoId, ')
          ..write('servidorId: $servidorId, ')
          ..write('patente: $patente, ')
          ..write('tipo: $tipo, ')
          ..write('color: $color, ')
          ..write('observacion: $observacion, ')
          ..write('horaEntrada: $horaEntrada, ')
          ..write('versionServidor: $versionServidor, ')
          ..write('estado: $estado, ')
          ..write('estadoSincronizacion: $estadoSincronizacion, ')
          ..write('creadaEn: $creadaEn, ')
          ..write('actualizadaEn: $actualizadaEn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ParkControlLocalDatabase extends GeneratedDatabase {
  _$ParkControlLocalDatabase(QueryExecutor e) : super(e);
  $ParkControlLocalDatabaseManager get managers =>
      $ParkControlLocalDatabaseManager(this);
  late final $OperacionesPendientesTable operacionesPendientes =
      $OperacionesPendientesTable(this);
  late final $TarifasLocalesTable tarifasLocales = $TarifasLocalesTable(this);
  late final $MovimientosLocalesTable movimientosLocales =
      $MovimientosLocalesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    operacionesPendientes,
    tarifasLocales,
    movimientosLocales,
  ];
}

typedef $$OperacionesPendientesTableCreateCompanionBuilder =
    OperacionesPendientesCompanion Function({
      Value<int> id,
      required String clave,
      required int estacionamientoId,
      required int usuarioId,
      required String tipo,
      required String metodo,
      required String ruta,
      Value<String?> cuerpoJson,
      Value<int> versionFormato,
      Value<String> estado,
      Value<int> intentos,
      Value<String?> ultimoError,
      Value<DateTime?> proximoIntentoEn,
      required DateTime creadaEn,
      required DateTime actualizadaEn,
    });
typedef $$OperacionesPendientesTableUpdateCompanionBuilder =
    OperacionesPendientesCompanion Function({
      Value<int> id,
      Value<String> clave,
      Value<int> estacionamientoId,
      Value<int> usuarioId,
      Value<String> tipo,
      Value<String> metodo,
      Value<String> ruta,
      Value<String?> cuerpoJson,
      Value<int> versionFormato,
      Value<String> estado,
      Value<int> intentos,
      Value<String?> ultimoError,
      Value<DateTime?> proximoIntentoEn,
      Value<DateTime> creadaEn,
      Value<DateTime> actualizadaEn,
    });

class $$OperacionesPendientesTableFilterComposer
    extends Composer<_$ParkControlLocalDatabase, $OperacionesPendientesTable> {
  $$OperacionesPendientesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clave => $composableBuilder(
    column: $table.clave,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usuarioId => $composableBuilder(
    column: $table.usuarioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tipo => $composableBuilder(
    column: $table.tipo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metodo => $composableBuilder(
    column: $table.metodo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruta => $composableBuilder(
    column: $table.ruta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cuerpoJson => $composableBuilder(
    column: $table.cuerpoJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionFormato => $composableBuilder(
    column: $table.versionFormato,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intentos => $composableBuilder(
    column: $table.intentos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ultimoError => $composableBuilder(
    column: $table.ultimoError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get proximoIntentoEn => $composableBuilder(
    column: $table.proximoIntentoEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get creadaEn => $composableBuilder(
    column: $table.creadaEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OperacionesPendientesTableOrderingComposer
    extends Composer<_$ParkControlLocalDatabase, $OperacionesPendientesTable> {
  $$OperacionesPendientesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clave => $composableBuilder(
    column: $table.clave,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usuarioId => $composableBuilder(
    column: $table.usuarioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tipo => $composableBuilder(
    column: $table.tipo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metodo => $composableBuilder(
    column: $table.metodo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruta => $composableBuilder(
    column: $table.ruta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cuerpoJson => $composableBuilder(
    column: $table.cuerpoJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionFormato => $composableBuilder(
    column: $table.versionFormato,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intentos => $composableBuilder(
    column: $table.intentos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ultimoError => $composableBuilder(
    column: $table.ultimoError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get proximoIntentoEn => $composableBuilder(
    column: $table.proximoIntentoEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get creadaEn => $composableBuilder(
    column: $table.creadaEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OperacionesPendientesTableAnnotationComposer
    extends Composer<_$ParkControlLocalDatabase, $OperacionesPendientesTable> {
  $$OperacionesPendientesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clave =>
      $composableBuilder(column: $table.clave, builder: (column) => column);

  GeneratedColumn<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get usuarioId =>
      $composableBuilder(column: $table.usuarioId, builder: (column) => column);

  GeneratedColumn<String> get tipo =>
      $composableBuilder(column: $table.tipo, builder: (column) => column);

  GeneratedColumn<String> get metodo =>
      $composableBuilder(column: $table.metodo, builder: (column) => column);

  GeneratedColumn<String> get ruta =>
      $composableBuilder(column: $table.ruta, builder: (column) => column);

  GeneratedColumn<String> get cuerpoJson => $composableBuilder(
    column: $table.cuerpoJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get versionFormato => $composableBuilder(
    column: $table.versionFormato,
    builder: (column) => column,
  );

  GeneratedColumn<String> get estado =>
      $composableBuilder(column: $table.estado, builder: (column) => column);

  GeneratedColumn<int> get intentos =>
      $composableBuilder(column: $table.intentos, builder: (column) => column);

  GeneratedColumn<String> get ultimoError => $composableBuilder(
    column: $table.ultimoError,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get proximoIntentoEn => $composableBuilder(
    column: $table.proximoIntentoEn,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get creadaEn =>
      $composableBuilder(column: $table.creadaEn, builder: (column) => column);

  GeneratedColumn<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => column,
  );
}

class $$OperacionesPendientesTableTableManager
    extends
        RootTableManager<
          _$ParkControlLocalDatabase,
          $OperacionesPendientesTable,
          OperacionesPendiente,
          $$OperacionesPendientesTableFilterComposer,
          $$OperacionesPendientesTableOrderingComposer,
          $$OperacionesPendientesTableAnnotationComposer,
          $$OperacionesPendientesTableCreateCompanionBuilder,
          $$OperacionesPendientesTableUpdateCompanionBuilder,
          (
            OperacionesPendiente,
            BaseReferences<
              _$ParkControlLocalDatabase,
              $OperacionesPendientesTable,
              OperacionesPendiente
            >,
          ),
          OperacionesPendiente,
          PrefetchHooks Function()
        > {
  $$OperacionesPendientesTableTableManager(
    _$ParkControlLocalDatabase db,
    $OperacionesPendientesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OperacionesPendientesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OperacionesPendientesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OperacionesPendientesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> clave = const Value.absent(),
                Value<int> estacionamientoId = const Value.absent(),
                Value<int> usuarioId = const Value.absent(),
                Value<String> tipo = const Value.absent(),
                Value<String> metodo = const Value.absent(),
                Value<String> ruta = const Value.absent(),
                Value<String?> cuerpoJson = const Value.absent(),
                Value<int> versionFormato = const Value.absent(),
                Value<String> estado = const Value.absent(),
                Value<int> intentos = const Value.absent(),
                Value<String?> ultimoError = const Value.absent(),
                Value<DateTime?> proximoIntentoEn = const Value.absent(),
                Value<DateTime> creadaEn = const Value.absent(),
                Value<DateTime> actualizadaEn = const Value.absent(),
              }) => OperacionesPendientesCompanion(
                id: id,
                clave: clave,
                estacionamientoId: estacionamientoId,
                usuarioId: usuarioId,
                tipo: tipo,
                metodo: metodo,
                ruta: ruta,
                cuerpoJson: cuerpoJson,
                versionFormato: versionFormato,
                estado: estado,
                intentos: intentos,
                ultimoError: ultimoError,
                proximoIntentoEn: proximoIntentoEn,
                creadaEn: creadaEn,
                actualizadaEn: actualizadaEn,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String clave,
                required int estacionamientoId,
                required int usuarioId,
                required String tipo,
                required String metodo,
                required String ruta,
                Value<String?> cuerpoJson = const Value.absent(),
                Value<int> versionFormato = const Value.absent(),
                Value<String> estado = const Value.absent(),
                Value<int> intentos = const Value.absent(),
                Value<String?> ultimoError = const Value.absent(),
                Value<DateTime?> proximoIntentoEn = const Value.absent(),
                required DateTime creadaEn,
                required DateTime actualizadaEn,
              }) => OperacionesPendientesCompanion.insert(
                id: id,
                clave: clave,
                estacionamientoId: estacionamientoId,
                usuarioId: usuarioId,
                tipo: tipo,
                metodo: metodo,
                ruta: ruta,
                cuerpoJson: cuerpoJson,
                versionFormato: versionFormato,
                estado: estado,
                intentos: intentos,
                ultimoError: ultimoError,
                proximoIntentoEn: proximoIntentoEn,
                creadaEn: creadaEn,
                actualizadaEn: actualizadaEn,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OperacionesPendientesTableProcessedTableManager =
    ProcessedTableManager<
      _$ParkControlLocalDatabase,
      $OperacionesPendientesTable,
      OperacionesPendiente,
      $$OperacionesPendientesTableFilterComposer,
      $$OperacionesPendientesTableOrderingComposer,
      $$OperacionesPendientesTableAnnotationComposer,
      $$OperacionesPendientesTableCreateCompanionBuilder,
      $$OperacionesPendientesTableUpdateCompanionBuilder,
      (
        OperacionesPendiente,
        BaseReferences<
          _$ParkControlLocalDatabase,
          $OperacionesPendientesTable,
          OperacionesPendiente
        >,
      ),
      OperacionesPendiente,
      PrefetchHooks Function()
    >;
typedef $$TarifasLocalesTableCreateCompanionBuilder =
    TarifasLocalesCompanion Function({
      Value<int> estacionamientoId,
      Value<int?> tarifaServidorId,
      required double tarifaPorMinuto,
      Value<DateTime?> servidorFecha,
      required DateTime sincronizadaEn,
    });
typedef $$TarifasLocalesTableUpdateCompanionBuilder =
    TarifasLocalesCompanion Function({
      Value<int> estacionamientoId,
      Value<int?> tarifaServidorId,
      Value<double> tarifaPorMinuto,
      Value<DateTime?> servidorFecha,
      Value<DateTime> sincronizadaEn,
    });

class $$TarifasLocalesTableFilterComposer
    extends Composer<_$ParkControlLocalDatabase, $TarifasLocalesTable> {
  $$TarifasLocalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tarifaServidorId => $composableBuilder(
    column: $table.tarifaServidorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tarifaPorMinuto => $composableBuilder(
    column: $table.tarifaPorMinuto,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get servidorFecha => $composableBuilder(
    column: $table.servidorFecha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sincronizadaEn => $composableBuilder(
    column: $table.sincronizadaEn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TarifasLocalesTableOrderingComposer
    extends Composer<_$ParkControlLocalDatabase, $TarifasLocalesTable> {
  $$TarifasLocalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tarifaServidorId => $composableBuilder(
    column: $table.tarifaServidorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tarifaPorMinuto => $composableBuilder(
    column: $table.tarifaPorMinuto,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get servidorFecha => $composableBuilder(
    column: $table.servidorFecha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sincronizadaEn => $composableBuilder(
    column: $table.sincronizadaEn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TarifasLocalesTableAnnotationComposer
    extends Composer<_$ParkControlLocalDatabase, $TarifasLocalesTable> {
  $$TarifasLocalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tarifaServidorId => $composableBuilder(
    column: $table.tarifaServidorId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get tarifaPorMinuto => $composableBuilder(
    column: $table.tarifaPorMinuto,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get servidorFecha => $composableBuilder(
    column: $table.servidorFecha,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sincronizadaEn => $composableBuilder(
    column: $table.sincronizadaEn,
    builder: (column) => column,
  );
}

class $$TarifasLocalesTableTableManager
    extends
        RootTableManager<
          _$ParkControlLocalDatabase,
          $TarifasLocalesTable,
          TarifasLocale,
          $$TarifasLocalesTableFilterComposer,
          $$TarifasLocalesTableOrderingComposer,
          $$TarifasLocalesTableAnnotationComposer,
          $$TarifasLocalesTableCreateCompanionBuilder,
          $$TarifasLocalesTableUpdateCompanionBuilder,
          (
            TarifasLocale,
            BaseReferences<
              _$ParkControlLocalDatabase,
              $TarifasLocalesTable,
              TarifasLocale
            >,
          ),
          TarifasLocale,
          PrefetchHooks Function()
        > {
  $$TarifasLocalesTableTableManager(
    _$ParkControlLocalDatabase db,
    $TarifasLocalesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TarifasLocalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TarifasLocalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TarifasLocalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> estacionamientoId = const Value.absent(),
                Value<int?> tarifaServidorId = const Value.absent(),
                Value<double> tarifaPorMinuto = const Value.absent(),
                Value<DateTime?> servidorFecha = const Value.absent(),
                Value<DateTime> sincronizadaEn = const Value.absent(),
              }) => TarifasLocalesCompanion(
                estacionamientoId: estacionamientoId,
                tarifaServidorId: tarifaServidorId,
                tarifaPorMinuto: tarifaPorMinuto,
                servidorFecha: servidorFecha,
                sincronizadaEn: sincronizadaEn,
              ),
          createCompanionCallback:
              ({
                Value<int> estacionamientoId = const Value.absent(),
                Value<int?> tarifaServidorId = const Value.absent(),
                required double tarifaPorMinuto,
                Value<DateTime?> servidorFecha = const Value.absent(),
                required DateTime sincronizadaEn,
              }) => TarifasLocalesCompanion.insert(
                estacionamientoId: estacionamientoId,
                tarifaServidorId: tarifaServidorId,
                tarifaPorMinuto: tarifaPorMinuto,
                servidorFecha: servidorFecha,
                sincronizadaEn: sincronizadaEn,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TarifasLocalesTableProcessedTableManager =
    ProcessedTableManager<
      _$ParkControlLocalDatabase,
      $TarifasLocalesTable,
      TarifasLocale,
      $$TarifasLocalesTableFilterComposer,
      $$TarifasLocalesTableOrderingComposer,
      $$TarifasLocalesTableAnnotationComposer,
      $$TarifasLocalesTableCreateCompanionBuilder,
      $$TarifasLocalesTableUpdateCompanionBuilder,
      (
        TarifasLocale,
        BaseReferences<
          _$ParkControlLocalDatabase,
          $TarifasLocalesTable,
          TarifasLocale
        >,
      ),
      TarifasLocale,
      PrefetchHooks Function()
    >;
typedef $$MovimientosLocalesTableCreateCompanionBuilder =
    MovimientosLocalesCompanion Function({
      required String claveLocal,
      required int estacionamientoId,
      Value<int?> servidorId,
      required String patente,
      required String tipo,
      required String color,
      Value<String> observacion,
      required DateTime horaEntrada,
      Value<int?> versionServidor,
      Value<String> estado,
      Value<String> estadoSincronizacion,
      required DateTime creadaEn,
      required DateTime actualizadaEn,
      Value<int> rowid,
    });
typedef $$MovimientosLocalesTableUpdateCompanionBuilder =
    MovimientosLocalesCompanion Function({
      Value<String> claveLocal,
      Value<int> estacionamientoId,
      Value<int?> servidorId,
      Value<String> patente,
      Value<String> tipo,
      Value<String> color,
      Value<String> observacion,
      Value<DateTime> horaEntrada,
      Value<int?> versionServidor,
      Value<String> estado,
      Value<String> estadoSincronizacion,
      Value<DateTime> creadaEn,
      Value<DateTime> actualizadaEn,
      Value<int> rowid,
    });

class $$MovimientosLocalesTableFilterComposer
    extends Composer<_$ParkControlLocalDatabase, $MovimientosLocalesTable> {
  $$MovimientosLocalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get claveLocal => $composableBuilder(
    column: $table.claveLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get servidorId => $composableBuilder(
    column: $table.servidorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patente => $composableBuilder(
    column: $table.patente,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tipo => $composableBuilder(
    column: $table.tipo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observacion => $composableBuilder(
    column: $table.observacion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get horaEntrada => $composableBuilder(
    column: $table.horaEntrada,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionServidor => $composableBuilder(
    column: $table.versionServidor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estadoSincronizacion => $composableBuilder(
    column: $table.estadoSincronizacion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get creadaEn => $composableBuilder(
    column: $table.creadaEn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MovimientosLocalesTableOrderingComposer
    extends Composer<_$ParkControlLocalDatabase, $MovimientosLocalesTable> {
  $$MovimientosLocalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get claveLocal => $composableBuilder(
    column: $table.claveLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get servidorId => $composableBuilder(
    column: $table.servidorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patente => $composableBuilder(
    column: $table.patente,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tipo => $composableBuilder(
    column: $table.tipo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observacion => $composableBuilder(
    column: $table.observacion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get horaEntrada => $composableBuilder(
    column: $table.horaEntrada,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionServidor => $composableBuilder(
    column: $table.versionServidor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estadoSincronizacion => $composableBuilder(
    column: $table.estadoSincronizacion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get creadaEn => $composableBuilder(
    column: $table.creadaEn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MovimientosLocalesTableAnnotationComposer
    extends Composer<_$ParkControlLocalDatabase, $MovimientosLocalesTable> {
  $$MovimientosLocalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get claveLocal => $composableBuilder(
    column: $table.claveLocal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estacionamientoId => $composableBuilder(
    column: $table.estacionamientoId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get servidorId => $composableBuilder(
    column: $table.servidorId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get patente =>
      $composableBuilder(column: $table.patente, builder: (column) => column);

  GeneratedColumn<String> get tipo =>
      $composableBuilder(column: $table.tipo, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get observacion => $composableBuilder(
    column: $table.observacion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get horaEntrada => $composableBuilder(
    column: $table.horaEntrada,
    builder: (column) => column,
  );

  GeneratedColumn<int> get versionServidor => $composableBuilder(
    column: $table.versionServidor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get estado =>
      $composableBuilder(column: $table.estado, builder: (column) => column);

  GeneratedColumn<String> get estadoSincronizacion => $composableBuilder(
    column: $table.estadoSincronizacion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get creadaEn =>
      $composableBuilder(column: $table.creadaEn, builder: (column) => column);

  GeneratedColumn<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => column,
  );
}

class $$MovimientosLocalesTableTableManager
    extends
        RootTableManager<
          _$ParkControlLocalDatabase,
          $MovimientosLocalesTable,
          MovimientosLocale,
          $$MovimientosLocalesTableFilterComposer,
          $$MovimientosLocalesTableOrderingComposer,
          $$MovimientosLocalesTableAnnotationComposer,
          $$MovimientosLocalesTableCreateCompanionBuilder,
          $$MovimientosLocalesTableUpdateCompanionBuilder,
          (
            MovimientosLocale,
            BaseReferences<
              _$ParkControlLocalDatabase,
              $MovimientosLocalesTable,
              MovimientosLocale
            >,
          ),
          MovimientosLocale,
          PrefetchHooks Function()
        > {
  $$MovimientosLocalesTableTableManager(
    _$ParkControlLocalDatabase db,
    $MovimientosLocalesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MovimientosLocalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MovimientosLocalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MovimientosLocalesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> claveLocal = const Value.absent(),
                Value<int> estacionamientoId = const Value.absent(),
                Value<int?> servidorId = const Value.absent(),
                Value<String> patente = const Value.absent(),
                Value<String> tipo = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> observacion = const Value.absent(),
                Value<DateTime> horaEntrada = const Value.absent(),
                Value<int?> versionServidor = const Value.absent(),
                Value<String> estado = const Value.absent(),
                Value<String> estadoSincronizacion = const Value.absent(),
                Value<DateTime> creadaEn = const Value.absent(),
                Value<DateTime> actualizadaEn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MovimientosLocalesCompanion(
                claveLocal: claveLocal,
                estacionamientoId: estacionamientoId,
                servidorId: servidorId,
                patente: patente,
                tipo: tipo,
                color: color,
                observacion: observacion,
                horaEntrada: horaEntrada,
                versionServidor: versionServidor,
                estado: estado,
                estadoSincronizacion: estadoSincronizacion,
                creadaEn: creadaEn,
                actualizadaEn: actualizadaEn,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String claveLocal,
                required int estacionamientoId,
                Value<int?> servidorId = const Value.absent(),
                required String patente,
                required String tipo,
                required String color,
                Value<String> observacion = const Value.absent(),
                required DateTime horaEntrada,
                Value<int?> versionServidor = const Value.absent(),
                Value<String> estado = const Value.absent(),
                Value<String> estadoSincronizacion = const Value.absent(),
                required DateTime creadaEn,
                required DateTime actualizadaEn,
                Value<int> rowid = const Value.absent(),
              }) => MovimientosLocalesCompanion.insert(
                claveLocal: claveLocal,
                estacionamientoId: estacionamientoId,
                servidorId: servidorId,
                patente: patente,
                tipo: tipo,
                color: color,
                observacion: observacion,
                horaEntrada: horaEntrada,
                versionServidor: versionServidor,
                estado: estado,
                estadoSincronizacion: estadoSincronizacion,
                creadaEn: creadaEn,
                actualizadaEn: actualizadaEn,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MovimientosLocalesTableProcessedTableManager =
    ProcessedTableManager<
      _$ParkControlLocalDatabase,
      $MovimientosLocalesTable,
      MovimientosLocale,
      $$MovimientosLocalesTableFilterComposer,
      $$MovimientosLocalesTableOrderingComposer,
      $$MovimientosLocalesTableAnnotationComposer,
      $$MovimientosLocalesTableCreateCompanionBuilder,
      $$MovimientosLocalesTableUpdateCompanionBuilder,
      (
        MovimientosLocale,
        BaseReferences<
          _$ParkControlLocalDatabase,
          $MovimientosLocalesTable,
          MovimientosLocale
        >,
      ),
      MovimientosLocale,
      PrefetchHooks Function()
    >;

class $ParkControlLocalDatabaseManager {
  final _$ParkControlLocalDatabase _db;
  $ParkControlLocalDatabaseManager(this._db);
  $$OperacionesPendientesTableTableManager get operacionesPendientes =>
      $$OperacionesPendientesTableTableManager(_db, _db.operacionesPendientes);
  $$TarifasLocalesTableTableManager get tarifasLocales =>
      $$TarifasLocalesTableTableManager(_db, _db.tarifasLocales);
  $$MovimientosLocalesTableTableManager get movimientosLocales =>
      $$MovimientosLocalesTableTableManager(_db, _db.movimientosLocales);
}
