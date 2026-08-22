import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class MorosidadScreen extends StatefulWidget {
  const MorosidadScreen({super.key});

  @override
  State<MorosidadScreen> createState() => _MorosidadScreenState();
}

class _MorosidadScreenState extends State<MorosidadScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Map<String, dynamic>> _morosos = [];
  bool _cargando = true;
  String? _error;
  String _filtroEstado = 'todos';
  String _filtroTexto = '';

  // Configuración de multas
  final _multaController = TextEditingController(text: '15000');
  final _motivoConfigController = TextEditingController(text: 'Salida sin pago / Fuga de vehículo');
  bool _guardandoConfig = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarTodo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _multaController.dispose();
    _motivoConfigController.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    await Future.wait([
      _cargarMorosos(),
      _cargarConfiguracionMultas(),
    ]);
  }

  Future<void> _cargarMorosos() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/morosidad?estado=$_filtroEstado'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _morosos = List<Map<String, dynamic>>.from(data['morosidad'] ?? []);
            _cargando = false;
          });
        }
      } else {
        throw Exception('Error al consultar morosidad');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar el registro de morosos';
        });
      }
    }
  }

  Future<void> _cargarConfiguracionMultas() async {
    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/configuracion/multas'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          _multaController.text = (data['multaMonto'] ?? 15000).toString();
          _motivoConfigController.text = data['motivoPredeterminado'] ?? 'Salida sin pago / Fuga de vehículo';
        }
      }
    } catch (_) {}
  }

  Future<void> _guardarConfiguracionMultas() async {
    final monto = double.tryParse(_multaController.text.trim());
    if (monto == null || monto < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto de multa válido')),
      );
      return;
    }

    setState(() => _guardandoConfig = true);
    try {
      final res = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/configuracion/multas'),
        body: jsonEncode({
          'multaMonto': monto,
          'motivoPredeterminado': _motivoConfigController.text.trim(),
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Configuración de multas guardada con éxito!')),
        );
      } else {
        throw Exception('Error al guardar');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al guardar la configuración de multas')),
      );
    } finally {
      if (mounted) setState(() => _guardandoConfig = false);
    }
  }

  Future<void> _pagarMulta(Map<String, dynamic> item) async {
    final deuda = num.tryParse(item['montoAdeudado']?.toString() ?? '0') ?? 0;
    final multa = num.tryParse(item['montoMulta']?.toString() ?? '15000') ?? 15000;
    final total = deuda + multa;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cobrar Multa - Patente ${item['patente']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Deuda de estacionamiento: \$$deuda CLP'),
            Text('• Multa por no pago: \$$multa CLP', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            Text('Total a cobrar: \$$total CLP', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF168A4C))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF168A4C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registrar Pago Total'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final res = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/morosidad/${item['id']}/pagar'),
        body: jsonEncode({
          'montoPagado': total,
          'metodoPago': 'efectivo',
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pago de multa registrado para ${item['patente']}')),
        );
        _cargarMorosos();
      }
    } catch (_) {}
  }

  Future<void> _condonarMulta(Map<String, dynamic> item) async {
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Condonar Multa - ${item['patente']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Esta acción anulará la deuda y multa de la patente sin cobro.'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(labelText: 'Motivo de condonación', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Condonar Deuda'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final res = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/morosidad/${item['id']}/condonar'),
        body: jsonEncode({'motivo': motivoCtrl.text.trim()}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Multa condonada para ${item['patente']}')),
        );
        _cargarMorosos();
      }
    } catch (_) {}
  }

  Future<void> _agregarMorosoManual() async {
    final patCtrl = TextEditingController();
    final deudaCtrl = TextEditingController(text: '0');
    final multaCtrl = TextEditingController(text: _multaController.text);
    final obsCtrl = TextEditingController();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar Patente Morosa / Multa'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: patCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Patente *', hintText: 'ABCD12', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deudaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Deuda estacionamiento (\$)', prefixText: '\$ ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: multaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monto de Multa (\$)', prefixText: '\$ ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(labelText: 'Motivo u Observación', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565FF)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (guardar != true) return;

    final pat = patCtrl.text.trim().toUpperCase();
    if (pat.isEmpty) return;

    try {
      final res = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/morosidad'),
        body: jsonEncode({
          'patente': pat,
          'montoAdeudado': double.tryParse(deudaCtrl.text) ?? 0,
          'montoMulta': double.tryParse(multaCtrl.text) ?? 15000,
          'motivo': obsCtrl.text.trim().isEmpty ? 'Ingreso manual' : obsCtrl.text.trim(),
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Patente $pat agregada a lista de morosos y multas')),
        );
        _cargarMorosos();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _morosos.where((m) {
      final pat = m['patente']?.toString().toUpperCase() ?? '';
      return _filtroTexto.isEmpty || pat.contains(_filtroTexto.toUpperCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Gestión de Morosos y Multas'),
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF3DDC84),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.gavel_rounded), text: 'Vehículos Morosos'),
            Tab(icon: Icon(Icons.settings_outlined), text: 'Configuración Multas'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFFB3261E),
              foregroundColor: Colors.white,
              onPressed: _agregarMorosoManual,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Multa / Moroso'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          // ==========================================
          // TAB 1: LISTA DE MOROSOS
          // ==========================================
          RefreshIndicator(
            onRefresh: _cargarMorosos,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Filtros y buscador
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _filtroTexto = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar por patente...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: DropdownButton<String>(
                        value: _filtroEstado,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'todos', child: Text('Todos')),
                          DropdownMenuItem(value: 'pendiente', child: Text('Pendientes')),
                          DropdownMenuItem(value: 'pagada', child: Text('Pagadas')),
                          DropdownMenuItem(value: 'condonada', child: Text('Condonadas')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _filtroEstado = v);
                          _cargarMorosos();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_cargando)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
                else if (_error != null)
                  Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                else if (filtrados.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Icon(Icons.verified_user_outlined, size: 64, color: Colors.green),
                          const SizedBox(height: 12),
                          const Text('No hay vehículos morosos ni multas registradas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          const Text('Todos los vehículos están al día.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                else
                  ...filtrados.map(_tarjetaMoroso),
              ],
            ),
          ),

          // ==========================================
          // TAB 2: CONFIGURACIÓN DE MULTAS
          // ==========================================
          ListView(
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
                          Icon(Icons.tune_rounded, color: Color(0xFF0F2B52)),
                          SizedBox(width: 10),
                          Text('Reglas de Multas por Fuga / No Pago', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Define la multa automática que se asignará a los vehículos que se retiren sin pagar o sean marcados como no pago por el cajero.',
                        style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      const Text('Monto de Multa Automática (CLP) *', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _multaController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixText: '\$ ',
                          suffixText: 'CLP',
                          border: OutlineInputBorder(),
                          hintText: '15000',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Motivo Predeterminado', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _motivoConfigController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Salida sin pago / Fuga de vehículo',
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565FF)),
                          onPressed: _guardandoConfig ? null : _guardarConfiguracionMultas,
                          icon: _guardandoConfig
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_outlined),
                          label: const Text('Guardar Configuración de Multas'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaMoroso(Map<String, dynamic> item) {
    final estado = (item['estado']?.toString() ?? 'pendiente').toLowerCase();
    final deuda = num.tryParse(item['montoAdeudado']?.toString() ?? '0') ?? 0;
    final multa = num.tryParse(item['montoMulta']?.toString() ?? '15000') ?? 15000;
    final total = deuda + multa;

    Color estadoColor;
    String estadoTexto;
    if (estado == 'pagada') {
      estadoColor = const Color(0xFF168A4C);
      estadoTexto = 'PAGADA';
    } else if (estado == 'condonada') {
      estadoColor = Colors.grey;
      estadoTexto = 'CONDONADA';
    } else {
      estadoColor = const Color(0xFFB3261E);
      estadoTexto = 'PENDIENTE';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.black87, width: 1.5),
                  ),
                  child: Text(
                    item['patente']?.toString().toUpperCase() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(estadoTexto, style: TextStyle(color: estadoColor, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const Spacer(),
                Text('\$$total CLP', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF172B4D))),
              ],
            ),
            const SizedBox(height: 10),
            Text('• Deuda estacionamiento: \$$deuda CLP  • Multa: \$$multa CLP', style: const TextStyle(fontSize: 12, color: Colors.black87)),
            if (item['motivo'] != null && item['motivo'].toString().isNotEmpty)
              Text('• Motivo: ${item['motivo']}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
            if (item['creadoEn'] != null)
              Text('• Fecha fuga/registro: ${item['creadoEn']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (estado == 'pendiente') ...[
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.grey.shade700, visualDensity: VisualDensity.compact),
                    onPressed: () => _condonarMulta(item),
                    icon: const Icon(Icons.undo, size: 14),
                    label: const Text('Condonar', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF168A4C), visualDensity: VisualDensity.compact),
                    onPressed: () => _pagarMulta(item),
                    icon: const Icon(Icons.payment, size: 14),
                    label: const Text('Cobrar Multa', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
