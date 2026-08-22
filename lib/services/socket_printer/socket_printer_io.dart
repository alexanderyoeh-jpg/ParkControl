import 'dart:io';
import 'dart:typed_data';

abstract class SocketPrinterImpl {
  static Future<bool> probarConexion(String host, int puerto, {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(host, puerto, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enviarBytes(String host, int puerto, Uint8List bytes, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final socket = await Socket.connect(host, puerto, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
