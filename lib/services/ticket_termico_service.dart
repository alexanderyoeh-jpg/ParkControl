import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'esc_pos_service.dart';
import 'impresion_config_service.dart';
import 'socket_printer/socket_printer.dart';

class TicketTermicoService {
  const TicketTermicoService._();

  static PdfPageFormat _formatoPagina(AnchoPapelTermico ancho) {
    if (ancho == AnchoPapelTermico.mm80) {
      return PdfPageFormat.roll80.copyWith(
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
        marginLeft: 4 * PdfPageFormat.mm,
        marginRight: 4 * PdfPageFormat.mm,
      );
    }

    return PdfPageFormat.roll57.copyWith(
      marginTop: 2 * PdfPageFormat.mm,
      marginBottom: 2 * PdfPageFormat.mm,
      marginLeft: 2 * PdfPageFormat.mm,
      marginRight: 2 * PdfPageFormat.mm,
    );
  }

  // ============================================================
  // TICKET DE ENTRADA
  // ============================================================

  static Future<Uint8List> generarTicketEntradaPdf({
    required String patente,
    required String tipoVehiculo,
    required DateTime horaEntrada,
    String? color,
    String? observacion,
    double? tarifaPorMinuto,
    ImpresionConfig? config,
  }) async {
    final conf = config ?? await ImpresionConfigService.obtenerConfiguracion();
    final formato = _formatoPagina(conf.anchoPapel);
    final doc = pw.Document();

    final horaFormateada =
        '${horaEntrada.day.toString().padLeft(2, '0')}/${horaEntrada.month.toString().padLeft(2, '0')}/${horaEntrada.year} '
        '${horaEntrada.hour.toString().padLeft(2, '0')}:${horaEntrada.minute.toString().padLeft(2, '0')}:${horaEntrada.second.toString().padLeft(2, '0')}';

    final nombreEst = conf.nombreEstacionamiento.isNotEmpty
        ? conf.nombreEstacionamiento
        : 'ParkControl';

    doc.addPage(
      pw.Page(
        pageFormat: formato,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Encabezado
              pw.Text(
                nombreEst.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              if (conf.encabezadoPersonalizado.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  conf.encabezadoPersonalizado,
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),
              pw.Text(
                'TICKET DE ENTRADA',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 6),

              // Patente destacada
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1.5),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Text(
                  patente.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),

              // Detalle
              _filaTexto('Tipo:', tipoVehiculo),
              if (color != null && color.isNotEmpty && color != 'No especificado')
                _filaTexto('Color:', color),
              _filaTexto('Ingreso:', horaFormateada),
              if (tarifaPorMinuto != null && tarifaPorMinuto > 0)
                _filaTexto(
                  'Tarifa:',
                  '\$${tarifaPorMinuto.toStringAsFixed(0)} / min',
                ),

              pw.SizedBox(height: 6),

              // Código de barras
              if (conf.incluirCodigoBarras && patente.isNotEmpty) ...[
                pw.Container(
                  height: 35,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: patente.toUpperCase(),
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  patente.toUpperCase(),
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 6),
              ],

              // Pie de página
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),
              pw.Text(
                conf.piePagina,
                style: const pw.TextStyle(fontSize: 7),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // ============================================================
  // COMPROBANTE DE SALIDA / COBRO
  // ============================================================

  static Future<Uint8List> generarTicketSalidaPdf({
    required String patente,
    required DateTime horaEntrada,
    required DateTime horaSalida,
    required int minutosTotales,
    required double totalPagar,
    required String metodoPago,
    String? cajeroNombre,
    double? tarifaPorMinuto,
    double? efectivoRecibido,
    double? vuelto,
    ImpresionConfig? config,
  }) async {
    final conf = config ?? await ImpresionConfigService.obtenerConfiguracion();
    final formato = _formatoPagina(conf.anchoPapel);
    final doc = pw.Document();

    final fechaSalidaFormateada =
        '${horaSalida.day.toString().padLeft(2, '0')}/${horaSalida.month.toString().padLeft(2, '0')}/${horaSalida.year} '
        '${horaSalida.hour.toString().padLeft(2, '0')}:${horaSalida.minute.toString().padLeft(2, '0')}';

    final fechaEntradaFormateada =
        '${horaEntrada.day.toString().padLeft(2, '0')}/${horaEntrada.month.toString().padLeft(2, '0')}/${horaEntrada.year} '
        '${horaEntrada.hour.toString().padLeft(2, '0')}:${horaEntrada.minute.toString().padLeft(2, '0')}';

    final horas = minutosTotales ~/ 60;
    final mins = minutosTotales % 60;
    final tiempoLegible = horas > 0
        ? '$horas h $mins min ($minutosTotales min)'
        : '$minutosTotales min';

    final nombreEst = conf.nombreEstacionamiento.isNotEmpty
        ? conf.nombreEstacionamiento
        : 'ParkControl';

    doc.addPage(
      pw.Page(
        pageFormat: formato,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                nombreEst.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              if (conf.encabezadoPersonalizado.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  conf.encabezadoPersonalizado,
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),
              pw.Text(
                'COMPROBANTE DE COBRO',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 6),

              // Patente
              pw.Text(
                'PATENTE: ${patente.toUpperCase()}',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),

              _filaTexto('Entrada:', fechaEntradaFormateada),
              _filaTexto('Salida:', fechaSalidaFormateada),
              _filaTexto('Permanencia:', tiempoLegible),
              if (tarifaPorMinuto != null && tarifaPorMinuto > 0)
                _filaTexto(
                  'Tarifa:',
                  '\$${tarifaPorMinuto.toStringAsFixed(0)} / min',
                ),

              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),

              // Total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL:',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${totalPagar.toStringAsFixed(0)} CLP',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 4),
              _filaTexto('Medio de pago:', metodoPago.toUpperCase()),
              if (efectivoRecibido != null && efectivoRecibido > 0)
                _filaTexto('Efectivo:', '\$${efectivoRecibido.toStringAsFixed(0)}'),
              if (vuelto != null && vuelto > 0)
                _filaTexto('Vuelto:', '\$${vuelto.toStringAsFixed(0)}'),
              if (cajeroNombre != null && cajeroNombre.isNotEmpty)
                _filaTexto('Atendido por:', cajeroNombre),

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),
              pw.Text(
                '¡Gracias por su visita!',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // ============================================================
  // TICKET DE PRUEBA
  // ============================================================

  static Future<Uint8List> generarTicketPruebaPdf({
    ImpresionConfig? config,
  }) async {
    final conf = config ?? await ImpresionConfigService.obtenerConfiguracion();
    final formato = _formatoPagina(conf.anchoPapel);
    final doc = pw.Document();
    final ahora = DateTime.now();

    doc.addPage(
      pw.Page(
        pageFormat: formato,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                conf.nombreEstacionamiento.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.Text(
                '*** PRUEBA DE IMPRESIÓN ***',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 6),
              _filaTexto('Ancho papel:', conf.anchoPapel.etiqueta),
              _filaTexto('Fecha y hora:', '${ahora.day}/${ahora.month}/${ahora.year} ${ahora.hour}:${ahora.minute}'),
              _filaTexto('Estado:', 'OPERATIVO'),
              pw.SizedBox(height: 6),
              if (conf.incluirCodigoBarras) ...[
                pw.Container(
                  height: 30,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: 'PARKCONTROL-OK',
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text('PARKCONTROL-OK', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 6),
              ],
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 4),
              pw.Text(
                'Impresora térmica configurada correctamente.',
                style: const pw.TextStyle(fontSize: 8),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // ============================================================
  // ACCIONES DE IMPRESIÓN DIRECTA O NATIVA
  // ============================================================

  static Future<void> imprimirTicketEntrada({
    required String patente,
    required String tipoVehiculo,
    required DateTime horaEntrada,
    String? color,
    String? observacion,
    double? tarifaPorMinuto,
  }) async {
    final config = await ImpresionConfigService.obtenerConfiguracion();

    // 1. Envío Wi-Fi / Red Local directo si está configurado
    if (config.tipoConexion == TipoConexionImpresora.redWifi && config.ipImpresora.trim().isNotEmpty) {
      try {
        final escPosBytes = EscPosGenerator.generarTicketEntradaBytes(
          nombreEstacionamiento: config.nombreEstacionamiento,
          patente: patente,
          tipoVehiculo: tipoVehiculo,
          horaEntrada: horaEntrada,
          tarifaPorMinuto: tarifaPorMinuto,
          piePagina: config.piePagina,
          anchoCaracteres: config.anchoPapel == AnchoPapelTermico.mm80 ? 48 : 32,
        );

        final enviado = await SocketPrinterService.enviarBytes(
          config.ipImpresora.trim(),
          config.puertoImpresora,
          escPosBytes,
        );

        if (enviado) return;
      } catch (_) {
        // Fallback a spooler si falla el socket
      }
    }

    // 2. Envío Bluetooth / USB / Spooler nativo
    final pdfBytes = await generarTicketEntradaPdf(
      patente: patente,
      tipoVehiculo: tipoVehiculo,
      horaEntrada: horaEntrada,
      color: color,
      observacion: observacion,
      tarifaPorMinuto: tarifaPorMinuto,
      config: config,
    );

    await _enviarAImpresora(pdfBytes, nombreDocumento: 'ticket-entrada-$patente.pdf');
  }

  static Future<void> imprimirTicketSalida({
    required String patente,
    required DateTime horaEntrada,
    required DateTime horaSalida,
    required int minutosTotales,
    required double totalPagar,
    required String metodoPago,
    String? cajeroNombre,
    double? tarifaPorMinuto,
    double? efectivoRecibido,
    double? vuelto,
  }) async {
    final config = await ImpresionConfigService.obtenerConfiguracion();

    // 1. Envío Wi-Fi / Red Local directo
    if (config.tipoConexion == TipoConexionImpresora.redWifi && config.ipImpresora.trim().isNotEmpty) {
      try {
        final escPosBytes = EscPosGenerator.generarTicketSalidaBytes(
          nombreEstacionamiento: config.nombreEstacionamiento,
          patente: patente,
          horaEntrada: horaEntrada,
          horaSalida: horaSalida,
          minutosTotales: minutosTotales,
          totalPagar: totalPagar,
          metodoPago: metodoPago,
          cajeroNombre: cajeroNombre,
          tarifaPorMinuto: tarifaPorMinuto,
          efectivoRecibido: efectivoRecibido,
          vuelto: vuelto,
          anchoCaracteres: config.anchoPapel == AnchoPapelTermico.mm80 ? 48 : 32,
        );

        final enviado = await SocketPrinterService.enviarBytes(
          config.ipImpresora.trim(),
          config.puertoImpresora,
          escPosBytes,
        );

        if (enviado) return;
      } catch (_) {
        // Fallback a spooler
      }
    }

    // 2. Envío Bluetooth / USB / Spooler nativo
    final pdfBytes = await generarTicketSalidaPdf(
      patente: patente,
      horaEntrada: horaEntrada,
      horaSalida: horaSalida,
      minutosTotales: minutosTotales,
      totalPagar: totalPagar,
      metodoPago: metodoPago,
      cajeroNombre: cajeroNombre,
      tarifaPorMinuto: tarifaPorMinuto,
      efectivoRecibido: efectivoRecibido,
      vuelto: vuelto,
      config: config,
    );

    await _enviarAImpresora(pdfBytes, nombreDocumento: 'boleta-salida-$patente.pdf');
  }

  static Future<void> imprimirTicketPrueba() async {
    final config = await ImpresionConfigService.obtenerConfiguracion();

    // 1. Envío Wi-Fi / Red Local directo
    if (config.tipoConexion == TipoConexionImpresora.redWifi && config.ipImpresora.trim().isNotEmpty) {
      try {
        final escPosBytes = EscPosGenerator.generarTicketPruebaBytes(
          nombreEstacionamiento: config.nombreEstacionamiento,
          anchoCaracteres: config.anchoPapel == AnchoPapelTermico.mm80 ? 48 : 32,
        );

        final enviado = await SocketPrinterService.enviarBytes(
          config.ipImpresora.trim(),
          config.puertoImpresora,
          escPosBytes,
        );

        if (enviado) return;
      } catch (_) {
        // Fallback a spooler
      }
    }

    // 2. Envío Bluetooth / USB / Spooler nativo
    final pdfBytes = await generarTicketPruebaPdf(config: config);
    await _enviarAImpresora(pdfBytes, nombreDocumento: 'ticket-prueba.pdf');
  }

  static Future<void> _enviarAImpresora(
    Uint8List bytes, {
    required String nombreDocumento,
  }) async {
    final config = await ImpresionConfigService.obtenerConfiguracion();

    if (config.impresoraUrl != null && config.impresoraUrl!.isNotEmpty) {
      try {
        final impresoras = await Printing.listPrinters();
        final seleccionada = impresoras.firstWhere(
          (p) => p.url == config.impresoraUrl,
          orElse: () => impresoras.firstWhere(
            (p) => p.name == config.impresoraNombre,
            orElse: () => impresoras.first,
          ),
        );

        final exito = await Printing.directPrintPdf(
          printer: seleccionada,
          onLayout: (_) async => bytes,
          name: nombreDocumento,
        );

        if (exito) return;
      } catch (_) {
        // Fallback al diálogo nativo de impresión si la directa falla
      }
    }

    await Printing.layoutPdf(
      name: nombreDocumento,
      onLayout: (_) async => bytes,
    );
  }

  static pw.Widget _filaTexto(String etiqueta, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            etiqueta,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            valor,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }
}
