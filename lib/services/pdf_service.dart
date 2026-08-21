import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Presenta documentos PDF ya descargados de una ruta autenticada.
///
/// [Printing.layoutPdf] utiliza los mecanismos nativos de Android/iOS y el
/// diálogo de impresión/guardado del navegador en web. Así no necesitamos
/// abrir una URL con el Bearer token como parámetro de consulta.
class PdfService {
  const PdfService._();

  static Future<void> imprimirOGuardar(
    Uint8List bytes, {
    required String nombreArchivo,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('No hay contenido PDF para abrir');
    }

    await Printing.layoutPdf(name: nombreArchivo, onLayout: (_) async => bytes);
  }
}
