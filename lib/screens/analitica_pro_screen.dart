import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class AnaliticaProScreen extends StatefulWidget {
  const AnaliticaProScreen({super.key});

  @override
  State<AnaliticaProScreen> createState() => _AnaliticaProScreenState();
}

class _AnaliticaProScreenState extends State<AnaliticaProScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animacion;
  String _periodo = 'mes';
  List<Map<String, dynamic>> _puntos = [];
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _diasSemana = [];
  List<Map<String, dynamic>> _horas = [];
  Map<String, dynamic> _destacados = {};
  int _diasComparativa = 90;
  int? _ventanaComparativa;
  String? _zonaHorariaComparativa;
  String? _advertencia;
  String? _error;
  String? _errorComparativa;
  bool _cargando = true;
  bool _cargandoComparativa = false;
  int _solicitudAnalitica = 0;
  int _solicitudComparativa = 0;

  @override
  void initState() {
    super.initState();
    _animacion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _cargar();
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    final solicitud = ++_solicitudAnalitica;

    setState(() {
      _cargando = true;
      _error = null;
    });
    unawaited(_cargarComparativa());

    try {
      final respuesta = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/pro/analitica?periodo=$_periodo'),
      ).timeout(const Duration(seconds: 12));
      final cuerpo = jsonDecode(respuesta.body);

      if (respuesta.statusCode != 200 || cuerpo is! Map) {
        final mensaje = cuerpo is Map ? cuerpo['mensaje']?.toString() : null;
        throw Exception(mensaje ?? 'No se pudo cargar la analítica Pro');
      }

      final datos = Map<String, dynamic>.from(cuerpo);
      final puntos = (datos['puntos'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

      if (!mounted || solicitud != _solicitudAnalitica) return;

      setState(() {
        _puntos = puntos;
        _resumen = datos['resumen'] is Map
            ? Map<String, dynamic>.from(datos['resumen'] as Map)
            : <String, dynamic>{};
        _advertencia = datos['advertenciaTributaria']?.toString();
        _cargando = false;
      });
      _animacion
        ..reset()
        ..forward();
    } catch (error) {
      if (!mounted || solicitud != _solicitudAnalitica) return;
      setState(() {
        _cargando = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cargarComparativa() async {
    final solicitud = ++_solicitudComparativa;
    if (mounted) {
      setState(() {
        _cargandoComparativa = true;
        _errorComparativa = null;
      });
    }

    try {
      final respuesta = await ApiClient.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/pro/analitica/comparativa?dias=$_diasComparativa',
        ),
      ).timeout(const Duration(seconds: 12));
      final cuerpo = jsonDecode(respuesta.body);

      if (respuesta.statusCode != 200 || cuerpo is! Map) {
        final mensaje = cuerpo is Map ? cuerpo['mensaje']?.toString() : null;
        throw Exception(mensaje ?? 'No se pudo cargar la comparación');
      }

      final contenido = Map<String, dynamic>.from(cuerpo);
      final datos = contenido['comparativa'] is Map
          ? Map<String, dynamic>.from(contenido['comparativa'] as Map)
          : contenido;

      if (!mounted || solicitud != _solicitudComparativa) return;
      setState(() {
        _diasSemana = _listaMapas(datos['diasSemana']);
        _horas = _listaMapas(datos['horas']);
        _destacados = datos['destacados'] is Map
            ? Map<String, dynamic>.from(datos['destacados'] as Map)
            : <String, dynamic>{};
        _ventanaComparativa = _enteroOpcional(datos['ventanaDias']);
        _zonaHorariaComparativa = datos['zonaHoraria']?.toString();
        _cargandoComparativa = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _solicitudComparativa) return;
      setState(() {
        _cargandoComparativa = false;
        _errorComparativa = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cambiarPeriodo(String periodo) async {
    if (periodo == _periodo) return;
    setState(() => _periodo = periodo);
    await _cargar();
  }

  Future<void> _cambiarVentanaComparativa(int dias) async {
    if (dias == _diasComparativa) return;
    setState(() => _diasComparativa = dias);
    await _cargarComparativa();
  }

  List<Map<String, dynamic>> _listaMapas(dynamic valor) =>
      (valor as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  int _entero(dynamic valor) => _numero(valor).round();

  int? _enteroOpcional(dynamic valor) {
    if (valor == null) return null;
    final numero = double.tryParse(valor.toString());
    return numero?.round();
  }

  String _pesos(dynamic valor) {
    final texto = _numero(valor).round().toString();
    final salida = StringBuffer();
    for (var indice = 0; indice < texto.length; indice++) {
      if (indice > 0 && (texto.length - indice) % 3 == 0) salida.write('.');
      salida.write(texto[indice]);
    }
    return '\$${salida.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Rendimiento Pro'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Contabilidad y rendimiento',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Indicadores reales de tu estacionamiento para tomar decisiones.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _periodoChip('dia', 'Día'),
                _periodoChip('semana', 'Semana'),
                _periodoChip('mes', 'Mes'),
                _periodoChip('semestre', 'Semestre'),
                _periodoChip('ano', 'Año'),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null) _tarjetaError(),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _grafico(),
              const SizedBox(height: 16),
              _metricas(),
              const SizedBox(height: 16),
              _comparativaOperativa(),
              const SizedBox(height: 16),
              _tarjetaTributaria(),
              const SizedBox(height: 16),
              _actividadOperativa(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _periodoChip(String valor, String etiqueta) {
    return ChoiceChip(
      label: Text(etiqueta),
      selected: _periodo == valor,
      selectedColor: const Color(0xFFDDE9FF),
      onSelected: (_) => _cambiarPeriodo(valor),
    );
  }

  Widget _grafico() {
    final maximo = _puntos.fold<double>(
      0,
      (actual, punto) => math.max(actual, _numero(punto['ingresos'])),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights_rounded, color: Color(0xFF2B6EEF)),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Ingresos del período',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            maximo == 0
                ? 'Aún no hay cobros registrados en este período.'
                : 'La animación recorre únicamente los datos disponibles hasta hoy.',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 220,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: CurvedAnimation(
                parent: _animacion,
                curve: Curves.easeOutCubic,
              ),
              builder: (_, _) => CustomPaint(
                painter: _GraficoIngresosPainter(
                  puntos: _puntos,
                  progreso: _animacion.value,
                  maximo: maximo,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricas() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _metrica(
          'Ingresos brutos',
          _pesos(_resumen['ingresosBrutos']),
          Icons.payments_outlined,
          const Color(0xFF168A4C),
        ),
        _metrica(
          'Venta neta estimada',
          _pesos(_resumen['ventaNetaEstimada']),
          Icons.account_balance_outlined,
          const Color(0xFF7055B5),
        ),
        _metrica(
          'Salidas',
          '${_entero(_resumen['salidas'])}',
          Icons.logout_rounded,
          const Color(0xFFED7D31),
        ),
        _metrica(
          'Ticket promedio',
          _pesos(_resumen['promedioPorSalida']),
          Icons.local_offer_outlined,
          const Color(0xFF1976D2),
        ),
      ],
    );
  }

  Widget _comparativaOperativa() {
    final diaFuerte = _destacado('diaFuerte', _diasSemana, fuerte: true);
    final diaLento = _destacado('diaLento', _diasSemana, fuerte: false);
    final horaFuerte = _destacado('horaFuerte', _horas, fuerte: true);
    final horaLenta = _destacado('horaLenta', _horas, fuerte: false);
    final tieneDatos =
        _diasSemana.any((punto) => _valorComparativo(punto) > 0) ||
        _horas.any((punto) => _valorComparativo(punto) > 0);
    final diasMostrados = _ventanaComparativa ?? _diasComparativa;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_graph_rounded, color: Color(0xFF7055B5)),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Patrones de demanda',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Compara la actividad real de los últimos $diasMostrados días${_textoZonaHoraria()}.',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ventanaComparativaChip(30, '30 días'),
              _ventanaComparativaChip(90, '90 días'),
              _ventanaComparativaChip(365, '365 días'),
            ],
          ),
          const SizedBox(height: 16),
          if (_cargandoComparativa)
            const SizedBox(
              height: 115,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorComparativa != null)
            _estadoComparativaNoDisponible()
          else if (!tieneDatos)
            _estadoComparativaVacia()
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _tarjetaDestacado(
                  titulo: 'Día fuerte',
                  dato: diaFuerte,
                  icono: Icons.calendar_month_rounded,
                  color: const Color(0xFF168A4C),
                ),
                _tarjetaDestacado(
                  titulo: 'Día lento',
                  dato: diaLento,
                  icono: Icons.event_busy_outlined,
                  color: const Color(0xFFB96A12),
                ),
                _tarjetaDestacado(
                  titulo: 'Hora fuerte',
                  dato: horaFuerte,
                  icono: Icons.schedule_rounded,
                  color: const Color(0xFF2B6EEF),
                ),
                _tarjetaDestacado(
                  titulo: 'Hora lenta',
                  dato: horaLenta,
                  icono: Icons.hourglass_empty_rounded,
                  color: const Color(0xFF7055B5),
                ),
              ],
            ),
            if (_diasSemana.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Actividad por día',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'La actividad suma entradas y salidas registradas.',
                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
              const SizedBox(height: 10),
              _miniBarras(_diasSemana, esHora: false),
            ],
            if (_horas.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Actividad por hora',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Identifica las franjas que conviene reforzar o impulsar.',
                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
              const SizedBox(height: 10),
              _miniBarras(_horas, esHora: true),
            ],
          ],
        ],
      ),
    );
  }

  Widget _ventanaComparativaChip(int dias, String etiqueta) {
    return ChoiceChip(
      label: Text(etiqueta),
      selected: _diasComparativa == dias,
      selectedColor: const Color(0xFFE9E2FB),
      onSelected: _cargandoComparativa
          ? null
          : (_) => _cambiarVentanaComparativa(dias),
    );
  }

  Widget _estadoComparativaNoDisponible() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F2FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFF7055B5)),
        const SizedBox(width: 9),
        const Expanded(
          child: Text(
            'La comparación no está disponible por ahora. La analítica principal sigue operativa.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: _cargarComparativa,
          child: const Text('Reintentar'),
        ),
      ],
    ),
  );

  Widget _estadoComparativaVacia() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F8FC),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      children: [
        Icon(Icons.query_stats_outlined, color: Color(0xFF718096)),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'Aún no hay suficientes movimientos para generar esta comparación.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _tarjetaDestacado({
    required String titulo,
    required Map<String, dynamic>? dato,
    required IconData icono,
    required Color color,
  }) {
    final valor = dato == null ? 0 : _valorComparativo(dato);
    final esMonto = dato != null && _usaMonto(dato);
    final etiqueta = dato == null ? 'Sin datos' : _etiquetaComparativa(dato);
    final detalle = dato == null
        ? 'Aún no disponible'
        : esMonto
        ? '${_pesos(valor)} registrados'
        : '${_entero(valor)} movimientos';

    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 72) / 2,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(height: 11),
            Text(
              titulo,
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            const SizedBox(height: 3),
            Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              detalle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBarras(
    List<Map<String, dynamic>> puntos, {
    required bool esHora,
  }) {
    final maximo = puntos.fold<double>(
      0,
      (actual, punto) => math.max(actual, _valorComparativo(punto)),
    );
    final primerIndice = 0;
    final medioIndice = puntos.length ~/ 2;
    final ultimoIndice = puntos.length - 1;

    return Column(
      children: [
        SizedBox(
          height: 98,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(puntos.length, (indice) {
              final punto = puntos[indice];
              final proporcion = maximo <= 0
                  ? 0.0
                  : (_valorComparativo(punto) / maximo).clamp(0.0, 1.0);
              final esDestacado = indice == _indiceMasAlto(puntos);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: proporcion),
                    duration: Duration(milliseconds: 380 + indice * 28),
                    curve: Curves.easeOutCubic,
                    builder: (context, alto, _) => Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: alto,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: esDestacado
                                ? const Color(0xFF168A4C)
                                : const Color(0xFF91B7FF),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _etiquetaEje(puntos[primerIndice], esHora: esHora),
            _etiquetaEje(puntos[medioIndice], esHora: esHora),
            _etiquetaEje(puntos[ultimoIndice], esHora: esHora),
          ],
        ),
      ],
    );
  }

  Widget _etiquetaEje(Map<String, dynamic> punto, {required bool esHora}) =>
      Text(
        _etiquetaComparativa(punto, esHora: esHora),
        style: const TextStyle(fontSize: 10, color: Color(0xFF718096)),
      );

  Map<String, dynamic>? _destacado(
    String clave,
    List<Map<String, dynamic>> origen, {
    required bool fuerte,
  }) {
    final valorDirecto = _destacados[clave];
    if (valorDirecto is Map) return Map<String, dynamic>.from(valorDirecto);
    if (origen.isEmpty) return null;

    final conValor = origen
        .where((punto) => _valorComparativo(punto) > 0)
        .toList(growable: false);
    if (conValor.isEmpty) return null;
    return conValor.reduce((actual, candidato) {
      final valorActual = _valorComparativo(actual);
      final valorCandidato = _valorComparativo(candidato);
      return fuerte
          ? (valorCandidato > valorActual ? candidato : actual)
          : (valorCandidato < valorActual ? candidato : actual);
    });
  }

  int _indiceMasAlto(List<Map<String, dynamic>> puntos) {
    var indiceMayor = 0;
    var mayor = -1.0;
    for (var indice = 0; indice < puntos.length; indice++) {
      final valor = _valorComparativo(puntos[indice]);
      if (valor > mayor) {
        mayor = valor;
        indiceMayor = indice;
      }
    }
    return indiceMayor;
  }

  bool _usaMonto(Map<String, dynamic> punto) =>
      punto['actividad'] == null &&
      (punto['ingresos'] != null ||
          punto['monto'] != null ||
          punto['total'] != null ||
          punto['valor'] != null);

  double _valorComparativo(Map<String, dynamic> punto) {
    for (final clave in const [
      'actividad',
      'movimientos',
      'cantidad',
      'ingresos',
      'monto',
      'total',
      'valor',
      'salidas',
    ]) {
      if (punto[clave] != null) return _numero(punto[clave]);
    }
    return 0;
  }

  String _etiquetaComparativa(
    Map<String, dynamic> punto, {
    bool esHora = false,
  }) {
    final valor =
        punto['etiqueta'] ??
        punto['label'] ??
        punto['nombre'] ??
        punto[esHora ? 'hora' : 'dia'] ??
        punto[esHora ? 'franja' : 'diaSemana'];
    final texto = valor?.toString().trim() ?? '';
    if (!esHora || texto.isEmpty || texto.contains(':')) {
      return texto.isEmpty ? '—' : texto;
    }
    final hora = int.tryParse(texto);
    return hora == null ? texto : '${hora.toString().padLeft(2, '0')}:00';
  }

  String _textoZonaHoraria() {
    final zona = _zonaHorariaComparativa?.trim();
    return zona == null || zona.isEmpty ? '' : ' · $zona';
  }

  Widget _metrica(String titulo, String valor, IconData icono, Color color) {
    return LayoutBuilder(
      builder: (context, limites) => SizedBox(
        width: (MediaQuery.sizeOf(context).width - 46) / 2,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE0E8F5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: color),
              const SizedBox(height: 12),
              Text(
                valor,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                titulo,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTributaria() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0D389)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calculate_outlined, color: Color(0xFFA46700)),
              SizedBox(width: 9),
              Text(
                'Estimación tributaria',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'IVA débito estimado (${_entero(_resumen['tasaIva'])}%): ${_pesos(_resumen['ivaDebitoEstimado'])}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            _advertencia ?? '',
            style: const TextStyle(fontSize: 12, color: Color(0xFF70531B)),
          ),
        ],
      ),
    );
  }

  Widget _actividadOperativa() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Control operativo',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 13),
          _fila('Entradas', _entero(_resumen['entradas']), Icons.login_rounded),
          _fila(
            'Modificaciones auditadas',
            _entero(_resumen['modificaciones']),
            Icons.edit_note_outlined,
          ),
          _fila(
            'Eliminaciones lógicas',
            _entero(_resumen['eliminaciones']),
            Icons.delete_outline,
          ),
        ],
      ),
    );
  }

  Widget _fila(String titulo, int valor, IconData icono) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icono, size: 19, color: const Color(0xFF2B6EEF)),
        const SizedBox(width: 10),
        Expanded(child: Text(titulo)),
        Text('$valor', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Widget _tarjetaError() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFECEC),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red),
        const SizedBox(width: 9),
        Expanded(child: Text(_error!)),
        TextButton(onPressed: _cargar, child: const Text('Reintentar')),
      ],
    ),
  );
}

