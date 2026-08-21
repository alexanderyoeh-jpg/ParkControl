import 'package:flutter/foundation.dart';

/// Configuración central de comunicación con la API de ParkControl.
///
/// En producción siempre se debe indicar la URL HTTPS de la API. Para otro
/// equipo o producción se usa, por ejemplo:
/// flutter run --dart-define=PARKCONTROL_API_URL=https://api.parkcontrol.cl
class ApiConfig {
  const ApiConfig._();

  static const String _urlDesdeCompilacion = String.fromEnvironment(
    'PARKCONTROL_API_URL',
    defaultValue: '',
  );

  /// URL que usa cada compilación. Android usa 10.0.2.2 sólo como comodidad
  /// para el emulador local; un teléfono físico y producción deben recibir
  /// explícitamente [PARKCONTROL_API_URL].
  static final String baseUrl = _resolverUrlBase();

  static String _resolverUrlBase() {
    final configurada = _urlDesdeCompilacion.trim();
    if (configurada.isNotEmpty) {
      return _normalizarUrl(configurada);
    }

    if (_requiereHttps) {
      throw StateError(
        'Las compilaciones profile/release requieren PARKCONTROL_API_URL con HTTPS.',
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }

    return 'http://localhost:3000';
  }

  static String _normalizarUrl(String valor) {
    final uri = Uri.tryParse(valor);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError(
        'PARKCONTROL_API_URL debe ser una URL http:// o https:// válida.',
      );
    }

    if (_requiereHttps && uri.scheme != 'https') {
      throw ArgumentError(
        'Las compilaciones profile/release requieren PARKCONTROL_API_URL con HTTPS.',
      );
    }

    return valor.replaceFirst(RegExp(r'/+$'), '');
  }

  static bool get _requiereHttps => kProfileMode || kReleaseMode;
}
