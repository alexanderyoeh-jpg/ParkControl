import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class ContabilidadScreen extends StatefulWidget {
  const ContabilidadScreen({super.key});

  @override
  State<ContabilidadScreen> createState() => _ContabilidadScreenState();
}

class _ContabilidadScreenState extends State<ContabilidadScreen> {
  // ============================================================
  // API
  // ============================================================

  static final String apiUrl = ApiConfig.baseUrl;

  // ============================================================
  // DATOS
  // ============================================================

  List<Map<String, dynamic>> registros = [];

  bool cargando = true;

  bool exportandoExcel = false;

  bool exportandoPdf = false;

  String? error;

  // ============================================================
  // RESUMEN
  // ============================================================

  int cantidadVehiculos = 0;

  double ingresosTotales = 0;

  double promedioPorVehiculo = 0;

  int minutosTotales = 0;

  // ============================================================
  // FECHAS
  // ============================================================

  DateTime? fechaInicio;

  DateTime? fechaFin;

  bool get _exportando => exportandoExcel || exportandoPdf;

  // ============================================================
  // INICIO
  // ============================================================

  @override
  void initState() {
    super.initState();

    cargarContabilidad();
  }

  // ============================================================
  // CARGAR CONTABILIDAD
  // ============================================================

  Future<void> cargarContabilidad() async {
    if (!mounted) return;

    setState(() {
      cargando = true;
      error = null;
    });

    try {
      String url = '$apiUrl/api/contabilidad';

      final parametros = <String>[];

      if (fechaInicio != null) {
        parametros.add('fechaInicio=${_fechaApi(fechaInicio!)}');
      }

      if (fechaFin != null) {
        parametros.add('fechaFin=${_fechaApi(fechaFin!)}');
      }

      if (parametros.isNotEmpty) {
        url += '?${parametros.join('&')}';
      }

      debugPrint('URL CONTABILIDAD: $url');

      final response = await ApiClient.get(Uri.parse(url));

      debugPrint('STATUS CONTABILIDAD: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode != 200) {
        final mensaje = ApiClient.extraerMensajeError(
          response,
          mensajePredeterminado: 'No se pudo obtener la información contable',
        );

        setState(() {
          cargando = false;
          error = mensaje;
        });

        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception('La API no devolvió un objeto válido');
      }

      final datos = Map<String, dynamic>.from(decoded);

      // ========================================================
      // RESUMEN
      // ========================================================

      final resumenApi = datos['resumen'];

      final resumen = resumenApi is Map
          ? Map<String, dynamic>.from(resumenApi)
          : <String, dynamic>{};

      // ========================================================
      // REGISTROS
      // ========================================================

      final registrosApi = datos['registros'];

      List<Map<String, dynamic>> listaRegistros = [];

      if (registrosApi is List) {
        listaRegistros = registrosApi
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      // ========================================================
      // ACTUALIZAR PANTALLA
      // ========================================================

      setState(() {
        cantidadVehiculos = _toInt(resumen['cantidadVehiculos']);

        ingresosTotales = _toDouble(resumen['ingresosTotales']);

        promedioPorVehiculo = _toDouble(resumen['promedioPorVehiculo']);

        minutosTotales = _toInt(resumen['minutosTotales']);

        registros = listaRegistros;

        cargando = false;

        error = null;
      });
    } catch (e) {
      debugPrint('ERROR CONTABILIDAD: $e');

      if (!mounted) return;

      setState(() {
        cargando = false;

        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // SELECCIONAR FECHA INICIAL
  // ============================================================

  Future<void> seleccionarFechaInicio() async {
    final ahora = DateTime.now();

    final fecha = await showDatePicker(
      context: context,

      initialDate: fechaInicio ?? fechaFin ?? ahora,

      firstDate: DateTime(2020),

      lastDate: DateTime(2100),

      helpText: 'Selecciona fecha inicial',

      cancelText: 'Cancelar',

      confirmText: 'Aceptar',
    );

    if (fecha == null) {
      return;
    }

    if (fechaFin != null && fecha.isAfter(fechaFin!)) {
      _mostrarMensaje(
        'La fecha inicial no puede ser posterior a la fecha final',
        esError: true,
      );

      return;
    }

    setState(() {
      fechaInicio = fecha;
    });

    await cargarContabilidad();
  }

  // ============================================================
  // SELECCIONAR FECHA FINAL
  // ============================================================

  Future<void> seleccionarFechaFin() async {
    final ahora = DateTime.now();

    final fecha = await showDatePicker(
      context: context,

      initialDate: fechaFin ?? fechaInicio ?? ahora,

      firstDate: DateTime(2020),

      lastDate: DateTime(2100),

      helpText: 'Selecciona fecha final',

      cancelText: 'Cancelar',

      confirmText: 'Aceptar',
    );

    if (fecha == null) {
      return;
    }

    if (fechaInicio != null && fecha.isBefore(fechaInicio!)) {
      _mostrarMensaje(
        'La fecha final no puede ser anterior a la fecha inicial',
        esError: true,
      );

      return;
    }

    setState(() {
      fechaFin = fecha;
    });

    await cargarContabilidad();
  }

  // ============================================================
  // QUITAR FILTROS
  // ============================================================

  Future<void> limpiarFiltros() async {
    setState(() {
      fechaInicio = null;
      fechaFin = null;
    });

    await cargarContabilidad();
  }

  // ============================================================
  // EXPORTAR EXCEL
  // ============================================================

  Future<void> exportarExcel() async {
    if (_exportando) {
      return;
    }

    if (registros.isEmpty) {
      _mostrarMensaje('No hay operaciones para exportar', esError: true);

      return;
    }

    setState(() {
      exportandoExcel = true;
    });

    try {
      final analiticas = await _cargarAnaliticasParaInforme();

      // ========================================================
      // CREAR LIBRO
      // ========================================================

      final excel = Excel.createExcel();

      // ========================================================
      // RENOMBRAR HOJA PRINCIPAL
      // ========================================================

      excel.rename('Sheet1', 'Resumen');

      final resumenSheet = excel['Resumen'];

      // ========================================================
      // CREAR HOJA OPERACIONES
      // ========================================================

      final operacionesSheet = excel['Operaciones'];

      _agregarHojasAnalitica(excel, analiticas);

      // ========================================================
      // ESTILOS
      // ========================================================

      final tituloStyle = CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final encabezadoStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

      final etiquetaStyle = CellStyle(bold: true);

      // ========================================================
      // HOJA RESUMEN
      // ========================================================

      resumenSheet.merge(
        CellIndex.indexByString('A1'),
        CellIndex.indexByString('B1'),
        customValue: TextCellValue('PARKCONTROL - INFORME CONTABLE'),
      );

      resumenSheet.cell(CellIndex.indexByString('A1')).cellStyle = tituloStyle;

      resumenSheet.cell(CellIndex.indexByString('A3')).value = TextCellValue(
        'Fecha inicial',
      );

      resumenSheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(
        fechaVisible(fechaInicio),
      );

      resumenSheet.cell(CellIndex.indexByString('A4')).value = TextCellValue(
        'Fecha final',
      );

      resumenSheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(
        fechaVisible(fechaFin),
      );

      resumenSheet.cell(CellIndex.indexByString('A6')).value = TextCellValue(
        'Indicador',
      );

      resumenSheet.cell(CellIndex.indexByString('B6')).value = TextCellValue(
        'Valor',
      );

      resumenSheet.cell(CellIndex.indexByString('A6')).cellStyle =
          encabezadoStyle;

      resumenSheet.cell(CellIndex.indexByString('B6')).cellStyle =
          encabezadoStyle;

      // Vehículos

      resumenSheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(
        'Vehículos atendidos',
      );

      resumenSheet.cell(CellIndex.indexByString('B7')).value = IntCellValue(
        cantidadVehiculos,
      );

      // Ingresos

      resumenSheet.cell(CellIndex.indexByString('A8')).value = TextCellValue(
        'Ingresos totales',
      );

      resumenSheet.cell(CellIndex.indexByString('B8')).value = DoubleCellValue(
        ingresosTotales,
      );

      // Promedio

      resumenSheet.cell(CellIndex.indexByString('A9')).value = TextCellValue(
        'Promedio por vehículo',
      );

      resumenSheet.cell(CellIndex.indexByString('B9')).value = DoubleCellValue(
        promedioPorVehiculo,
      );

      // Minutos

      resumenSheet.cell(CellIndex.indexByString('A10')).value = TextCellValue(
        'Minutos totales',
      );

      resumenSheet.cell(CellIndex.indexByString('B10')).value = IntCellValue(
        minutosTotales,
      );

      // ========================================================
      // ESTILO ETIQUETAS
      // ========================================================

      for (final celda in ['A3', 'A4', 'A7', 'A8', 'A9', 'A10']) {
        resumenSheet.cell(CellIndex.indexByString(celda)).cellStyle =
            etiquetaStyle;
      }

      // ========================================================
      // ANCHO RESUMEN
      // ========================================================

      resumenSheet.setColumnWidth(0, 28);

      resumenSheet.setColumnWidth(1, 24);

      // ========================================================
      // HOJA OPERACIONES
      // ========================================================

      final encabezados = [
        'ID',
        'Patente',
        'Tipo',
        'Color',
        'Observación',
        'Entrada',
        'Salida',
        'Minutos',
        'Tarifa por minuto',
        'Monto',
        'Medio de pago',
        'Estado',
      ];

      operacionesSheet.appendRow(
        encabezados.map((texto) => TextCellValue(texto)).toList(),
      );

      // Aplicar estilo a encabezados

      for (int columna = 0; columna < encabezados.length; columna++) {
        operacionesSheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: 0),
                )
                .cellStyle =
            encabezadoStyle;
      }

      // ========================================================
      // REGISTROS
      // ========================================================

      for (int i = 0; i < registros.length; i++) {
        final registro = registros[i];

        final id = _toInt(registro['id']);

        final patente = registro['patente']?.toString().toUpperCase() ?? '';

        final tipo = registro['tipo']?.toString() ?? '';

        final color = registro['color']?.toString() ?? '';

        final observacion = registro['observacion']?.toString() ?? '';

        final entrada = formatearFecha(registro['horaEntrada']);

        final salida = formatearFecha(registro['horaSalida']);

        final minutos = _toInt(registro['minutos']);

        final tarifa = _toDouble(registro['tarifaPorMinuto']);

        final monto = _toDouble(registro['monto']);

        final estado = registro['estado']?.toString() ?? 'salio';

        final metodoPago = _etiquetaMetodoPago(registro['metodoPago']);

        operacionesSheet.appendRow([
          IntCellValue(id),
          TextCellValue(patente),
          TextCellValue(tipo),
          TextCellValue(color),
          TextCellValue(observacion),
          TextCellValue(entrada),
          TextCellValue(salida),
          IntCellValue(minutos),
          DoubleCellValue(tarifa),
          DoubleCellValue(monto),
          TextCellValue(metodoPago),
          TextCellValue(estado),
        ]);
      }

      // ========================================================
      // ANCHOS DE COLUMNAS
      // ========================================================

      operacionesSheet.setColumnWidth(0, 10);

      operacionesSheet.setColumnWidth(1, 14);

      operacionesSheet.setColumnWidth(2, 16);

      operacionesSheet.setColumnWidth(3, 16);

      operacionesSheet.setColumnWidth(4, 30);

      operacionesSheet.setColumnWidth(5, 20);

      operacionesSheet.setColumnWidth(6, 20);

      operacionesSheet.setColumnWidth(7, 12);

      operacionesSheet.setColumnWidth(8, 18);

      operacionesSheet.setColumnWidth(9, 16);

      operacionesSheet.setColumnWidth(10, 12);

      operacionesSheet.setColumnWidth(11, 12);

      // ========================================================
      // GUARDAR EN MEMORIA
      // ========================================================

      final bytes = excel.save();

      if (bytes == null || bytes.isEmpty) {
        throw Exception('No se pudo generar el archivo Excel');
      }

      final Uint8List archivo = Uint8List.fromList(bytes);

      // ========================================================
      // NOMBRE DEL ARCHIVO
      // ========================================================

      final nombreArchivo = _nombreArchivoExcel();

      // ========================================================
      // COMPARTIR
      // ========================================================

      await SharePlus.instance.share(
        ShareParams(
          title: 'Informe contable ParkControl',
          subject: 'Informe contable ParkControl',
          text: 'Informe contable generado desde ParkControl.',
          files: [
            XFile.fromData(
              archivo,
              name: nombreArchivo,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
        ),
      );

      if (!mounted) return;

      setState(() {
        exportandoExcel = false;
      });

      _mostrarMensaje('Excel generado correctamente');
    } catch (e) {
      debugPrint('ERROR EXPORTANDO EXCEL: $e');

      if (!mounted) return;

      setState(() {
        exportandoExcel = false;
      });

      _mostrarMensaje('No se pudo generar el archivo Excel', esError: true);
    }
  }

  // ============================================================
  // EXPORTAR PDF CONTABLE
  // ============================================================

  Future<void> exportarPdf() async {
    if (_exportando) return;

    if (registros.isEmpty) {
      _mostrarMensaje('No hay operaciones para exportar', esError: true);
      return;
    }

    setState(() {
      exportandoPdf = true;
    });

    try {
      final documento = pw.Document(
        title: 'Informe contable ParkControl',
        author: 'ParkControl',
      );
      final fechaGeneracion = formatearFecha(DateTime.now().toIso8601String());

      documento.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (contexto) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PARKCONTROL',
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.Text(
                'Informe contable Pro',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Divider(color: PdfColors.blue900),
            ],
          ),
          footer: (contexto) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Página ${contexto.pageNumber} de ${contexto.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (contexto) => [
            pw.SizedBox(height: 12),
            pw.Text(
              'Período: ${fechaVisible(fechaInicio)} - ${fechaVisible(fechaFin)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Generado: $fechaGeneracion',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              children: [
                _tarjetaPdf('Vehículos', '$cantidadVehiculos'),
                pw.SizedBox(width: 8),
                _tarjetaPdf('Ingresos', pesos(ingresosTotales)),
                pw.SizedBox(width: 8),
                _tarjetaPdf('Promedio', pesos(promedioPorVehiculo)),
                pw.SizedBox(width: 8),
                _tarjetaPdf('Minutos', '$minutosTotales'),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Operaciones cobradas',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue900,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headers: const [
                'Folio',
                'Patente',
                'Salida',
                'Min.',
                'Pago',
                'Monto',
              ],
              data: registros
                  .map(
                    (registro) => [
                      _toInt(registro['id']).toString(),
                      registro['patente']?.toString().toUpperCase() ?? '-',
                      formatearFecha(registro['horaSalida']),
                      _toInt(registro['minutos']).toString(),
                      _etiquetaMetodoPago(registro['metodoPago']),
                      pesos(registro['monto']),
                    ],
                  )
                  .toList(),
              columnWidths: {
                0: pw.FlexColumnWidth(0.65),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.8),
                3: pw.FlexColumnWidth(0.55),
                4: pw.FlexColumnWidth(1),
                5: pw.FlexColumnWidth(1),
              },
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              'Informe generado a partir de los movimientos registrados. '
              'Las estimaciones tributarias no reemplazan la declaración ante el SII.',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      );

      final archivo = await documento.save();
      await SharePlus.instance.share(
        ShareParams(
          title: 'Informe contable ParkControl',
          subject: 'Informe contable ParkControl',
          text: 'Informe contable generado desde ParkControl.',
          files: [
            XFile.fromData(
              Uint8List.fromList(archivo),
              name: _nombreArchivoPdf(),
              mimeType: 'application/pdf',
            ),
          ],
        ),
      );

      if (!mounted) return;
      setState(() {
        exportandoPdf = false;
      });
      _mostrarMensaje('PDF generado correctamente');
    } catch (e) {
      debugPrint('ERROR EXPORTANDO PDF: $e');
      if (!mounted) return;
      setState(() {
        exportandoPdf = false;
      });
      _mostrarMensaje('No se pudo generar el archivo PDF', esError: true);
    }
  }

  pw.Widget _tarjetaPdf(String titulo, String valor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.blueGrey200),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(titulo, style: const pw.TextStyle(fontSize: 7)),
            pw.SizedBox(height: 3),
            pw.Text(
              valor,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  String _nombreArchivoPdf() {
    final sufijo = fechaInicio != null && fechaFin != null
        ? '${_fechaApi(fechaInicio!)}_${_fechaApi(fechaFin!)}'
        : _fechaApi(DateTime.now());
    return 'parkcontrol_contabilidad_$sufijo.pdf';
  }

  String _etiquetaMetodoPago(dynamic valor) {
    switch (valor?.toString().trim().toLowerCase()) {
      case 'transferencia':
        return 'Transferencia';
      case 'tarjeta':
        return 'Tarjeta';
      case 'otro':
        return 'Otro';
      case 'efectivo':
      default:
        return 'Efectivo';
    }
  }

  // ============================================================
  // INFORMACIÓN OPERATIVA PARA EL LIBRO PRO
  // ============================================================

  Future<Map<String, Map<String, dynamic>>>
  _cargarAnaliticasParaInforme() async {
    const periodos = ['dia', 'semana', 'mes', 'semestre', 'ano'];

    final respuestas = await Future.wait(
      periodos.map((periodo) async {
        final respuesta = await ApiClient.get(
          Uri.parse('$apiUrl/api/pro/analitica?periodo=$periodo'),
        ).timeout(const Duration(seconds: 15));

        final cuerpo = jsonDecode(respuesta.body);

        if (respuesta.statusCode != 200 || cuerpo is! Map) {
          throw Exception(
            cuerpo is Map && cuerpo['mensaje'] != null
                ? cuerpo['mensaje'].toString()
                : 'No se pudo preparar el informe de $periodo',
          );
        }

        return MapEntry(periodo, Map<String, dynamic>.from(cuerpo));
      }),
    );

    return Map<String, Map<String, dynamic>>.fromEntries(respuestas);
  }

  void _agregarHojasAnalitica(
    Excel excel,
    Map<String, Map<String, dynamic>> analiticas,
  ) {
    const configuracion = <String, String>{
      'dia': 'Detalle diario',
      'semana': 'Detalle semanal',
      'mes': 'Detalle mensual',
      'semestre': 'Detalle semestral',
      'ano': 'Detalle anual',
    };

    final encabezado = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );
    final titulo = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
    );

    final resumenSheet = excel['Resumen por período'];
    resumenSheet.merge(
      CellIndex.indexByString('A1'),
      CellIndex.indexByString('F1'),
      customValue: TextCellValue('PARKCONTROL - RESUMEN OPERATIVO PRO'),
    );
    resumenSheet.cell(CellIndex.indexByString('A1')).cellStyle = titulo;
    resumenSheet.appendRow([
      TextCellValue('Período'),
      TextCellValue('Entradas'),
      TextCellValue('Salidas'),
      TextCellValue('Modificaciones'),
      TextCellValue('Eliminaciones'),
      TextCellValue('Ingresos brutos'),
    ]);

    for (var columna = 0; columna < 6; columna++) {
      resumenSheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: 1),
              )
              .cellStyle =
          encabezado;
      resumenSheet.setColumnWidth(columna, columna == 0 ? 18 : 18);
    }

    for (final periodo in configuracion.keys) {
      final resumen = analiticas[periodo]?['resumen'];
      final datos = resumen is Map
          ? Map<String, dynamic>.from(resumen)
          : <String, dynamic>{};

      resumenSheet.appendRow([
        TextCellValue(configuracion[periodo]!),
        IntCellValue(_toInt(datos['entradas'])),
        IntCellValue(_toInt(datos['salidas'])),
        IntCellValue(_toInt(datos['modificaciones'])),
        IntCellValue(_toInt(datos['eliminaciones'])),
        DoubleCellValue(_toDouble(datos['ingresosBrutos'])),
      ]);
    }

    for (final entrada in configuracion.entries) {
      final sheet = excel[entrada.value];
      final analitica = analiticas[entrada.key] ?? <String, dynamic>{};
      final puntosOriginales = analitica['puntos'];
      final puntos = puntosOriginales is List
          ? puntosOriginales
                .whereType<Map>()
                .map((punto) => Map<String, dynamic>.from(punto))
                .where((punto) => punto['disponible'] != false)
                .toList()
          : <Map<String, dynamic>>[];

      sheet.merge(
        CellIndex.indexByString('A1'),
        CellIndex.indexByString('F1'),
        customValue: TextCellValue(
          'PARKCONTROL - ${entrada.value.toUpperCase()}',
        ),
      );
      sheet.cell(CellIndex.indexByString('A1')).cellStyle = titulo;
      sheet.appendRow([
        TextCellValue('Corte'),
        TextCellValue('Entradas'),
        TextCellValue('Salidas'),
        TextCellValue('Modificaciones'),
        TextCellValue('Eliminaciones'),
        TextCellValue('Ingresos'),
      ]);

      for (var columna = 0; columna < 6; columna++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: 1),
                )
                .cellStyle =
            encabezado;
        sheet.setColumnWidth(columna, columna == 0 ? 18 : 16);
      }

      for (final punto in puntos) {
        sheet.appendRow([
          TextCellValue(punto['etiqueta']?.toString() ?? '-'),
          IntCellValue(_toInt(punto['entradas'])),
          IntCellValue(_toInt(punto['salidas'])),
          IntCellValue(_toInt(punto['modificaciones'])),
          IntCellValue(_toInt(punto['eliminaciones'])),
          DoubleCellValue(_toDouble(punto['ingresos'])),
        ]);
      }
    }
  }