class _GraficoIngresosPainter extends CustomPainter {
  final List<Map<String, dynamic>> puntos;
  final double progreso;
  final double maximo;

  const _GraficoIngresosPainter({
    required this.puntos,
    required this.progreso,
    required this.maximo,
  });

  double _numero(dynamic valor) => valor is num
      ? valor.toDouble()
      : double.tryParse(valor?.toString() ?? '') ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    const margenSuperior = 12.0;
    const margenInferior = 30.0;
    const margenLateral = 5.0;
    final alto = size.height - margenSuperior - margenInferior;
    final ancho = size.width - margenLateral * 2;
    final visibles = puntos
        .where((punto) => punto['disponible'] == true)
        .toList();
    final totalAnimado = (visibles.length * progreso).ceil();
    final grilla = Paint()
      ..color = const Color(0xFFE8EDF6)
      ..strokeWidth = 1;

    for (var fila = 0; fila < 4; fila++) {
      final y = margenSuperior + alto * fila / 3;
      canvas.drawLine(
        Offset(margenLateral, y),
        Offset(size.width - margenLateral, y),
        grilla,
      );
    }

    if (visibles.isEmpty) return;
    final paso = ancho / visibles.length;
    final anchoBarra = math.max(3.0, paso * 0.58);
    final barras = Paint()..color = const Color(0xFF2B6EEF);
    final linea = Paint()
      ..color = const Color(0xFF0C9C6C)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final ruta = Path();

