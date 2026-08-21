import 'package:shared_preferences/shared_preferences.dart';

enum AnchoPapelTermico {
  mm58(58, '58 mm (Estándar roll57)'),
  mm80(80, '80 mm (Ancho roll80)');

  const AnchoPapelTermico(this.milimetros, this.etiqueta);

  final int milimetros;
  final String etiqueta;

  static AnchoPapelTermico desdeMilimetros(int? mm) {
    if (mm == 80) return AnchoPapelTermico.mm80;
    return AnchoPapelTermico.mm58;
  }
}

class ImpresionConfig {
  const ImpresionConfig({
    this.anchoPapel = AnchoPapelTermico.mm58,
    this.imprimirEntradaAutomatica = true,
    this.imprimirSalidaAutomatica = true,
    this.nombreEstacionamiento = 'ParkControl',
    this.encabezadoPersonalizado = '',
    this.piePagina = 'Conserve este ticket para retirar su vehículo.\nNo nos responsabilizamos por objetos de valor.',
    this.impresoraNombre,
    this.impresoraUrl,
    this.incluirCodigoBarras = true,
    this.cortarPapel = true,
  });

  final AnchoPapelTermico anchoPapel;
  final bool imprimirEntradaAutomatica;
  final bool imprimirSalidaAutomatica;
  final String nombreEstacionamiento;
  final String encabezadoPersonalizado;
  final String piePagina;
  final String? impresoraNombre;
  final String? impresoraUrl;
  final bool incluirCodigoBarras;
  final bool cortarPapel;

  ImpresionConfig copyWith({
    AnchoPapelTermico? anchoPapel,
    bool? imprimirEntradaAutomatica,
    bool? imprimirSalidaAutomatica,
    String? nombreEstacionamiento,
    String? encabezadoPersonalizado,
    String? piePagina,
    String? impresoraNombre,
    String? impresoraUrl,
    bool? incluirCodigoBarras,
    bool? cortarPapel,
  }) {
    return ImpresionConfig(
      anchoPapel: anchoPapel ?? this.anchoPapel,
      imprimirEntradaAutomatica:
          imprimirEntradaAutomatica ?? this.imprimirEntradaAutomatica,
      imprimirSalidaAutomatica:
          imprimirSalidaAutomatica ?? this.imprimirSalidaAutomatica,
      nombreEstacionamiento:
          nombreEstacionamiento ?? this.nombreEstacionamiento,
      encabezadoPersonalizado:
          encabezadoPersonalizado ?? this.encabezadoPersonalizado,
      piePagina: piePagina ?? this.piePagina,
      impresoraNombre: impresoraNombre ?? this.impresoraNombre,
      impresoraUrl: impresoraUrl ?? this.impresoraUrl,
      incluirCodigoBarras:
          incluirCodigoBarras ?? this.incluirCodigoBarras,
      cortarPapel: cortarPapel ?? this.cortarPapel,
    );
  }
}

class ImpresionConfigService {
  const ImpresionConfigService._();

  static const String _prefAnchoPapel = 'impresion_ancho_papel';
  static const String _prefEntradaAuto = 'impresion_entrada_automatica';
  static const String _prefSalidaAuto = 'impresion_salida_automatica';
  static const String _prefNombreEst = 'impresion_nombre_estacionamiento';
  static const String _prefEncabezado = 'impresion_encabezado_personalizado';
  static const String _prefPiePagina = 'impresion_pie_pagina';
  static const String _prefImpresoraNombre = 'impresion_impresora_nombre';
  static const String _prefImpresoraUrl = 'impresion_impresora_url';
  static const String _prefCodigoBarras = 'impresion_incluir_codigo_barras';
  static const String _prefCortarPapel = 'impresion_cortar_papel';

  static ImpresionConfig? _configEnMemoria;

  static Future<ImpresionConfig> obtenerConfiguracion() async {
    if (_configEnMemoria != null) return _configEnMemoria!;

    final pref = await SharedPreferences.getInstance();

    final anchoMm = pref.getInt(_prefAnchoPapel);
    final config = ImpresionConfig(
      anchoPapel: AnchoPapelTermico.desdeMilimetros(anchoMm),
      imprimirEntradaAutomatica: pref.getBool(_prefEntradaAuto) ?? true,
      imprimirSalidaAutomatica: pref.getBool(_prefSalidaAuto) ?? true,
      nombreEstacionamiento: pref.getString(_prefNombreEst) ?? 'ParkControl',
      encabezadoPersonalizado: pref.getString(_prefEncabezado) ?? '',
      piePagina: pref.getString(_prefPiePagina) ??
          'Conserve este ticket para retirar su vehículo.\nNo nos responsabilizamos por objetos de valor.',
      impresoraNombre: pref.getString(_prefImpresoraNombre),
      impresoraUrl: pref.getString(_prefImpresoraUrl),
      incluirCodigoBarras: pref.getBool(_prefCodigoBarras) ?? true,
      cortarPapel: pref.getBool(_prefCortarPapel) ?? true,
    );

    _configEnMemoria = config;
    return config;
  }

  static Future<void> guardarConfiguracion(ImpresionConfig config) async {
    _configEnMemoria = config;
    final pref = await SharedPreferences.getInstance();

    await pref.setInt(_prefAnchoPapel, config.anchoPapel.milimetros);
    await pref.setBool(_prefEntradaAuto, config.imprimirEntradaAutomatica);
    await pref.setBool(_prefSalidaAuto, config.imprimirSalidaAutomatica);
    await pref.setString(_prefNombreEst, config.nombreEstacionamiento);
    await pref.setString(_prefEncabezado, config.encabezadoPersonalizado);
    await pref.setString(_prefPiePagina, config.piePagina);
    await pref.setBool(_prefCodigoBarras, config.incluirCodigoBarras);
    await pref.setBool(_prefCortarPapel, config.cortarPapel);

    if (config.impresoraNombre != null) {
      await pref.setString(_prefImpresoraNombre, config.impresoraNombre!);
    } else {
      await pref.remove(_prefImpresoraNombre);
    }

    if (config.impresoraUrl != null) {
      await pref.setString(_prefImpresoraUrl, config.impresoraUrl!);
    } else {
      await pref.remove(_prefImpresoraUrl);
    }
  }
}
