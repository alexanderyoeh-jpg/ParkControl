import 'dart:convert';

import '../config/api_config.dart';
import 'api_client.dart';

/// Capacidades vigentes entregadas por el backend.
///
/// La interfaz usa esta información sólo para mostrar u ocultar accesos. Las
/// rutas del backend vuelven a validar cada capacidad, por lo que no depende
/// de Flutter para proteger los planes Lite y Pro.
class CapacidadesPlan {
  final String plan;
  final bool boletasPdf;
  final bool contabilidadAvanzada;
  final bool exportacionDatos;
  final bool graficosAvanzados;
  final bool reportesPorCorreo;
  final bool cierreCaja;
  final int maxAdministradores;
  final int maxCajeros;

  const CapacidadesPlan({
    required this.plan,
    required this.boletasPdf,
    required this.contabilidadAvanzada,
    required this.exportacionDatos,
    required this.graficosAvanzados,
    required this.reportesPorCorreo,
    required this.cierreCaja,
    required this.maxAdministradores,
    required this.maxCajeros,
  });

  bool get esPro => plan == 'PRO';

  static Future<CapacidadesPlan?> obtenerActuales() async {
    final respuesta = await ApiClient.get(
      Uri.parse('${ApiConfig.baseUrl}/api/cuenta/capacidades'),
    ).timeout(const Duration(seconds: 10));

    if (respuesta.statusCode != 200) {
      return null;
    }

    final decodificado = jsonDecode(respuesta.body);

    if (decodificado is! Map) {
      return null;
    }

    final datos = Map<String, dynamic>.from(decodificado);
    final capacidadesBrutas = datos['capacidades'];

    if (capacidadesBrutas is! Map) {
      return null;
    }

    final capacidades = Map<String, dynamic>.from(capacidadesBrutas);

    return CapacidadesPlan(
      plan: (datos['plan'] ?? capacidades['plan'] ?? 'LITE')
          .toString()
          .trim()
          .toUpperCase(),
      boletasPdf: _booleano(capacidades['boletasPdf']),
      contabilidadAvanzada: _booleano(capacidades['contabilidadAvanzada']),
      exportacionDatos: _booleano(capacidades['exportacionDatos']),
      graficosAvanzados: _booleano(capacidades['graficosAvanzados']),
      reportesPorCorreo: _booleano(capacidades['reportesPorCorreo']),
      cierreCaja: _booleano(capacidades['cierreCaja']),
      maxAdministradores: _entero(capacidades['maxAdministradores']),
      maxCajeros: _entero(capacidades['maxCajeros']),
    );
  }

  static bool _booleano(dynamic valor) =>
      valor == true || valor == 1 || valor?.toString().toLowerCase() == 'true';

  static int _entero(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
