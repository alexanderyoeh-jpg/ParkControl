import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../offline/offline_app_service.dart';
import '../services/api_client.dart';

class VehiculosDentroScreen extends StatefulWidget {
  const VehiculosDentroScreen({super.key});

  @override
  State<VehiculosDentroScreen> createState() =>
      _VehiculosDentroScreenState();
}

class _VehiculosDentroScreenState
    extends State<VehiculosDentroScreen> {
  // ============================================================
  // API
  // ============================================================

  static final String apiUrl = ApiConfig.baseUrl;

  // ============================================================
  // DATOS
  // ============================================================

  List<Map<String, dynamic>> vehiculos = [];

  bool cargando = true;
  bool esModoOffline = false;

  String? error;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    cargarVehiculos();
  }

  // ============================================================
  // CARGAR VEHÍCULOS
  // ============================================================

  Future<void> cargarVehiculos() async {
    if (mounted) {
      setState(() {
        cargando = true;
        error = null;
      });
    }

    try {
      final response = await ApiClient.get(
        Uri.parse(
          '$apiUrl/api/vehiculos-dentro',
        ),
      ).timeout(const Duration(seconds: 8));

      debugPrint(
        'STATUS VEHÍCULOS DENTRO: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          ApiClient.extraerMensajeError(
            response,
            mensajePredeterminado: 'No se pudieron cargar los vehículos',
          ),
        );
      }

      final datos = jsonDecode(response.body);

      if (datos is! List) {
        throw Exception(
          'La API no devolvió una lista válida',
        );
      }

      final lista = <Map<String, dynamic>>[];

      for (final item in datos) {
        if (item is Map) {
          lista.add(
            Map<String, dynamic>.from(item),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        vehiculos = lista;
        cargando = false;
        error = null;
        esModoOffline = false;
      });
    } catch (e) {
      debugPrint(
        'ERROR VEHÍCULOS DENTRO (intentando caché offline): $e',
      );

      try {
        final locales =
            await OfflineAppService.instancia.listarVehiculosDentro();
        if (!mounted) return;

        final lista = locales
            .map((m) => {
                  'id': m.servidorId ?? 0,
                  'patente': m.patente,
                  'tipo': m.tipo,
                  'color': m.color,
                  'observacion': m.observacion,
                  'horaEntrada': m.horaEntrada.toIso8601String(),
                  'esOffline': true,
                })
            .toList();

        setState(() {
          vehiculos = lista;
          cargando = false;
          error = null;
          esModoOffline = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión: mostrando vehículos desde la memoria local.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        cargando = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String formatearFechaHora(String? valor) {
    if (valor == null || valor.isEmpty) {
      return '--';
    }

    try {
      final fecha =
          DateTime.parse(valor).toLocal();

      final dia =
          fecha.day.toString().padLeft(2, '0');

      final mes =
          fecha.month.toString().padLeft(2, '0');

      final anio =
          fecha.year.toString();

      final hora =
          fecha.hour.toString().padLeft(2, '0');

      final minuto =
          fecha.minute.toString().padLeft(2, '0');

      return '$dia/$mes/$anio $hora:$minuto';
    } catch (_) {
      return '--';
    }
  }

  // ============================================================
  // FORMATEAR SOLO HORA
  // ============================================================

  String formatearHora(String? valor) {
    if (valor == null || valor.isEmpty) {
      return '--:--';
    }

    try {
      final fecha =
          DateTime.parse(valor).toLocal();

      final hora =
          fecha.hour.toString().padLeft(2, '0');

      final minuto =
          fecha.minute.toString().padLeft(2, '0');

      return '$hora:$minuto';
    } catch (_) {
      return '--:--';
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF7F8FA),

      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        backgroundColor:
            const Color(0xFF0F2B52),

        foregroundColor:
            Colors.white,

        title: const Text(
          'Vehículos dentro',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed:
                cargando
                    ? null
                    : cargarVehiculos,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: RefreshIndicator(
        onRefresh:
            cargarVehiculos,

        child: _contenido(),
      ),
    );
  }

  // ============================================================
  // CONTENIDO
  // ============================================================

  Widget _contenido() {
    if (cargando) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),

        children: const [
          SizedBox(
            height: 280,
          ),

          Center(
            child:
                CircularProgressIndicator(),
          ),
        ],
      );
    }

    if (error != null) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),

        padding:
            const EdgeInsets.all(20),

        children: [
          const SizedBox(
            height: 180,
          ),

          const Icon(
            Icons.cloud_off,
            size: 60,
            color: Colors.grey,
          ),

          const SizedBox(
            height: 16,
          ),

          Center(
            child: Text(
              error!,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          Center(
            child:
                ElevatedButton.icon(
              onPressed:
                  cargarVehiculos,

              icon: const Icon(
                Icons.refresh,
              ),

              label:
                  const Text(
                'Reintentar',
              ),
            ),
          ),
        ],
      );
    }

    if (vehiculos.isEmpty) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),

        children: const [
          SizedBox(
            height: 180,
          ),

          Icon(
            Icons.local_parking_outlined,
            size: 64,
            color: Colors.grey,
          ),

          SizedBox(
            height: 16,
          ),

          Center(
            child: Text(
              'No hay vehículos dentro',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 17,
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          ),

          SizedBox(
            height: 8,
          ),

          Center(
            child: Text(
              'Los vehículos registrados aparecerán aquí.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),

      padding:
          const EdgeInsets.all(16),

      children: [
        // ======================================================
        // RESUMEN
        // ======================================================

        Container(
          width: double.infinity,

          padding:
              const EdgeInsets.all(18),

          decoration:
              BoxDecoration(
            color: Colors.white,

            borderRadius:
                BorderRadius.circular(16),

            boxShadow: [
              BoxShadow(
                color:
                    Colors.black
                        .withOpacity(
                  0.05,
                ),

                blurRadius: 10,

                offset:
                    const Offset(0, 4),
              ),
            ],
          ),

          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,

                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFE8F0FE,
                  ),

                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),

                child: const Icon(
                  Icons.directions_car,
                  color:
                      Color(0xFF0F5ED7),
                  size: 28,
                ),
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Vehículos actualmente dentro',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      vehiculos.length
                          .toString(),

                      style:
                          const TextStyle(
                        fontSize: 28,
                        fontWeight:
                            FontWeight.bold,
                        color:
                            Color(0xFF172B4D),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),

                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFE8F7EF,
                  ),

                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),

                child: const Text(
                  'ACTIVOS',
                  style: TextStyle(
                    color:
                        Color(0xFF26734D),
                    fontSize: 10,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(
          height: 18,
        ),

        // ======================================================
        // LISTA
        // ======================================================

        for (
          int index = 0;
          index < vehiculos.length;
          index++
        )
          _tarjetaVehiculo(
            vehiculos[index],
          ),
      ],
    );
  }

  // ============================================================
  // TARJETA VEHÍCULO
  // ============================================================

  Widget _tarjetaVehiculo(
    Map<String, dynamic> vehiculo,
  ) {
    final patente =
        vehiculo['patente']
                ?.toString()
                .trim()
                .toUpperCase() ??
            '-';

    final tipo =
        vehiculo['tipo']
                ?.toString() ??
            'Auto';

    final color =
        vehiculo['color']
                ?.toString() ??
            'No especificado';

    final observacion =
        vehiculo['observacion']
                ?.toString()
                .trim() ??
            '';

    final horaEntrada =
        vehiculo['horaEntrada']
            ?.toString();

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),

      elevation: 1,

      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),

      child: Padding(
        padding:
            const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            // ==================================================
            // CABECERA
            // ==================================================

            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,

                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFFE8F0FE,
                    ),

                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),

                  child: const Icon(
                    Icons.directions_car,
                    color:
                        Color(0xFF0F5ED7),
                    size: 28,
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [
                      Text(
                        patente,

                        style:
                            const TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                          color:
                              Color(
                            0xFF172B4D,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 3,
                      ),

                      Text(
                        tipo,

                        style:
                            const TextStyle(
                          color:
                              Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),

                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFFE8F7EF,
                    ),

                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),

                  child:
                      const Text(
                    'DENTRO',
                    style:
                        TextStyle(
                      color:
                          Color(
                        0xFF26734D,
                      ),
                      fontSize: 10,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(
              height: 28,
            ),

            // ==================================================
            // DATOS
            // ==================================================

            _dato(
              'Color',
              color,
            ),

            _dato(
              'Hora entrada',
              formatearHora(
                horaEntrada,
              ),
            ),

            _dato(
              'Fecha entrada',
              formatearFechaHora(
                horaEntrada,
              ),
            ),

            if (observacion.isNotEmpty)
              _dato(
                'Observación',
                observacion,
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DATO
  // ============================================================

  Widget _dato(
    String titulo,
    String valor,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 9,
      ),

      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 115,

            child: Text(
              titulo,

              style:
                  const TextStyle(
                color:
                    Colors.grey,
                fontSize: 13,
              ),
            ),
          ),

          Expanded(
            child: Text(
              valor,

              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
