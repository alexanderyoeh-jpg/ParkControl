import 'dart:typed_data';

abstract class SocketPrinterImpl {
  static Future<bool> probarConexion(String host, int puerto, {Duration timeout = const Duration(seconds: 3)}) async {
    return false;
  }

  static Future<bool> enviarBytes(String host, int puerto, Uint8List bytes, {Duration timeout = const Duration(seconds: 5)}) async {
    return false;
  }
}
