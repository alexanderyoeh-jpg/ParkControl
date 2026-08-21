import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/api_client.dart';
import 'cache_operativo_repository.dart';

class ErrorSincronizacionInicial implements Exception {
  const ErrorSincronizacionInicial(this.mensaje, {this.codigoHttp});

  final String mensaje;
  final int? codigoHttp;

  @override
  String toString() => mensaje;
}

class EstadoSincronizacionRemoto {
  const EstadoSincronizacionRemoto({
    required this.estacionamientoId,
    required this.tarifaServidorId,
    required this.tarifaPorMinuto,
    required this.servidorFecha,
    required this.movimientos,
  });

  final int estacionamientoId;
  final int? tarifaServidorId;
  final double tarifaPorMinuto;
  final DateTime servidorFecha;
  final List<MovimientoServidorSnapshot> movimientos;

  factory EstadoSincronizacionRemoto.desdeJson(Map<String, dynamic> json) {
    if (json['versionFormato'] != 1) {
      throw const FormatException('Versión de sincronización no compatible');
    }

    final estacionamientoId = _enteroPositivo(
      json['estacionamientoId'],
      'estacionamientoId',
    );
    final servidorFecha = DateTime.tryParse(
      json['servidorFecha']?.toString() ?? '',
    );
    final tarifaJson = json['tarifa'];
    final movimientosJson = json['movimientos'];

    if (servidorFecha == null ||
        tarifaJson is! Map<String, dynamic> ||
        movimientosJson is! List) {
      throw const FormatException('Estado de sincronización incompleto');
    }

    final tarifaServidorId = tarifaJson['id'] == null
        ? null
        : _enteroPositivo(tarifaJson['id'], 'tarifa.id');
    final tarifaPorMinuto = tarifaJson['tarifaPorMinuto'];

    if (tarifaPorMinuto is! num ||
        !tarifaPorMinuto.toDouble().isFinite ||
        tarifaPorMinuto < 0) {
      throw const FormatException('Tarifa de sincronización no válida');
    }

    final movimientos = movimientosJson
        .map((valor) {
          if (valor is! Map<String, dynamic>) {
            throw const FormatException(
              'Movimiento de sincronización no válido',
            );
          }

          final horaEntrada = DateTime.tryParse(
            valor['horaEntrada']?.toString() ?? '',
          );
          final patente = valor['patente']?.toString().trim() ?? '';
          final tipo = valor['tipo']?.toString().trim() ?? '';
          final color = valor['color']?.toString().trim() ?? '';

          if (horaEntrada == null ||
              patente.isEmpty ||
              tipo.isEmpty ||
              color.isEmpty) {
            throw const FormatException(
              'Movimiento de sincronización incompleto',
            );
          }

          return MovimientoServidorSnapshot(
            id: _enteroPositivo(valor['id'], 'movimiento.id'),
            patente: patente,
            tipo: tipo,
            color: color,
            observacion: valor['observacion']?.toString() ?? '',
            horaEntrada: horaEntrada,
            version: _enteroPositivo(valor['version'], 'movimiento.version'),
          );
        })
        .toList(growable: false);

    return EstadoSincronizacionRemoto(
      estacionamientoId: estacionamientoId,
      tarifaServidorId: tarifaServidorId,
      tarifaPorMinuto: tarifaPorMinuto.toDouble(),
      servidorFecha: servidorFecha,
      movimientos: movimientos,
    );
  }

  static int _enteroPositivo(Object? valor, String campo) {
    if (valor is! num || valor.toInt() != valor || valor < 1) {
      throw FormatException('$campo no es válido');
    }
    return valor.toInt();
  }
}

typedef ObtenerEstadoRemoto = Future<http.Response> Function(Uri uri);

class SincronizacionInicialService {
  SincronizacionInicialService(this._cache, {ObtenerEstadoRemoto? obtener})
    : _obtener = obtener ?? ApiClient.get;

  final CacheOperativoRepository _cache;
  final ObtenerEstadoRemoto _obtener;

  Future<EstadoSincronizacionRemoto> actualizar() async {
    final respuesta = await _obtener(
      Uri.parse('${ApiConfig.baseUrl}/api/sincronizacion/estado'),
    );

    if (respuesta.statusCode != 200) {
      throw ErrorSincronizacionInicial(
        _mensajeError(respuesta.body),
        codigoHttp: respuesta.statusCode,
      );
    }

    try {
      final decodificado = jsonDecode(respuesta.body);
      if (decodificado is! Map<String, dynamic>) {
        throw const FormatException('Respuesta de sincronización no válida');
      }

      final estado = EstadoSincronizacionRemoto.desdeJson(decodificado);
      await _cache.reconciliarEstadoServidor(
        estacionamientoId: estado.estacionamientoId,
        tarifaServidorId: estado.tarifaServidorId,
        tarifaPorMinuto: estado.tarifaPorMinuto,
        movimientos: estado.movimientos,
        servidorFecha: estado.servidorFecha,
      );
      return estado;
    } on FormatException catch (error) {
      throw ErrorSincronizacionInicial(error.message);
    }
  }

  static String _mensajeError(String cuerpo) {
    try {
      final json = jsonDecode(cuerpo);
      if (json is Map<String, dynamic>) {
        final mensaje = json['mensaje']?.toString().trim();
        if (mensaje != null && mensaje.isNotEmpty) {
          return mensaje;
        }
      }
    } catch (_) {
      // La respuesta puede ser texto o HTML de infraestructura.
    }
    return 'No se pudo actualizar el estado local';
  }
}
