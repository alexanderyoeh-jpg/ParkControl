import 'dart:typed_data';

import 'socket_printer_stub.dart'
    if (dart.library.io) 'socket_printer_io.dart' as impl;

class SocketPrinterService {
  const SocketPrinterService._();

  static Future<bool> probarConexion(String host, int puerto, {Duration timeout = const Duration(seconds: 3)}) {
    return impl.SocketPrinterImpl.probarConexion(host, puerto, timeout: timeout);
  }

  static Future<bool> enviarBytes(String host, int puerto, Uint8List bytes, {Duration timeout = const Duration(seconds: 5)}) {
    return impl.SocketPrinterImpl.enviarBytes(host, puerto, bytes, timeout: timeout);
  }
}
