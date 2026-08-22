import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';

class SuperadminContabilidadScreen extends StatefulWidget {
  const SuperadminContabilidadScreen({super.key});

  @override
  State<SuperadminContabilidadScreen> createState() => _SuperadminContabilidadScreenState();
}

class _SuperadminContabilidadScreenState extends State<SuperadminContabilidadScreen> {
  bool _cargando = true;
  String? _error;
  double _totalHistorico = 0;
  double _ingresosMesActual = 0;
  double _mrrEstimado = 0;
  List<Map<String, dynamic>> _ingresosPorMes = [];
  List<Map<String, dynamic>> _pagos = [];
  Map<String, dynamic> _resumenPlanes = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final res = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/superadmin/contabilidad'),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _totalHistorico = (data['totalHistorico'] as num?)?.toDouble() ?? 0;
            _ingresosMesActual = (data['ingresosMesActual'] as num?)?.toDouble() ?? 0;
            _mrrEstimado = (data['mrrEstimado'] as num?)?.toDouble() ?? 0;
            _ingresosPorMes = List<Map<String, dynamic>>.from(data['ingresosPorMes'] ?? []);
            _pagos = List<Map<String, dynamic>>.from(data['pagos'] ?? []);
            _resumenPlanes = Map<String, dynamic>.from(data['resumenPlanes'] ?? {});
            _cargando = false;
          });
        }
      } else {
        throw Exception('Error al cargar contabilidad SaaS');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar la contabilidad de la plataforma';
        });
      }
    }
  }

  String _pesos(num valor) {
    final partes = valor.round().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    return '\$$partes CLP';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Contabilidad y Suscripciones SaaS'),
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text(
                        'Resumen Financiero de la Plataforma',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF172B4D)),
                      ),
                      const SizedBox(height: 4),
                      const Text('Ingresos globales por suscripciones de estacionamientos.', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 20),

                      // Tarjetas de KPIs Financieros
                      Row(
                        children: [
                          Expanded(
                            child: _tarjetaKpi(
                              'MRR Estimado',
                              _pesos(_mrrEstimado),
                              'Recurrente mensual',
                              Icons.trending_up_rounded,
                              const Color(0xFF168A4C),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _tarjetaKpi(
                              'Mes Actual',
                              _pesos(_ingresosMesActual),
                              'Cobrado este mes',
                              Icons.calendar_month_outlined,
                              const Color(0xFF1565FF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _tarjetaKpi(
                        'Total Histórico Recaudado',
                        _pesos(_totalHistorico),
                        '${_pagos.length} pagos confirmados en la plataforma',
                        Icons.account_balance_wallet_outlined,
                        const Color(0xFF7055B5),
                      ),
                      const SizedBox(height: 24),

                      // Resumen de Clientes / Suscripciones
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.pie_chart_outline, color: Color(0xFF0F2B52)),
                                  SizedBox(width: 8),
                                  Text('Estado de Clientes y Licencias', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _indicadorEstado('Total', _resumenPlanes['total']?.toString() ?? '0', Colors.blueGrey),
                                  _indicadorEstado('Activos', _resumenPlanes['activos']?.toString() ?? '0', const Color(0xFF168A4C)),
                                  _indicadorEstado('Vencidos', _resumenPlanes['vencidos']?.toString() ?? '0', const Color(0xFFF08A24)),
                                  _indicadorEstado('Suspendidos', _resumenPlanes['suspendidos']?.toString() ?? '0', const Color(0xFFB3261E)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Ingresos por Mes
                      const Text(
                        'Historial de Ingresos Mensuales',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF172B4D)),
                      ),
                      const SizedBox(height: 12),
                      if (_ingresosPorMes.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay registros mensuales aún.')))
                      else
                        ..._ingresosPorMes.map((m) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFE6EEFF),
                                  child: Icon(Icons.bar_chart, color: Color(0xFF1565FF)),
                                ),
                                title: Text(
                                  'Período ${m['mes']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                trailing: Text(
                                  _pesos((m['total'] as num?)?.toDouble() ?? 0),
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF168A4C)),
                                ),
                              ),
                            )),

                      const SizedBox(height: 24),

                      // Últimos Pagos Registrados
                      const Text(
                        'Últimos Pagos de Suscripciones',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF172B4D)),
                      ),
                      const SizedBox(height: 12),
                      if (_pagos.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay pagos registrados aún.')))
                      else
                        ..._pagos.take(15).map((p) => Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          p['estacionamientoNombre']?.toString() ?? 'Estacionamiento',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _pesos((p['monto'] as num?)?.toDouble() ?? 0),
                                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF168A4C), fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('• Plan: ${p['estacionamientoPlan']?.toString().toUpperCase()} • Método: ${p['metodo']}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                    if (p['fechaPago'] != null)
                                      Text('• Fecha: ${p['fechaPago']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _tarjetaKpi(String titulo, String valor, String subtitulo, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 22),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF172B4D))),
          const SizedBox(height: 2),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
          Text(subtitulo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _indicadorEstado(String label, String valor, Color color) {
    return Column(
      children: [
        Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
