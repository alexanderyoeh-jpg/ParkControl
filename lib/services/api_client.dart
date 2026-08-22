import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Contexto no secreto de la sesión abierta en este proceso/pestaña.
///
/// No se persiste: evita que una segunda pestaña cambie la identidad que usa
/// la cola offline de la primera.
class ContextoSesionActual {
  const ContextoSesionActual({
    required this.idSesionLocal,
    required this.usuarioId,
    this.estacionamientoId,
  });

  final int idSesionLocal;
  final int usuarioId;
  final int? estacionamientoId;
}

/// Cliente HTTP central de ParkControl.
///
/// Adjunta la sesión actual a cada llamada protegida de la API para que el
/// servidor pueda validar identidad y permisos.
class ApiClient {
  const ApiClient._();

  static const String _tokenKey = 'auth_token';
  static final Random _generadorSeguro = Random.secure();
  static String? _tokenEnMemoria;
  static ContextoSesionActual? _contextoSesionActual;
  static String? _tokenSuperAdminOriginal;
  static ContextoSesionActual? _contextoSuperAdminOriginal;
  static int _siguienteIdSesionLocal = 0;

  static ContextoSesionActual? get contextoSesionActual =>
      _contextoSesionActual;

  static bool get estaEnModoSoporte => _tokenSuperAdminOriginal != null;

  /// Inicia una sesión delegada en modo soporte para un estacionamiento específico.
  static Future<void> iniciarModoSoporte({
    required String tokenSoporte,
    required int usuarioId,
    required int estacionamientoId,
  }) async {
    final tokenNormalizado = tokenSoporte.trim();
    if (tokenNormalizado.isEmpty) {
      throw ArgumentError('El token de soporte no puede estar vacío');
    }

    _tokenSuperAdminOriginal ??= _tokenEnMemoria;
    _contextoSuperAdminOriginal ??= _contextoSesionActual;

    _tokenEnMemoria = tokenNormalizado;
    _contextoSesionActual = ContextoSesionActual(
      idSesionLocal: ++_siguienteIdSesionLocal,
      usuarioId: usuarioId,
      estacionamientoId: estacionamientoId,
    );
  }

  /// Restaura la sesión original de SuperAdministrador saliendo del modo soporte.
  static Future<void> salirDeModoSoporte() async {
    if (_tokenSuperAdminOriginal != null) {
      _tokenEnMemoria = _tokenSuperAdminOriginal;
      _contextoSesionActual = _contextoSuperAdminOriginal;
      _tokenSuperAdminOriginal = null;
      _contextoSuperAdminOriginal = null;
    }
  }

  /// Elimina el token de instalaciones anteriores que se guardaba en
  static Future<void> inicializarSesion() async {
    final preferencias = await SharedPreferences.getInstance();
    final token = preferencias.getString(_tokenKey);
    final usuarioId = preferencias.getInt('sesion_usuario_id');
    final estacionamientoId = preferencias.getInt('sesion_estacionamiento_id');

    if (token != null && token.trim().isNotEmpty && usuarioId != null && usuarioId > 0) {
      _tokenEnMemoria = token.trim();
      _contextoSesionActual = ContextoSesionActual(
        idSesionLocal: ++_siguienteIdSesionLocal,
        usuarioId: usuarioId,
        estacionamientoId: estacionamientoId ?? 1,
      );
    }
  }

