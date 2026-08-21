import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/api_client.dart';
import 'cola_sincronizacion_repository.dart';
import 'parkcontrol_local_database.dart';

typedef EnviarOperacionOffline =
    Future<http.Response> Function(OperacionesPendiente operacion);
typedef RefrescarCacheOffline = Future<void> Function();
typedef RegistrarResultadoOffline =
    Future<void> Function(
      OperacionesPendiente operacion,
      http.Response respuesta,
    );

enum ResultadoProcesamientoOffline {
  completada,
  reintentoProgramado,
  conflicto,
  bloqueada,
  sinOperaciones,
  yaProcesando,
}

class CoordinadorSincronizacion {
  CoordinadorSincronizacion(
    this._cola, {
    EnviarOperacionOffline? enviar,
    this.refrescarCache,
    this.registrarResultado,
  }) : _enviar = enviar ?? _enviarConApi;

  final ColaSincronizacionRepository _cola;
  final EnviarOperacionOffline _enviar;
  final RefrescarCacheOffline? refrescarCache;
  final RegistrarResultadoOffline? registrarResultado;
  // La cola pertenece a un cajero dentro de un estacionamiento. Dos cajeros
  // distintos no deben reservar ni enviar operaciones del otro, pero sí
  // pueden sincronizar sus propias colas sin bloquearse entre ellos.
  final Set<String> _contextosProcesando = <String>{};

  Future<ResultadoProcesamientoOffline> procesarUna({
    required int estacionamientoId,
    required int usuarioId,
    DateTime? ahora,
  }) async {
    final contexto = '$estacionamientoId:$usuarioId';
    if (!_contextosProcesando.add(contexto)) {
      return ResultadoProcesamientoOffline.yaProcesando;
    }

    try {
      final operacion = await _cola.reservarSiguiente(
        estacionamientoId: estacionamientoId,
        usuarioId: usuarioId,
        ahora: ahora,
      );
      if (operacion == null) {
        return ResultadoProcesamientoOffline.sinOperaciones;
      }

      try {
        final respuesta = await _enviar(operacion);
        final mensaje = _mensajeRespuesta(respuesta);

        if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
          try {
            await registrarResultado?.call(operacion, respuesta);
          } catch (error) {
            // La solicitud ya fue confirmada por el backend, pero se conserva
            // la misma clave idempotente para reintentar sólo la proyección
            // local. Así una entrada confirmada no se duplica al llegar el
            // snapshot antes de que conozcamos su id de servidor.
            await _cola.registrarFallo(
              operacion.clave,
              'No se pudo actualizar la proyección local: $error',
              estacionamientoId: estacionamientoId,
              usuarioId: usuarioId,
              ahora: ahora,
            );
            return ResultadoProcesamientoOffline.reintentoProgramado;
          }

          await _cola.marcarCompletada(
            operacion.clave,
            estacionamientoId: estacionamientoId,
            usuarioId: usuarioId,
            ahora: ahora,
          );

          // La operación ya fue confirmada por el backend. Una falla al
          // refrescar la proyección no debe provocar un segundo cambio: el
          // próximo snapshot podrá actualizar la caché con seguridad.
          try {
            await refrescarCache?.call();
          } catch (_) {
            // El estado confirmado permanece en la cola.
          }
          return ResultadoProcesamientoOffline.completada;
        }

        if (respuesta.statusCode == 401 || respuesta.statusCode == 403) {
          await _cola.marcarBloqueada(
            operacion.clave,
            mensaje,
            estacionamientoId: estacionamientoId,
            usuarioId: usuarioId,
            ahora: ahora,
          );
          return ResultadoProcesamientoOffline.bloqueada;
        }

        if ([408, 425, 429].contains(respuesta.statusCode)) {
          await _cola.registrarFallo(
            operacion.clave,
            mensaje,
            estacionamientoId: estacionamientoId,
            usuarioId: usuarioId,
            ahora: ahora,
          );
          return ResultadoProcesamientoOffline.reintentoProgramado;
        }

        if (respuesta.statusCode == 409 ||
            (respuesta.statusCode >= 400 && respuesta.statusCode < 500)) {
          await _cola.marcarConflicto(
            operacion.clave,
            mensaje,
            estacionamientoId: estacionamientoId,
            usuarioId: usuarioId,
            ahora: ahora,
          );
          return ResultadoProcesamientoOffline.conflicto;
        }

        await _cola.registrarFallo(
          operacion.clave,
          mensaje,
          estacionamientoId: estacionamientoId,
          usuarioId: usuarioId,
          ahora: ahora,
        );
        return ResultadoProcesamientoOffline.reintentoProgramado;
      } catch (error) {
        await _cola.registrarFallo(
          operacion.clave,
          'Sin conexión: $error',
          estacionamientoId: estacionamientoId,
          usuarioId: usuarioId,
          ahora: ahora,
        );
        return ResultadoProcesamientoOffline.reintentoProgramado;
      }
    } finally {
      _contextosProcesando.remove(contexto);
    }
  }

  Future<int> procesarDisponibles({
    required int estacionamientoId,
    required int usuarioId,
    int maximo = 20,
  }) async {
    if (maximo < 1 || maximo > 100) {
      throw ArgumentError.value(maximo, 'maximo');
    }

    var completadas = 0;
    for (var intento = 0; intento < maximo; intento++) {
      final resultado = await procesarUna(
        estacionamientoId: estacionamientoId,
        usuarioId: usuarioId,
      );
      if (resultado != ResultadoProcesamientoOffline.completada) {
        break;
      }
      completadas++;
    }
    return completadas;
  }

  static Future<http.Response> _enviarConApi(OperacionesPendiente operacion) {
    final uri = Uri.parse('${ApiConfig.baseUrl}${operacion.ruta}');

    switch (operacion.metodo) {
      case 'POST':
        return ApiClient.post(
          uri,
          body: operacion.cuerpoJson,
          claveIdempotencia: operacion.clave,
        );
      case 'PUT':
        return ApiClient.put(
          uri,
          body: operacion.cuerpoJson,
          claveIdempotencia: operacion.clave,
        );
      case 'DELETE':
        return ApiClient.delete(
          uri,
          body: operacion.cuerpoJson,
          claveIdempotencia: operacion.clave,
        );
      default:
        throw StateError('Método offline no compatible: ${operacion.metodo}');
    }
  }

  static String _mensajeRespuesta(http.Response respuesta) {
    try {
      final cuerpo = jsonDecode(respuesta.body);
      if (cuerpo is Map<String, dynamic>) {
        final mensaje = cuerpo['mensaje']?.toString().trim();
        if (mensaje != null && mensaje.isNotEmpty) {
          return mensaje;
        }
        final codigo = cuerpo['codigo']?.toString().trim();
        if (codigo != null && codigo.isNotEmpty) {
          return codigo;
        }
      }
    } catch (_) {
      // Un proxy puede devolver texto o HTML; se usa un mensaje estable.
    }
    return 'El servidor respondió con estado ${respuesta.statusCode}';
  }
}
