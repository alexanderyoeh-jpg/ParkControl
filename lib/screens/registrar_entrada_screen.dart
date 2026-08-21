import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../offline/offline_app_service.dart';
import '../services/api_client.dart';
import '../services/impresion_config_service.dart';
import '../services/ticket_termico_service.dart';

class RegistrarEntradaScreen extends StatefulWidget {
  const RegistrarEntradaScreen({super.key});

  @override
  State<RegistrarEntradaScreen> createState() => _RegistrarEntradaScreenState();
}

class _RegistrarEntradaScreenState extends State<RegistrarEntradaScreen> {
  final TextEditingController patenteController = TextEditingController();

  final TextEditingController colorController = TextEditingController();

  final TextEditingController observacionController = TextEditingController();

  String tipoVehiculo = 'Auto';

  bool cargando = false;
  String? _claveOperacionPendiente;
  String? _datosOperacionPendiente;

  @override
  void initState() {
    super.initState();
    OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();
  }

  Future<void> _gestionarImpresionTicket({
    required String patente,
    required String tipo,
    required DateTime hora,
    String? color,
    String? observacion,
  }) async {
    try {
      final config = await ImpresionConfigService.obtenerConfiguracion();
      if (config.imprimirEntradaAutomatica) {
        await TicketTermicoService.imprimirTicketEntrada(
          patente: patente,
          tipoVehiculo: tipo,
          horaEntrada: hora,
          color: color,
          observacion: observacion,
        );
      }
    } catch (e) {
      debugPrint('No se pudo auto-imprimir ticket: $e');
    }
  }

  @override
  void dispose() {
    patenteController.dispose();
    colorController.dispose();
    observacionController.dispose();
    super.dispose();
  }

  // ============================================================
  // REGISTRAR ENTRADA
  // ============================================================

  Future<void> registrarEntrada() async {
    final patente = patenteController.text.trim().toUpperCase();

    final color = colorController.text.trim();

    final observacion = observacionController.text.trim();
    final horaOperacion = DateTime.now().toUtc();

    if (patente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa la patente del vehículo')),
      );
      return;
    }

    final datosEntrada = {
      'patente': patente,
      'tipo': tipoVehiculo,
      'color': color.isEmpty ? 'No especificado' : color,
      'observacion': observacion,
    };
    final firmaDatos = jsonEncode(datosEntrada);

    if (_datosOperacionPendiente != firmaDatos) {
      _datosOperacionPendiente = firmaDatos;
      _claveOperacionPendiente = ApiClient.crearClaveIdempotencia();
    }

    setState(() {
      cargando = true;
    });

    try {
      final response = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/entradas'),
        body: firmaDatos,
        claveIdempotencia: _claveOperacionPendiente,
      ).timeout(const Duration(seconds: 10));

      debugPrint('STATUS ENTRADA: ${response.statusCode}');

      final result = jsonDecode(response.body);

      if (response.statusCode < 500) {
        _claveOperacionPendiente = null;
        _datosOperacionPendiente = null;
      }

      if (!mounted) return;

      // ========================================================
      // ENTRADA REGISTRADA
      // ========================================================

