import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() =>
      _HistorialScreenState();
}

class _HistorialScreenState
    extends State<HistorialScreen> {
  // ============================================================
  // API
  // ============================================================

  static final String apiUrl = ApiConfig.baseUrl;

  // ============================================================
  // DATOS
  // ============================================================

  List<Map<String, dynamic>> registros = [];

  bool cargando = true;

  String? error;

  // ============================================================
  // FILTRO
  // ============================================================

  String filtroActual = 'Hoy';

  DateTime? fechaDesde;

  DateTime? fechaHasta;

  // ============================================================
  // INICIO
  // ============================================================

  @override
  void initState() {
    super.initState();

    cargarHistorial();
  }

  // ============================================================
  // CARGAR HISTORIAL
  // ============================================================

  Future<void> cargarHistorial() async {
    if (!mounted) return;

    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final response = await ApiClient.get(
        Uri.parse(
          '$apiUrl/api/historial',
        ),
      );

      debugPrint(
        'STATUS HISTORIAL: ${response.statusCode}',
      );

      debugPrint(
        'BODY HISTORIAL: ${response.body}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error del servidor ${response.statusCode}',
        );
      }

      final decoded =
          jsonDecode(response.body);

      if (decoded is! List) {
        throw Exception(
          'La API no devolvió una lista válida',
        );
      }

      final lista =
          decoded
              .map<Map<String, dynamic>>(
                (item) {
                  return Map<String, dynamic>.from(
                    item as Map,
                  );
                },
              )
              .toList();

      if (!mounted) return;

      setState(() {
        registros = lista;
        cargando = false;
        error = null;
      });
    } catch (e) {
      debugPrint(
        'ERROR HISTORIAL: $e',
      );

      if (!mounted) return;

      setState(() {
        cargando = false;
        error =
            'No se pudo cargar el historial';
      });
    }
  }

  // ============================================================
  // REGISTROS FILTRADOS
  // ============================================================

  List<Map<String, dynamic>>
      get registrosFiltrados {
    if (filtroActual == 'Todos') {
      return List<Map<String, dynamic>>.from(
        registros,
      );
    }

    final ahora = DateTime.now();

    DateTime inicio;
    DateTime fin;

    // ==========================================================
    // HOY
    // ==========================================================

    if (filtroActual == 'Hoy') {
      inicio = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
      );

      fin = inicio.add(
        const Duration(
          days: 1,
        ),
      );
    }

    // ==========================================================
    // ÚLTIMOS 7 DÍAS
    // ==========================================================

    else if (filtroActual == '7 días') {
      final hoy = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
      );

      inicio = hoy.subtract(
        const Duration(
          days: 6,
        ),
      );

      fin = hoy.add(
        const Duration(
          days: 1,
        ),
      );
    }

    // ==========================================================
    // ESTE MES
    // ==========================================================

    else if (filtroActual == 'Este mes') {
      inicio = DateTime(
        ahora.year,
        ahora.month,
        1,
      );

      fin = DateTime(
        ahora.year,
        ahora.month + 1,
        1,
      );
    }

    // ==========================================================
    // RANGO PERSONALIZADO
    // ==========================================================

    else if (filtroActual ==
            'Personalizado' &&
        fechaDesde != null &&
        fechaHasta != null) {
      inicio = DateTime(
        fechaDesde!.year,
        fechaDesde!.month,
        fechaDesde!.day,
      );

      fin = DateTime(
        fechaHasta!.year,
        fechaHasta!.month,
        fechaHasta!.day,
      ).add(
        const Duration(
          days: 1,
        ),
      );
    }

    // ==========================================================
    // SEGURIDAD
    // ==========================================================

    else {
      return List<Map<String, dynamic>>.from(
        registros,
      );
    }

    return registros.where(
      (registro) {
        final horaSalidaTexto =
            registro['horaSalida']
                ?.toString();

        if (horaSalidaTexto == null ||
            horaSalidaTexto.isEmpty) {
          return false;
        }

        try {
          final fecha =
              DateTime.parse(
            horaSalidaTexto,
          ).toLocal();

          return !fecha.isBefore(inicio) &&
              fecha.isBefore(fin);
        } catch (_) {
          return false;
        }
      },
    ).toList();
  }

  // ============================================================
  // CANTIDAD DE REGISTROS
  // ============================================================

  int get cantidadFiltrada {
    return registrosFiltrados.length;
  }

  // ============================================================
  // TOTAL RECAUDADO
  // ============================================================

  double get totalRecaudado {
    double total = 0;

    for (final registro
        in registrosFiltrados) {
      total += convertirNumero(
        registro['monto'],
      );
    }

    return total;
  }

  // ============================================================
  // MINUTOS TOTALES
  // ============================================================

  int get minutosTotales {
    int total = 0;

    for (final registro
        in registrosFiltrados) {
      final minutos =
          convertirNumeroEntero(
        registro['minutos'],
      );

      total += minutos;
    }

    return total;
  }

  // ============================================================
  // PROMEDIO
  // ============================================================

  double get promedioPorVehiculo {
    if (cantidadFiltrada == 0) {
      return 0;
    }

    return totalRecaudado /
        cantidadFiltrada;
  }

  // ============================================================
  // CONVERTIR NÚMERO
  // ============================================================

  double convertirNumero(
    dynamic valor,
  ) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
          valor?.toString() ?? '',
        ) ??
        0;
  }

  // ============================================================
  // CONVERTIR ENTERO
  // ============================================================

  int convertirNumeroEntero(
    dynamic valor,
  ) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(
          valor?.toString() ?? '',
        ) ??
        0;
  }

  // ============================================================
  // FORMATO PESOS
  // ============================================================

  String formatoPesos(
    dynamic valor,
  ) {
    final numero =
        convertirNumero(valor).round();

    final texto =
        numero.toString();

    final buffer =
        StringBuffer();

    for (
      int i = 0;
      i < texto.length;
      i++
    ) {
      final posicion =
          texto.length - i;

      buffer.write(
        texto[i],
      );

      if (posicion > 1 &&
          posicion % 3 == 1) {
        buffer.write('.');
      }
    }

    return '\$${buffer.toString()}';
  }

  // ============================================================
  // FORMATEAR FECHA
  // ============================================================

  String formatearFecha(
    String? fecha,
  ) {
    if (fecha == null ||
        fecha.isEmpty) {
      return '-';
    }

    try {
      final date =
          DateTime.parse(
        fecha,
      ).toLocal();

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return fecha;
    }
  }

  // ============================================================
  // OBTENER MINUTOS
  // ============================================================

  String obtenerMinutos(
    Map<String, dynamic> registro,
  ) {
    final minutos =
        registro['minutos'];

    if (minutos == null) {
      return '0 min';
    }

    return '$minutos min';
  }

  // ============================================================
  // FECHA PARA MOSTRAR
  // ============================================================

  String fechaPersonalizadaVisible() {
    if (fechaDesde == null ||
        fechaHasta == null) {
      return 'Seleccionar fechas';
    }

    return '${_fechaCorta(fechaDesde!)} - '
        '${_fechaCorta(fechaHasta!)}';
  }

  // ============================================================
  // FECHA CORTA
  // ============================================================

  String _fechaCorta(
    DateTime fecha,
  ) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  // ============================================================
  // SELECCIONAR RANGO
  // ============================================================

  Future<void> seleccionarRango() async {
    final ahora = DateTime.now();

    final rango =
        await showDateRangePicker(
      context: context,
      firstDate: DateTime(
        ahora.year - 5,
      ),
      lastDate: DateTime(
        ahora.year + 1,
      ),
      initialDateRange:
          fechaDesde != null &&
                  fechaHasta != null
              ? DateTimeRange(
                  start: fechaDesde!,
                  end: fechaHasta!,
                )
              : DateTimeRange(
                  start: DateTime(
                    ahora.year,
                    ahora.month,
                    ahora.day,
                  ),
                  end: DateTime(
                    ahora.year,
                    ahora.month,
                    ahora.day,
                  ),
                ),
      helpText:
          'Selecciona el período',
      cancelText:
          'Cancelar',
      confirmText:
          'Aplicar',
    );

    if (rango == null) {
      return;
    }

    setState(() {
      fechaDesde = rango.start;
      fechaHasta = rango.end;
      filtroActual = 'Personalizado';
    });
  }

  // ============================================================
  // CAMBIAR FILTRO
  // ============================================================

  void cambiarFiltro(
    String filtro,
  ) {
    if (filtro == 'Personalizado') {
      seleccionarRango();
      return;
    }

    setState(() {
      filtroActual = filtro;
    });
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final filtrados =
        registrosFiltrados;

    return Scaffold(
      backgroundColor:
          const Color(0xFFF7F8FA),

      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        backgroundColor:
            const Color(0xFF0F2B52),

        foregroundColor:
            Colors.white,

        title: const Text(
          'Historial',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            onPressed:
                cargando
                    ? null
                    : cargarHistorial,

            icon: const Icon(
              Icons.refresh,
            ),

            tooltip:
                'Actualizar historial',
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: RefreshIndicator(
        onRefresh:
            cargarHistorial,

        child:
            cargando &&
                    registros.isEmpty
                ? ListView(
                    physics:
                        AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 280,
                      ),
                      Center(
                        child:
                            CircularProgressIndicator(),
                      ),
                    ],
                  )
                : ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),

                    padding:
                        const EdgeInsets.all(
                      16,
                    ),

                    children: [
                      // ==================================================
                      // TÍTULO
                      // ==================================================

                      const Text(
                        'Historial de salidas',
                        style:
                            TextStyle(
                          fontSize: 22,
                          fontWeight:
                              FontWeight.bold,
                          color:
                              Color(
                            0xFF172B4D,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 6,
                      ),

                      const Text(
                        'Consulta y controla las operaciones del estacionamiento.',
                        style:
                            TextStyle(
                          color:
                              Colors.grey,
                        ),
                      ),

                      const SizedBox(
                        height: 20,
                      ),

                      // ==================================================
                      // FILTROS
                      // ==================================================

                      _seccionTitulo(
                        'Período',
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      _filtros(),

                      const SizedBox(
                        height: 18,
                      ),

                      // ==================================================
                      // RESUMEN
                      // ==================================================

                      _seccionTitulo(
                        'Resumen',
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      _resumen(),

                      const SizedBox(
                        height: 24,
                      ),

                      // ==================================================
                      // ERROR
                      // ==================================================

                      if (error != null)
                        Container(
                          margin:
                              const EdgeInsets.only(
                            bottom: 16,
                          ),
                          padding:
                              const EdgeInsets.all(
                            14,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFFFFEAEA,
                            ),
                            borderRadius:
                                BorderRadius.circular(
                              12,
                            ),
                          ),
                          child:
                              Row(
                            children: [
                              const Icon(
                                Icons
                                    .error_outline,
                                color:
                                    Colors.red,
                              ),

                              const SizedBox(
                                width: 10,
                              ),

                              Expanded(
                                child:
                                    Text(
                                  error!,
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.red,
                                  ),
                                ),
                              ),

                              IconButton(
                                onPressed:
                                    cargarHistorial,
                                icon:
                                    const Icon(
                                  Icons.refresh,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ==================================================
                      // TÍTULO MOVIMIENTOS
                      // ==================================================

                      Row(
                        children: [
                          const Expanded(
                            child:
                                Text(
                              'Movimientos',
                              style:
                                  TextStyle(
                                fontSize:
                                    18,
                                fontWeight:
                                    FontWeight
                                        .bold,
                                color:
                                    Color(
                                  0xFF172B4D,
                                ),
                              ),
                            ),
                          ),

                          Text(
                            '$cantidadFiltrada registro(s)',
                            style:
                                const TextStyle(
                              color:
                                  Colors.grey,
                              fontSize:
                                  13,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      // ==================================================
                      // SIN REGISTROS
                      // ==================================================

                      if (filtrados.isEmpty)
                        _sinRegistros(),

                      // ==================================================
                      // LISTA
                      // ==================================================

                      ...filtrados.map(
                        (registro) =>
                            _tarjetaRegistro(
                          registro,
                        ),
                      ),

                      const SizedBox(
                        height: 80,
                      ),
                    ],
                  ),
      ),
    );
  }

  // ============================================================
  // TÍTULO DE SECCIÓN
  // ============================================================

  Widget _seccionTitulo(
    String titulo,
  ) {
    return Text(
      titulo,
      style: const TextStyle(
        fontSize: 17,
        fontWeight:
            FontWeight.bold,
        color:
            Color(0xFF172B4D),
      ),
    );
  }

  // ============================================================
  // FILTROS
  // ============================================================

  Widget _filtros() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chipFiltro(
          'Hoy',
        ),

        _chipFiltro(
          '7 días',
        ),

        _chipFiltro(
          'Este mes',
        ),

        _chipFiltro(
          'Todos',
        ),

        _chipFiltro(
          'Personalizado',
        ),
      ],
    );
  }

  // ============================================================
  // CHIP FILTRO
  // ============================================================

  Widget _chipFiltro(
    String texto,
  ) {
    final activo =
        filtroActual == texto;

    return FilterChip(
      label:
          Text(texto),

      selected:
          activo,

      onSelected:
          (_) {
        cambiarFiltro(
          texto,
        );
      },

      selectedColor:
          const Color(
        0xFFDCEAFF,
      ),

      checkmarkColor:
          const Color(
        0xFF0F5ED7,
      ),

      labelStyle:
          TextStyle(
        color:
            activo
                ? const Color(
                    0xFF0F5ED7,
                  )
                : Colors.black87,
        fontWeight:
            activo
                ? FontWeight.w600
                : FontWeight.normal,
      ),
    );
  }

  // ============================================================
  // RESUMEN
  // ============================================================

  Widget _resumen() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child:
                  _tarjetaResumen(
                icono:
                    Icons.directions_car,
                titulo:
                    cantidadFiltrada
                        .toString(),
                subtitulo:
                    'Vehículos',
              ),
            ),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child:
                  _tarjetaResumen(
                icono:
                    Icons.attach_money,
                titulo:
                    formatoPesos(
                  totalRecaudado,
                ),
                subtitulo:
                    'Recaudado',
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 10,
        ),

        Row(
          children: [
            Expanded(
              child:
                  _tarjetaResumen(
                icono:
                    Icons.timer_outlined,
                titulo:
                    '$minutosTotales',
                subtitulo:
                    'Minutos',
              ),
            ),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child:
                  _tarjetaResumen(
                icono:
                    Icons.analytics_outlined,
                titulo:
                    formatoPesos(
                  promedioPorVehiculo,
                ),
                subtitulo:
                    'Promedio',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // TARJETA RESUMEN
  // ============================================================

  Widget _tarjetaResumen({
    required IconData icono,
    required String titulo,
    required String subtitulo,
  }) {
    return Card(
      elevation: 1,

      margin:
          EdgeInsets.zero,

      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),

      child:
          Padding(
        padding:
            const EdgeInsets.all(
          14,
        ),

        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            Icon(
              icono,
              color:
                  const Color(
                0xFF0F5ED7,
              ),
              size: 26,
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              titulo,

              maxLines: 1,

              overflow:
                  TextOverflow.ellipsis,

              style:
                  const TextStyle(
                fontSize: 21,
                fontWeight:
                    FontWeight.bold,
                color:
                    Color(
                  0xFF172B4D,
                ),
              ),
            ),

            const SizedBox(
              height: 3,
            ),

            Text(
              subtitulo,

              style:
                  const TextStyle(
                fontSize: 12,
                color:
                    Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SIN REGISTROS
  // ============================================================

  Widget _sinRegistros() {
    return Card(
      elevation: 1,

      child:
          Padding(
        padding:
            const EdgeInsets.symmetric(
          vertical: 36,
          horizontal: 20,
        ),

        child:
            Column(
          children: [
            const Icon(
              Icons
                  .history_toggle_off,
              size: 55,
              color:
                  Colors.grey,
            ),

            const SizedBox(
              height: 12,
            ),

            const Text(
              'No hay movimientos',
              style:
                  TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.w600,
              ),
            ),

            const SizedBox(
              height: 6,
            ),

            Text(
              filtroActual ==
                      'Personalizado'
                  ? fechaPersonalizadaVisible()
                  : 'No existen salidas para este período.',
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TARJETA REGISTRO
  // ============================================================

  Widget _tarjetaRegistro(
    Map<String, dynamic> registro,
  ) {
    final patente =
        registro['patente']
                ?.toString() ??
            '-';

    final tipo =
        registro['tipo']
                ?.toString() ??
            '-';

    final color =
        registro['color']
                ?.toString() ??
            '-';

    final observacion =
        registro['observacion']
                ?.toString() ??
            '';

    final horaEntrada =
        registro['horaEntrada']
            ?.toString();

    final horaSalida =
        registro['horaSalida']
            ?.toString();

    final tarifa =
        registro['tarifaPorMinuto'];

    final monto =
        registro['monto'];

    final id =
        registro['id'];

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),

      elevation: 1,

      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),

      child:
          Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),

        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            // ==================================================
            // CABECERA
            // ==================================================

            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,

                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFFE8F0FE,
                    ),

                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),

                  child:
                      const Icon(
                    Icons
                        .directions_car,
                    color:
                        Color(
                      0xFF0F5ED7,
                    ),
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [
                      Text(
                        patente
                            .toUpperCase(),

                        style:
                            const TextStyle(
                          fontSize:
                              20,
                          fontWeight:
                              FontWeight
                                  .bold,
                          color:
                              Color(
                            0xFF172B4D,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 3,
                      ),

                      Text(
                        '$tipo • $color',

                        style:
                            const TextStyle(
                          color:
                              Colors.grey,
                          fontSize:
                              13,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  formatoPesos(
                    monto,
                  ),

                  style:
                      const TextStyle(
                    fontSize:
                        18,
                    fontWeight:
                        FontWeight
                            .bold,
                    color:
                        Color(
                      0xFF172B4D,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 14,
            ),

            const Divider(
              height: 1,
            ),

            const SizedBox(
              height: 14,
            ),

            // ==================================================
            // FOLIO
            // ==================================================

            if (id != null)
              _dato(
                'Folio',
                _formatearFolio(
                  id,
                ),
              ),

            // ==================================================
            // ENTRADA
            // ==================================================

            _dato(
              'Entrada',
              formatearFecha(
                horaEntrada,
              ),
            ),

            // ==================================================
            // SALIDA
            // ==================================================

            _dato(
              'Salida',
              formatearFecha(
                horaSalida,
              ),
            ),

            // ==================================================
            // TIEMPO
            // ==================================================

            _dato(
              'Tiempo',
              obtenerMinutos(
                registro,
              ),
            ),

            // ==================================================
            // TARIFA
            // ==================================================

            _dato(
              'Tarifa aplicada',
              '${formatoPesos(tarifa)}/min',
            ),

            // ==================================================
            // OBSERVACIÓN
            // ==================================================

            if (observacion
                .trim()
                .isNotEmpty)
              _dato(
                'Observación',
                observacion,
              ),

            const Divider(
              height: 24,
            ),

            // ==================================================
            // TOTAL
            // ==================================================

            Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceBetween,

              children: [
                const Text(
                  'TOTAL PAGADO',

                  style:
                      TextStyle(
                    color:
                        Colors.grey,
                    fontSize:
                        13,
                    fontWeight:
                        FontWeight
                            .w600,
                  ),
                ),

                Text(
                  formatoPesos(
                    monto,
                  ),

                  style:
                      const TextStyle(
                    fontSize:
                        22,
                    fontWeight:
                        FontWeight
                            .bold,
                    color:
                        Color(
                      0xFF0F5ED7,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FOLIO
  // ============================================================

  String _formatearFolio(
    dynamic id,
  ) {
    final numero =
        convertirNumeroEntero(
      id,
    );

    return 'PC-${numero.toString().padLeft(6, '0')}';
  }

  // ============================================================
  // DATO
  // ============================================================

  Widget _dato(
    String titulo,
    String valor,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 8,
      ),

      child:
          Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 125,

            child:
                Text(
              titulo,

              style:
                  const TextStyle(
                color:
                    Colors.grey,
                fontSize:
                    13,
              ),
            ),
          ),

          Expanded(
            child:
                Text(
              valor,

              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
                fontSize:
                    13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