  static String crearClaveIdempotencia() {
    final instante = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final aleatorio = List.generate(
      16,
      (_) => _generadorSeguro.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();

    return 'pc-$instante-$aleatorio';
  }

  static Future<void> guardarSesion({
    required String token,
    required int usuarioId,
    int? estacionamientoId,
  }) async {
    final tokenNormalizado = token.trim();
    if (tokenNormalizado.isEmpty) {
      throw ArgumentError.value(
        token,
        'token',
        'La sesión no puede estar vacía',
      );
    }

    if (usuarioId <= 0 ||
        (estacionamientoId != null && estacionamientoId <= 0)) {
      throw ArgumentError('La sesión no identifica correctamente al usuario');
    }

    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString(_tokenKey, tokenNormalizado);
    await preferencias.setInt('sesion_usuario_id', usuarioId);
    if (estacionamientoId != null) {
      await preferencias.setInt('sesion_estacionamiento_id', estacionamientoId);
    } else {
      await preferencias.remove('sesion_estacionamiento_id');
    }

    _tokenEnMemoria = tokenNormalizado;
    _tokenSuperAdminOriginal = null;
    _contextoSuperAdminOriginal = null;
    _contextoSesionActual = ContextoSesionActual(
      idSesionLocal: ++_siguienteIdSesionLocal,
      usuarioId: usuarioId,
      estacionamientoId: estacionamientoId ?? 1,
    );
  }

  static Future<void> borrarSesion() async {
    _tokenEnMemoria = null;
    _contextoSesionActual = null;
    _tokenSuperAdminOriginal = null;
    _contextoSuperAdminOriginal = null;
    final preferencias = await SharedPreferences.getInstance();

    await preferencias.remove(_tokenKey);
    await preferencias.remove('sesion_usuario_id');
    await preferencias.remove('sesion_estacionamiento_id');
    await preferencias.remove('usuario');
    await preferencias.remove('sesion_activa');
  }

  static Future<void> cerrarSesion() async {
    final token = _tokenEnMemoria?.trim();
    await borrarSesion();

    if (token != null && token.isNotEmpty) {
      // La pantalla no debe quedar bloqueada si se cerró sesión sin red. El
      // servidor invalida la sesión cuando recibe el aviso, pero el token ya
      // no está disponible localmente aunque la solicitud falle.
      unawaited(_notificarCierreRemoto(token));
    }
  }

  static Future<void> _notificarCierreRemoto(String token) async {
    try {
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/logout'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // El cierre local ya fue aplicado. No se expone el error ni el token.
    }
  }

  static Future<Map<String, String>> _headers({
    bool incluirJson = false,
    String? claveIdempotencia,
  }) async {
    final token = _tokenEnMemoria?.trim();

    final headers = <String, String>{'Accept': 'application/json'};

    if (incluirJson) {
      headers['Content-Type'] = 'application/json';
    }

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    if (claveIdempotencia != null && claveIdempotencia.trim().isNotEmpty) {
      headers['Idempotency-Key'] = claveIdempotencia.trim();
    }

    return headers;
  }

  static Future<http.Response> get(Uri url) async {
    return http.get(url, headers: await _headers());
  }

  static Future<http.Response> getPublico(Uri url) async {
    return http.get(url, headers: const {'Accept': 'application/json'});
  }

  /// Descarga un PDF autenticado sin exponer la sesión en la URL.
  ///
  /// Esto funciona igual en Android, iOS y web porque la petición conserva el
  /// header Authorization. La presentación o impresión del archivo se deja a
  /// la capa de interfaz, que recibe sólo los bytes ya autorizados.
  static Future<Uint8List> descargarPdf(Uri url) async {
    final headers = await _headers();
    headers['Accept'] = 'application/pdf, application/json';

    final respuesta = await http.get(url, headers: headers);

    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw Exception(
        _mensajeRespuesta(respuesta, 'No se pudo descargar el documento PDF'),
      );
    }

    final tipoContenido = (respuesta.headers['content-type'] ?? '')
        .toLowerCase();

    if (!tipoContenido.contains('application/pdf')) {
      throw Exception('La respuesta del servidor no es un documento PDF');
    }

    if (respuesta.bodyBytes.isEmpty) {
      throw Exception('El documento PDF recibido está vacío');
    }

    return respuesta.bodyBytes;
  }

  static Future<http.Response> post(
    Uri url, {
    Object? body,
    String? claveIdempotencia,
  }) async {
    return http.post(
      url,
      headers: await _headers(
        incluirJson: true,
        claveIdempotencia: claveIdempotencia,
      ),
      body: body,
    );
  }

  static Future<http.Response> postPublico(Uri url, {Object? body}) async {
    return http.post(
      url,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: body,
    );
  }

