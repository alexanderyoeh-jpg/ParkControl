import 'package:flutter_test/flutter_test.dart';
import 'package:parkcontrol/offline/offline_app_service.dart';

void main() {
  test('el cierre de caja se bloquea ante operaciones no confirmadas', () {
    const resumen = ResumenSincronizacionOffline(
      pendientes: 1,
      enviando: 2,
      conflictos: 3,
      bloqueadas: 4,
      otras: 1,
    );

    expect(resumen.totalQueImpidenCierreCaja, 11);
    expect(resumen.impideCierreCaja, isTrue);
  });

  test('una cola sin operaciones activas permite cerrar caja', () {
    const resumen = ResumenSincronizacionOffline.vacio();

    expect(resumen.totalQueImpidenCierreCaja, 0);
    expect(resumen.impideCierreCaja, isFalse);
  });
}
