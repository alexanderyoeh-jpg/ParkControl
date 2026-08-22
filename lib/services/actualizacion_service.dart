import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class InfoVersion {
  final String version;
  final int versionCode;
  final String fecha;
  final String nombreApp;
  final Map<String, dynamic> plataformas;
  final List<String> novedades;

  const InfoVersion({
    required this.version,
    required this.versionCode,
    required this.fecha,
    required this.nombreApp,
    required this.plataformas,
    required this.novedades,
  });

  factory InfoVersion.fromJson(Map<String, dynamic> json) {
    return InfoVersion(
      version: json['version']?.toString() ?? '1.0.0',
      versionCode: json['versionCode'] is int ? json['versionCode'] : 1,
      fecha: json['fecha']?.toString() ?? '',
      nombreApp: json['nombreApp']?.toString() ?? 'ParkControl',
      plataformas: json['plataformas'] is Map ? Map<String, dynamic>.from(json['plataformas']) : {},
      novedades: (json['novedades'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  String get urlAndroidApk =>
      plataformas['android']?['url']?.toString() ?? '${ApiConfig.baseUrl}/downloads/parkcontrol.apk';

  String get urlWindowsZip =>
      plataformas['windows']?['url']?.toString() ?? '${ApiConfig.baseUrl}/downloads/parkcontrol-windows.zip';

  String get urlWebApp =>
      plataformas['web']?['url']?.toString() ?? 'https://app.neatspace.cl';
}

class ActualizacionService {
  const ActualizacionService();

  static const String versionActual = '1.0.0';
  static const int versionCodeActual = 1;

  Future<InfoVersion?> consultarUltimaVersion() async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/version');
      final res = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(
        const Duration(seconds: 6),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return InfoVersion.fromJson(data);
      }
    } catch (e) {
      debugPrint('No se pudo verificar actualización: $e');
    }
    return null;
  }

  bool hayNuevaVersion(InfoVersion info) {
    return info.versionCode > versionCodeActual || info.version != versionActual;
  }
}
