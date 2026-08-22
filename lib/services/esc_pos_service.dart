import 'dart:convert';
import 'dart:typed_data';

/// Generador de comandos binarios ESC/POS nativos para impresoras térmicas.
/// Permite enviar secuencias de bytes directas por Bluetooth, USB, o Socket TCP Wi-Fi.
class EscPosGenerator {
  EscPosGenerator() : _buffer = <int>[];

  final List<int> _buffer;

  Uint8List toBytes() => Uint8List.fromList(_buffer);

  void reset() {
    _buffer.clear();
    // ESC @ (Initialize printer)
    _buffer.addAll([0x1B, 0x40]);
  }

  void alignLeft() {
    // ESC a 0
    _buffer.addAll([0x1B, 0x61, 0x00]);
  }

  void alignCenter() {
    // ESC a 1
    _buffer.addAll([0x1B, 0x61, 0x01]);
  }

  void alignRight() {
    // ESC a 2
    _buffer.addAll([0x1B, 0x61, 0x02]);
  }

  void bold(bool enable) {
    // ESC E n
    _buffer.addAll([0x1B, 0x45, enable ? 0x01 : 0x00]);
  }

  void doubleSize(bool enable) {
    // GS ! n
    _buffer.addAll([0x1D, 0x21, enable ? 0x11 : 0x00]);
  }

  void text(String text) {
    // Codificación Latin-1 / ASCII estándar para impresoras térmicas
    _buffer.addAll(latin1.encode(text));
  }

  void textLine(String text) {
    this.text('$text\n');
  }

  void divider({int length = 32}) {
    textLine('-' * length);
  }

  void feed(int lines) {
    // ESC d n
    _buffer.addAll([0x1B, 0x64, lines]);
  }

  void cutPaper() {
    feed(3);
    // GS V 66 0 (Cut paper)
    _buffer.addAll([0x1D, 0x56, 0x42, 0x00]);
  }

  /// Genera un ticket de entrada en bytes ESC/POS puros
  static Uint8List generarTicketEntradaBytes({
    required String nombreEstacionamiento,
    required String patente,
    required String tipoVehiculo,
    required DateTime horaEntrada,
    double? tarifaPorMinuto,
    String? piePagina,
    int anchoCaracteres = 32,
  }) {
    final g = EscPosGenerator()..reset();

    final horaFormateada =
        '${horaEntrada.day.toString().padLeft(2, '0')}/${horaEntrada.month.toString().padLeft(2, '0')}/${horaEntrada.year} '
        '${horaEntrada.hour.toString().padLeft(2, '0')}:${horaEntrada.minute.toString().padLeft(2, '0')}';

    // Encabezado
    g.alignCenter();
    g.bold(true);
    g.textLine(nombreEstacionamiento.toUpperCase());
    g.bold(false);
    g.divider(length: anchoCaracteres);
    g.textLine('TICKET DE ENTRADA');
    g.divider(length: anchoCaracteres);

    // Patente grande
    g.feed(1);
    g.doubleSize(true);
    g.bold(true);
    g.textLine(patente.toUpperCase());
    g.doubleSize(false);
    g.bold(false);
    g.feed(1);

    // Detalle
    g.alignLeft();
    g.textLine('Tipo:    $tipoVehiculo');
    g.textLine('Ingreso: $horaFormateada');
    if (tarifaPorMinuto != null && tarifaPorMinuto > 0) {
      g.textLine('Tarifa:  \$${tarifaPorMinuto.toStringAsFixed(0)} / min');
    }

    g.divider(length: anchoCaracteres);
    if (piePagina != null && piePagina.isNotEmpty) {
      g.alignCenter();
      g.textLine(piePagina);
    }

    g.cutPaper();
    return g.toBytes();
  }

  /// Genera un ticket de salida / boleta en bytes ESC/POS
  static Uint8List generarTicketSalidaBytes({
    required String nombreEstacionamiento,
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
    int anchoCaracteres = 32,
  }) {
    final g = EscPosGenerator()..reset();

    final entradaFmt =
        '${horaEntrada.day.toString().padLeft(2, '0')}/${horaEntrada.month.toString().padLeft(2, '0')} '
        '${horaEntrada.hour.toString().padLeft(2, '0')}:${horaEntrada.minute.toString().padLeft(2, '0')}';
    final salidaFmt =
        '${horaSalida.day.toString().padLeft(2, '0')}/${horaSalida.month.toString().padLeft(2, '0')} '
        '${horaSalida.hour.toString().padLeft(2, '0')}:${horaSalida.minute.toString().padLeft(2, '0')}';

    final horas = minutosTotales ~/ 60;
    final mins = minutosTotales % 60;
    final tiempoLegible = horas > 0 ? '${horas}h ${mins}m' : '${mins} min';

    // Encabezado
    g.alignCenter();
    g.bold(true);
    g.textLine(nombreEstacionamiento.toUpperCase());
    g.bold(false);
    g.divider(length: anchoCaracteres);
    g.textLine('COMPROBANTE DE PAGO');
    g.divider(length: anchoCaracteres);

    // Patente
    g.feed(1);
    g.doubleSize(true);
    g.bold(true);
    g.textLine(patente.toUpperCase());
    g.doubleSize(false);
    g.bold(false);
    g.feed(1);

    // Detalle de tiempos
    g.alignLeft();
    g.textLine('Entrada:      $entradaFmt');
    g.textLine('Salida:       $salidaFmt');
    g.textLine('Permanencia:  $tiempoLegible');
    if (tarifaPorMinuto != null && tarifaPorMinuto > 0) {
      g.textLine('Tarifa:       \$${tarifaPorMinuto.toStringAsFixed(0)} / min');
    }

    g.divider(length: anchoCaracteres);

    // Total destacado
    g.bold(true);
    g.doubleSize(true);
    g.textLine('TOTAL: \$${totalPagar.toStringAsFixed(0)} CLP');
    g.doubleSize(false);
    g.bold(false);

    g.divider(length: anchoCaracteres);
    g.textLine('Pago:         ${metodoPago.toUpperCase()}');
    if (efectivoRecibido != null && efectivoRecibido > 0) {
      g.textLine('Efectivo:     \$${efectivoRecibido.toStringAsFixed(0)}');
    }
    if (vuelto != null && vuelto > 0) {
      g.textLine('Vuelto:       \$${vuelto.toStringAsFixed(0)}');
    }
    if (cajeroNombre != null && cajeroNombre.isNotEmpty) {
      g.textLine('Atendido:     $cajeroNombre');
    }

    g.divider(length: anchoCaracteres);
    g.alignCenter();
    g.textLine('¡Gracias por su visita!');

    g.cutPaper();
    return g.toBytes();
  }

  /// Genera un ticket de prueba en bytes ESC/POS
  static Uint8List generarTicketPruebaBytes({
    required String nombreEstacionamiento,
    int anchoCaracteres = 32,
  }) {
    final g = EscPosGenerator()..reset();
    g.alignCenter();
    g.bold(true);
    g.textLine(nombreEstacionamiento.toUpperCase());
    g.divider(length: anchoCaracteres);
    g.textLine('PRUEBA DE IMPRESIÓN');
    g.divider(length: anchoCaracteres);
    g.feed(1);
    g.doubleSize(true);
    g.textLine('PARKCONTROL OK');
    g.doubleSize(false);
    g.feed(1);
    g.textLine('Impresora térmica conectada correctamente.');
    g.divider(length: anchoCaracteres);
    g.cutPaper();
    return g.toBytes();
  }
}
