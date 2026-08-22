import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';
import 'cache_operativo_repository.dart';
import 'cola_sincronizacion_repository.dart';
import 'coordinador_sincronizacion.dart';
import 'operaciones_offline_service.dart';
import 'parkcontrol_local_database.dart';
import 'sincronizacion_inicial_service.dart';

class SesionOffline {
  const SesionOffline({
    required this.idSesionLocal,
    required this.usuarioId,
    required this.estacionamientoId,
  });

  final int idSesionLocal;
  final int usuarioId;
  final int estacionamientoId;
}

class ResumenSincronizacionOffline {
  const ResumenSincronizacionOffline({
    required this.pendientes,
    required this.enviando,
    required this.conflictos,
    required this.bloqueadas,
    required this.otras,
    this.proximoIntentoEn,
    this.ultimoMensaje,
  });

  const ResumenSincronizacionOffline.vacio()
    : pendientes = 0,
      enviando = 0,
      conflictos = 0,
      bloqueadas = 0,
      otras = 0,
      proximoIntentoEn = null,
      ultimoMensaje = null;

  final int pendientes;
  final int enviando;
  final int conflictos;
  final int bloqueadas;
  final int otras;
  final DateTime? proximoIntentoEn;
  final String? ultimoMensaje;

  int get totalActivas =>
      pendientes + enviando + conflictos + bloqueadas + otras;
  bool get hayOperaciones => totalActivas > 0;

  /// Un cierre de caja no puede dejar operaciones locales sin confirmación.
  ///
  /// Aunque hoy los estados esperados son pendiente, enviando, conflicto y
  /// bloqueada, también se bloquea cualquier estado desconocido (`otras`) por
  /// seguridad: una operación no completada podría afectar el arqueo cuando
  /// llegue al servidor.
  int get totalQueImpidenCierreCaja => totalActivas;
  bool get impideCierreCaja => totalQueImpidenCierreCaja > 0;
  bool get requiereAtencion => conflictos > 0 || bloqueadas > 0;

  static ResumenSincronizacionOffline desdeOperaciones(
    List<OperacionesPendiente> operaciones,
  ) {
    var pendientes = 0;
    var enviando = 0;
    var conflictos = 0;
    var bloqueadas = 0;
    var otras = 0;
    DateTime? proximoIntentoEn;
    String? ultimoMensaje;
    DateTime? fechaUltimoMensaje;

    for (final operacion in operaciones) {
      switch (operacion.estado) {
        case 'pendiente':
          pendientes++;
          final proximo = operacion.proximoIntentoEn;
          if (proximo != null &&
              (proximoIntentoEn == null ||
                  proximo.isBefore(proximoIntentoEn))) {
            proximoIntentoEn = proximo;
          }
          break;
        case 'enviando':
          enviando++;
          break;
        case 'conflicto':
          conflictos++;
          break;
        case 'bloqueada':
          bloqueadas++;
          break;
        default:
          otras++;
      }

      final mensaje = operacion.ultimoError?.trim();
      if (mensaje != null && mensaje.isNotEmpty) {
        final fecha = operacion.actualizadaEn;
        if (fechaUltimoMensaje == null || fecha.isAfter(fechaUltimoMensaje)) {
          fechaUltimoMensaje = fecha;
          ultimoMensaje = mensaje;
        }
      }
    }

    return ResumenSincronizacionOffline(
      pendientes: pendientes,
      enviando: enviando,
      conflictos: conflictos,
      bloqueadas: bloqueadas,
      otras: otras,
      proximoIntentoEn: proximoIntentoEn,
      ultimoMensaje: ultimoMensaje,
    );
  }
}

class OperacionSincronizacionOffline {
  const OperacionSincronizacionOffline({
    required this.clave,
    required this.tipo,
    required this.metodo,
    required this.ruta,
    required this.estado,
    required this.intentos,
    required this.creadaEn,
    required this.actualizadaEn,
    this.patente,
    this.ultimoError,
    this.proximoIntentoEn,
  });

  final String clave;
  final String tipo;
  final String metodo;
  final String ruta;
  final String estado;
  final int intentos;
  final String? patente;
  final String? ultimoError;
  final DateTime? proximoIntentoEn;
  final DateTime creadaEn;
  final DateTime actualizadaEn;

  bool get requiereAtencion => estado == 'conflicto' || estado == 'bloqueada';

