import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../offline/offline_app_service.dart';
import '../services/api_client.dart';
import 'sincronizacion_offline_screen.dart';

/// Cierre de caja Pro.
///
/// Los montos visibles provienen del servidor. La pantalla nunca calcula ni
/// confirma cobros localmente: sólo presenta el esperado que devuelve la API y
/// registra el efectivo declarado por el cajero.
class TurnoCajaScreen extends StatefulWidget {
  const TurnoCajaScreen({super.key});

  @override
  State<TurnoCajaScreen> createState() => _TurnoCajaScreenState();
}

class _TurnoCajaScreenState extends State<TurnoCajaScreen> {
  Map<String, dynamic>? _turno;
  Map<String, dynamic>? _entregaAnterior;
  bool _cargando = true;
  bool _enviando = false;
  bool _verificandoCierreOffline = false;
  String? _error;
  late final Stream<ResumenSincronizacionOffline> _resumenesOffline;

  @override
  void initState() {
    super.initState();
    _resumenesOffline = OfflineAppService.instancia
        .observarResumenSincronizacion();
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
        Uri.parse('${ApiConfig.baseUrl}/api/turnos/actual'),
      ).timeout(const Duration(seconds: 12));
      final cuerpo = jsonDecode(respuesta.body);

      if (respuesta.statusCode != 200 || cuerpo is! Map) {
        throw Exception(_mensajeApi(cuerpo, 'No se pudo consultar la caja.'));
      }

