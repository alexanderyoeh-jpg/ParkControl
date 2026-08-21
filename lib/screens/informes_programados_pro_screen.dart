import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class InformesProgramadosProScreen extends StatefulWidget {
  const InformesProgramadosProScreen({super.key});

  @override
  State<InformesProgramadosProScreen> createState() =>
      _InformesProgramadosProScreenState();
}

class _InformesProgramadosProScreenState
    extends State<InformesProgramadosProScreen> {
  bool _cargando = true;
  bool _transporteDisponible = false;
  String _mensajeTransporte = '';
  String? _error;
  List<Map<String, dynamic>> _programaciones = [];
  List<Map<String, dynamic>> _envios = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/pro/informes-correo'),
      ).timeout(const Duration(seconds: 15));
      final datos = jsonDecode(respuesta.body);

      if (respuesta.statusCode != 200 || datos is! Map) {
        throw Exception(_mensajeRespuesta(datos));
      }

      final transporte = datos['transporte'] is Map
          ? Map<String, dynamic>.from(datos['transporte'] as Map)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _transporteDisponible = transporte['disponible'] == true;
        _mensajeTransporte = transporte['mensaje']?.toString() ?? '';
        _programaciones = _listaMapas(datos['programaciones']);
        _envios = _listaMapas(datos['envios']);
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> _listaMapas(dynamic valor) {
    if (valor is! List) return [];
    return valor.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  String _mensajeRespuesta(dynamic datos) {
    if (datos is Map) {
      return datos['mensaje']?.toString() ?? 'No se pudo completar la acción';
    }
    return 'No se pudo completar la acción';
  }

  Future<Map<String, dynamic>> _respuestaJson(Future<dynamic> solicitud) async {
    final respuesta = await solicitud.timeout(const Duration(seconds: 15));
    final datos = jsonDecode(respuesta.body);

    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw Exception(_mensajeRespuesta(datos));
    }

    return datos is Map ? Map<String, dynamic>.from(datos) : {};
  }

  String _frecuencia(dynamic valor) {
    switch (valor?.toString()) {
      case 'diario':
        return 'Diario';
      case 'semanal':
        return 'Semanal · lunes';
      case 'mensual':
        return 'Mensual · día 1';
      default:
        return 'Manual';
    }
  }

  String _estadoEnvio(dynamic valor) {
    switch (valor?.toString()) {
      case 'pendiente':
        return 'Pendiente';
      case 'enviando':
        return 'Enviando';
      case 'reintento':
        return 'Reintento programado';
      case 'enviado':
        return 'Enviado';
      case 'fallido':
        return 'Fallido';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Sin estado';
    }
  }

  Color _colorEstadoEnvio(dynamic valor) {
    switch (valor?.toString()) {
      case 'enviado':
        return const Color(0xFF168A4C);
      case 'fallido':
      case 'cancelado':
        return Colors.red.shade700;
      case 'reintento':
        return const Color(0xFFE07117);
      default:
        return const Color(0xFF2B6EEF);
    }
  }

  Future<void> _mostrarError(Object error) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se pudo completar'),
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarProgramacion({Map<String, dynamic>? existente}) async {
    var frecuencia = existente?['frecuencia']?.toString() ?? 'diario';
    final controladorHora = TextEditingController(
      text: existente?['horaLocal']?.toString() ?? '08:00',
    );
    var activo = existente?['activo'] != false;
    var guardando = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !guardando,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, actualizar) => AlertDialog(
          title: Text(
            existente == null ? 'Programar informe' : 'Editar programación',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El informe se entrega al correo de tu cuenta administradora. No se puede indicar una dirección externa desde esta pantalla.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: frecuencia,
                  decoration: const InputDecoration(
                    labelText: 'Frecuencia',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'diario', child: Text('Diario')),
                    DropdownMenuItem(
                      value: 'semanal',
                      child: Text('Semanal · lunes'),
                    ),
                    DropdownMenuItem(
                      value: 'mensual',
                      child: Text('Mensual · día 1'),
                    ),
                  ],
                  onChanged: existente == null
                      ? (valor) {
                          if (valor != null)
                            actualizar(() => frecuencia = valor);
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controladorHora,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'Hora local',
                    hintText: '08:00',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Programación activa'),
                  value: activo,
                  onChanged: (valor) => actualizar(() => activo = valor),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: guardando
                  ? null
                  : () async {
                      actualizar(() => guardando = true);
                      try {
                        final cuerpo = jsonEncode({
                          if (existente == null) 'frecuencia': frecuencia,
                          'horaLocal': controladorHora.text.trim(),
                          'activo': activo,
                          if (existente != null) 'usarMiCorreo': true,
                        });

                        if (existente == null) {
                          await _respuestaJson(
                            ApiClient.post(
                              Uri.parse(
                                '${ApiConfig.baseUrl}/api/pro/informes-correo',
                              ),
                              body: cuerpo,
                            ),
                          );
                        } else {
                          await _respuestaJson(
                            ApiClient.patch(
                              Uri.parse(
                                '${ApiConfig.baseUrl}/api/pro/informes-correo/${existente['id']}',
                              ),
                              body: cuerpo,
                            ),
                          );
                        }

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await _cargar();
                      } catch (error) {
                        if (dialogContext.mounted) {
                          actualizar(() => guardando = false);
                        }
                        await _mostrarError(error);
                      }
                    },
              child: Text(guardando ? 'Guardando…' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    controladorHora.dispose();
  }

  Future<void> _desactivar(Map<String, dynamic> programacion) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desactivar programación'),
        content: Text(
          'Se detendrán los informes ${_frecuencia(programacion['frecuencia']).toLowerCase()}. El historial se conservará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _respuestaJson(
        ApiClient.delete(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/pro/informes-correo/${programacion['id']}',
          ),
        ),
      );
      await _cargar();
    } catch (error) {
      await _mostrarError(error);
    }
  }

  Future<void> _enviarPrueba(Map<String, dynamic> programacion) async {
    try {
      final datos = await _respuestaJson(
        ApiClient.post(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/pro/informes-correo/${programacion['id']}/envio-prueba',
          ),
          body: jsonEncode({}),
          claveIdempotencia: ApiClient.crearClaveIdempotencia(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(datos['mensaje']?.toString() ?? 'Informe en cola'),
        ),
      );
      await _cargar();
    } catch (error) {
      await _mostrarError(error);
    }
  }

  Future<void> _reintentar(Map<String, dynamic> envio) async {
    try {
      final datos = await _respuestaJson(
        ApiClient.post(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/pro/informes-correo/envios/${envio['id']}/reintentar',
          ),
          body: jsonEncode({}),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(datos['mensaje']?.toString() ?? 'Reintento en cola'),
        ),
      );
      await _cargar();
    } catch (error) {
      await _mostrarError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Informes por correo Pro'),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _cargando || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _guardarProgramacion(),
              icon: const Icon(Icons.add),
              label: const Text('Programar'),
            ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Informes programados',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Resumen contable y CSV generados por el servidor a partir de datos reales.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 18),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _tarjetaError()
            else ...[
              _tarjetaTransporte(),
              const SizedBox(height: 18),
              const Text(
                'Programaciones',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (_programaciones.isEmpty)
                _tarjetaVacia(
                  icono: Icons.schedule_send_outlined,
                  texto: 'Aún no hay informes programados.',
                )
              else
                ..._programaciones.map(_tarjetaProgramacion),
              const SizedBox(height: 22),
              const Text(
                'Historial de envíos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (_envios.isEmpty)
                _tarjetaVacia(
                  icono: Icons.mark_email_read_outlined,
                  texto: 'Los resultados de envío aparecerán aquí.',
                )
              else
                ..._envios.map(_tarjetaEnvio),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjetaTransporte() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _transporteDisponible
          ? const Color(0xFFE7F7ED)
          : const Color(0xFFFFF5E6),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(
          _transporteDisponible
              ? Icons.mark_email_read_outlined
              : Icons.info_outline,
          color: _transporteDisponible
              ? const Color(0xFF168A4C)
              : const Color(0xFFE07117),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            _mensajeTransporte.isEmpty
                ? (_transporteDisponible
                      ? 'El correo está configurado.'
                      : 'El correo aún no está configurado.')
                : _mensajeTransporte,
          ),
        ),
      ],
    ),
  );

  Widget _tarjetaProgramacion(Map<String, dynamic> programacion) {
    final activa = programacion['activo'] == true;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.schedule_send_outlined,
                  color: Color(0xFF2B6EEF),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _frecuencia(programacion['frecuencia']),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Chip(
                  label: Text(activa ? 'Activa' : 'Pausada'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: activa
                      ? const Color(0xFFE7F7ED)
                      : const Color(0xFFF0F2F5),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text('Hora local: ${programacion['horaLocal'] ?? '--:--'}'),
            const SizedBox(height: 3),
            Text(
              'Destino: ${programacion['correoDestino'] ?? 'Correo protegido'}',
            ),
            if (programacion['zonaHoraria'] != null) ...[
              const SizedBox(height: 3),
              Text(
                'Zona: ${programacion['zonaHoraria']}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _guardarProgramacion(existente: programacion),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
                if (_transporteDisponible && activa)
                  FilledButton.icon(
                    onPressed: () => _enviarPrueba(programacion),
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Enviar ahora'),
                  ),
                if (activa)
                  TextButton.icon(
                    onPressed: () => _desactivar(programacion),
                    icon: const Icon(Icons.pause_circle_outline, size: 18),
                    label: const Text('Desactivar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaEnvio(Map<String, dynamic> envio) {
    final estado = envio['estado'];
    final permiteReintento = estado == 'fallido' || estado == 'cancelado';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.mail_outline, color: _colorEstadoEnvio(estado)),
        title: Text(_estadoEnvio(estado)),
        subtitle: Text(
          '${_frecuencia(envio['frecuencia'])} · ${envio['periodoInicio'] ?? '-'} a ${envio['periodoFin'] ?? '-'}\n${envio['correoDestino'] ?? 'Correo protegido'}${envio['errorPublico'] == null ? '' : '\n${envio['errorPublico']}'}',
        ),
        isThreeLine: envio['errorPublico'] != null,
        trailing: permiteReintento && _transporteDisponible
            ? IconButton(
                tooltip: 'Reintentar',
                onPressed: () => _reintentar(envio),
                icon: const Icon(Icons.refresh),
              )
            : null,
      ),
    );
  }

  Widget _tarjetaVacia({required IconData icono, required String texto}) =>
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Icon(icono, color: Colors.blueGrey),
              const SizedBox(width: 12),
              Expanded(child: Text(texto)),
            ],
          ),
        ),
      );

  Widget _tarjetaError() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFECEC),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red),
        const SizedBox(width: 9),
        Expanded(child: Text(_error!)),
        TextButton(onPressed: _cargar, child: const Text('Reintentar')),
      ],
    ),
  );
}
