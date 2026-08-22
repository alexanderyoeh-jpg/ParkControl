import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../offline/offline_app_service.dart';
import '../services/api_client.dart';
import '../services/impresion_config_service.dart';
import '../services/pdf_service.dart';
import '../services/ticket_termico_service.dart';

class RegistrarSalidaScreen extends StatefulWidget {
  final bool permitirComprobantePdf;
  final bool permitirSeleccionMedioPago;

  const RegistrarSalidaScreen({
    super.key,
    this.permitirComprobantePdf = false,
    this.permitirSeleccionMedioPago = false,
  });

  @override
  State<RegistrarSalidaScreen> createState() => _RegistrarSalidaScreenState();
}

class _RegistrarSalidaScreenState extends State<RegistrarSalidaScreen> {
  final TextEditingController patenteController = TextEditingController();

  bool vehiculoEncontrado = false;
  bool buscando = false;
  bool registrandoSalida = false;
  String? _claveOperacionPendiente;
  String? _datosOperacionPendiente;
  String _metodoPago = 'efectivo';

  double montoCalculado = 0;

  Map<String, dynamic>? vehiculoActual;

  @override
  void initState() {
    super.initState();
    OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();
  }

  @override
  void dispose() {
    patenteController.dispose();
    super.dispose();
  }

  // ============================================================
  // BUSCAR VEHÍCULO
  // ============================================================

  Future<void> buscarVehiculo() async {
    final patente = patenteController.text.trim().toUpperCase();

    if (patente.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ingresa una patente')));
      return;
    }

    setState(() {
      buscando = true;
      vehiculoEncontrado = false;
      vehiculoActual = null;
      montoCalculado = 0;
    });

    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/vehiculos/$patente'),
      ).timeout(const Duration(milliseconds: 2500));

      debugPrint('STATUS BUSCAR SALIDA: ${response.statusCode}');

      final result = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final vehiculo = Map<String, dynamic>.from(result['vehiculo']);

        // ======================================================
        // OBTENER TARIFA
        // ======================================================

        double tarifaPorMinuto = 48;
        int? tarifaIdEsperada;

        try {
          final tarifaResponse = await ApiClient.get(
            Uri.parse('${ApiConfig.baseUrl}/api/tarifa'),
          ).timeout(const Duration(milliseconds: 2000));

          if (tarifaResponse.statusCode == 200) {
            final tarifaResult = jsonDecode(tarifaResponse.body);

            tarifaPorMinuto = NumberUtils.toDouble(
              tarifaResult['tarifaPorMinuto'],
            );
            tarifaIdEsperada = NumberUtils.toInt(tarifaResult['tarifaId']);
          }
        } catch (e) {
          debugPrint('ERROR OBTENIENDO TARIFA: $e');
        }

        // ======================================================
        // CALCULAR MONTO PRELIMINAR
        // ======================================================

        final horaEntradaTexto = vehiculo['horaEntrada']?.toString() ?? '';

        DateTime? horaEntrada;

        try {
          horaEntrada = DateTime.parse(horaEntradaTexto);
        } catch (_) {
          horaEntrada = null;
        }

        double montoTotal = 0;

        if (horaEntrada != null) {
          final horaActual = DateTime.now();

          int minutosEstacionado = horaActual.difference(horaEntrada).inMinutes;

          if (minutosEstacionado < 1) {
            minutosEstacionado = 1;
          }

          montoTotal = minutosEstacionado * tarifaPorMinuto;
        }

        setState(() {
          buscando = false;
          vehiculoEncontrado = true;
          vehiculoActual = {
            ...vehiculo,
            'tarifaIdEsperada': tarifaIdEsperada,
            'tarifaPorMinuto': tarifaPorMinuto,
          };
          montoCalculado = montoTotal;
        });

