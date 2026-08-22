import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/actualizacion_service.dart';

class ModalDescargas extends StatefulWidget {
  const ModalDescargas({super.key});

  static Future<void> mostrar(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ModalDescargas(),
    );
  }

  @override
  State<ModalDescargas> createState() => _ModalDescargasState();
}

class _ModalDescargasState extends State<ModalDescargas> {
  final _servicio = const ActualizacionService();
  InfoVersion? _info;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarInfo();
  }

  Future<void> _cargarInfo() async {
    final info = await _servicio.consultarUltimaVersion();
    if (!mounted) return;
    setState(() {
      _info = info;
      _cargando = false;
    });
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final androidUrl = _info?.urlAndroidApk ?? 'https://api.neatspace.cl/downloads/parkcontrol.apk';
    final windowsUrl = _info?.urlWindowsZip ?? 'https://api.neatspace.cl/downloads/parkcontrol-windows.zip';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F5ED7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.download_rounded, color: Color(0xFF0F5ED7), size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Descargar ParkControl',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Versión oficial v${_info?.version ?? ActualizacionService.versionActual} para todos tus dispositivos',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Opciones de Plataforma
              _TarjetaPlataforma(
                icono: Icons.android_rounded,
                colorIcono: const Color(0xFF3DDC84),
                titulo: 'Android (APK Directo)',
                descripcion: 'Instalador nativo para celulares y tablets Android con auto-actualización.',
                textoBoton: 'Descargar APK (.apk)',
                destacado: kIsWeb && defaultTargetPlatform == TargetPlatform.android,
                onTap: () => _abrirUrl(androidUrl),
              ),
              const SizedBox(height: 12),

              _TarjetaPlataforma(
                icono: Icons.desktop_windows_rounded,
                colorIcono: const Color(0xFF0078D4),
                titulo: 'Windows (PC de Caja)',
                descripcion: 'Aplicación de escritorio optimizada para computadores y cajas de cobro.',
                textoBoton: 'Descargar para Windows (.zip)',
                destacado: kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
                onTap: () => _abrirUrl(windowsUrl),
              ),
              const SizedBox(height: 12),

              _TarjetaPlataforma(
                icono: Icons.apple_rounded,
                colorIcono: Colors.grey.shade800,
                titulo: 'iPhone & iPad (iOS)',
                descripcion: 'Instala como App nativa desde Safari: presiona Compartir 📤 y "Añadir a pantalla de inicio" ➕.',
                textoBoton: 'Ver instrucciones',
                destacado: kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
                onTap: () => _mostrarGuiaIos(context),
              ),
              const SizedBox(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sincronización y cobro offline incluidos',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarGuiaIos(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.apple, size: 28),
            SizedBox(width: 8),
            Text('Instalar en iPhone / iPad'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ParkControl funciona como una aplicación nativa en iOS (PWA):', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('1. Abre Safari y entra a https://app.neatspace.cl'),
            SizedBox(height: 6),
            Text('2. Presiona el botón Compartir 📤 (en la barra inferior)'),
            SizedBox(height: 6),
            Text('3. Selecciona "Añadir a pantalla de inicio" ➕'),
            SizedBox(height: 12),
            Text('¡Listo! Se creará el icono de ParkControl en tu pantalla principal y se actualizará automáticamente cada vez que la abras.', style: TextStyle(color: Color(0xFF0F5ED7), fontSize: 13)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

class _TarjetaPlataforma extends StatelessWidget {
  final IconData icono;
  final Color colorIcono;
  final String titulo;
  final String descripcion;
  final String textoBoton;
  final bool destacado;
  final VoidCallback onTap;

  const _TarjetaPlataforma({
    required this.icono,
    required this.colorIcono,
    required this.titulo,
    required this.descripcion,
    required this.textoBoton,
    required this.destacado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: destacado ? const Color(0xFF0F5ED7).withValues(alpha: 0.06) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: destacado ? const Color(0xFF0F5ED7) : Colors.grey.shade200,
          width: destacado ? 1.8 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(icono, color: colorIcono, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    if (destacado) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F5ED7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Tu dispositivo',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  descripcion,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: destacado ? const Color(0xFF0F5ED7) : null,
              foregroundColor: destacado ? Colors.white : null,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onTap,
            child: Text(textoBoton, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