  // ============================================================
  // NOMBRE ARCHIVO EXCEL
  // ============================================================

  String _nombreArchivoExcel() {
    if (fechaInicio != null && fechaFin != null) {
      return 'parkcontrol_contabilidad_'
          '${_fechaApi(fechaInicio!)}_'
          '${_fechaApi(fechaFin!)}.xlsx';
    }

    if (fechaInicio != null) {
      return 'parkcontrol_contabilidad_desde_'
          '${_fechaApi(fechaInicio!)}.xlsx';
    }

    if (fechaFin != null) {
      return 'parkcontrol_contabilidad_hasta_'
          '${_fechaApi(fechaFin!)}.xlsx';
    }

    final ahora = DateTime.now();

    return 'parkcontrol_contabilidad_'
        '${ahora.year}-'
        '${ahora.month.toString().padLeft(2, '0')}-'
        '${ahora.day.toString().padLeft(2, '0')}.xlsx';
  }

  // ============================================================
  // FECHA PARA API
  // ============================================================

  String _fechaApi(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // FECHA VISIBLE
  // ============================================================

  String fechaVisible(DateTime? fecha) {
    if (fecha == null) {
      return 'Todas';
    }

    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  // ============================================================
  // FECHA Y HORA
  // ============================================================

  String formatearFecha(dynamic valor) {
    if (valor == null) {
      return '-';
    }

    final texto = valor.toString();

    if (texto.isEmpty) {
      return '-';
    }

    try {
      final fecha = DateTime.parse(texto).toLocal();

      return '${fecha.day.toString().padLeft(2, '0')}/'
          '${fecha.month.toString().padLeft(2, '0')}/'
          '${fecha.year} '
          '${fecha.hour.toString().padLeft(2, '0')}:'
          '${fecha.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return texto;
    }
  }

  // ============================================================
  // FORMATO PESOS
  // ============================================================

  String pesos(dynamic valor) {
    final numero = _toDouble(valor).round();

    final texto = numero.toString();

    final buffer = StringBuffer();

    for (int i = 0; i < texto.length; i++) {
      final posicion = texto.length - i;

      buffer.write(texto[i]);

      if (posicion > 1 && posicion % 3 == 1) {
        buffer.write('.');
      }
    }

    return '\$${buffer.toString()}';
  }

  // ============================================================
  // DOUBLE
  // ============================================================

  double _toDouble(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  // ============================================================
  // INT
  // ============================================================

  int _toInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: esError ? Colors.red : const Color(0xFF20B46A),
        content: Text(mensaje),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),

        foregroundColor: Colors.white,

        title: const Text(
          'Contabilidad Pro',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando || _exportando ? null : cargarContabilidad,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: RefreshIndicator(
        onRefresh: cargarContabilidad,

        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.all(16),

          children: [
            // ==================================================
            // TÍTULO
            // ==================================================
            const Text(
              'Resumen contable',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Consulta los ingresos y operaciones del estacionamiento.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // FILTROS
            // ==================================================
            Card(
              elevation: 1,

              child: Padding(
                padding: const EdgeInsets.all(16),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Row(
                      children: [
                        Icon(Icons.date_range, color: Color(0xFF0F5ED7)),

                        SizedBox(width: 10),

                        Text(
                          'Período',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // FECHA INICIO
                    InkWell(
                      borderRadius: BorderRadius.circular(10),

                      onTap: cargando || _exportando
                          ? null
                          : seleccionarFechaInicio,

                      child: Container(
                        width: double.infinity,

                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),

                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),

                          borderRadius: BorderRadius.circular(10),
                        ),

                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 20),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  const Text(
                                    'Fecha inicial',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(
                                    fechaVisible(fechaInicio),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // FECHA FINAL
                    InkWell(
                      borderRadius: BorderRadius.circular(10),

                      onTap: cargando || _exportando
                          ? null
                          : seleccionarFechaFin,

                      child: Container(
                        width: double.infinity,

                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),

                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),

                          borderRadius: BorderRadius.circular(10),
                        ),

                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 20),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  const Text(
                                    'Fecha final',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),

                                  const SizedBox(height: 3),

                                  Text(
                                    fechaVisible(fechaFin),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // LIMPIAR
                    SizedBox(
                      width: double.infinity,

                      child: OutlinedButton.icon(
                        onPressed:
                            cargando ||
                                _exportando ||
                                (fechaInicio == null && fechaFin == null)
                            ? null
                            : limpiarFiltros,

                        icon: const Icon(Icons.filter_alt_off),

                        label: const Text('Limpiar filtros'),

                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F5ED7),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ==================================================
            // ERROR
            // ==================================================
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),

                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 28,
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                      IconButton(
                        onPressed: cargarContabilidad,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),

            if (cargando)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),

                child: LinearProgressIndicator(),
              ),

            // ==================================================
            // RESUMEN
            // ==================================================
            Row(
              children: [
                Expanded(
                  child: _tarjetaResumen(
                    icono: Icons.directions_car,
                    titulo: 'Vehículos',
                    valor: cargando ? '...' : cantidadVehiculos.toString(),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: _tarjetaResumen(
                    icono: Icons.attach_money,
                    titulo: 'Ingresos',
                    valor: cargando ? '...' : pesos(ingresosTotales),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _tarjetaResumen(
                    icono: Icons.analytics_outlined,
                    titulo: 'Promedio',
                    valor: cargando ? '...' : pesos(promedioPorVehiculo),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: _tarjetaResumen(
                    icono: Icons.schedule,
                    titulo: 'Minutos',
                    valor: cargando ? '...' : '$minutosTotales',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ==================================================
            // BOTÓN EXCEL
            // ==================================================
            SizedBox(
              width: double.infinity,

              height: 52,

              child: ElevatedButton.icon(
                onPressed: cargando || _exportando || registros.isEmpty
                    ? null
                    : exportarExcel,

                icon: exportandoExcel
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.file_download_outlined),

                label: Text(
                  exportandoExcel
                      ? 'Generando Excel...'
                      : 'Exportar contabilidad a Excel',

                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF188038),

                  foregroundColor: Colors.white,

                  disabledBackgroundColor: Colors.grey.shade400,

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: cargando || _exportando || registros.isEmpty
                    ? null
                    : exportarPdf,
                icon: exportandoPdf
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  exportandoPdf
                      ? 'Generando PDF...'
                      : 'Exportar informe contable a PDF',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB3261E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ==================================================
            // DETALLE
            // ==================================================
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Detalle de operaciones',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF172B4D),
                    ),
                  ),
                ),

                Text(
                  '${registros.length} registro(s)',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ==================================================
            // SIN REGISTROS
            // ==================================================
            if (!cargando && registros.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),

                  child: Column(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 55,
                        color: Colors.grey,
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'No hay operaciones en este período',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),

            // ==================================================
            // LISTA
            // ==================================================
            ...registros.map((registro) => _tarjetaRegistro(registro)),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TARJETA RESUMEN
  // ============================================================

  Widget _tarjetaResumen({
    required IconData icono,
    required String titulo,
    required String valor,
  }) {
    return Card(
      elevation: 1,

      margin: EdgeInsets.zero,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(14),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Container(
              width: 42,

              height: 42,

              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),

                borderRadius: BorderRadius.circular(10),
              ),

              child: Icon(icono, color: const Color(0xFF0F5ED7)),
            ),

            const SizedBox(height: 10),

            Text(
              titulo,

              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),

            const SizedBox(height: 4),

            Text(
              valor,

              maxLines: 1,

              overflow: TextOverflow.ellipsis,

              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
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

  Widget _tarjetaRegistro(Map<String, dynamic> registro) {
    final patente = registro['patente']?.toString().toUpperCase() ?? '-';

    final tipo = registro['tipo']?.toString() ?? '-';

    final color = registro['color']?.toString() ?? '-';

    final observacion = registro['observacion']?.toString() ?? '';

    final horaEntrada = registro['horaEntrada'];

    final horaSalida = registro['horaSalida'];

    final minutos = _toInt(registro['minutos']);

    final tarifa = _toDouble(registro['tarifaPorMinuto']);

    final monto = _toDouble(registro['monto']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),

      elevation: 1,

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                Container(
                  width: 46,

                  height: 46,

                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),

                    borderRadius: BorderRadius.circular(10),
                  ),

                  child: const Icon(
                    Icons.directions_car,
                    color: Color(0xFF0F5ED7),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        patente,

                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        '$tipo • $color',

                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  pesos(monto),

                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF20B46A),
                  ),
                ),
              ],
            ),

            const Divider(height: 26),

            _dato('Entrada', formatearFecha(horaEntrada)),

            _dato('Salida', formatearFecha(horaSalida)),

            _dato('Tiempo', '$minutos min'),

            _dato('Tarifa', '${pesos(tarifa)}/min'),

            if (observacion.isNotEmpty) _dato('Observación', observacion),

            const Divider(height: 22),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,

              children: [
                const Text(
                  'Total cobrado',

                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),

                Text(
                  pesos(monto),

                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF172B4D),
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
  // DATO
  // ============================================================

  Widget _dato(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 95,

            child: Text(
              titulo,

              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),

          Expanded(
            child: Text(
              valor,

              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