        return;
      }

      setState(() {
        buscando = false;
        vehiculoEncontrado = false;
        vehiculoActual = null;
        montoCalculado = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['mensaje'] ?? 'No se encontró el vehículo $patente',
          ),
        ),
      );
    } catch (e) {
      debugPrint('ERROR BUSCANDO VEHÍCULO (MODO OFFLINE): $e');

      if (!mounted) return;

      final local = await OfflineAppService.instancia.buscarVehiculoDentro(
        patente,
      );
      final tarifaLocal =
          await OfflineAppService.instancia.tarifaPorMinutoActual() ?? 48.0;

      if (!mounted) return;

      if (local != null) {
        final minutos = DateTime.now()
            .toUtc()
            .difference(local.horaEntrada.toUtc())
            .inMinutes
            .clamp(1, 1 << 31)
            .toDouble();

        setState(() {
          buscando = false;
          vehiculoEncontrado = true;
          vehiculoActual = {
            'id': local.servidorId,
            'patente': local.patente,
            'tipo': local.tipo,
            'color': local.color,
            'observacion': local.observacion,
            'horaEntrada': local.horaEntrada.toIso8601String(),
            'version': local.versionServidor,
            'tarifaPorMinuto': tarifaLocal,
            'offline': true,
          };
          montoCalculado = minutos * tarifaLocal;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehículo encontrado en caché local sin conexión'),
          ),
        );

        return;
      }

      // Si no estaba en la caché local previa, permitir registrar salida manual directa
      final horaActual = DateTime.now();
      final horaEstimada = horaActual.subtract(const Duration(minutes: 30));
      const minutosEstimados = 30.0;
      final montoEstimado = minutosEstimados * tarifaLocal;

      setState(() {
        buscando = false;
        vehiculoEncontrado = true;
        vehiculoActual = {
          'id': null,
          'patente': patente,
          'tipo': 'Auto',
          'color': 'No especificado',
          'observacion': 'Salida offline directa',
          'horaEntrada': horaEstimada.toIso8601String(),
          'tarifaPorMinuto': tarifaLocal,
          'offline': true,
        };
        montoCalculado = montoEstimado;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modo Offline: Cobro habilitado para $patente (Tarifa \$${tarifaLocal.toInt()}/min)'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ============================================================
  // REGISTRAR SALIDA
  // ============================================================

  Future<void> registrarSalida() async {
    final patente = patenteController.text.trim().toUpperCase();
    final horaOperacion = DateTime.now().toUtc();

    if (patente.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ingresa una patente')));
      return;
    }

    final datosSalida = <String, dynamic>{
      'patente': patente,
      'metodoPago': _metodoPago,
    };

    final movimientoId = NumberUtils.toInt(vehiculoActual?['id']);
    final version = NumberUtils.toInt(vehiculoActual?['version']);
    final tarifaId = NumberUtils.toInt(vehiculoActual?['tarifaIdEsperada']);

    if (movimientoId != null) {
      datosSalida['movimientoId'] = movimientoId;
    }
    if (version != null) {
      datosSalida['versionEsperada'] = version;
    }
    if (tarifaId != null) {
      datosSalida['tarifaIdEsperada'] = tarifaId;
    }

    final firmaDatos = jsonEncode(datosSalida);

    if (_datosOperacionPendiente != firmaDatos) {
      _datosOperacionPendiente = firmaDatos;
      _claveOperacionPendiente = ApiClient.crearClaveIdempotencia();
    }

    setState(() {
      registrandoSalida = true;
    });

    try {
      final response = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/salidas'),
        body: firmaDatos,
        claveIdempotencia: _claveOperacionPendiente,
      ).timeout(const Duration(milliseconds: 2500));

      debugPrint('STATUS SALIDA: ${response.statusCode}');

      final result = jsonDecode(response.body);

      if (response.statusCode < 500) {
        _claveOperacionPendiente = null;
        _datosOperacionPendiente = null;
      }

      if (!mounted) return;

      // ========================================================
      // SALIDA REGISTRADA
      // ========================================================

      if (response.statusCode == 200) {
        final salida = Map<String, dynamic>.from(result['salida']);

        final montoFinal = NumberUtils.toDouble(salida['monto']);

        setState(() {
          registrandoSalida = false;
          montoCalculado = montoFinal;
          vehiculoEncontrado = false;
          vehiculoActual = null;
        });

        patenteController.clear();
        OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();

        // ======================================================
        // MOSTRAR BOLETA
        // ======================================================

        await _mostrarConfirmacionSalida(salida);

        return;
      }

      // ========================================================
      // ERRORES DE LA API (404, 400, 403, 409, 429, 500, etc.)
      // ========================================================

      setState(() {
        registrandoSalida = false;
      });

      final mensajeError = ApiClient.extraerMensajeError(
        response,
        mensajePredeterminado: 'Error al registrar la salida',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensajeError),
          backgroundColor: response.statusCode == 403 ? Colors.red.shade700 : null,
        ),
      );
      return;
    } catch (e) {
      debugPrint('ERROR REGISTRANDO SALIDA (MODO OFFLINE): $e');

      try {
        await OfflineAppService.instancia.registrarSalida(
          clave: _claveOperacionPendiente ?? ApiClient.crearClaveIdempotencia(),
          patente: patente,
          horaSalida: horaOperacion,
          metodoPago: _metodoPago,
        );

        _claveOperacionPendiente = null;
        _datosOperacionPendiente = null;

        if (!mounted) return;

        final horaEntradaLocal = DateTime.tryParse(vehiculoActual?['horaEntrada']?.toString() ?? '') ?? horaOperacion.subtract(const Duration(minutes: 15));
        final minutosLocales = horaOperacion.difference(horaEntradaLocal).inMinutes.clamp(1, 1 << 30);
        final tarifaLocal = NumberUtils.toDouble(vehiculoActual?['tarifaPorMinuto']) > 0 ? NumberUtils.toDouble(vehiculoActual!['tarifaPorMinuto']) : 48.0;
        final montoFinal = montoCalculado > 0 ? montoCalculado : (minutosLocales * tarifaLocal);

        final salidaLocal = <String, dynamic>{
          'patente': patente,
          'tipo': vehiculoActual?['tipo'] ?? 'Auto',
          'color': vehiculoActual?['color'] ?? 'No especificado',
          'horaEntrada': horaEntradaLocal.toIso8601String(),
          'horaSalida': horaOperacion.toIso8601String(),
          'minutos': minutosLocales,
          'tarifaPorMinuto': tarifaLocal,
          'monto': montoFinal,
          'metodoPago': _metodoPago,
          'offline': true,
        };

        setState(() {
          registrandoSalida = false;
          vehiculoEncontrado = false;
          vehiculoActual = null;
          montoCalculado = 0;
        });

        patenteController.clear();

        _imprimirTicketTermicoSalida(salidaLocal);
        await _mostrarConfirmacionSalida(salidaLocal);
        return;
      } catch (offlineError) {
        debugPrint('ERROR SALIDA OFFLINE: $offlineError');
      }

      if (!mounted) return;

      setState(() {
        registrandoSalida = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo procesar la salida')),
      );
    }
  }

  // ============================================================
  // CONFIRMAR SALIDA PARA CAJERO
  // ============================================================

  Future<void> _mostrarConfirmacionSalida(Map<String, dynamic> salida) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.receipt_long, color: Color(0xFF20B46A)),
              SizedBox(width: 10),
              Text('Salida confirmada'),
            ],
          ),

          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF20B46A),
                  size: 54,
                ),

                const SizedBox(height: 10),

                const Text(
                  'Salida registrada',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 18),

                _filaConfirmacion(
                  'Patente',
                  salida['patente']?.toString().toUpperCase() ?? '-',
                ),

                _filaConfirmacion('Tipo', salida['tipo']?.toString() ?? '-'),

                _filaConfirmacion('Color', salida['color']?.toString() ?? '-'),

                _filaConfirmacion(
                  'Entrada',
                  _fechaHoraVisible(salida['horaEntrada']),
                ),

                _filaConfirmacion(
                  'Salida',
                  _fechaHoraVisible(salida['horaSalida']),
                ),

                _filaConfirmacion(
                  'Minutos',
                  '${NumberUtils.toDouble(salida['minutos']).round()}',
                ),

                _filaConfirmacion(
                  'Tarifa',
                  pesos(NumberUtils.toDouble(salida['tarifaPorMinuto'])),
                ),

                _filaConfirmacion(
                  'Pago',
                  _etiquetaMetodoPago(salida['metodoPago']),
                ),

                const Divider(height: 24),

                if (salida['esAbonado'] == true) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E7D32)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.badge, size: 16, color: Color(0xFF2E7D32)),
                        SizedBox(width: 6),
                        Text(
                          'ABONADO VIGENTE (\$0 CLP)',
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                const Text(
                  'TOTAL PAGADO',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  pesos(NumberUtils.toDouble(salida['monto'])),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: salida['esAbonado'] == true ? const Color(0xFF2E7D32) : const Color(0xFF172B4D),
                  ),
                ),
              ],
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F2B52),
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _imprimirTicketTermicoSalida(salida);
              },
              icon: const Icon(Icons.print),
              label: const Text('Ticket Térmico'),
            ),
            if (widget.permitirComprobantePdf)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _abrirComprobantePdf(salida);
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
          ],
        );
      },
    );

    // Auto-impresión si está habilitada
    try {
      final config = await ImpresionConfigService.obtenerConfiguracion();
      if (config.imprimirSalidaAutomatica) {
        await _imprimirTicketTermicoSalida(salida);
      }
    } catch (_) {}
  }

  Future<void> _imprimirTicketTermicoSalida(Map<String, dynamic> salida) async {
    try {
      final patente = salida['patente']?.toString() ?? '';
      final horaEntrada = DateTime.tryParse(salida['horaEntrada']?.toString() ?? '')?.toLocal() ?? DateTime.now();
      final horaSalida = DateTime.tryParse(salida['horaSalida']?.toString() ?? '')?.toLocal() ?? DateTime.now();
      final minutos = NumberUtils.toInt(salida['minutos']) ?? 0;
      final monto = NumberUtils.toDouble(salida['monto']);
      final metodo = salida['metodoPago']?.toString() ?? _metodoPago;

      await TicketTermicoService.imprimirTicketSalida(
        patente: patente,
        horaEntrada: horaEntrada,
        horaSalida: horaSalida,
        minutosTotales: minutos,
        totalPagar: monto,
        metodoPago: metodo,
      );
    } catch (e) {
      if (mounted) {
        _mostrarMensaje('No se pudo imprimir el ticket térmico: $e', esError: true);
      }
    }
  }

  Future<void> _abrirComprobantePdf(Map<String, dynamic> salida) async {
    final id = NumberUtils.toDouble(salida['id']).round();

    if (id <= 0) return;

    try {
      final pdf = await ApiClient.descargarPdf(
        Uri.parse('${ApiConfig.baseUrl}/api/boletas/$id/pdf'),
      );
      await PdfService.imprimirOGuardar(
        pdf,
        nombreArchivo: 'comprobante-$id.pdf',
      );
    } catch (_) {
      if (mounted) {
        _mostrarMensaje('No se pudo abrir el comprobante PDF', esError: true);
      }
    }
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: esError ? Colors.red.shade700 : null,
        ),
      );
  }

  // ============================================================
  // FILA DE CONFIRMACIÓN EN PANTALLA
  // ============================================================

  Widget _filaConfirmacion(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 90,
            child: Text(titulo, style: const TextStyle(color: Colors.grey)),
          ),

          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FORMATO FECHA/HORA
  // ============================================================

  String _fechaHoraVisible(dynamic valor) {
    if (valor == null || valor.toString().isEmpty) {
      return '--';
    }

    try {
      final fecha = DateTime.parse(valor.toString()).toLocal();

      final dia = fecha.day.toString().padLeft(2, '0');

      final mes = fecha.month.toString().padLeft(2, '0');

      final anio = fecha.year.toString();

      final hora = fecha.hour.toString().padLeft(2, '0');

      final minuto = fecha.minute.toString().padLeft(2, '0');

      return '$dia/$mes/$anio $hora:$minuto';
    } catch (_) {
      return valor.toString();
    }
  }

  // ============================================================
  // PESOS
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
  // HORA SIMPLE
  // ============================================================

  String _horaVisible(String? valor) {
    if (valor == null || valor.isEmpty) {
      return '--:--';
    }

    try {
      final fecha = DateTime.parse(valor).toLocal();

      final hora = fecha.hour.toString().padLeft(2, '0');

      final minuto = fecha.minute.toString().padLeft(2, '0');

      return '$hora:$minuto';
    } catch (_) {
      return valor;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final patenteMostrada =
        vehiculoActual?['patente']?.toString().toUpperCase() ??
        patenteController.text.trim().toUpperCase();

    final tipo = vehiculoActual?['tipo']?.toString() ?? 'Auto';

    final color = vehiculoActual?['color']?.toString() ?? '';

    final horaEntrada = vehiculoActual?['horaEntrada']?.toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),

        foregroundColor: Colors.white,

        title: const Text(
          'Registrar salida',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              'Salida de vehículo',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Busca el vehículo mediante su patente.',
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 24),

            const Text(
              'Patente',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: patenteController,

              textCapitalization: TextCapitalization.characters,

              enabled: !registrandoSalida,

              decoration: InputDecoration(
                hintText: 'Ejemplo: ABCD12',

                prefixIcon: const Icon(Icons.directions_car),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,

              height: 52,

              child: ElevatedButton.icon(
                onPressed: buscando || registrandoSalida
                    ? null
                    : buscarVehiculo,

                icon: buscando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),

                label: Text(
                  buscando ? 'Buscando...' : 'Buscar vehículo',

                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            if (vehiculoEncontrado) ...[
              const SizedBox(height: 24),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Vehículo encontrado',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 16),

                      _dato('Patente', patenteMostrada),

                      _dato('Tipo', tipo),

                      _dato('Color', color),

                      _dato('Hora de entrada', _horaVisible(horaEntrada)),

                      const Divider(height: 24),

                      const Text(
                        'Monto a pagar',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        pesos(montoCalculado),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      if (widget.permitirSeleccionMedioPago) ...[
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          initialValue: _metodoPago,
                          decoration: const InputDecoration(
                            labelText: 'Medio de pago',
                            prefixIcon: Icon(Icons.payments_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'efectivo',
                              child: Text('Efectivo'),
                            ),
                            DropdownMenuItem(
                              value: 'transferencia',
                              child: Text('Transferencia'),
                            ),
                            DropdownMenuItem(
                              value: 'tarjeta',
                              child: Text('Tarjeta (débito o crédito)'),
                            ),
                            DropdownMenuItem(
                              value: 'no_pago',
                              child: Text('⚠️ No Pago / Fuga de vehículo', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            ),
                            DropdownMenuItem(
                              value: 'otro',
                              child: Text('Otro medio'),
                            ),
                          ],
                          onChanged: registrandoSalida
                              ? null
                              : (valor) {
                                  if (valor == null) return;
                                  setState(() => _metodoPago = valor);
                                },
                        ),
                        if (_metodoPago == 'no_pago') ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'El vehículo se registrará como FUGA / NO PAGO. La patente quedará registrada en lista de morosos con multa automática (\$15.000) para sus próximos ingresos.',
                                    style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,

                        height: 52,

                        child: ElevatedButton.icon(
                          onPressed: registrandoSalida ? null : registrarSalida,

                          icon: registrandoSalida
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.logout),

                          label: Text(
                            registrandoSalida
                                ? 'Registrando...'
                                : 'Registrar salida',

                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD92D20),

                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DATO
  // ============================================================

  String _etiquetaMetodoPago(dynamic valor) {
    switch (valor?.toString()) {
      case 'transferencia':
        return 'Transferencia';
      case 'tarjeta':
        return 'Tarjeta';
      case 'otro':
        return 'Otro medio';
      default:
        return 'Efectivo';
    }
  }

  Widget _dato(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),

      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [
          Text(titulo, style: const TextStyle(color: Colors.grey)),

          Flexible(
            child: Text(
              valor,

              textAlign: TextAlign.right,

              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// UTILIDAD PARA CONVERTIR NÚMEROS
// ============================================================

class NumberUtils {
  static double toDouble(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static int? toInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString());
  }
}
