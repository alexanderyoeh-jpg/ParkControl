import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../offline/offline_app_service.dart';
import '../services/api_client.dart';

class TarifasScreen extends StatefulWidget {
  const TarifasScreen({super.key});

  @override
  State<TarifasScreen> createState() => _TarifasScreenState();
}

class _TarifasScreenState extends State<TarifasScreen> {
  static final String _apiUrl = ApiConfig.baseUrl;

  final TextEditingController _tarifaController = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarTarifa();
  }

  @override
  void dispose() {
    _tarifaController.dispose();
    super.dispose();
  }

  Future<void> _cargarTarifa() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await ApiClient.get(
        Uri.parse('$_apiUrl/api/tarifa'),
      );

      if (respuesta.statusCode != 200) {
        throw Exception(
          ApiClient.extraerMensajeError(
            respuesta,
            mensajePredeterminado: 'No se pudo obtener la tarifa',
          ),
        );
      }

      final datos = jsonDecode(respuesta.body);

      if (datos is! Map) {
        throw Exception('La tarifa recibida no es válida');
      }

      final valor = _aNumero(datos['tarifaPorMinuto']);

      if (!mounted) return;

      setState(() {
        _tarifaController.text = valor.toStringAsFixed(0);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _guardarTarifa() async {
    final texto = _tarifaController.text
        .trim()
        .replaceAll(',', '.');

    final valor = double.tryParse(texto);

    if (valor == null || valor <= 0) {
      _mostrarMensaje(
        'Ingresa una tarifa mayor a \$0.',
        esError: true,
      );
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      final respuesta = await ApiClient.put(
        Uri.parse('$_apiUrl/api/tarifa'),
        body: jsonEncode({
          'tarifaPorMinuto': valor,
        }),
      );

      if (!mounted) return;

      if (respuesta.statusCode != 200) {
        _mostrarMensaje(
          ApiClient.extraerMensajeError(
            respuesta,
            mensajePredeterminado: 'No se pudo actualizar la tarifa.',
          ),
          esError: true,
        );
        return;
      }

      setState(() {
        _tarifaController.text = valor.toStringAsFixed(0);
      });

      _mostrarMensaje(
        'Tarifa actualizada para todo el estacionamiento.',
      );

      OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();
    } catch (_) {
      if (!mounted) return;

      _mostrarMensaje(
        'No se pudo conectar con el servidor.',
        esError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  double _aNumero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _pesos(double valor) {
    final numero = valor.round().toString();
    final resultado = StringBuffer();

    for (var indice = 0; indice < numero.length; indice++) {
      if (indice > 0 && (numero.length - indice) % 3 == 0) {
        resultado.write('.');
      }
      resultado.write(numero[indice]);
    }

    return '\$$resultado';
  }

  void _mostrarMensaje(
    String mensaje, {
    bool esError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor:
              esError ? Colors.red : const Color(0xFF168A4C),
          content: Text(mensaje),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final tarifa = double.tryParse(
          _tarifaController.text.replaceAll(',', '.'),
        ) ??
        0;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Tarifas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargarTarifa,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarTarifa,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Tarifa vigente',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Este valor se usa directamente al calcular las salidas.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              _mensajeEstado(
                icono: Icons.cloud_off_outlined,
                mensaje: _error!,
                color: Colors.red,
                accion: _cargarTarifa,
                textoAccion: 'Reintentar',
              ),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2B52),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cobro actual',
                      style: TextStyle(color: Color(0xFFCAD9F2)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_pesos(tarifa)} / minuto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Referencia: ${_pesos(tarifa * 60)} por hora.',
                      style: const TextStyle(color: Color(0xFFCAD9F2)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _tarifaController,
                enabled: !_guardando,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tarifa por minuto',
                  helperText: 'Monto en pesos chilenos (CLP).',
                  prefixText: '\$ ',
                  suffixText: ' / min',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6DB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF956F00)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'El cambio se aplica a las próximas salidas. Las operaciones ya cerradas mantienen su monto registrado.',
                        style: TextStyle(color: Color(0xFF6C5200)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardarTarifa,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _guardando ? 'Guardando...' : 'Guardar tarifa',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF168A4C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mensajeEstado({
    required IconData icono,
    required String mensaje,
    required Color color,
    required VoidCallback accion,
    required String textoAccion,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje)),
          TextButton(onPressed: accion, child: Text(textoAccion)),
        ],
      ),
    );
  }
}