      if (!mounted) return;
      setState(() {
        _turno = cuerpo['turno'] is Map
            ? Map<String, dynamic>.from(cuerpo['turno'] as Map)
            : null;
        _entregaAnterior = cuerpo['entregaAnterior'] is Map
            ? Map<String, dynamic>.from(cuerpo['entregaAnterior'] as Map)
            : null;
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

  String _mensajeApi(dynamic cuerpo, String porDefecto) {
    if (cuerpo is Map) {
      final mensaje = cuerpo['mensaje']?.toString().trim();
      if (mensaje != null && mensaje.isNotEmpty) return mensaje;
    }
    return porDefecto;
  }

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double? _montoDesdeTexto(String valor) {
    final normalizado = valor.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalizado);
  }

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
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year} · $hora:$minuto';
  }

  Future<void> _mostrarInicio() async {
    final monto = TextEditingController(text: '0');
    final novedad = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Iniciar turno de caja'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Registra el fondo físico recibido antes de comenzar a cobrar.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: monto,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Fondo inicial',
                  prefixText: '\$ ',
                  hintText: 'Ej.: 10.000',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: novedad,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Novedad de apertura (opcional)',
                  hintText: 'Ej.: fondo recibido completo',
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Iniciar turno'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    final montoInicial = _montoDesdeTexto(monto.text);
    if (montoInicial == null || montoInicial < 0) {
      _notificar('Ingresa un fondo inicial válido.', esError: true);
      return;
    }

    await _iniciarTurno(montoInicial, novedad.text);
  }

  Future<void> _iniciarTurno(double montoInicial, String novedad) async {
    setState(() => _enviando = true);
    try {
      final respuesta = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/turnos/iniciar'),
        body: jsonEncode({
          'montoInicial': montoInicial,
          'novedad': novedad.trim(),
        }),
      ).timeout(const Duration(seconds: 12));
      final cuerpo = jsonDecode(respuesta.body);

      if (respuesta.statusCode != 201 || cuerpo is! Map) {
        throw Exception(_mensajeApi(cuerpo, 'No se pudo iniciar el turno.'));
      }

      if (!mounted) return;
      _notificar('Turno de caja iniciado.');
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      _notificar(
        error.toString().replaceFirst('Exception: ', ''),
        esError: true,
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _mostrarCierre() async {
    if (_verificandoCierreOffline || _enviando) return;

    setState(() => _verificandoCierreOffline = true);

    try {
      final puedeCerrar = await _validarColaAntesDeCerrar();
      if (!puedeCerrar || !mounted) return;

      final turno = _turno;
      if (turno == null) return;

      final declarado = TextEditingController(
        text: _numero(turno['montoEsperado']).round().toString(),
      );
      final novedad = TextEditingController();
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cerrar turno de caja'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _resumenDialogo('Fondo inicial', _pesos(turno['montoInicial'])),
                _resumenDialogo(
                  'Cobrado total en el turno',
                  _pesos(turno['montoRecaudado']),
                ),
                _resumenDialogo(
                  'Cobrado en efectivo',
                  _pesos(turno['montoEfectivo']),
                ),
                _resumenDialogo(
                  'Transferencias',
                  _pesos(turno['montoTransferencia']),
                ),
                _resumenDialogo('Tarjetas', _pesos(turno['montoTarjeta'])),
                _resumenDialogo('Otros medios', _pesos(turno['montoOtros'])),
                const Divider(height: 24),
                _resumenDialogo(
                  'Efectivo esperado',
                  _pesos(turno['montoEsperado']),
                  destacado: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: declarado,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Efectivo contado y declarado',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: novedad,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Novedad para el siguiente cajero',
                    hintText: 'Obligatorio si existe una diferencia',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'El cierre no se podrá modificar. El administrador verá el monto esperado, declarado y la diferencia.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Volver'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Confirmar cierre'),
            ),
          ],
        ),
      );

      if (confirmar != true || !mounted) return;
      final montoDeclarado = _montoDesdeTexto(declarado.text);
      if (montoDeclarado == null || montoDeclarado < 0) {
        _notificar('Ingresa un efectivo declarado válido.', esError: true);
        return;
      }

      final diferencia = montoDeclarado - _numero(turno['montoEsperado']);
      if (diferencia != 0 && novedad.text.trim().isEmpty) {
        _notificar(
          'Describe la novedad antes de cerrar una caja con diferencia.',
          esError: true,
        );
        return;
      }

      // Se vuelve a consultar la cola porque el cajero pudo pasar varios
      // minutos contando efectivo con el diálogo abierto.
      final puedeCerrarAhora = await _validarColaAntesDeCerrar();
      if (!puedeCerrarAhora || !mounted) return;

      await _cerrarTurno(_entero(turno['id']), montoDeclarado, novedad.text);
    } finally {
      if (mounted) setState(() => _verificandoCierreOffline = false);
    }
  }

  Future<bool> _validarColaAntesDeCerrar() async {
    final resumen = await OfflineAppService.instancia.resumenSincronizacion();
    if (!resumen.impideCierreCaja) return true;
    if (!mounted) return false;

    final resultado = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.sync_problem_outlined),
        title: const Text('Cierre pendiente de sincronización'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No puedes cerrar la caja mientras existan ${resumen.totalQueImpidenCierreCaja} operación(es) offline sin confirmar de esta sesión.',
              ),
              const SizedBox(height: 12),
              _detalleEstadoOffline('Pendientes', resumen.pendientes),
              _detalleEstadoOffline('Enviando', resumen.enviando),
              _detalleEstadoOffline('Bloqueadas', resumen.bloqueadas),
              _detalleEstadoOffline('Con conflicto', resumen.conflictos),
              if (resumen.otras > 0)
                _detalleEstadoOffline('En revisión', resumen.otras),
              const SizedBox(height: 12),
              const Text(
                'Sincroniza o resuelve estas operaciones antes del arqueo para que ningún cobro quede fuera del turno.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'volver'),
            child: const Text('Volver'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.pop(dialogContext, 'limpiar_y_cerrar'),
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: const Text('Limpiar y Continuar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'sincronizar'),
            icon: const Icon(Icons.sync),
            label: const Text('Ir a sincronización'),
          ),
        ],
      ),
    );

    if (resultado == 'limpiar_y_cerrar') {
      await OfflineAppService.instancia.limpiarConflictosLocales();
      _notificar('Conflictos locales limpiados. Procediendo al cierre.');
      return true;
    }

    if (resultado == 'sincronizar' && mounted) {
      await _abrirSincronizacion();
    }

    return false;
  }

  Widget _detalleEstadoOffline(String etiqueta, int cantidad) {
    if (cantidad <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('• $etiqueta: $cantidad'),
    );
  }

  Future<void> _abrirSincronizacion() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SincronizacionOfflineScreen()),
    );

    if (mounted) await _cargar();
  }

  int _entero(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Future<void> _cerrarTurno(
    int turnoId,
    double montoDeclarado,
    String novedad,
  ) async {
    if (turnoId <= 0) return;
    setState(() => _enviando = true);

    try {
      final respuesta = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/turnos/$turnoId/cerrar'),
        body: jsonEncode({
          'montoDeclarado': montoDeclarado,
          'novedad': novedad.trim(),
        }),
      ).timeout(const Duration(seconds: 12));
      final cuerpo = jsonDecode(respuesta.body);
      if (respuesta.statusCode != 200 || cuerpo is! Map) {
        throw Exception(_mensajeApi(cuerpo, 'No se pudo cerrar el turno.'));
      }

      if (!mounted) return;
      final turnoCerrado = cuerpo['turno'] is Map
          ? Map<String, dynamic>.from(cuerpo['turno'] as Map)
          : <String, dynamic>{};
      _notificar(
        'Cierre registrado · Diferencia: ${_pesos(turnoCerrado['diferencia'])}',
      );
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      _notificar(
        error.toString().replaceFirst('Exception: ', ''),
        esError: true,
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _notificar(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: esError
              ? Colors.red.shade700
              : const Color(0xFF0F6B48),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Turno y cierre de caja'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando || _enviando || _verificandoCierreOffline
                ? null
                : _cargar,
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
              'Entrega de caja',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Cada cierre queda auditado con sus cobros, efectivo y novedades.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 18),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _tarjetaError()
            else ...[
              if (_entregaAnterior != null) ...[
                _tarjetaEntregaAnterior(_entregaAnterior!),
                const SizedBox(height: 14),
              ],
              if (_turno == null)
                _estadoSinTurno()
              else
                _estadoTurnoAbierto(_turno!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _estadoSinTurno() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.point_of_sale_outlined,
            size: 38,
            color: Color(0xFF2B6EEF),
          ),
          const SizedBox(height: 14),
          const Text(
            'No tienes un turno abierto',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          const Text(
            'Inicia la caja cuando recibas el fondo. Sólo puede existir un turno abierto en este estacionamiento.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _enviando ? null : _mostrarInicio,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar turno de caja'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoTurnoAbierto(Map<String, dynamic> turno) {
    final montoEsperado = _numero(turno['montoEsperado']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F2B52), Color(0xFF1D4E87)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(21),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_open_outlined, color: Color(0xFFAED3FF)),
                  SizedBox(width: 8),
                  Text(
                    'Turno abierto',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Efectivo esperado',
                style: TextStyle(color: Color(0xFFBED7F4)),
              ),
              const SizedBox(height: 4),
              Text(
                _pesos(montoEsperado),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_entero(turno['salidas'])} salidas · ${_pesos(turno['montoRecaudado'])} cobrado total',
                style: const TextStyle(color: Color(0xFFBED7F4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _detalleTurno('Inicio del turno', _fecha(turno['abiertoEn'])),
        _detalleTurno('Fondo inicial', _pesos(turno['montoInicial'])),
        _detalleTurno('Cobrado en efectivo', _pesos(turno['montoEfectivo'])),
        _detalleTurno('Transferencias', _pesos(turno['montoTransferencia'])),
        _detalleTurno('Tarjetas', _pesos(turno['montoTarjeta'])),
        if ((turno['novedadApertura']?.toString().trim().isNotEmpty ?? false))
          _detalleTurno(
            'Novedad de apertura',
            turno['novedadApertura'].toString(),
          ),
        const SizedBox(height: 4),
        StreamBuilder<ResumenSincronizacionOffline>(
          stream: _resumenesOffline,
          builder: (context, snapshot) {
            final resumen = snapshot.data;
            if (resumen == null || !resumen.impideCierreCaja) {
              return const SizedBox.shrink();
            }

            return _advertenciaColaOffline(resumen);
          },
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F6B48),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: _enviando || _verificandoCierreOffline
                ? null
                : _mostrarCierre,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Contar y cerrar caja'),
          ),
        ),
      ],
    );
  }

  Widget _advertenciaColaOffline(ResumenSincronizacionOffline resumen) {
    final total = resumen.totalQueImpidenCierreCaja;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0D28A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sync_problem_outlined, color: Color(0xFF9A6700)),
              SizedBox(width: 8),
              Text(
                'Cierre bloqueado temporalmente',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$total operación(es) offline de esta sesión aún no están confirmadas.',
            style: const TextStyle(color: Color(0xFF6A4A00)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sincronízalas o resuelve sus conflictos antes de cerrar la caja.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _enviando || _verificandoCierreOffline
                  ? null
                  : _abrirSincronizacion,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Abrir sincronización'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaEntregaAnterior(Map<String, dynamic> entrega) {
    final diferencia = _numero(entrega['diferencia']);
    final hayDiferencia = diferencia != 0;
    final novedad = entrega['novedadCierre']?.toString().trim();
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: hayDiferencia
            ? const Color(0xFFFFF5E5)
            : const Color(0xFFEAF8F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hayDiferencia
              ? const Color(0xFFF1CF86)
              : const Color(0xFFB9E3CA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hayDiferencia
                    ? Icons.warning_amber_outlined
                    : Icons.handshake_outlined,
                color: hayDiferencia
                    ? const Color(0xFFA46700)
                    : const Color(0xFF0F7A4A),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Última entrega de caja',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Cajero: ${entrega['cajeroNombre'] ?? 'No informado'}'),
          Text('Cerró: ${_fecha(entrega['cerradoEn'])}'),
          const SizedBox(height: 6),
          Text(
            'Efectivo esperado ${_pesos(entrega['montoEsperado'])} · Declarado ${_pesos(entrega['montoDeclarado'])}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            'Transferencias ${_pesos(entrega['montoTransferencia'])} · Tarjetas ${_pesos(entrega['montoTarjeta'])}',
            style: const TextStyle(color: Colors.blueGrey),
          ),
          if (_entero(entrega['vehiculosDentroAlCierre']) > 0) ...[
            const SizedBox(height: 5),
            Text(
              '${_entero(entrega['vehiculosDentroAlCierre'])} vehículo(s) permanecían dentro al cierre.',
              style: const TextStyle(color: Colors.blueGrey),
            ),
          ],
          if (hayDiferencia) ...[
            const SizedBox(height: 5),
            Text(
              'Diferencia: ${_pesos(diferencia)}',
              style: const TextStyle(
                color: Color(0xFFA46700),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (novedad != null && novedad.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text('Novedad: $novedad'),
          ],
        ],
      ),
    );
  }

  Widget _detalleTurno(String etiqueta, String valor) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE0E8F5)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(etiqueta, style: const TextStyle(color: Colors.blueGrey)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _resumenDialogo(
    String etiqueta,
    String valor, {
    bool destacado = false,
  }) => Row(
    children: [
      Expanded(child: Text(etiqueta)),
      Text(
        valor,
        style: TextStyle(
          fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    ],
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
        const SizedBox(height: 8),
        TextButton(onPressed: _cargar, child: const Text('Reintentar')),
      ],
    ),
  );
}
