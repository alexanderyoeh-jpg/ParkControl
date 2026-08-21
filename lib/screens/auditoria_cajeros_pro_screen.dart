import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';
import '../services/pdf_service.dart';

/// Auditoría Pro enfocada en turnos y desempeño de cajeros.
/// Los gráficos se alimentan únicamente de /api/pro/auditoria-cajeros y los
/// cierres persistidos en /api/pro/turnos.
class AuditoriaCajerosProScreen extends StatefulWidget {
  const AuditoriaCajerosProScreen({super.key});

  @override
  State<AuditoriaCajerosProScreen> createState() =>
      _AuditoriaCajerosProScreenState();
}

class _AuditoriaCajerosProScreenState extends State<AuditoriaCajerosProScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animacion;
  String _periodo = 'mes';
  List<Map<String, dynamic>> _puntos = [];
  List<Map<String, dynamic>> _cajeros = [];
  List<Map<String, dynamic>> _turnos = [];
  Map<String, dynamic> _resumen = {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _animacion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _cargar();
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuestas = await Future.wait([
        ApiClient.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/pro/auditoria-cajeros?periodo=$_periodo',
          ),
        ).timeout(const Duration(seconds: 12)),
        ApiClient.get(
          Uri.parse('${ApiConfig.baseUrl}/api/pro/turnos'),
        ).timeout(const Duration(seconds: 12)),
      ]);
      final auditoria = jsonDecode(respuestas[0].body);
      final turnos = jsonDecode(respuestas[1].body);

      if (respuestas[0].statusCode != 200 || auditoria is! Map) {
        throw Exception(
          ApiClient.extraerMensajeError(
            respuestas[0],
            mensajePredeterminado: 'No se pudo cargar la auditoría de cajeros.',
          ),
        );
      }

      if (respuestas[1].statusCode != 200 || turnos is! Map) {
        throw Exception(
          ApiClient.extraerMensajeError(
            respuestas[1],
            mensajePredeterminado: 'No se pudieron cargar los turnos de caja.',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _puntos = (auditoria['puntos'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _cajeros = (auditoria['cajeros'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _turnos = (turnos['turnos'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _resumen = auditoria['resumen'] is Map
            ? Map<String, dynamic>.from(auditoria['resumen'] as Map)
            : <String, dynamic>{};
        _cargando = false;
      });
      _animacion
        ..reset()
        ..forward();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _mensajeApi(dynamic datos, String porDefecto) {
    if (datos is Map) {
      final mensaje = datos['mensaje']?.toString().trim();
      if (mensaje != null && mensaje.isNotEmpty) return mensaje;
    }
    return porDefecto;
  }

  Future<void> _cambiarPeriodo(String periodo) async {
    if (periodo == _periodo) return;
    setState(() => _periodo = periodo);
    await _cargar();
  }

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  int _entero(dynamic valor) => _numero(valor).round();

  String _pesos(dynamic valor) {
    final texto = _numero(valor).round().toString();
    final salida = StringBuffer();
    for (var indice = 0; indice < texto.length; indice++) {
      if (indice > 0 && (texto.length - indice) % 3 == 0) salida.write('.');
      salida.write(texto[indice]);
    }
    return '\$${salida.toString()}';
  }

  String _fecha(dynamic valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '')?.toLocal();
    if (fecha == null) return '-';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} · ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Auditoría de cajeros Pro'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Control de turnos y caja',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Datos reales de cobros, cierres, modificaciones y anulaciones por cajero.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipPeriodo('dia', 'Día'),
                _chipPeriodo('semana', 'Semana'),
                _chipPeriodo('mes', 'Mes'),
                _chipPeriodo('semestre', 'Semestre'),
                _chipPeriodo('ano', 'Año'),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null)
              _tarjetaError()
            else if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 65),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _graficoRecaudacion(),
              const SizedBox(height: 16),
              _metricas(),
              if (_tieneAlertasCierre) ...[
                const SizedBox(height: 16),
                _alertasCierre(),
              ],
              const SizedBox(height: 22),
              _titulo('Desempeño por cajero'),
              const SizedBox(height: 10),
              _desempenoCajeros(),
              const SizedBox(height: 22),
              _titulo('Últimos turnos'),
              const SizedBox(height: 10),
              _ultimosTurnos(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipPeriodo(String valor, String etiqueta) => ChoiceChip(
    label: Text(etiqueta),
    selected: _periodo == valor,
    selectedColor: const Color(0xFFDDE9FF),
    onSelected: (_) => _cambiarPeriodo(valor),
  );

  Widget _titulo(String texto) => Text(
    texto,
    style: const TextStyle(
      color: Color(0xFF172B4D),
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
  );

  int get _cierresConDiferenciaPendiente => _turnos.where((turno) {
    final cerrado = turno['estado']?.toString() == 'cerrado';
    final pendiente =
        (turno['estadoRevision']?.toString() ?? 'pendiente') == 'pendiente';
    return cerrado && pendiente && _numero(turno['diferencia']).abs() > 0.009;
  }).length;

  int get _cierresObservados => _turnos.where((turno) {
    return turno['estado']?.toString() == 'cerrado' &&
        turno['estadoRevision']?.toString() == 'observado';
  }).length;

  bool get _tieneAlertasCierre =>
      _cierresConDiferenciaPendiente > 0 || _cierresObservados > 0;

  Widget _alertasCierre() {
    final diferencias = _cierresConDiferenciaPendiente;
    final observados = _cierresObservados;
    final mensajes = <String>[];

    if (diferencias > 0) {
      mensajes.add(
        '$diferencias cierre${diferencias == 1 ? '' : 's'} con diferencia pendiente de revisión',
      );
    }
    if (observados > 0) {
      mensajes.add(
        '$observados cierre${observados == 1 ? '' : 's'} observado${observados == 1 ? '' : 's'}',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E5),
        border: Border.all(color: const Color(0xFFF2C36D)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFA46700)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Atención requerida en cierres de caja',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7A4B00),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${mensajes.join(' · ')}. Revisa los turnos antes de confirmar la conciliación.',
                  style: const TextStyle(color: Color(0xFF7A4B00)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _graficoRecaudacion() {
    final maximo = _puntos.fold<double>(
      0,
      (mayor, punto) => math.max(mayor, _numero(punto['recaudado'])),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      decoration: _caja(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.query_stats_rounded, color: Color(0xFF2B6EEF)),
              SizedBox(width: 9),
              Text(
                'Recaudación por turnos',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            maximo == 0
                ? 'Aún no existen cobros cerrados por cajeros en este período.'
                : 'El recorrido animado muestra la caja registrada hasta el momento actual.',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 215,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: CurvedAnimation(
                parent: _animacion,
                curve: Curves.easeOutCubic,
              ),
              builder: (_, __) => CustomPaint(
                painter: _GraficoAuditoriaPainter(
                  puntos: _puntos,
                  progreso: _animacion.value,
                  maximo: maximo,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricas() => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      _metrica(
        'Recaudado',
        _pesos(_resumen['recaudado']),
        Icons.payments_outlined,
        const Color(0xFF168A4C),
      ),
      _metrica(
        'Turnos cerrados',
        '${_entero(_resumen['turnosCerrados'])}',
        Icons.fact_check_outlined,
        const Color(0xFF7055B5),
      ),
      _metrica(
        'Modificaciones',
        '${_entero(_resumen['modificaciones'])}',
        Icons.edit_note_outlined,
        const Color(0xFFF08A24),
      ),
      _metrica(
        'Eliminaciones',
        '${_entero(_resumen['eliminaciones'])}',
        Icons.delete_outline,
        const Color(0xFFE05A47),
      ),
    ],
  );

  Widget _metrica(String titulo, String valor, IconData icono, Color color) =>
      SizedBox(
        width: (MediaQuery.sizeOf(context).width - 46) / 2,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: _caja(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: color),
              const SizedBox(height: 12),
              Text(
                valor,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                titulo,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      );

  BoxDecoration _caja() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFE0E8F5)),
  );

  Widget _desempenoCajeros() {
    if (_cajeros.isEmpty)
      return _vacio('Aún no hay cajeros registrados para este período.');

    final maximo = _cajeros.fold<double>(
      0,
      (mayor, cajero) => math.max(mayor, _numero(cajero['recaudado'])),
    );
    return Column(
      children: _cajeros.map((cajero) {
        final recaudado = _numero(cajero['recaudado']);
        final progreso = maximo == 0 ? 0.0 : recaudado / maximo;
        final diferencia = _numero(cajero['diferenciaAcumulada']);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: _caja(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFE6EEFF),
                    child: Text(
                      (cajero['nombre']?.toString().trim().isNotEmpty ?? false)
                          ? cajero['nombre'].toString().trim()[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Color(0xFF2B6EEF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cajero['nombre']?.toString() ?? 'Cajero',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          cajero['email']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _pesos(recaudado),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F6B48),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progreso,
                  minHeight: 7,
                  color: const Color(0xFF2B6EEF),
                  backgroundColor: const Color(0xFFE8EDF6),
                ),
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 12,
                runSpacing: 5,
                children: [
                  _datoCajero('${_entero(cajero['turnosCerrados'])} turnos'),
                  _datoCajero('${_entero(cajero['cobros'])} cobros'),
                  _datoCajero(
                    '${_entero(cajero['modificaciones'])} modificaciones',
                  ),
                  _datoCajero(
                    '${_entero(cajero['eliminaciones'])} eliminaciones',
                  ),
                ],
              ),
              if (diferencia != 0) ...[
                const SizedBox(height: 9),
                Text(
                  'Diferencia acumulada en cierres: ${_pesos(diferencia)}',
                  style: const TextStyle(
                    color: Color(0xFFA46700),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _datoCajero(String texto) =>
      Text(texto, style: const TextStyle(fontSize: 12, color: Colors.blueGrey));

  Widget _ultimosTurnos() {
    if (_turnos.isEmpty)
      return _vacio('Aún no se han registrado turnos de caja.');
    return Column(
      children: _turnos.take(12).map((turno) {
        final abierto = turno['estado']?.toString() == 'abierto';
        final diferencia = _numero(turno['diferencia']);
        final novedad = turno['novedadCierre']?.toString().trim();
        final estadoRevision =
            turno['estadoRevision']?.toString() ?? 'pendiente';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: _caja(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    abierto ? Icons.lock_open_outlined : Icons.lock_outline,
                    color: abierto
                        ? const Color(0xFF2B6EEF)
                        : const Color(0xFF0F7A4A),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      turno['cajeroNombre']?.toString() ?? 'Cajero',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _estadoTurno(abierto),
                ],
              ),
              const SizedBox(height: 10),
              Text('Inicio: ${_fecha(turno['abiertoEn'])}'),
              if (!abierto) Text('Cierre: ${_fecha(turno['cerradoEn'])}'),
              const SizedBox(height: 6),
              Text(
                abierto
                    ? 'Efectivo esperado: ${_pesos(turno['montoEsperado'])}'
                    : 'Efectivo esperado ${_pesos(turno['montoEsperado'])} · Declarado ${_pesos(turno['montoDeclarado'])}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Total cobrado ${_pesos(turno['montoRecaudado'])} · Transferencias ${_pesos(turno['montoTransferencia'])} · Tarjetas ${_pesos(turno['montoTarjeta'])}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              if (!abierto && _entero(turno['vehiculosDentroAlCierre']) > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _mostrarVehiculosAlCierre(turno),
                    icon: const Icon(Icons.local_parking_outlined, size: 18),
                    label: Text(
                      'Ver ${_entero(turno['vehiculosDentroAlCierre'])} vehículo(s) que quedaron dentro',
                    ),
                  ),
                ),
              if (!abierto && diferencia != 0) ...[
                const SizedBox(height: 5),
                Text(
                  'Diferencia: ${_pesos(diferencia)}',
                  style: const TextStyle(
                    color: Color(0xFFA46700),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (!abierto) ...[
                const SizedBox(height: 9),
                _revisionTurno(turno, estadoRevision),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _abrirPdfCierre(turno),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Descargar comprobante de cierre'),
                  ),
                ),
              ],
              if (novedad != null && novedad.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Novedad: $novedad',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _revisionTurno(Map<String, dynamic> turno, String estadoRevision) {
    if (estadoRevision == 'pendiente') {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _mostrarRevisionCierre(turno),
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('Revisar cierre'),
        ),
      );
    }

    final observado = estadoRevision == 'observado';
    final comentario = turno['observacionRevision']?.toString().trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: observado ? const Color(0xFFFFF5E5) : const Color(0xFFEAF8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            observado ? 'Cierre observado' : 'Cierre confirmado',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: observado
                  ? const Color(0xFFA46700)
                  : const Color(0xFF0F7A4A),
            ),
          ),
          if (turno['revisorNombre'] != null)
            Text(
              'Por: ${turno['revisorNombre']} · ${_fecha(turno['revisadoEn'])}',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          if (comentario != null && comentario.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(comentario, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Future<void> _mostrarRevisionCierre(Map<String, dynamic> turno) async {
    final turnoId = _entero(turno['id']);
    if (turnoId <= 0) return;
    String estadoRevision = 'revisado';
    final observacion = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, actualizar) => AlertDialog(
          title: const Text('Revisar cierre de caja'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Efectivo esperado: ${_pesos(turno['montoEsperado'])}'),
                Text('Efectivo declarado: ${_pesos(turno['montoDeclarado'])}'),
                Text('Diferencia: ${_pesos(turno['diferencia'])}'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: estadoRevision,
                  decoration: const InputDecoration(
                    labelText: 'Resultado de la revisión',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'revisado',
                      child: Text('Confirmar cierre'),
                    ),
                    DropdownMenuItem(
                      value: 'observado',
                      child: Text('Observar cierre'),
                    ),
                  ],
                  onChanged: (valor) {
                    if (valor == null) return;
                    actualizar(() => estadoRevision = valor);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacion,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: estadoRevision == 'observado'
                        ? 'Observación requerida'
                        : 'Comentario de revisión (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (estadoRevision == 'observado' &&
                    observacion.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                estadoRevision == 'observado'
                    ? 'Registrar observación'
                    : 'Confirmar',
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmar != true || !mounted) return;
    try {
      final respuesta = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/pro/turnos/$turnoId/revision'),
        body: jsonEncode({
          'estadoRevision': estadoRevision,
          'observacion': observacion.text.trim(),
        }),
      ).timeout(const Duration(seconds: 12));
      final cuerpo = jsonDecode(respuesta.body);
      if (respuesta.statusCode != 200 || cuerpo is! Map) {
        throw Exception(_mensajeApi(cuerpo, 'No se pudo revisar el cierre.'));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cuerpo['mensaje']?.toString() ?? 'Cierre revisado.'),
        ),
      );
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _abrirPdfCierre(Map<String, dynamic> turno) async {
    final turnoId = _entero(turno['id']);
    if (turnoId <= 0) return;

    try {
      final pdf = await ApiClient.descargarPdf(
        Uri.parse('${ApiConfig.baseUrl}/api/pro/turnos/$turnoId/pdf'),
      );
      await PdfService.imprimirOGuardar(
        pdf,
        nombreArchivo: 'cierre-caja-$turnoId.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _mostrarVehiculosAlCierre(Map<String, dynamic> turno) async {
    final turnoId = _entero(turno['id']);
    if (turnoId <= 0) return;

    try {
      final respuesta = await ApiClient.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/pro/turnos/$turnoId/vehiculos-abiertos',
        ),
      ).timeout(const Duration(seconds: 12));
      final cuerpo = jsonDecode(respuesta.body);
      if (respuesta.statusCode != 200 || cuerpo is! Map) {
        throw Exception(
          _mensajeApi(cuerpo, 'No se pudieron consultar los vehículos.'),
        );
      }
      if (!mounted) return;
      final vehiculos = (cuerpo['vehiculos'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Vehículos dentro al cierre'),
          content: SizedBox(
            width: double.maxFinite,
            child: vehiculos.isEmpty
                ? const Text(
                    'No se registraron vehículos dentro en este cierre.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: vehiculos.length,
                    separatorBuilder: (_, __) => const Divider(height: 14),
                    itemBuilder: (_, indice) {
                      final vehiculo = vehiculos[indice];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.directions_car_outlined),
                        title: Text(vehiculo['patente']?.toString() ?? '-'),
                        subtitle: Text(
                          '${vehiculo['tipo'] ?? 'Vehículo'} · ${vehiculo['color'] ?? '-'}\nEntrada: ${_fecha(vehiculo['horaEntrada'])}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _estadoTurno(bool abierto) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: abierto ? const Color(0xFFE6EEFF) : const Color(0xFFEAF8F0),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      abierto ? 'Abierto' : 'Cerrado',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: abierto ? const Color(0xFF2B6EEF) : const Color(0xFF0F7A4A),
      ),
    ),
  );

  Widget _vacio(String mensaje) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: _caja(),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, size: 36, color: Colors.blueGrey),
        const SizedBox(height: 10),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.blueGrey),
        ),
      ],
    ),
  );

  Widget _tarjetaError() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFECEC),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, color: Colors.red, size: 38),
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center),
        TextButton(onPressed: _cargar, child: const Text('Reintentar')),
      ],
    ),
  );
}

class _GraficoAuditoriaPainter extends CustomPainter {
  final List<Map<String, dynamic>> puntos;
  final double progreso;
  final double maximo;

  const _GraficoAuditoriaPainter({
    required this.puntos,
    required this.progreso,
    required this.maximo,
  });

  double _numero(dynamic valor) => valor is num
      ? valor.toDouble()
      : double.tryParse(valor?.toString() ?? '') ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    const arriba = 10.0;
    const abajo = 29.0;
    const lado = 5.0;
    final alto = size.height - arriba - abajo;
    final ancho = size.width - lado * 2;
    final visibles = puntos
        .where((punto) => punto['disponible'] == true)
        .toList();
    final cantidad = (visibles.length * progreso).ceil();
    final grilla = Paint()
      ..color = const Color(0xFFE8EDF6)
      ..strokeWidth = 1;
    for (var fila = 0; fila < 4; fila++) {
      final y = arriba + alto * fila / 3;
      canvas.drawLine(Offset(lado, y), Offset(size.width - lado, y), grilla);
    }

    if (visibles.isEmpty || cantidad == 0 || maximo <= 0) return;
    final mostrados = visibles.take(cantidad).toList();
    final separacion = ancho / math.max(1, visibles.length - 1);
    final linea = Path();
    final puntosLinea = <Offset>[];
    for (var indice = 0; indice < mostrados.length; indice++) {
      final valor = _numero(mostrados[indice]['recaudado']);
      final x = lado + indice * separacion;
      final y = arriba + alto - (valor / maximo) * alto;
      final punto = Offset(x, y);
      puntosLinea.add(punto);
      if (indice == 0) {
        linea.moveTo(x, y);
      } else {
        linea.lineTo(x, y);
      }
    }
    canvas.drawPath(
      linea,
      Paint()
        ..color = const Color(0xFF2B6EEF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final puntoPintura = Paint()..color = const Color(0xFF2B6EEF);
    for (final punto in puntosLinea) {
      canvas.drawCircle(punto, 3.2, puntoPintura);
    }
    final etiqueta = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
    final pasoEtiqueta = math.max(1, (visibles.length / 6).ceil());
    for (var indice = 0; indice < mostrados.length; indice += pasoEtiqueta) {
      etiqueta.text = TextSpan(
        text: mostrados[indice]['etiqueta']?.toString() ?? '',
        style: const TextStyle(fontSize: 10, color: Color(0xFF6A7890)),
      );
      etiqueta.layout(maxWidth: 45);
      etiqueta.paint(
        canvas,
        Offset(lado + indice * separacion - 6, size.height - 19),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraficoAuditoriaPainter anterior) =>
      anterior.progreso != progreso ||
      anterior.puntos != puntos ||
      anterior.maximo != maximo;
}
