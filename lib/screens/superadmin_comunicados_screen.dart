import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';

class SuperadminComunicadosScreen extends StatefulWidget {
  const SuperadminComunicadosScreen({super.key});

  @override
  State<SuperadminComunicadosScreen> createState() => _SuperadminComunicadosScreenState();
}

class _SuperadminComunicadosScreenState extends State<SuperadminComunicadosScreen> {
  final _asuntoCtrl = TextEditingController();
  final _mensajeCtrl = TextEditingController();
  String _destinatariosTipo = 'todos';
  bool _enviando = false;
  bool _cargandoHistorial = true;
  List<Map<String, dynamic>> _comunicados = [];

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _asuntoCtrl.dispose();
    _mensajeCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/superadmin/comunicados'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _comunicados = List<Map<String, dynamic>>.from(data['comunicados'] ?? []);
            _cargandoHistorial = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoHistorial = false);
    }
  }

  Future<void> _enviarComunicado() async {
    final asunto = _asuntoCtrl.text.trim();
    final mensaje = _mensajeCtrl.text.trim();

    if (asunto.isEmpty || mensaje.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el asunto y el mensaje del comunicado')),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.campaign_rounded, color: Color(0xFF1565FF)),
            SizedBox(width: 10),
            Text('Confirmar Envío Masivo'),
          ],
        ),
        content: Text(
          'Se enviará este correo a los administradores de los estacionamientos seleccionados ($_destinatariosTipo) desde neatspacespa@gmail.com.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565FF)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Enviar a Todos'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _enviando = true);
    try {
      final res = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/superadmin/comunicados/enviar'),
        body: jsonEncode({
          'asunto': asunto,
          'mensaje': mensaje,
          'destinatariosTipo': _destinatariosTipo,
        }),
      ).timeout(const Duration(seconds: 25));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF168A4C),
            content: Text(data['mensaje'] ?? '¡Comunicado enviado con éxito!'),
          ),
        );
        _asuntoCtrl.clear();
        _mensajeCtrl.clear();
        _cargarHistorial();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al enviar el comunicado masivo')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión con el servidor de correo')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Comunicados y Correos Masivos'),
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.campaign_rounded, color: Color(0xFF1565FF)),
                      SizedBox(width: 10),
                      Text('Redactar Comunicado a Estacionamientos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Envía anuncios, actualizaciones o notificaciones importantes a los administradores de los estacionamientos desde neatspacespa@gmail.com.',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                  ),
                  const SizedBox(height: 18),

                  const Text('Destinatarios *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _destinatariosTipo,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos los estacionamientos')),
                      DropdownMenuItem(value: 'activos', child: Text('Solo estacionamientos Activos')),
                      DropdownMenuItem(value: 'suspendidos', child: Text('Solo estacionamientos Suspendidos')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _destinatariosTipo = v);
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text('Asunto del Correo *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _asuntoCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Ej. Actualización de plataforma ParkControl',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Mensaje / Comunicado *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _mensajeCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Escribe aquí el contenido del correo para todos los administradores...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F2B52)),
                      onPressed: _enviando ? null : _enviarComunicado,
                      icon: _enviando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _enviando ? 'Enviando correos...' : 'Enviar Comunicado Masivo',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Historial de Comunicados Enviados',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF172B4D)),
          ),
          const SizedBox(height: 12),

          if (_cargandoHistorial)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_comunicados.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay comunicados enviados aún.')))
          else
            ..._comunicados.map((c) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.mark_email_read_outlined, color: Color(0xFF168A4C), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c['asunto']?.toString() ?? 'Sin asunto',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFE6EEFF), borderRadius: BorderRadius.circular(6)),
                              child: Text('${c['totalEnviados']} enviados', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565FF))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(c['mensaje']?.toString() ?? '', style: const TextStyle(color: Colors.black87, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text('Fecha: ${c['creadoEn']} • Destinatarios: ${c['destinatariosTipo']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
