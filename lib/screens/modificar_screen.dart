import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../offline/offline_app_service.dart';
import '../services/api_client.dart';

class ModificarScreen extends StatefulWidget {
  const ModificarScreen({super.key});

  @override
  State<ModificarScreen> createState() => _ModificarScreenState();
}

class _ModificarScreenState extends State<ModificarScreen> {
  // ============================================================
  // API
  // ============================================================

  static final String apiUrl = ApiConfig.baseUrl;

  // ============================================================
  // CONTROLADORES
  // ============================================================

  final TextEditingController patenteBusquedaController =
      TextEditingController();

  final TextEditingController patenteController = TextEditingController();

  final TextEditingController tipoController = TextEditingController();

  final TextEditingController colorController = TextEditingController();

  final TextEditingController observacionController = TextEditingController();

  // ============================================================
  // ESTADOS
  // ============================================================

  bool buscando = false;
  bool guardando = false;
  bool eliminando = false;

  String? error;

  Map<String, dynamic>? registro;
  String? _claveModificacionPendiente;
  String? _datosModificacionPendiente;
  String? _claveEliminacionPendiente;
  String? _datosEliminacionPendiente;

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void initState() {
    super.initState();
    OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();
  }

  @override
  void dispose() {
    patenteBusquedaController.dispose();
    patenteController.dispose();
    tipoController.dispose();
    colorController.dispose();
    observacionController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUSCAR PATENTE
  // ============================================================

  Future<void> buscarPatente() async {
    final patente = patenteBusquedaController.text.trim().toUpperCase();

    if (patente.isEmpty) {
      _mostrarMensaje('Ingresa una patente', esError: true);
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      buscando = true;
      error = null;
      registro = null;
    });

    try {
      final url = '$apiUrl/api/modificar/${Uri.encodeComponent(patente)}';

      debugPrint('GET MODIFICAR: $url');

      final response = await ApiClient.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 10));

