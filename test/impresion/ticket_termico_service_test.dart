import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkcontrol/services/esc_pos_service.dart';
import 'package:parkcontrol/services/impresion_config_service.dart';
import 'package:parkcontrol/services/ticket_termico_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImpresionConfigService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('retorna configuración predeterminada de 58mm', () async {
      final config = await ImpresionConfigService.obtenerConfiguracion();
      expect(config.anchoPapel, AnchoPapelTermico.mm58);
      expect(config.imprimirEntradaAutomatica, isTrue);
      expect(config.imprimirSalidaAutomatica, isTrue);
      expect(config.nombreEstacionamiento, 'ParkControl');
    });

    test('guarda y recupera cambios de configuración', () async {
      const nueva = ImpresionConfig(
        anchoPapel: AnchoPapelTermico.mm80,
        imprimirEntradaAutomatica: false,
        imprimirSalidaAutomatica: true,
        nombreEstacionamiento: 'Estacionamiento Test',
        encabezadoPersonalizado: 'RUT: 12.345.678-9',
        piePagina: 'Gracias por preferirnos',
        incluirCodigoBarras: false,
      );

      await ImpresionConfigService.guardarConfiguracion(nueva);
      final leida = await ImpresionConfigService.obtenerConfiguracion();

      expect(leida.anchoPapel, AnchoPapelTermico.mm80);
      expect(leida.imprimirEntradaAutomatica, isFalse);
      expect(leida.nombreEstacionamiento, 'Estacionamiento Test');
      expect(leida.encabezadoPersonalizado, 'RUT: 12.345.678-9');
      expect(leida.incluirCodigoBarras, isFalse);
    });
  });

  group('TicketTermicoService', () {
    test('genera PDF válido para ticket de entrada en 58mm', () async {
      final pdfBytes = await TicketTermicoService.generarTicketEntradaPdf(
        patente: 'ABCD-12',
        tipoVehiculo: 'Auto',
        horaEntrada: DateTime(2026, 8, 20, 14, 30),
        color: 'Rojo',
        observacion: 'Rayón lateral previo',
        tarifaPorMinuto: 30.0,
      );

      expect(pdfBytes, isNotEmpty);
      final encabezado = String.fromCharCodes(pdfBytes.take(4));
      expect(encabezado, '%PDF');
    });

    test('genera PDF válido para ticket de salida en 80mm', () async {
      const config80 = ImpresionConfig(anchoPapel: AnchoPapelTermico.mm80);

      final pdfBytes = await TicketTermicoService.generarTicketSalidaPdf(
        patente: 'WXYZ-99',
        horaEntrada: DateTime(2026, 8, 20, 10, 0),
        horaSalida: DateTime(2026, 8, 20, 12, 30),
        minutosTotales: 150,
        totalPagar: 4500.0,
        metodoPago: 'efectivo',
        cajeroNombre: 'Juan Cajero',
        tarifaPorMinuto: 30.0,
        efectivoRecibido: 5000.0,
        vuelto: 500.0,
        config: config80,
      );

      expect(pdfBytes, isNotEmpty);
      final encabezado = String.fromCharCodes(pdfBytes.take(4));
      expect(encabezado, '%PDF');
    });

    test('genera PDF de prueba correctamente', () async {
      final pdfBytes = await TicketTermicoService.generarTicketPruebaPdf();
      expect(pdfBytes, isNotEmpty);
      final encabezado = String.fromCharCodes(pdfBytes.take(4));
      expect(encabezado, '%PDF');
    });
  });

  group('EscPosGenerator', () {
    test('genera secuencias de bytes ESC/POS válidas con corte de papel', () {
      final bytes = EscPosGenerator.generarTicketEntradaBytes(
        nombreEstacionamiento: 'ParkControl Central',
        patente: 'KJHG-44',
        tipoVehiculo: 'Camioneta',
        horaEntrada: DateTime(2026, 8, 20, 16, 0),
        tarifaPorMinuto: 25.0,
        piePagina: 'Conserve su ticket',
      );

      expect(bytes, isNotEmpty);
      // Debe comenzar con inicialización ESC @ (0x1B, 0x40)
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);

      // Debe contener la patente en texto
      final contenidoTexto = latin1.decode(bytes);
      expect(contenidoTexto, contains('KJHG-44'));
      expect(contenidoTexto, contains('PARKCONTROL CENTRAL'));
    });
  });
}
