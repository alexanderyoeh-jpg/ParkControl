import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});

  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  static final String _apiUrl = ApiConfig.baseUrl;

  List<Map<String, dynamic>> _registros = [];
  bool _cargando = true;
  String? _error;
  String _filtro = 'TODAS';

  @override
  void initState() {
    super.initState();
    _cargarAuditoria();
  }

  Future<void> _cargarAuditoria() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuesta = await ApiClient.get(
        Uri.parse('$_apiUrl/api/auditoria'),
      ).timeout(const Duration(seconds: 12));

      if (respuesta.statusCode != 200) {
        throw Exception(
          ApiClient.extraerMensajeError(
            respuesta,
            mensajePredeterminado: 'No se pudo cargar la auditoría',
          ),
        );
      }

      final datos = jsonDecode(respuesta.body);
      final lista = datos is Map ? datos['auditoria'] : null;

      if (lista is! List) {
        throw Exception('La auditoría no tiene un formato válido');
      }

      if (!mounted) return;

      setState(() {
        _registros = lista
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
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

  List<Map<String, dynamic>> get _registrosFiltrados {
    if (_filtro == 'TODAS') return _registros;

    if (_filtro == 'VEHICULOS') {
      return _registros.where((r) {
        final accion = r['accion']?.toString() ?? '';
        return accion == 'MODIFICACION' || accion == 'ELIMINACION';
      }).toList();
    }

    if (_filtro == 'TURNOS') {
      return _registros.where((r) {
        final accion = r['accion']?.toString() ?? '';
        return accion.startsWith('TURNO_');
      }).toList();
    }

    if (_filtro == 'OFFLINE') {
      return _registros.where((r) {
        final accion = r['accion']?.toString() ?? '';
        return accion.contains('OFFLINE') || accion.contains('CONFLICTO');
      }).toList();
    }

    return _registros.where((registro) {
      return registro['accion']?.toString() == _filtro;
    }).toList();
  }

  String _fecha(dynamic valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '');

    if (fecha == null) return '-';

    final local = fecha.toLocal();
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${local.year} · $hora:$minuto';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Auditoría general'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargarAuditoria,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarAuditoria,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Registro de auditoría y trazabilidad',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Historial cronológico de cambios en vehículos, turnos de caja y contingencias.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 16),
            _filtros(),
            const SizedBox(height: 16),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.only(top: 56),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _estadoError()
            else if (_registrosFiltrados.isEmpty)
              _estadoVacio()
            else
              ..._registrosFiltrados.map(_tarjetaRegistro),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chipFiltro('TODAS', 'Todas'),
          const SizedBox(width: 8),
          _chipFiltro('VEHICULOS', 'Vehículos'),
          const SizedBox(width: 8),
          _chipFiltro('TURNOS', 'Turnos y Caja'),
          const SizedBox(width: 8),
          _chipFiltro('OFFLINE', 'Contingencias Offline'),
        ],
      ),
    );
  }

  Widget _chipFiltro(String valor, String etiqueta) {
    return ChoiceChip(
      label: Text(etiqueta),
      selected: _filtro == valor,
      onSelected: (_) {
        setState(() {
          _filtro = valor;
        });
      },
      selectedColor: const Color(0xFFDDEBFF),
    );
  }

  Widget _tarjetaRegistro(Map<String, dynamic> registro) {
    final accion = registro['accion']?.toString() ?? 'CAMBIO';
    final usuario = registro['usuarioNombre']?.toString().trim();
    final correo = registro['usuarioEmail']?.toString().trim();
    final observacion = registro['observacionNueva']?.toString().trim() ?? '';
    final patenteAnterior = registro['patenteAnterior']?.toString().trim();
    final patenteNueva = registro['patenteNueva']?.toString().trim();

    IconData icono;
    Color colorIcono;
    Color fondoIcono;
    String titulo;
    String detalle;

    switch (accion) {
      case 'ELIMINACION':
        icono = Icons.delete_outline;
        colorIcono = Colors.red;
        fondoIcono = const Color(0xFFFFE7E7);
        titulo = 'Operación anulada';
        detalle = 'Patente: ${patenteAnterior ?? 'No especificada'}';
        break;

      case 'MODIFICACION':
        icono = Icons.edit_outlined;
        colorIcono = const Color(0xFF1565FF);
        fondoIcono = const Color(0xFFE5F2FF);
        titulo = 'Vehículo modificado';
        if (patenteAnterior != null && patenteNueva != null && patenteAnterior != patenteNueva) {
          detalle = 'Patente cambiada: $patenteAnterior → $patenteNueva';
        } else {
          detalle = 'Patente: ${patenteNueva ?? patenteAnterior ?? '-'}\n'
              'Tipo: ${registro['tipoNuevo'] ?? '-'}'
              ' · Color: ${registro['colorNuevo'] ?? '-'}';
        }
        break;

      case 'TURNO_INICIADO':
        icono = Icons.lock_open_outlined;
        colorIcono = Colors.green.shade700;
        fondoIcono = Colors.green.shade50;
        titulo = 'Apertura de turno de caja';
        detalle = observacion.isNotEmpty ? observacion : 'Turno de caja iniciado';
        break;

      case 'TURNO_CERRADO':
        icono = Icons.lock_clock_outlined;
        colorIcono = Colors.orange.shade800;
        fondoIcono = Colors.orange.shade50;
        titulo = 'Cierre de turno de caja';
        detalle = observacion.isNotEmpty ? observacion : 'Turno cerrado y totalizado';
        break;

      case 'TURNO_REVISADO':
        icono = Icons.verified_user_outlined;
        colorIcono = Colors.indigo.shade800;
        fondoIcono = Colors.indigo.shade50;
        titulo = 'Turno revisado por administrador';
        detalle = observacion.isNotEmpty ? observacion : 'Revisión administrativa registrada';
        break;

      case 'CONFLICTO_OFFLINE_DESCARTADO':
        icono = Icons.sync_problem_outlined;
        colorIcono = Colors.amber.shade900;
        fondoIcono = Colors.amber.shade50;
        titulo = 'Conflicto offline resuelto';
        detalle = observacion.isNotEmpty ? observacion : 'Operación conflictiva descartada';
        break;

      default:
        icono = Icons.info_outline;
        colorIcono = Colors.blueGrey;
        fondoIcono = const Color(0xFFECEFF1);
        titulo = accion.replaceAll('_', ' ');
        detalle = observacion.isNotEmpty ? observacion : 'Evento auditado';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE4EAF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: fondoIcono,
                  child: Icon(icono, color: colorIcono),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  _fecha(registro['fecha']),
                  style: const TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              detalle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text(
                  'Responsable: ${(usuario == null || usuario.isEmpty) ? 'No informado' : usuario}',
                  style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                ),
              ],
            ),
            if (correo != null && correo.isNotEmpty) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(
                  correo,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _estadoError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 54),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 54, color: Colors.red),
            const SizedBox(height: 14),
            Text(_error ?? 'Error desconocido', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _cargarAuditoria,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estadoVacio() {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.history_toggle_off, size: 58, color: Colors.blueGrey),
          SizedBox(height: 14),
          Text(
            'Aún no hay registros de auditoría con este filtro.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
