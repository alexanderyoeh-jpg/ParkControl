import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class ReportesScreen extends StatefulWidget {
  /// El cajero recibe sólo los conteos operativos. Los valores monetarios se
  /// reservan para la administración del estacionamiento.
  final bool mostrarFinanzas;

  const ReportesScreen({super.key, this.mostrarFinanzas = true});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  // ============================================================
  // API
  // ============================================================

  static final String apiUrl = ApiConfig.baseUrl;

  // ============================================================
  // DATOS
  // ============================================================

  int entradasHoy = 0;

  int salidasHoy = 0;

  int vehiculosDentro = 0;

  double ingresosHoy = 0.0;

  double promedioHoy = 0.0;

  bool cargando = true;

  String? error;

  // ============================================================
  // INICIO
  // ============================================================

  @override
  void initState() {
    super.initState();

    cargarReportes();
  }

  // ============================================================
  // CARGAR REPORTES
  // ============================================================

  Future<void> cargarReportes() async {
    if (!mounted) return;

    setState(() {
      cargando = true;
      error = null;
    });

    try {
      // ========================================================
      // CONSULTAR RESUMEN REAL DEL BACKEND
      // ========================================================

      final response = await ApiClient.get(Uri.parse('$apiUrl/api/resumen'));

      debugPrint('STATUS REPORTES: ${response.statusCode}');

      // ========================================================
      // VERIFICAR RESPUESTA
      // ========================================================

      if (response.statusCode != 200) {
        throw Exception(
          ApiClient.extraerMensajeError(
            response,
            mensajePredeterminado: 'No se pudo cargar el resumen operativo.',
          ),
        );
      }

      // ========================================================
      // DECODIFICAR JSON
      // ========================================================

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception('La API no devolvió un resumen válido');
      }

      final datos = Map<String, dynamic>.from(decoded);

      // ========================================================
      // OBTENER DATOS
      // ========================================================

      final nuevasEntradasHoy = _convertirEntero(datos['entradasHoy']);

      final nuevasSalidasHoy = _convertirEntero(datos['salidasHoy']);

      final nuevosVehiculosDentro = _convertirEntero(datos['vehiculosDentro']);

      final nuevosIngresosHoy = _convertirNumero(datos['recaudacionHoy']);

      // ========================================================
      // CALCULAR PROMEDIO
      // ========================================================

      double nuevoPromedioHoy = 0.0;

      if (nuevasSalidasHoy > 0) {
        nuevoPromedioHoy = nuevosIngresosHoy / nuevasSalidasHoy;
      }

      // ========================================================
      // ACTUALIZAR PANTALLA
      // ========================================================

      if (!mounted) return;

      setState(() {
        entradasHoy = nuevasEntradasHoy;

        salidasHoy = nuevasSalidasHoy;

        vehiculosDentro = nuevosVehiculosDentro;

        ingresosHoy = nuevosIngresosHoy;

        promedioHoy = nuevoPromedioHoy;

        cargando = false;

        error = null;
      });
    } catch (e) {
      debugPrint('ERROR REPORTES: $e');

      if (!mounted) return;

      setState(() {
        cargando = false;

        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ============================================================
  // CONVERTIR ENTERO
  // ============================================================

  int _convertirEntero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString()) ?? 0;
  }

  // ============================================================
  // CONVERTIR NÚMERO
  // ============================================================

  double _convertirNumero(dynamic valor) {
    if (valor == null) {
      return 0.0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString()) ?? 0.0;
  }

  // ============================================================
  // FORMATO PESOS CHILENOS
  // ============================================================

  String pesos(double valor) {
    final numero = valor.round();

    final texto = numero.toString();

    final buffer = StringBuffer();

    for (int i = 0; i < texto.length; i++) {
      final posicion = texto.length - i;

      buffer.write(texto[i]);

      if (posicion > 1 && posicion % 3 == 1) {
        buffer.write('.');
      }
    }

    return '\$${buffer.toString()}';
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),

        foregroundColor: Colors.white,

        title: const Text(
          'Reportes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',

            onPressed: cargando ? null : cargarReportes,

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: RefreshIndicator(
        onRefresh: cargarReportes,

        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.all(16),

          children: [
            // ==================================================
            // TÍTULO
            // ==================================================
            const Text(
              'Resumen del día',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Información real obtenida desde la base de datos de ParkControl.',
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // ERROR
            // ==================================================
            if (error != null)
              Container(
                width: double.infinity,

                margin: const EdgeInsets.only(bottom: 16),

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: const Color(0xFFFFEAEA),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),

                    IconButton(
                      onPressed: cargarReportes,

                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),

            // ==================================================
            // CARGANDO
            // ==================================================
            if (cargando)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(),
              ),

            // ==================================================
            // INGRESOS
            // ==================================================
            if (widget.mostrarFinanzas) ...[
              _tarjetaReporte(
                icono: Icons.attach_money,

                titulo: 'Ingresos del día',

                valor: cargando ? '...' : pesos(ingresosHoy),
              ),

              const SizedBox(height: 12),
            ],

            // ==================================================
            // VEHÍCULOS ATENDIDOS
            // ==================================================
            _tarjetaReporte(
              icono: Icons.directions_car,

              titulo: 'Vehículos atendidos',

              valor: cargando ? '...' : salidasHoy.toString(),
            ),

            const SizedBox(height: 12),

            // ==================================================
            // PROMEDIO
            // ==================================================
            if (widget.mostrarFinanzas) ...[
              _tarjetaReporte(
                icono: Icons.analytics_outlined,

                titulo: 'Promedio por vehículo',

                valor: cargando ? '...' : pesos(promedioHoy),
              ),

              const SizedBox(height: 12),
            ],

            // ==================================================
            // ENTRADAS
            // ==================================================
            _tarjetaReporte(
              icono: Icons.login,

              titulo: 'Entradas de hoy',

              valor: cargando ? '...' : entradasHoy.toString(),
            ),

            const SizedBox(height: 12),

            // ==================================================
            // SALIDAS
            // ==================================================
            _tarjetaReporte(
              icono: Icons.logout,

              titulo: 'Salidas de hoy',

              valor: cargando ? '...' : salidasHoy.toString(),
            ),

            const SizedBox(height: 12),

            // ==================================================
            // VEHÍCULOS DENTRO
            // ==================================================
            _tarjetaReporte(
              icono: Icons.local_parking_outlined,

              titulo: 'Vehículos actualmente dentro',

              valor: cargando ? '...' : vehiculosDentro.toString(),
            ),

            const SizedBox(height: 24),

            // ==================================================
            // INFORMACIÓN
            // ==================================================
            Card(
              elevation: 1,

              child: Padding(
                padding: const EdgeInsets.all(18),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,

                          color: Color(0xFF1565FF),
                        ),

                        SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            'Datos en tiempo real',
                            style: TextStyle(
                              fontSize: 18,

                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Text(
                      'Los datos se obtienen directamente '
                      'desde la API y la base de datos SQLite '
                      'de ParkControl.',

                      style: TextStyle(color: Colors.grey.shade700),
                    ),

                    const SizedBox(height: 10),

                    if (widget.mostrarFinanzas) ...[
                      const SizedBox(height: 10),

                      Text(
                        'Los ingresos corresponden a las '
                        'salidas registradas durante el día.',

                        style: TextStyle(color: Colors.grey.shade700),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'El promedio corresponde a los ingresos '
                        'divididos por la cantidad de salidas.',

                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // BOTÓN ACTUALIZAR
            // ==================================================
            SizedBox(
              width: double.infinity,

              height: 50,

              child: OutlinedButton.icon(
                onPressed: cargando ? null : cargarReportes,

                icon: const Icon(Icons.refresh),

                label: const Text(
                  'Actualizar reportes',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),

                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F5ED7),

                  side: const BorderSide(color: Color(0xFF0F5ED7)),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TARJETA DE REPORTE
  // ============================================================

  Widget _tarjetaReporte({
    required IconData icono,
    required String titulo,
    required String valor,
  }) {
    return Card(
      elevation: 1,

      margin: EdgeInsets.zero,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(18),

        child: Row(
          children: [
            Container(
              width: 52,

              height: 52,

              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),

                borderRadius: BorderRadius.circular(12),
              ),

              child: Icon(icono, color: const Color(0xFF0F5ED7), size: 28),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    titulo,

                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    valor,

                    style: const TextStyle(
                      fontSize: 25,

                      fontWeight: FontWeight.bold,

                      color: Color(0xFF172B4D),
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
