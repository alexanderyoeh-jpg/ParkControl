import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  List<Map<String, dynamic>> registros = [];

  @override
  void initState() {
    super.initState();
    cargarHistorial();
  }

  Future<void> cargarHistorial() async {
    final prefs = await SharedPreferences.getInstance();

    final datos =
        prefs.getStringList('historial_salidas') ?? [];

    final lista = <Map<String, dynamic>>[];

    for (final dato in datos) {
      final registro =
          jsonDecode(dato) as Map<String, dynamic>;

      lista.add(registro);
    }

    lista.sort((a, b) {
      final fechaA =
          DateTime.parse(a['horaSalida'].toString());

      final fechaB =
          DateTime.parse(b['horaSalida'].toString());

      return fechaB.compareTo(fechaA);
    });

    if (!mounted) return;

    setState(() {
      registros = lista;
    });
  }

  String formatearFecha(String fecha) {
    final date = DateTime.parse(fecha);

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String formatoPesos(dynamic valor) {
    final numero = (valor as num).round();

    return '\$${numero.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Historial',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: registros.isEmpty
          ? const Center(
              child: Text(
                'No hay salidas registradas',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: cargarHistorial,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: registros.length,
                itemBuilder: (context, index) {
                  final registro = registros[index];

                  return Card(
                    margin: const EdgeInsets.only(
                      bottom: 12,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.directions_car,
                                color: Color(0xFF0F5ED7),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  registro['patente']
                                      .toString(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                formatoPesos(
                                  registro['montoTotal'],
                                ),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          const Divider(height: 24),

                          _dato(
                            'Tipo',
                            registro['tipo']?.toString() ??
                                '-',
                          ),

                          _dato(
                            'Color',
                            registro['color']?.toString() ??
                                '-',
                          ),

                          _dato(
                            'Entrada',
                            formatearFecha(
                              registro['horaEntrada']
                                  .toString(),
                            ),
                          ),

                          _dato(
                            'Salida',
                            formatearFecha(
                              registro['horaSalida']
                                  .toString(),
                            ),
                          ),

                          _dato(
                            'Tiempo',
                            '${registro['minutosEstacionado']} min',
                          ),

                          _dato(
                            'Tarifa aplicada',
                            '${formatoPesos(registro['tarifaPorMinuto'])}/min',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _dato(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              titulo,
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}