    for (var indice = 0; indice < visibles.length; indice++) {
      if (indice >= totalAnimado) break;
      final punto = visibles[indice];
      final ingreso = _numero(punto['ingresos']);
      final proporcion = maximo <= 0 ? 0.03 : ingreso / maximo;
      final altoBarra = math.max(3.0, alto * proporcion);
      final x = margenLateral + paso * indice + (paso - anchoBarra) / 2;
      final y = margenSuperior + alto - altoBarra;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, anchoBarra, altoBarra),
          const Radius.circular(4),
        ),
        barras,
      );
      final centro = Offset(x + anchoBarra / 2, y);
      if (indice == 0) {
        ruta.moveTo(centro.dx, centro.dy);
      } else {
        ruta.lineTo(centro.dx, centro.dy);
      }
    }
    canvas.drawPath(ruta, linea);

    final texto = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
    final saltoEtiqueta = math.max(1, (visibles.length / 6).ceil());
    for (var indice = 0; indice < visibles.length; indice += saltoEtiqueta) {
      if (indice >= totalAnimado) break;
      texto.text = TextSpan(
        text: visibles[indice]['etiqueta']?.toString() ?? '',
        style: const TextStyle(color: Color(0xFF718096), fontSize: 10),
      );
      texto.layout();
      texto.paint(
        canvas,
        Offset(margenLateral + paso * indice, size.height - 19),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraficoIngresosPainter anterior) =>
      anterior.progreso != progreso ||
      anterior.puntos != puntos ||
      anterior.maximo != maximo;
}