      if (response.statusCode == 201) {
        setState(() {
          cargando = false;
        });

        _gestionarImpresionTicket(
          patente: patente,
          tipo: tipoVehiculo,
          hora: DateTime.now(),
          color: color,
          observacion: observacion,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['mensaje'] ?? 'Entrada registrada correctamente',
            ),
            action: SnackBarAction(
              label: 'Imprimir Ticket',
              onPressed: () {
                TicketTermicoService.imprimirTicketEntrada(
                  patente: patente,
                  tipoVehiculo: tipoVehiculo,
                  horaEntrada: DateTime.now(),
                  color: color,
                  observacion: observacion,
                );
              },
            ),
          ),
        );

        patenteController.clear();
        colorController.clear();
        observacionController.clear();
        OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();

        setState(() {
          tipoVehiculo = 'Auto';
        });

        return;
      }

      // ========================================================
      // ERRORES DE LA API (409, 400, 403, 429, 500, etc.)
      // ========================================================

      setState(() {
        cargando = false;
      });

      final mensajeError = ApiClient.extraerMensajeError(
        response,
        mensajePredeterminado: 'Error al registrar la entrada',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensajeError),
          backgroundColor: response.statusCode == 403 ? Colors.red.shade700 : null,
        ),
      );
      return;
    } catch (e) {
      debugPrint('ERROR ENTRADA: $e');

      try {
        await OfflineAppService.instancia.registrarEntrada(
          clave: _claveOperacionPendiente ?? ApiClient.crearClaveIdempotencia(),
          patente: patente,
          tipo: tipoVehiculo,
          color: color.isEmpty ? 'No especificado' : color,
          observacion: observacion,
          horaEntrada: horaOperacion,
        );

        _claveOperacionPendiente = null;
        _datosOperacionPendiente = null;

        _gestionarImpresionTicket(
          patente: patente,
          tipo: tipoVehiculo,
          hora: DateTime.now(),
          color: color,
          observacion: observacion,
        );

        if (!mounted) return;

        setState(() {
          cargando = false;
          tipoVehiculo = 'Auto';
        });

        patenteController.clear();
        colorController.clear();
        observacionController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Entrada guardada sin conexión. Se sincronizará al volver internet.',
            ),
            action: SnackBarAction(
              label: 'Imprimir Ticket',
              onPressed: () {
                TicketTermicoService.imprimirTicketEntrada(
                  patente: patente,
                  tipoVehiculo: tipoVehiculo,
                  horaEntrada: DateTime.now(),
                  color: color,
                  observacion: observacion,
                );
              },
            ),
          ),
        );

        return;
      } catch (offlineError) {
        debugPrint('ERROR ENTRADA OFFLINE: $offlineError');
      }

      if (!mounted) return;

      setState(() {
        cargando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar con la API')),
      );
    }
  }

  // ============================================================
  // INTERFAZ
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();

    final fecha =
        '${ahora.day.toString().padLeft(2, '0')}/'
        '${ahora.month.toString().padLeft(2, '0')}/'
        '${ahora.year}';

    final hora =
        '${ahora.hour.toString().padLeft(2, '0')}:'
        '${ahora.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Registrar entrada',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              'Ingreso de vehículo',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Completa los datos para registrar la entrada.',
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 24),

            const Text(
              'Patente *',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: patenteController,
              textCapitalization: TextCapitalization.characters,

              decoration: InputDecoration(
                hintText: 'ABCD12',

                prefixIcon: const Icon(Icons.directions_car),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Tipo de vehículo *',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: tipoVehiculo,

              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              items: const [
                DropdownMenuItem(value: 'Auto', child: Text('Auto')),
                DropdownMenuItem(value: 'Moto', child: Text('Moto')),
                DropdownMenuItem(value: 'Camioneta', child: Text('Camioneta')),
                DropdownMenuItem(value: 'Camión', child: Text('Camión')),
              ],

              onChanged: cargando
                  ? null
                  : (valor) {
                      if (valor != null) {
                        setState(() {
                          tipoVehiculo = valor;
                        });
                      }
                    },
            ),

            const SizedBox(height: 18),

            const Text(
              'Color (opcional)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: colorController,

              decoration: InputDecoration(
                hintText: 'Blanco',

                prefixIcon: const Icon(Icons.palette_outlined),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Observación (opcional)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: observacionController,

              maxLines: 2,

              decoration: InputDecoration(
                hintText: 'Ej.: Cliente habitual',

                prefixIcon: const Icon(Icons.notes),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 22),

            const Text(
              'Fecha y hora de ingreso',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    readOnly: true,

                    controller: TextEditingController(text: fecha),

                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.calendar_today_outlined),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: TextField(
                    readOnly: true,

                    controller: TextEditingController(text: hora),

                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.access_time),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,

              child: ElevatedButton.icon(
                onPressed: cargando ? null : registrarEntrada,

                icon: cargando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login),

                label: Text(
                  cargando ? 'Registrando...' : 'Registrar entrada',

                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF20B46A),

                  foregroundColor: Colors.white,

                  disabledBackgroundColor: const Color(
                    0xFF20B46A,
                  ).withOpacity(0.6),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color: const Color(0xFFE8F7EF),

                borderRadius: BorderRadius.circular(10),
              ),

              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF20B46A)),

                  SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'Verifica la patente antes de registrar.',
                      style: TextStyle(color: Color(0xFF26734D)),
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
