import 'package:flutter_test/flutter_test.dart';
import 'package:parkcontrol/models/abonado.dart';

void main() {
  group('Abonado Model', () {
    test('parses JSON correctamente con cálculos de estado', () {
      final json = {
        'id': 10,
        'nombreTitular': 'Empresa Transporte SA',
        'rut': '77.888.999-0',
        'telefono': '+56987654321',
        'email': 'contacto@transporte.cl',
        'patente': 'GGHH-22',
        'tipoVehiculo': 'Camioneta',
        'montoMensual': 75000.0,
        'fechaInicio': '2026-08-01',
        'fechaVencimiento': '2026-09-01',
        'estado': 'activo',
        'observacion': 'Estacionamiento 12',
        'estadoComercial': 'al_dia',
      };

      final abonado = Abonado.fromJson(json);

      expect(abonado.id, 10);
      expect(abonado.nombreTitular, 'Empresa Transporte SA');
      expect(abonado.patente, 'GGHH-22');
      expect(abonado.montoMensual, 75000.0);
      expect(abonado.estaVigente, isTrue);
      expect(abonado.etiquetaEstado, contains('Al día'));
    });

    test('reconoce estado vencido y suspendido', () {
      const vencido = Abonado(
        id: 1,
        nombreTitular: 'Pedro Pérez',
        patente: 'AA-11-22',
        tipoVehiculo: 'Auto',
        montoMensual: 50000,
        fechaInicio: '2026-06-01',
        fechaVencimiento: '2026-07-01',
        estado: 'activo',
        estadoComercial: 'vencido',
      );

      expect(vencido.estaVigente, isFalse);
      expect(vencido.etiquetaEstado, 'Vencido');

      const suspendido = Abonado(
        id: 2,
        nombreTitular: 'Ana Gómez',
        patente: 'BB-22-33',
        tipoVehiculo: 'Auto',
        montoMensual: 50000,
        fechaInicio: '2026-08-01',
        fechaVencimiento: '2026-09-01',
        estado: 'suspendido',
        estadoComercial: 'suspendido',
      );

      expect(suspendido.estaVigente, isFalse);
      expect(suspendido.etiquetaEstado, 'Suspendido');
    });
  });
}