  String get titulo {
    final tipoLegible = switch (tipo) {
      'entrada' => 'Entrada',
      'salida' => 'Salida',
      'modificacion' => 'Modificación',
      'eliminacion' => 'Eliminación',
      _ => tipo,
    };

    final patenteLegible = patente?.trim();
    if (patenteLegible == null || patenteLegible.isEmpty) {
      return tipoLegible;
    }

    return '$tipoLegible · $patenteLegible';
  }

  factory OperacionSincronizacionOffline.desdeOperacion(
    OperacionesPendiente operacion,
  ) {
    return OperacionSincronizacionOffline(
      clave: operacion.clave,
      tipo: operacion.tipo,
      metodo: operacion.metodo,
      ruta: operacion.ruta,
      estado: operacion.estado,
      intentos: operacion.intentos,
      patente: _extraerPatente(operacion.cuerpoJson),
      ultimoError: operacion.ultimoError,
      proximoIntentoEn: operacion.proximoIntentoEn,
      creadaEn: operacion.creadaEn,
      actualizadaEn: operacion.actualizadaEn,
    );
  }

  static String? _extraerPatente(String? cuerpoJson) {
    if (cuerpoJson == null || cuerpoJson.trim().isEmpty) {
      return null;
    }

    try {
      final cuerpo = jsonDecode(cuerpoJson);
      if (cuerpo is! Map<String, dynamic>) {
        return null;
      }

      for (final campo in ['patente', 'patenteNueva', 'patenteActual']) {
        final valor = cuerpo[campo]?.toString().trim();
        if (valor != null && valor.isNotEmpty) {
          return valor.toUpperCase();
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}

class ComprobanteOfflineSincronizado {
  const ComprobanteOfflineSincronizado({
    required this.estacionamientoId,
    required this.usuarioId,
    required this.claveOperacion,
    required this.salida,
    required this.sincronizadoEn,
  });

  final int estacionamientoId;
  final int usuarioId;
  final String claveOperacion;
  final Map<String, dynamic> salida;
  final DateTime sincronizadoEn;

  String get patente => salida['patente']?.toString().toUpperCase() ?? '-';
  int? get folio => _entero(salida['id']);
  double get monto => _numero(salida['monto']);

  Map<String, dynamic> toJson() {
    return {
      'estacionamientoId': estacionamientoId,
      'usuarioId': usuarioId,
      'claveOperacion': claveOperacion,
      'salida': salida,
      'sincronizadoEn': sincronizadoEn.toUtc().toIso8601String(),
    };
  }

  static ComprobanteOfflineSincronizado? fromJson(Object? valor) {
    if (valor is! Map<String, dynamic>) {
      return null;
    }

    final estacionamientoId = _entero(valor['estacionamientoId']);
    final usuarioId = _entero(valor['usuarioId']);
    final claveOperacion = valor['claveOperacion']?.toString().trim();
    final salida = valor['salida'];
    final sincronizadoEn = DateTime.tryParse(
      valor['sincronizadoEn']?.toString() ?? '',
    );

    if (estacionamientoId == null ||
        estacionamientoId <= 0 ||
        usuarioId == null ||
        usuarioId <= 0 ||
        claveOperacion == null ||
        claveOperacion.isEmpty ||
        salida is! Map<String, dynamic> ||
        sincronizadoEn == null) {
      return null;
    }

    return ComprobanteOfflineSincronizado(
      estacionamientoId: estacionamientoId,
      usuarioId: usuarioId,
      claveOperacion: claveOperacion,
      salida: Map<String, dynamic>.from(salida),
      sincronizadoEn: sincronizadoEn,
    );
  }

  static int? _entero(Object? valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num && valor.toInt() == valor) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '');
  }

  static double _numero(Object? valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }
}

class OfflineAppService {
  static final OfflineAppService instancia = OfflineAppService._internal();
  static const String _comprobantesKey =
      'offline_comprobantes_sincronizados_v1';

  OfflineAppService._internal()
    : _db = ParkControlLocalDatabase.predeterminada() {
    _cache = CacheOperativoRepository(_db);
    _cola = ColaSincronizacionRepository(_db);
    _operaciones = OperacionesOfflineService(_db);
    _sincronizacion = SincronizacionInicialService(_cache);
    _coordinador = CoordinadorSincronizacion(
      _cola,
      refrescarCache: sincronizarEstadoInicialSilencioso,
      registrarResultado: _registrarResultadoSincronizacion,
    );
  }

  final ParkControlLocalDatabase _db;
  late final CacheOperativoRepository _cache;
  late final ColaSincronizacionRepository _cola;
  late final OperacionesOfflineService _operaciones;
  late final SincronizacionInicialService _sincronizacion;
  late final CoordinadorSincronizacion _coordinador;
  final Set<String> _contextosConEnviosRestablecidos = <String>{};
  int? _idSesionParaContextosRestaurados;

  Future<SesionOffline> sesionActual() async {
    final contexto = ApiClient.contextoSesionActual;
    final usuarioId = contexto?.usuarioId ?? 1;
    final estacionamientoId = contexto?.estacionamientoId ?? 1;

    return SesionOffline(
      idSesionLocal: contexto?.idSesionLocal ?? 1,
      usuarioId: usuarioId,
      estacionamientoId: estacionamientoId,
    );
  }

  Future<void> sincronizarEstadoInicialSilencioso() async {
    try {
      await _sincronizacion.actualizar();
    } catch (_) {
      // La operación online sigue siendo prioritaria; la caché se usará sólo
      // cuando la red no esté disponible.
    }
  }

  Future<ResumenSincronizacionOffline> resumenSincronizacion() async {
    try {
      final sesion = await sesionActual();
      final operaciones = await _cola.listarActivas(
        estacionamientoId: sesion.estacionamientoId,
        usuarioId: sesion.usuarioId,
      );
      return ResumenSincronizacionOffline.desdeOperaciones(operaciones);
    } catch (_) {
      return const ResumenSincronizacionOffline.vacio();
    }
  }

  Stream<ResumenSincronizacionOffline> observarResumenSincronizacion() async* {
    try {
      final sesion = await sesionActual();
      yield* _cola
          .observarActivas(
            estacionamientoId: sesion.estacionamientoId,
            usuarioId: sesion.usuarioId,
          )
          .map(ResumenSincronizacionOffline.desdeOperaciones);
    } catch (_) {
      yield const ResumenSincronizacionOffline.vacio();
    }
  }

  Stream<List<OperacionSincronizacionOffline>>
  observarOperacionesSincronizacion() async* {
    try {
      final sesion = await sesionActual();
      yield* _cola
          .observarActivas(
            estacionamientoId: sesion.estacionamientoId,
            usuarioId: sesion.usuarioId,
          )
          .map(
            (operaciones) => operaciones
                .map(OperacionSincronizacionOffline.desdeOperacion)
                .toList(growable: false),
          );
    } catch (_) {
      yield const [];
    }
  }

  Future<int> procesarPendientesDisponibles({
    int maximo = 20,
    bool forzarAhora = false,
  }) async {
    final sesion = await sesionActual();
    await _restablecerEnviosInterrumpidosUnaVez(sesion);

    if (forzarAhora) {
      await _cola.reintentarPendientesAhora(
        estacionamientoId: sesion.estacionamientoId,
        usuarioId: sesion.usuarioId,
      );
    }

    return _coordinador.procesarDisponibles(
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
      maximo: maximo,
    );
  }

  Future<List<ComprobanteOfflineSincronizado>>
  comprobantesSincronizadosPendientes() async {
    try {
      final sesion = await sesionActual();
      final comprobantes = await _leerComprobantes();
      return comprobantes
          .where(
            (comprobante) =>
                comprobante.estacionamientoId == sesion.estacionamientoId &&
                comprobante.usuarioId == sesion.usuarioId,
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<int> contarComprobantesSincronizadosPendientes() async {
    final comprobantes = await comprobantesSincronizadosPendientes();
    return comprobantes.length;
  }

  Future<void> marcarComprobanteSincronizadoVisto(String claveOperacion) async {
    final sesion = await sesionActual();
    final clave = claveOperacion.trim();
    final comprobantes = await _leerComprobantes();
    final filtrados = comprobantes
        .where(
          (comprobante) =>
              comprobante.estacionamientoId != sesion.estacionamientoId ||
              comprobante.usuarioId != sesion.usuarioId ||
              comprobante.claveOperacion != clave,
        )
        .toList(growable: false);

    await _guardarComprobantes(filtrados);
  }

  Future<int> reanudarBloqueadasActuales() async {
    final sesion = await sesionActual();
    return _cola.reanudarBloqueadas(
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
    );
  }

  Future<void> _registrarResultadoSincronizacion(
    OperacionesPendiente operacion,
    dynamic respuesta,
  ) async {
    final decoded = jsonDecode(respuesta.body);
    if (decoded is! Map<String, dynamic>) {
      if (operacion.tipo == 'entrada') {
        throw const FormatException(
          'La confirmación de entrada no tiene un formato válido',
        );
      }
      return;
    }

    if (operacion.tipo == 'entrada') {
      final movimiento = decoded['movimiento'];
      if (movimiento is! Map<String, dynamic>) {
        throw const FormatException(
          'La confirmación de entrada no incluye el movimiento',
        );
      }

      final servidorId = _entero(movimiento['id']);
      final versionServidor = _entero(movimiento['version']);
      if (servidorId == null ||
          servidorId < 1 ||
          versionServidor == null ||
          versionServidor < 1) {
        throw const FormatException(
          'La confirmación de entrada contiene identificadores inválidos',
        );
      }

      await _cache.vincularEntradaConfirmada(
        estacionamientoId: operacion.estacionamientoId,
        claveOperacion: operacion.clave,
        servidorId: servidorId,
        versionServidor: versionServidor,
      );
      return;
    }

    if (operacion.tipo != 'salida') {
      return;
    }

    final salida = decoded['salida'];
    if (salida is! Map<String, dynamic>) {
      return;
    }

    final comprobante = ComprobanteOfflineSincronizado(
      estacionamientoId: operacion.estacionamientoId,
      usuarioId: operacion.usuarioId,
      claveOperacion: operacion.clave,
      salida: Map<String, dynamic>.from(salida),
      sincronizadoEn: DateTime.now().toUtc(),
    );

    final comprobantes = await _leerComprobantes();
    final delMismoCajero = <ComprobanteOfflineSincronizado>[
      comprobante,
      ...comprobantes.where(
        (actual) =>
            actual.estacionamientoId == comprobante.estacionamientoId &&
            actual.usuarioId == comprobante.usuarioId &&
            actual.claveOperacion != comprobante.claveOperacion,
      ),
    ].take(30).toList(growable: false);
    final otrosCajeros = comprobantes.where(
      (actual) =>
          actual.estacionamientoId != comprobante.estacionamientoId ||
          actual.usuarioId != comprobante.usuarioId,
    );
    final actualizados = <ComprobanteOfflineSincronizado>[
      ...delMismoCajero,
      ...otrosCajeros,
    ];

    await _guardarComprobantes(actualizados);
  }

  Future<List<ComprobanteOfflineSincronizado>> _leerComprobantes() async {
    final preferencias = await SharedPreferences.getInstance();
    final texto = preferencias.getString(_comprobantesKey);
    if (texto == null || texto.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(texto);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .map(ComprobanteOfflineSincronizado.fromJson)
          .whereType<ComprobanteOfflineSincronizado>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _guardarComprobantes(
    List<ComprobanteOfflineSincronizado> comprobantes,
  ) async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString(
      _comprobantesKey,
      jsonEncode(
        comprobantes
            .map((comprobante) => comprobante.toJson())
            .toList(growable: false),
      ),
    );
  }

  Future<void> descartarConflictoAuditado({
    required OperacionSincronizacionOffline operacion,
    required String motivo,
  }) async {
    final motivoLimpio = motivo.trim();
    if (operacion.estado != 'conflicto') {
      throw const ErrorOperacionOffline(
        'ESTADO_CONFLICTO_REQUERIDO',
        'Sólo se pueden descartar operaciones en conflicto',
      );
    }
    if (motivoLimpio.length < 5 || motivoLimpio.length > 500) {
      throw const ErrorOperacionOffline(
        'MOTIVO_RESOLUCION_INVALIDO',
        'Indica un motivo entre 5 y 500 caracteres',
      );
    }

    final sesion = await sesionActual();
    final respuesta = await ApiClient.post(
      Uri.parse('${ApiConfig.baseUrl}/api/sincronizacion/conflictos/resolver'),
      claveIdempotencia: operacion.clave,
      body: jsonEncode({
        'claveOperacion': operacion.clave,
        'accion': 'descartar_operacion_local',
        'tipo': operacion.tipo,
        'estado': operacion.estado,
        'metodo': operacion.metodo,
        'ruta': operacion.ruta,
        'patente': operacion.patente,
        'ultimoError': operacion.ultimoError,
        'motivo': motivoLimpio,
      }),
    );

    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw ErrorOperacionOffline(
        'RESOLUCION_CONFLICTO_RECHAZADA',
        _mensajeRespuesta(respuesta.body),
      );
    }

    final filas = await _cola.descartarConflicto(
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
      clave: operacion.clave,
      motivo: motivoLimpio,
    );

    if (filas != 1) {
      throw const ErrorOperacionOffline(
        'CONFLICTO_LOCAL_NO_DISPONIBLE',
        'La operación ya no está disponible como conflicto local',
      );
    }
  }

  static String _mensajeRespuesta(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final mensaje = decoded['mensaje']?.toString().trim();
        if (mensaje != null && mensaje.isNotEmpty) {
          return mensaje;
        }
        final codigo = decoded['codigo']?.toString().trim();
        if (codigo != null && codigo.isNotEmpty) {
          return codigo;
        }
      }
    } catch (_) {
      // Puede venir texto plano o HTML desde un proxy.
    }

    return 'No se pudo resolver el conflicto offline';
  }

  Future<void> _restablecerEnviosInterrumpidosUnaVez(
    SesionOffline sesion,
  ) async {
    if (_idSesionParaContextosRestaurados != sesion.idSesionLocal) {
      _contextosConEnviosRestablecidos.clear();
      _idSesionParaContextosRestaurados = sesion.idSesionLocal;
    }

    final contexto = '${sesion.estacionamientoId}:${sesion.usuarioId}';
    if (_contextosConEnviosRestablecidos.contains(contexto)) {
      return;
    }

    await _cola.restablecerEnviosInterrumpidos(
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
    );
    _contextosConEnviosRestablecidos.add(contexto);
  }

  Future<MovimientosLocale> registrarEntrada({
    required String clave,
    required String patente,
    required String tipo,
    required String color,
    required String observacion,
    required DateTime horaEntrada,
  }) async {
    final sesion = await sesionActual();
    return _operaciones.registrarEntrada(
      clave: clave,
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
      patente: patente,
      tipo: tipo,
      color: color,
      observacion: observacion,
      horaEntrada: horaEntrada,
    );
  }

  Future<MovimientosLocale?> buscarVehiculoDentro(String patente) async {
    final sesion = await sesionActual();
    return _cache.buscarPatenteDentro(sesion.estacionamientoId, patente);
  }

  Future<List<MovimientosLocale>> listarVehiculosDentro() async {
    final sesion = await sesionActual();
    return _cache.listarDentro(sesion.estacionamientoId);
  }

  Future<double?> tarifaPorMinutoActual() async {
    final sesion = await sesionActual();
    final tarifa = await _cache.obtenerTarifa(sesion.estacionamientoId);
    return tarifa?.tarifaPorMinuto;
  }

  Future<void> registrarSalida({
    required String clave,
    required String patente,
    required DateTime horaSalida,
    String metodoPago = 'efectivo',
  }) async {
    final sesion = await sesionActual();
    await _operaciones.registrarSalida(
      clave: clave,
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
      patente: patente,
      horaSalida: horaSalida,
      metodoPago: metodoPago,
    );
  }

  Future<MovimientosLocale> modificarVehiculo({
    required String clave,
    required String patenteActual,
    required String patenteNueva,
    required String tipo,
    required String color,
    required String observacion,
  }) async {
    final sesion = await sesionActual();
    return _operaciones.modificarVehiculo(
      clave: clave,
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
      patenteActual: patenteActual,
      patenteNueva: patenteNueva,
      tipo: tipo,
      color: color,
      observacion: observacion,
    );
  }

  Future<void> eliminarVehiculo({
    required String clave,
    required String patente,
  }) async {
    final sesion = await sesionActual();
    await _operaciones.eliminarVehiculo(
      clave: clave,
      estacionamientoId: sesion.estacionamientoId,
      usuarioId: sesion.usuarioId,
      patente: patente,
    );
  }

  static int? _entero(Object? valor) {
    if (valor is int && valor > 0) {
      return valor;
    }
    if (valor is num && valor > 0 && valor.toInt() == valor) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '');
  }
}
