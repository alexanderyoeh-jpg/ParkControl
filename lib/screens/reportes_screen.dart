import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  int salidasHoy = 0;
  double ingresosHoy = 0;
  double promedioHoy = 0;

  @override
  void initState() {
    super.initState();
    cargarReportes();
  }

  Future<void> cargarReportes() async {
    final prefs = await SharedPreferences.getInstance();

    final datos =
        prefs.getStringList('historial_salidas') ?? [];

    final ahora = DateTime.now();

    int cantidad = 0;
    double total = 0;

    for (final dato in datos) {
      final registro =
          jsonDecode(dato) as Map<String, dynamic>;

      final fechaSalida =
          DateTime.parse(registro['horaSalida'].toString());

      final esHoy =
          fechaSalida.year == ahora.year &&
          fechaSalida.month == ahora.month &&
          fechaSalida.day == ahora.day;

      if (esHoy) {
        cantidad++;

        total +=
            (registro['montoTotal'] as num).toDouble();
      }
    }

    if (!mounted) return;

    setState(() {
      salidasHoy = cantidad;
      ingresosHoy = total;
      promedioHoy =
          cantidad > 0 ? total / cantidad : 0;
    });
  }

  String pesos(double valor) {
    return '\$${valor.round()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Reportes',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: RefreshIndicator(
        onRefresh: cargarReportes,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Resumen del día',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            _tarjetaReporte(
              icono: Icons.directions_car,
              titulo: 'Vehículos atendidos',
              valor: salidasHoy.toString(),
            ),

            const SizedBox(height: 12),

            _tarjetaReporte(
              icono: Icons.attach_money,
              titulo: 'Ingresos del día',
              valor: pesos(ingresosHoy),
            ),

            const SizedBox(height: 12),

            _tarjetaReporte(
              icono: Icons.analytics_outlined,
              titulo: 'Promedio por vehículo',
              valor: pesos(promedioHoy),
            ),

            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Información',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Los ingresos se calculan utilizando '
                      'el monto registrado en cada salida.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'La tarifa utilizada corresponde a la '
                      'tarifa vigente al momento de cada salida.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaReporte({
    required IconData icono,
    required String titulo,
    required String valor,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icono,
                color: const Color(0xFF0F5ED7),
                size: 28,
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}