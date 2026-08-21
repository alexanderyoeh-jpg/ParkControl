import 'dart:convert';

import '../config/api_config.dart';
import '../models/abonado.dart';
import 'api_client.dart';

class AbonadosService {
  const AbonadosService();

  static String get _baseUrl => ApiConfig.baseUrl;

  Future<List<Abonado>> obtenerAbonados({
    String? buscar,
    String? estado,
  }) async {
    final queryParams = <String, String>{};
    if (buscar != null && buscar.trim().isNotEmpty) {
      queryParams['buscar'] = buscar.trim();
    }
    if (estado != null && estado.trim().isNotEmpty && estado != 'todos') {
      queryParams['estado'] = estado.trim();
    }

    final uri = Uri.parse('$_baseUrl/api/abonados').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final res = await ApiClient.get(uri);
    if (res.statusCode != 200) {
      throw Exception(_extraerMensajeError(res, 'No se pudieron cargar los abonados'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['abonados'] as List<dynamic>? ?? [];
    return list.map((item) => Abonado.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> verificarPatente(String patente) async {
    final uri = Uri.parse('$_baseUrl/api/abonados/verificar/${Uri.encodeComponent(patente.trim())}');
    final res = await ApiClient.get(uri);
    if (res.statusCode != 200) {
      return {'esAbonado': false, 'vigente': false, 'abonado': null};
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Abonado> crearAbonado({
    required String nombreTitular,
    required String patente,
    String? rut,
    String? telefono,
    String? email,
    String tipoVehiculo = 'Auto',
    double montoMensual = 0.0,
    required String fechaInicio,
    required String fechaVencimiento,
    String? observacion,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/abonados');
    final body = jsonEncode({
      'nombreTitular': nombreTitular.trim(),
      'patente': patente.trim().toUpperCase(),
      'rut': rut?.trim(),
      'telefono': telefono?.trim(),
      'email': email?.trim(),
      'tipoVehiculo': tipoVehiculo,
      'montoMensual': montoMensual,
      'fechaInicio': fechaInicio,
      'fechaVencimiento': fechaVencimiento,
      'observacion': observacion?.trim(),
    });

    final res = await ApiClient.post(uri, body: body);
    if (res.statusCode != 201) {
      throw Exception(_extraerMensajeError(res, 'No se pudo crear el abonado'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Abonado.fromJson(data['abonado'] as Map<String, dynamic>);
  }

  Future<void> actualizarAbonado({
    required int id,
    String? nombreTitular,
    String? rut,
    String? telefono,
    String? email,
    String? tipoVehiculo,
    double? montoMensual,
    String? fechaInicio,
    String? fechaVencimiento,
    String? estado,
    String? observacion,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/abonados/$id');
    final body = jsonEncode({
      if (nombreTitular != null) 'nombreTitular': nombreTitular.trim(),
      if (rut != null) 'rut': rut.trim(),
      if (telefono != null) 'telefono': telefono.trim(),
      if (email != null) 'email': email.trim(),
      if (tipoVehiculo != null) 'tipoVehiculo': tipoVehiculo,
      if (montoMensual != null) 'montoMensual': montoMensual,
      if (fechaInicio != null) 'fechaInicio': fechaInicio,
      if (fechaVencimiento != null) 'fechaVencimiento': fechaVencimiento,
      if (estado != null) 'estado': estado,
      if (observacion != null) 'observacion': observacion.trim(),
    });

    final res = await ApiClient.put(uri, body: body);
    if (res.statusCode != 200) {
      throw Exception(_extraerMensajeError(res, 'No se pudo actualizar el abonado'));
    }
  }

  Future<void> renovarMesAbonado(int id, String fechaVencimientoActual) async {
    DateTime baseDate;
    try {
      baseDate = DateTime.parse(fechaVencimientoActual);
      if (baseDate.isBefore(DateTime.now())) {
        baseDate = DateTime.now();
      }
    } catch (_) {
      baseDate = DateTime.now();
    }

    final nuevaFecha = baseDate.add(const Duration(days: 30)).toIso8601String().slice(0, 10);
    await actualizarAbonado(
      id: id,
      fechaVencimiento: nuevaFecha,
      estado: 'activo',
    );
  }

  Future<void> eliminarAbonado(int id) async {
    final uri = Uri.parse('$_baseUrl/api/abonados/$id');
    final res = await ApiClient.delete(uri);
    if (res.statusCode != 200) {
      throw Exception(_extraerMensajeError(res, 'No se pudo eliminar el abonado'));
    }
  }

  static String _extraerMensajeError(dynamic res, String porDefecto) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['mensaje'] != null) {
        return body['mensaje'].toString();
      }
    } catch (_) {}
    return porDefecto;
  }
}

extension StringSlice on String {
  String slice(int start, [int? end]) {
    if (start < 0) start = length + start;
    if (end != null && end < 0) end = length + end;
    start = start.clamp(0, length);
    end = (end ?? length).clamp(start, length);
    return substring(start, end);
  }
}