      debugPrint('STATUS BUSCAR MODIFICAR: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          buscando = false;
          error = _mensajeError(response.body);
        });

        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        setState(() {
          buscando = false;
          error = 'La API devolvió un formato inválido';
        });

        return;
      }

      final datos = Map<String, dynamic>.from(decoded);

      dynamic datosRegistro = datos['registro'];

      if (datosRegistro == null) {
        datosRegistro = datos['vehiculo'];
      }

      if (datosRegistro == null) {
        datosRegistro = datos;
      }

      if (datosRegistro is! Map) {
        setState(() {
          buscando = false;
          error = 'No se encontró información del vehículo';
        });

        return;
      }

      final mapa = Map<String, dynamic>.from(datosRegistro);

      setState(() {
        registro = mapa;
        buscando = false;
        error = null;

        patenteController.text = _texto(mapa, ['patente'], defecto: '');

        tipoController.text = _texto(mapa, ['tipo'], defecto: '');

        colorController.text = _texto(mapa, ['color'], defecto: '');

        observacionController.text = _texto(mapa, ['observacion'], defecto: '');
      });

      _mostrarMensaje('Vehículo encontrado');
    } catch (e) {
      debugPrint('ERROR BUSCAR MODIFICAR: $e');

      if (!mounted) return;

      final local = await OfflineAppService.instancia.buscarVehiculoDentro(
        patente,
      );

      if (local != null) {
        final mapa = {
          'id': local.servidorId,
          'patente': local.patente,
          'tipo': local.tipo,
          'color': local.color,
          'observacion': local.observacion,
          'horaEntrada': local.horaEntrada.toIso8601String(),
          'version': local.versionServidor,
          'estado': local.estado,
          'offline': true,
        };

        setState(() {
          registro = mapa;
          buscando = false;
          error = null;
          patenteController.text = local.patente;
          tipoController.text = local.tipo;
          colorController.text = local.color;
          observacionController.text = local.observacion;
        });

        _mostrarMensaje('Vehículo encontrado en caché local');
        return;
      }

      setState(() {
        buscando = false;
        error = 'No se pudo conectar con la API';
      });
    }
  }

  // ============================================================
  // GUARDAR CAMBIOS
  // ============================================================

  Future<void> guardarCambios() async {
    if (registro == null) {
      _mostrarMensaje('Primero busca una patente', esError: true);
      return;
    }

    final patenteOriginal = _texto(registro!, [
      'patente',
    ], defecto: '').trim().toUpperCase();

    final patenteNueva = patenteController.text.trim().toUpperCase();

    final tipo = tipoController.text.trim();

    final color = colorController.text.trim();

    final observacion = observacionController.text.trim();

    // ==========================================================
    // VALIDACIONES
    // ==========================================================

    if (patenteNueva.isEmpty) {
      _mostrarMensaje('La patente es obligatoria', esError: true);
      return;
    }

    if (tipo.isEmpty) {
      _mostrarMensaje('El tipo de vehículo es obligatorio', esError: true);
      return;
    }

    if (color.isEmpty) {
      _mostrarMensaje('El color es obligatorio', esError: true);
      return;
    }

    final datosModificacion = <String, dynamic>{
      'patente': patenteNueva,
      'tipo': tipo,
      'color': color,
      'observacion': observacion,
    };

    final version = _numeroNullable(registro?['version']);
    if (version != null) {
      datosModificacion['versionEsperada'] = version;
    }

    final firmaDatos = jsonEncode({
      'patenteOriginal': patenteOriginal,
      ...datosModificacion,
    });

    if (_datosModificacionPendiente != firmaDatos) {
      _datosModificacionPendiente = firmaDatos;
      _claveModificacionPendiente = ApiClient.crearClaveIdempotencia();
    }

    FocusScope.of(context).unfocus();

    setState(() {
      guardando = true;
    });

    try {
      final url =
          '$apiUrl/api/modificar/${Uri.encodeComponent(patenteOriginal)}';

      debugPrint('PUT MODIFICAR: $url');

      final response = await ApiClient.put(
        Uri.parse(url),
        body: jsonEncode(datosModificacion),
        claveIdempotencia: _claveModificacionPendiente,
      ).timeout(const Duration(seconds: 10));

      debugPrint('STATUS GUARDAR MODIFICACION: ${response.statusCode}');

      if (response.statusCode < 500) {
        _claveModificacionPendiente = null;
        _datosModificacionPendiente = null;
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        Map<String, dynamic>? actualizado;

        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map && decoded['registro'] is Map) {
            actualizado = Map<String, dynamic>.from(decoded['registro'] as Map);
          } else if (decoded is Map && decoded['vehiculo'] is Map) {
            actualizado = Map<String, dynamic>.from(decoded['vehiculo'] as Map);
          }
        } catch (_) {}

        setState(() {
          guardando = false;

          if (actualizado != null) {
            registro = actualizado;
          } else {
            registro = {
              ...registro!,
              'patente': patenteNueva,
              'tipo': tipo,
              'color': color,
              'observacion': observacion,
            };
          }
        });

        // Actualizar campos.
        patenteController.text = patenteNueva;

        tipoController.text = tipo;

        colorController.text = color;

        observacionController.text = observacion;

        // La nueva patente pasa a ser
        // la patente de búsqueda.
        patenteBusquedaController.text = patenteNueva;

        _mostrarMensaje('Registro modificado correctamente');
        OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();

        // Volvemos a consultar desde la API.
        await buscarPatente();

        return;
      }

      setState(() {
        guardando = false;
      });

      _mostrarMensaje(_mensajeError(response.body), esError: true);
    } catch (e) {
      debugPrint('ERROR GUARDAR MODIFICACION: $e');

      try {
        final actualizado = await OfflineAppService.instancia.modificarVehiculo(
          clave:
              _claveModificacionPendiente ?? ApiClient.crearClaveIdempotencia(),
          patenteActual: patenteOriginal,
          patenteNueva: patenteNueva,
          tipo: tipo,
          color: color,
          observacion: observacion,
        );

        _claveModificacionPendiente = null;
        _datosModificacionPendiente = null;

        if (!mounted) return;

        setState(() {
          guardando = false;
          registro = {
            'id': actualizado.servidorId,
            'patente': actualizado.patente,
            'tipo': actualizado.tipo,
            'color': actualizado.color,
            'observacion': actualizado.observacion,
            'horaEntrada': actualizado.horaEntrada.toIso8601String(),
            'version': actualizado.versionServidor,
            'estado': actualizado.estado,
            'offline': true,
          };
        });

        patenteController.text = actualizado.patente;
        tipoController.text = actualizado.tipo;
        colorController.text = actualizado.color;
        observacionController.text = actualizado.observacion;
        patenteBusquedaController.text = actualizado.patente;

        _mostrarMensaje(
          'Modificación guardada sin conexión. Se sincronizará al volver internet.',
        );

        return;
      } catch (offlineError) {
        debugPrint('ERROR MODIFICACION OFFLINE: $offlineError');
      }

      if (!mounted) return;

      setState(() {
        guardando = false;
      });

      _mostrarMensaje('No se pudo conectar con la API', esError: true);
    }
  }

  // ============================================================
  // CONFIRMAR ELIMINACIÓN
  // ============================================================

  Future<void> confirmarEliminar() async {
    if (registro == null) {
      return;
    }

    final patente = _texto(registro!, ['patente'], defecto: '').toUpperCase();

    final estado = _texto(registro!, ['estado'], defecto: 'dentro');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 10),
              Expanded(child: Text('Eliminar registro')),
            ],
          ),
          content: Text(
            '¿Seguro que deseas eliminar el registro de la patente $patente?\n\n'
            'Estado actual: $estado\n\n'
            'La eliminación quedará registrada para que el administrador pueda revisarla.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      await eliminarRegistro();
    }
  }

  // ============================================================
  // ELIMINAR REGISTRO
  // ============================================================

  Future<void> eliminarRegistro() async {
    if (registro == null) {
      return;
    }

    final patente = _texto(registro!, [
      'patente',
    ], defecto: '').trim().toUpperCase();

    if (patente.isEmpty) {
      _mostrarMensaje('La patente no es válida', esError: true);
      return;
    }

    final firmaDatos = jsonEncode({'patente': patente});

    if (_datosEliminacionPendiente != firmaDatos) {
      _datosEliminacionPendiente = firmaDatos;
      _claveEliminacionPendiente = ApiClient.crearClaveIdempotencia();
    }

    setState(() {
      eliminando = true;
    });

    try {
      final url = '$apiUrl/api/modificar/${Uri.encodeComponent(patente)}';

      debugPrint('DELETE MODIFICAR: $url');

      final response = await ApiClient.delete(
        Uri.parse(url),
        claveIdempotencia: _claveEliminacionPendiente,
        body: registro?['version'] == null
            ? null
            : jsonEncode({
                'versionEsperada': _numeroNullable(registro?['version']),
              }),
      ).timeout(const Duration(seconds: 10));

      debugPrint('STATUS ELIMINAR: ${response.statusCode}');

      if (response.statusCode < 500) {
        _claveEliminacionPendiente = null;
        _datosEliminacionPendiente = null;
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          eliminando = false;

          registro = null;

          error = null;

          patenteBusquedaController.clear();

          patenteController.clear();

          tipoController.clear();

          colorController.clear();

          observacionController.clear();
        });

        _mostrarMensaje('Registro eliminado correctamente');
        OfflineAppService.instancia.sincronizarEstadoInicialSilencioso();

        return;
      }

      setState(() {
        eliminando = false;
      });

      _mostrarMensaje(_mensajeError(response.body), esError: true);
    } catch (e) {
      debugPrint('ERROR ELIMINAR: $e');

      try {
        await OfflineAppService.instancia.eliminarVehiculo(
          clave:
              _claveEliminacionPendiente ?? ApiClient.crearClaveIdempotencia(),
          patente: patente,
        );

        _claveEliminacionPendiente = null;
        _datosEliminacionPendiente = null;

        if (!mounted) return;

        setState(() {
          eliminando = false;
          registro = null;
          error = null;
          patenteBusquedaController.clear();
          patenteController.clear();
          tipoController.clear();
          colorController.clear();
          observacionController.clear();
        });

        _mostrarMensaje(
          'Eliminación guardada sin conexión. Se sincronizará al volver internet.',
        );

        return;
      } catch (offlineError) {
        debugPrint('ERROR ELIMINACION OFFLINE: $offlineError');
      }

      if (!mounted) return;

      setState(() {
        eliminando = false;
      });

      _mostrarMensaje('No se pudo conectar con la API', esError: true);
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
          'Modificar registros',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            onPressed: buscando || guardando || eliminando
                ? null
                : () {
                    final patente = patenteBusquedaController.text.trim();

                    if (patente.isNotEmpty) {
                      buscarPatente();
                    }
                  },

            tooltip: 'Buscar nuevamente',

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: () async {
          final patente = patenteBusquedaController.text.trim();

          if (patente.isNotEmpty) {
            await buscarPatente();
          }
        },

        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.all(16),

          children: [
            _tarjetaBusqueda(),

            const SizedBox(height: 16),

            if (buscando)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),

            if (error != null && !buscando) _tarjetaError(),

            if (registro != null && !buscando) _formularioRegistro(),

            if (registro == null && error == null && !buscando)
              _tarjetaInformacion(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TARJETA BÚSQUEDA
  // ============================================================

  Widget _tarjetaBusqueda() {
    return Card(
      elevation: 1,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(18),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Row(
              children: [
                Icon(Icons.search, color: Color(0xFF0F5ED7)),

                SizedBox(width: 10),

                Text(
                  'Buscar patente',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF172B4D),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            const Text(
              'Busca una patente actualmente registrada para corregir sus datos o eliminarla.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: patenteBusquedaController,

              textCapitalization: TextCapitalization.characters,

              textInputAction: TextInputAction.search,

              onSubmitted: (_) => buscarPatente(),

              decoration: InputDecoration(
                labelText: 'Patente',

                hintText: 'Ej: TEST01',

                prefixIcon: const Icon(Icons.directions_car_outlined),

                suffixIcon: IconButton(
                  onPressed: () {
                    patenteBusquedaController.clear();

                    setState(() {
                      registro = null;

                      error = null;

                      patenteController.clear();

                      tipoController.clear();

                      colorController.clear();

                      observacionController.clear();
                    });
                  },

                  icon: const Icon(Icons.clear),
                ),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,

              height: 48,

              child: ElevatedButton.icon(
                onPressed: buscando ? null : buscarPatente,

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

                label: Text(buscando ? 'Buscando...' : 'Buscar vehículo'),

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5ED7),

                  foregroundColor: Colors.white,

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TARJETA INFORMACIÓN
  // ============================================================

  Widget _tarjetaInformacion() {
    return Card(
      elevation: 1,

      child: Padding(
        padding: const EdgeInsets.all(22),

        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,

              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),

                borderRadius: BorderRadius.circular(16),
              ),

              child: const Icon(
                Icons.edit_note,
                color: Color(0xFF0F5ED7),
                size: 34,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              'Modificar un registro',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Busca una patente para corregir la patente, tipo, color u observación. También puedes eliminar un registro ingresado por error.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _tarjetaError() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),

            const SizedBox(height: 12),

            Text(
              error ?? 'Error desconocido',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: buscarPatente,

              icon: const Icon(Icons.refresh),

              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FORMULARIO
  // ============================================================

  Widget _formularioRegistro() {
    final id = _numero(registro!['id']);

    final patenteOriginal = _texto(registro!, [
      'patente',
    ], defecto: '').toUpperCase();

    final estado = _texto(registro!, ['estado'], defecto: 'dentro');

    final horaEntrada = _texto(registro!, [
      'horaEntrada',
      'hora_entrada',
    ], defecto: '');

    final horaSalida = _texto(registro!, [
      'horaSalida',
      'hora_salida',
    ], defecto: '');

    final monto = _numeroDouble(registro!['monto']);

    final dentro = estado.toLowerCase() == 'dentro';

    return Card(
      elevation: 1,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

      child: Padding(
        padding: const EdgeInsets.all(18),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // ==================================================
            // ENCABEZADO
            // ==================================================
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,

                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),

                    borderRadius: BorderRadius.circular(10),
                  ),

                  child: const Icon(Icons.edit_note, color: Color(0xFF0F5ED7)),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Editar registro',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        'ID del registro: $id',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ==================================================
            // ESTADO
            // ==================================================
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color: dentro
                    ? const Color(0xFFEAF8F0)
                    : const Color(0xFFF2F4F7),

                borderRadius: BorderRadius.circular(10),

                border: Border.all(
                  color: dentro
                      ? const Color(0xFFB7E5C8)
                      : const Color(0xFFE0E3E7),
                ),
              ),

              child: Row(
                children: [
                  Icon(
                    dentro ? Icons.directions_car : Icons.check_circle_outline,

                    color: dentro ? const Color(0xFF20B46A) : Colors.grey,
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          'Estado: $estado',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),

                        if (horaEntrada.isNotEmpty) const SizedBox(height: 4),

                        if (horaEntrada.isNotEmpty)
                          Text(
                            'Entrada: $horaEntrada',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),

                        if (horaSalida.isNotEmpty) const SizedBox(height: 3),

                        if (horaSalida.isNotEmpty)
                          Text(
                            'Salida: $horaSalida',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // PATENTE
            // ==================================================
            _campo(
              controller: patenteController,
              label: 'Patente',
              icono: Icons.directions_car_outlined,
              mayusculas: true,
            ),

            const SizedBox(height: 12),

            // ==================================================
            // TIPO
            // ==================================================
            _campo(
              controller: tipoController,
              label: 'Tipo de vehículo',
              icono: Icons.commute_outlined,
            ),

            const SizedBox(height: 12),

            // ==================================================
            // COLOR
            // ==================================================
            _campo(
              controller: colorController,
              label: 'Color',
              icono: Icons.palette_outlined,
            ),

            const SizedBox(height: 12),

            // ==================================================
            // OBSERVACIÓN
            // ==================================================
            _campo(
              controller: observacionController,
              label: 'Observación',
              icono: Icons.notes_outlined,
              maxLines: 3,
            ),

            const SizedBox(height: 16),

            // ==================================================
            // TOTAL
            // ==================================================
            if (!dentro && monto > 0)
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),

                  borderRadius: BorderRadius.circular(10),
                ),

                child: Row(
                  children: [
                    const Icon(Icons.attach_money, color: Color(0xFF20B46A)),

                    const SizedBox(width: 8),

                    const Text(
                      'Total cobrado:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),

                    const Spacer(),

                    Text(
                      _formatoPesos(monto),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF20B46A),
                      ),
                    ),
                  ],
                ),
              ),

            if (!dentro && monto > 0) const SizedBox(height: 16),

            // ==================================================
            // GUARDAR
            // ==================================================
            SizedBox(
              width: double.infinity,

              height: 50,

              child: ElevatedButton.icon(
                onPressed: guardando || eliminando ? null : guardarCambios,

                icon: guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),

                label: Text(guardando ? 'Guardando...' : 'Guardar cambios'),

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5ED7),

                  foregroundColor: Colors.white,

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ==================================================
            // ELIMINAR
            // ==================================================
            SizedBox(
              width: double.infinity,

              height: 48,

              child: OutlinedButton.icon(
                onPressed: guardando || eliminando ? null : confirmarEliminar,

                icon: eliminando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),

                label: Text(eliminando ? 'Eliminando...' : 'Eliminar registro'),

                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,

                  side: const BorderSide(color: Colors.red),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ==================================================
            // AUDITORÍA
            // ==================================================
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),

                borderRadius: BorderRadius.circular(10),

                border: Border.all(color: const Color(0xFFFFE082)),
              ),

              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Icon(Icons.history, size: 18, color: Colors.orange),

                  SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      'Toda modificación o eliminación queda registrada con el usuario responsable para revisión del administrador.',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ==================================================
            // PATENTE ORIGINAL
            // ==================================================
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: patenteController,
              builder: (context, value, child) {
                final actual = value.text.trim().toUpperCase();

                if (actual == patenteOriginal || actual.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Text(
                  'Patente original: $patenteOriginal',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CAMPO
  // ============================================================

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icono,
    bool mayusculas = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,

      textCapitalization: mayusculas
          ? TextCapitalization.characters
          : TextCapitalization.sentences,

      maxLines: maxLines,

      decoration: InputDecoration(
        labelText: label,

        prefixIcon: Icon(icono),

        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ============================================================
  // TEXTO
  // ============================================================

  String _texto(
    Map<String, dynamic> mapa,
    List<String> campos, {
    String defecto = '-',
  }) {
    for (final campo in campos) {
      if (mapa.containsKey(campo) && mapa[campo] != null) {
        final valor = mapa[campo].toString().trim();

        if (valor.isNotEmpty) {
          return valor;
        }
      }
    }

    return defecto;
  }

  // ============================================================
  // NÚMERO
  // ============================================================

  int _numero(dynamic valor) {
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

  int? _numeroNullable(dynamic valor) {
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

  // ============================================================
  // DOUBLE
  // ============================================================

  double _numeroDouble(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString()) ?? 0;
  }

  // ============================================================
  // FORMATO PESOS
  // ============================================================

  String _formatoPesos(double valor) {
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
  // MENSAJE ERROR API
  // ============================================================

  String _mensajeError(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is Map) {
        if (decoded['mensaje'] != null) {
          return decoded['mensaje'].toString();
        }

        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }

        if (decoded['error'] != null) {
          return decoded['error'].toString();
        }

        if (decoded['codigo'] != null) {
          final codigo = decoded['codigo'].toString();
          if (codigo == 'MOVIMIENTO_DESACTUALIZADO') {
            return 'El vehículo fue modificado o retirado desde otra sesión';
          }
          if (codigo == 'PATENTE_YA_DENTRO') {
            return 'La nueva patente ya se encuentra dentro del estacionamiento';
          }
          return codigo.replaceAll('_', ' ');
        }
      }
    } catch (_) {}

    if (body.contains('Cannot GET')) {
      return 'La ruta de modificación no está disponible en el servidor';
    }

    if (body.contains('Cannot PUT')) {
      return 'La ruta para guardar modificaciones no está disponible';
    }

    if (body.contains('Cannot DELETE')) {
      return 'La ruta para eliminar registros no está disponible';
    }

    return 'No se pudo completar la operación';
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,

        backgroundColor: esError ? Colors.red : const Color(0xFF20B46A),

        content: Text(mensaje),
      ),
    );
  }
}