  static Future<http.Response> put(
    Uri url, {
    Object? body,
    String? claveIdempotencia,
  }) async {
    return http.put(
      url,
      headers: await _headers(
        incluirJson: true,
        claveIdempotencia: claveIdempotencia,
      ),
      body: body,
    );
  }

  static Future<http.Response> patch(Uri url, {Object? body}) async {
    return http.patch(
      url,
      headers: await _headers(incluirJson: true),
      body: body,
    );
  }

  static Future<http.Response> delete(
    Uri url, {
    Object? body,
    String? claveIdempotencia,
  }) async {
    return http.delete(
      url,
      headers: await _headers(
        incluirJson: body != null,
        claveIdempotencia: claveIdempotencia,
      ),
      body: body,
    );
  }

  /// Extrae un mensaje de error claro y legible desde la respuesta HTTP del servidor.
  ///
  /// Examina las propiedades 'mensaje', 'error', 'detalle' y 'codigo' del JSON,
  /// o genera un mensaje contextual según el código HTTP si el cuerpo no es JSON.
  static String extraerMensajeError(
    http.Response? respuesta, {
    String mensajePredeterminado = 'Error inesperado en la solicitud',
  }) {
    if (respuesta == null) return mensajePredeterminado;

    try {
      final cuerpo = jsonDecode(respuesta.body);
      if (cuerpo is Map) {
        if (cuerpo['mensaje'] != null) {
          final m = cuerpo['mensaje'].toString().trim();
          if (m.isNotEmpty) return m;
        }
        if (cuerpo['error'] != null) {
          final e = cuerpo['error'].toString().trim();
          if (e.isNotEmpty) return e;
        }
        if (cuerpo['detalle'] != null) {
          final d = cuerpo['detalle'].toString().trim();
          if (d.isNotEmpty) return d;
        }
        if (cuerpo['codigo'] != null) {
          final c = cuerpo['codigo'].toString().trim();
          if (c.isNotEmpty) {
            return _mapearCodigoError(c);
          }
        }
      }
    } catch (_) {
      // El cuerpo no es JSON (ej. error 502/504 en HTML o texto plano)
    }

    switch (respuesta.statusCode) {
      case 400:
        return 'Los datos enviados no son válidos';
      case 401:
        return 'Sesión expirada o no autorizada. Por favor inicia sesión nuevamente.';
      case 403:
        return 'No tienes permisos o esta función no está disponible en tu plan.';
      case 404:
        return 'El recurso solicitado no fue encontrado';
      case 409:
        return 'Conflicto con el estado actual del sistema';
      case 429:
        return 'Demasiadas solicitudes. Por favor espera unos momentos antes de reintentar.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'El servidor no está disponible en este momento. Inténtalo más tarde.';
      default:
        return mensajePredeterminado;
    }
  }

  static String _mapearCodigoError(String codigo) {
    switch (codigo) {
      case 'FUNCION_NO_DISPONIBLE_PLAN':
        return 'Esta función no está disponible en tu plan actual.';
      case 'LIMITE_USUARIOS_PLAN':
        return 'Has alcanzado el límite máximo de usuarios permitidos por tu plan.';
      case 'MOVIMIENTO_DESACTUALIZADO':
        return 'El vehículo fue modificado o retirado desde otra sesión.';
      case 'TARIFA_DESACTUALIZADA':
        return 'La tarifa del estacionamiento fue modificada recientemente.';
      case 'PATENTE_YA_DENTRO':
        return 'Esta patente ya se encuentra dentro del estacionamiento.';
      case 'BLOQUEO_INTENTOS_LOGIN':
        return 'Demasiados intentos fallidos. Acceso temporalmente bloqueado.';
      case 'SUPERADMIN_YA_CONFIGURADO':
        return 'El SuperAdministrador ya fue configurado previamente.';
      case 'CONFIGURACION_DESHABILITADA':
        return 'La configuración inicial no está permitida.';
      default:
        return codigo.replaceAll('_', ' ').toLowerCase();
    }
  }

  static String _mensajeRespuesta(
    http.Response respuesta,
    String mensajePredeterminado,
  ) {
    return extraerMensajeError(
      respuesta,
      mensajePredeterminado: mensajePredeterminado,
    );
  }
}
