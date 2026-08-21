import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';
import '../services/pdf_service.dart';

class BoletasScreen extends StatefulWidget {
  const BoletasScreen({super.key});

  @override
  State<BoletasScreen> createState() => _BoletasScreenState();
}

class _BoletasScreenState extends State<BoletasScreen> {
  // ============================================================
  // API
  // ============================================================

  static final String apiUrl = ApiConfig.baseUrl;

  // ============================================================
  // DATOS
  // ============================================================

  List<Map<String, dynamic>> boletas = [];

  bool cargando = true;

  bool abriendoPdf = false;

  String? error;

  // ============================================================
  // INICIO
  // ============================================================

  @override
  void initState() {
    super.initState();

    cargarBoletas();
  }

  // ============================================================
  // CARGAR BOLETAS DESDE EL SERVIDOR
  // ============================================================

  Future<void> cargarBoletas() async {
    if (!mounted) return;

    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final response = await ApiClient.get(Uri.parse('$apiUrl/api/boletas'));

      debugPrint('STATUS BOLETAS: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          cargando = false;
          error = ApiClient.extraerMensajeError(
            response,
            mensajePredeterminado: 'No se pudieron cargar los comprobantes.',
          );
        });

        return;
      }

      final decoded = jsonDecode(response.body);

      final lista = _extraerBoletas(decoded);

      setState(() {
        boletas = lista;
        cargando = false;
        error = null;
      });
    } catch (e) {
      debugPrint('ERROR BOLETAS: $e');

      if (!mounted) return;

      setState(() {
        cargando = false;
        error = 'No se pudo conectar con el servidor';
      });
    }
  }

  // ============================================================
  // EXTRAER BOLETAS
  // ============================================================

  List<Map<String, dynamic>> _extraerBoletas(dynamic decoded) {
    // ----------------------------------------------------------
    // LA API DEVUELVE DIRECTAMENTE UNA LISTA
    // ----------------------------------------------------------

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    // ----------------------------------------------------------
    // LA API DEVUELVE UN OBJETO
    // ----------------------------------------------------------

    if (decoded is Map) {
      final mapa = Map<String, dynamic>.from(decoded);

      const posiblesCampos = [
        'boletas',
        'registros',
        'data',
        'datos',
        'resultados',
      ];

      for (final campo in posiblesCampos) {
        final valor = mapa[campo];

        if (valor is List) {
          return valor
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      }
    }

    return [];
  }

  // ============================================================
  // OBTENER VALOR
  // ============================================================

  dynamic _valor(Map<String, dynamic> boleta, List<String> campos) {
    for (final campo in campos) {
      if (boleta.containsKey(campo) && boleta[campo] != null) {
        return boleta[campo];
      }
    }

    return null;
  }

  // ============================================================
  // TEXTO
  // ============================================================

  String _texto(
    Map<String, dynamic> boleta,
    List<String> campos, {
    String defecto = '-',
  }) {
    final valor = _valor(boleta, campos);

    if (valor == null) {
      return defecto;
    }

    final texto = valor.toString().trim();

    if (texto.isEmpty) {
      return defecto;
    }

    return texto;
  }

  // ============================================================
  // DOUBLE
  // ============================================================

  double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  // ============================================================
  // PESOS
  // ============================================================

  String pesos(dynamic valor) {
    final numero = _double(valor).round();

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
  // FECHA
  // ============================================================

  String formatearFecha(dynamic valor) {
    if (valor == null) {
      return '-';
    }

    final texto = valor.toString();

    if (texto.isEmpty) {
      return '-';
    }

    try {
      final fecha = DateTime.parse(texto).toLocal();

      return '${fecha.day.toString().padLeft(2, '0')}/'
          '${fecha.month.toString().padLeft(2, '0')}/'
          '${fecha.year} '
          '${fecha.hour.toString().padLeft(2, '0')}:'
          '${fecha.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return texto;
    }
  }

  // ============================================================
  // OBTENER ID DE BOLETA
  // ============================================================

  dynamic _idBoleta(Map<String, dynamic> boleta) {
    return _valor(boleta, ['id', 'movimientoId', 'boletaId']);
  }

  // ============================================================
  // DESCARGAR PDF AUTENTICADO DESDE EL SERVIDOR
  // ============================================================

  Future<void> abrirPdf(Map<String, dynamic> boleta) async {
    if (abriendoPdf) {
      return;
    }

    final id = _idBoleta(boleta);

    if (id == null) {
      _mostrarMensaje('El comprobante no tiene un ID válido', esError: true);

      return;
    }

    final url = '$apiUrl/api/boletas/$id/pdf';

    if (!mounted) return;

    setState(() {
      abriendoPdf = true;
    });

    try {
      final pdf = await ApiClient.descargarPdf(Uri.parse(url));
      await PdfService.imprimirOGuardar(
        pdf,
        nombreArchivo: 'comprobante-$id.pdf',
      );
    } catch (e) {
      debugPrint('ERROR ABRIENDO PDF: $e');

      if (!mounted) return;

      _mostrarMensaje('No se pudo abrir el comprobante PDF', esError: true);
    } finally {
      if (mounted) {
        setState(() {
          abriendoPdf = false;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),

        foregroundColor: Colors.white,

        title: const Text(
          'Comprobantes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            onPressed: cargando ? null : cargarBoletas,

            icon: const Icon(Icons.refresh),

            tooltip: 'Actualizar comprobantes',
          ),
        ],
      ),

      body: RefreshIndicator(onRefresh: cargarBoletas, child: _contenido()),
    );
  }

  // ============================================================
  // CONTENIDO
  // ============================================================

  Widget _contenido() {
    if (cargando && boletas.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),

        children: const [
          SizedBox(height: 250),

          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (error != null && boletas.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),

        padding: const EdgeInsets.all(16),

        children: [
          const SizedBox(height: 100),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),

              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 55),

                  const SizedBox(height: 16),

                  Text(
                    error!,
                    textAlign: TextAlign.center,

                    style: const TextStyle(color: Colors.red, fontSize: 15),
                  ),

                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    onPressed: cargarBoletas,

                    icon: const Icon(Icons.refresh),

                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (boletas.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),

        padding: const EdgeInsets.all(16),

        children: [
          const SizedBox(height: 100),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),

              child: Column(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    color: Colors.grey,
                    size: 65,
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'No hay comprobantes emitidos',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Los comprobantes generados aparecerán aquí.',
                    textAlign: TextAlign.center,

                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),

      padding: const EdgeInsets.all(16),

      itemCount: boletas.length,

      itemBuilder: (context, index) {
        final boleta = boletas[index];

        return _tarjetaBoleta(boleta);
      },
    );
  }

  // ============================================================
  // TARJETA BOLETA
  // ============================================================

  Widget _tarjetaBoleta(Map<String, dynamic> boleta) {
    final folio = _texto(boleta, ['folio', 'numeroBoleta', 'numero', 'id']);

    final patente = _texto(boleta, ['patente', 'placa']).toUpperCase();

    final tipo = _texto(boleta, ['tipo', 'tipoVehiculo']);

    final color = _texto(boleta, ['color']);

    final horaEntrada = _valor(boleta, [
      'horaEntrada',
      'entrada',
      'fechaEntrada',
    ]);

    final horaSalida = _valor(boleta, [
      'horaSalida',
      'salida',
      'fechaSalida',
      'fecha',
      'createdAt',
    ]);

    final minutos = _texto(boleta, [
      'minutos',
      'minutosEstacionado',
      'tiempo',
    ], defecto: '0');

    final monto = _valor(boleta, [
      'monto',
      'total',
      'montoTotal',
      'totalCobrado',
    ]);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),

      elevation: 1,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: InkWell(
        borderRadius: BorderRadius.circular(14),

        onTap: () {
          _mostrarDetalle(boleta);
        },

        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,

                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),

                      borderRadius: BorderRadius.circular(10),
                    ),

                    child: const Icon(
                      Icons.receipt_long,
                      color: Color(0xFF0F5ED7),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          'Comprobante $folio',

                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF172B4D),
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          patente,

                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Text(
                    pesos(monto),

                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF20B46A),
                    ),
                  ),
                ],
              ),

              const Divider(height: 24),

              _dato('Fecha salida', formatearFecha(horaSalida)),

              _dato('Entrada', formatearFecha(horaEntrada)),

              _dato('Tiempo', '$minutos min'),

              if (tipo != '-') _dato('Tipo', tipo),

              if (color != '-') _dato('Color', color),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,

                child: OutlinedButton.icon(
                  onPressed: () {
                    _mostrarDetalle(boleta);
                  },

                  icon: const Icon(Icons.visibility_outlined),

                  label: const Text('Ver comprobante'),

                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F5ED7),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DETALLE DE BOLETA
  // ============================================================

  void _mostrarDetalle(Map<String, dynamic> boleta) {
    final folio = _texto(boleta, ['folio', 'numeroBoleta', 'numero', 'id']);

    final patente = _texto(boleta, ['patente', 'placa']).toUpperCase();

    final tipo = _texto(boleta, ['tipo', 'tipoVehiculo']);

    final color = _texto(boleta, ['color']);

    final horaEntrada = _valor(boleta, [
      'horaEntrada',
      'entrada',
      'fechaEntrada',
    ]);

    final horaSalida = _valor(boleta, [
      'horaSalida',
      'salida',
      'fechaSalida',
      'fecha',
      'createdAt',
    ]);

    final minutos = _texto(boleta, [
      'minutos',
      'minutosEstacionado',
      'tiempo',
    ], defecto: '0');

    final tarifa = _valor(boleta, ['tarifaPorMinuto', 'tarifa']);

    final monto = _valor(boleta, [
      'monto',
      'total',
      'montoTotal',
      'totalCobrado',
    ]);

    final observacion = _texto(boleta, [
      'observacion',
      'observación',
    ], defecto: '');

    showModalBottomSheet(
      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),

          padding: const EdgeInsets.all(20),

          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 5,

                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,

                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Icon(
                        Icons.receipt_long,
                        color: Color(0xFF0F5ED7),
                        size: 30,
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          'Comprobante $folio',

                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF172B4D),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  _dato('Patente', patente),

                  _dato('Entrada', formatearFecha(horaEntrada)),

                  _dato('Salida', formatearFecha(horaSalida)),

                  _dato('Tiempo', '$minutos min'),

                  if (tipo != '-') _dato('Tipo', tipo),

                  if (color != '-') _dato('Color', color),

                  if (tarifa != null) _dato('Tarifa', '${pesos(tarifa)}/min'),

                  if (observacion.isNotEmpty) _dato('Observación', observacion),

                  const Divider(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,

                    children: [
                      const Text(
                        'TOTAL',

                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      Text(
                        pesos(monto),

                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF20B46A),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ==================================================
                  // BOTÓN PDF
                  // ==================================================
                  SizedBox(
                    width: double.infinity,

                    child: ElevatedButton.icon(
                      onPressed: abriendoPdf
                          ? null
                          : () async {
                              Navigator.pop(context);

                              await abrirPdf(boleta);
                            },

                      icon: abriendoPdf
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.print_outlined),

                      label: Text(
                        abriendoPdf ? 'Abriendo PDF...' : 'Imprimir / PDF',
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5ED7),

                        foregroundColor: Colors.white,

                        disabledBackgroundColor: const Color(0xFF0F5ED7),

                        disabledForegroundColor: Colors.white,

                        minimumSize: const Size(double.infinity, 50),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Center(
                    child: Text(
                      'El PDF se genera directamente desde el servidor.',

                      textAlign: TextAlign.center,

                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // DATO
  // ============================================================

  Widget _dato(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 105,

            child: Text(
              titulo,

              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),

          Expanded(
            child: Text(
              valor,

              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: esError ? Colors.red : const Color(0xFF20B46A),

        content: Text(mensaje),
      ),
    );
  }
}
