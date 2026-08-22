import 'package:flutter/material.dart';

import '../offline/offline_app_service.dart';

class SincronizacionOfflineScreen extends StatefulWidget {
  const SincronizacionOfflineScreen({super.key});

  @override
  State<SincronizacionOfflineScreen> createState() =>
      _SincronizacionOfflineScreenState();
}

class _SincronizacionOfflineScreenState
    extends State<SincronizacionOfflineScreen> {
  late final Stream<List<OperacionSincronizacionOffline>> _operaciones;
  List<ComprobanteOfflineSincronizado> _comprobantes = const [];
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _operaciones = OfflineAppService.instancia
        .observarOperacionesSincronizacion();
    _cargarComprobantes();
  }

  Future<void> _cargarComprobantes() async {
    final comprobantes = await OfflineAppService.instancia
        .comprobantesSincronizadosPendientes();

    if (!mounted) {
      return;
    }

    setState(() {
      _comprobantes = comprobantes;
    });
  }

  Future<void> _sincronizarAhora() async {
    if (_procesando) {
      return;
    }

    setState(() {
      _procesando = true;
    });

    try {
      final completadas = await OfflineAppService.instancia
          .procesarPendientesDisponibles(forzarAhora: true);

      if (!mounted) {
        return;
      }

      await _cargarComprobantes();
      if (!mounted) return;

      final mensaje = completadas > 0
          ? 'Se sincronizaron $completadas operación(es).'
          : 'No hay operaciones listas para enviar o aún no hay conexión.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar la sincronización.'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  Future<void> _reanudarBloqueadas() async {
    if (_procesando) {
      return;
    }

    setState(() {
      _procesando = true;
    });

    try {
      final reanudadas = await OfflineAppService.instancia
          .reanudarBloqueadasActuales();
      final completadas = await OfflineAppService.instancia
          .procesarPendientesDisponibles(forzarAhora: true);

      if (!mounted) {
        return;
      }

      await _cargarComprobantes();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reanudadas: $reanudadas · Sincronizadas: $completadas',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron reanudar las operaciones bloqueadas.'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  Future<void> _marcarComprobanteVisto(
    ComprobanteOfflineSincronizado comprobante,
  ) async {
    await OfflineAppService.instancia.marcarComprobanteSincronizadoVisto(
      comprobante.claveOperacion,
    );
    await _cargarComprobantes();
  }

  Future<void> _mostrarComprobante(
    ComprobanteOfflineSincronizado comprobante,
  ) async {
    final salida = comprobante.salida;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.receipt_long, color: Color(0xFF168A4C)),
              SizedBox(width: 10),
              Text('Comprobante sincronizado'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_done_outlined,
                  color: Color(0xFF168A4C),
                  size: 54,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Salida confirmada por el servidor',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                _filaComprobante('Folio', _crearFolio(salida['id'])),
                _filaComprobante('Patente', comprobante.patente),
                _filaComprobante('Tipo', salida['tipo']?.toString() ?? '-'),
                _filaComprobante('Color', salida['color']?.toString() ?? '-'),
                _filaComprobante(
                  'Entrada',
                  _fechaHoraVisible(salida['horaEntrada']),
                ),
                _filaComprobante(
                  'Salida',
                  _fechaHoraVisible(salida['horaSalida']),
                ),
                _filaComprobante(
                  'Minutos',
                  '${_numero(salida['minutos']).round()}',
                ),
                _filaComprobante(
                  'Tarifa',
                  _pesos(_numero(salida['tarifaPorMinuto'])),
                ),
                const Divider(height: 24),
                const Text(
                  'TOTAL PAGADO',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _pesos(comprobante.monto),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF172B4D),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'El comprobante PDF queda disponible en Comprobantes e historial.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _marcarComprobanteVisto(comprobante);
              },
              icon: const Icon(Icons.check),
              label: const Text('Marcar visto'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _descartarConflicto(
    OperacionSincronizacionOffline operacion,
  ) async {
    final motivo = await _solicitarMotivoDescarte(operacion);
    if (motivo == null || motivo.trim().isEmpty || _procesando) {
      return;
    }

    setState(() {
      _procesando = true;
    });

    try {
      await OfflineAppService.instancia.descartarConflictoAuditado(
        operacion: operacion,
        motivo: motivo,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conflicto auditado y retirado de la cola local.'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeError(error)),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  Future<String?> _solicitarMotivoDescarte(
    OperacionSincronizacionOffline operacion,
  ) async {
    final controlador = TextEditingController();

    final resultado = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Descartar operación local'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Esta acción no modifica movimientos del servidor. Sólo retira "${operacion.titulo}" de este dispositivo y deja auditoría.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controlador,
                autofocus: true,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Ej: se recalculará con la tarifa vigente',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final motivo = controlador.text.trim();
                if (motivo.length < 5) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'El motivo debe tener al menos 5 caracteres.',
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogContext, motivo);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9A3412),
                foregroundColor: Colors.white,
              ),
              child: const Text('Descartar'),
            ),
          ],
        );
      },
    );

    controlador.dispose();
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Sincronización offline'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar ahora',
            onPressed: _procesando ? null : _sincronizarAhora,
            icon: _procesando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: StreamBuilder<List<OperacionSincronizacionOffline>>(
        stream: _operaciones,
        builder: (context, snapshot) {
          final operaciones = snapshot.data ?? const [];

          if (snapshot.connectionState == ConnectionState.waiting &&
              operaciones.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (operaciones.isEmpty && _comprobantes.isEmpty) {
            return _estadoVacio();
          }

          final bloqueadas = operaciones
              .where((operacion) => operacion.estado == 'bloqueada')
              .length;

          return RefreshIndicator(
            onRefresh: _sincronizarAhora,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                if (_comprobantes.isNotEmpty) ...[
                  _comprobantesSincronizados(),
                  const SizedBox(height: 14),
                ],
                if (operaciones.isNotEmpty) _resumen(operaciones),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1565FF),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _procesando ? null : _reintentarConflictos,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reintentar Todo', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB3261E),
                          side: const BorderSide(color: Color(0xFFB3261E)),
                        ),
                        onPressed: _procesando ? null : _limpiarConflictos,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Limpiar Conflictos', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
                if (bloqueadas > 0) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _procesando ? null : _reanudarBloqueadas,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Reintentar bloqueadas'),
                  ),
                ],
                if (operaciones.isNotEmpty) const SizedBox(height: 14),
                ...operaciones.map(_tarjetaOperacion),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _reintentarConflictos() async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      final completadas = await OfflineAppService.instancia.reintentarConflictos();
      await _cargarComprobantes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Operaciones sincronizadas: $completadas')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al reintentar operaciones')),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _limpiarConflictos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar conflictos locales'),
        content: const Text('¿Deseas descartar los conflictos locales pendientes y desbloquear el cierre de caja de inmediato?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpiar y Desbloquear'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando = true);
    try {
      final limpiadas = await OfflineAppService.instancia.limpiarConflictosLocales();
      await _cargarComprobantes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se limpiaron $limpiadas conflicto(s) local(es). Cierre de caja habilitado.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al limpiar conflictos')),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Widget _comprobantesSincronizados() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long, color: Color(0xFF168A4C)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Comprobantes offline confirmados',
                  style: TextStyle(
                    color: Color(0xFF166534),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Estas salidas fueron registradas sin internet y ya quedaron confirmadas por el servidor.',
            style: TextStyle(color: Color(0xFF166534)),
          ),
          const SizedBox(height: 12),
          ..._comprobantes.map(_tarjetaComprobante),
        ],
      ),
    );
  }

  Widget _tarjetaComprobante(ComprobanteOfflineSincronizado comprobante) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE8F7EF),
            child: Icon(Icons.check_circle, color: Color(0xFF168A4C)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_crearFolio(comprobante.folio)} · ${comprobante.patente}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_pesos(comprobante.monto)} · ${_hora(comprobante.sincronizadoEn)}',
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _mostrarComprobante(comprobante),
            child: const Text('Ver'),
          ),
        ],
      ),
    );
  }

  Widget _estadoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F7EF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.cloud_done_outlined,
                color: Color(0xFF168A4C),
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Todo sincronizado',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No hay operaciones pendientes en este dispositivo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumen(List<OperacionSincronizacionOffline> operaciones) {
    final pendientes = operaciones
        .where((operacion) => operacion.estado == 'pendiente')
        .length;
    final enviando = operaciones
        .where((operacion) => operacion.estado == 'enviando')
        .length;
    final conflictos = operaciones
        .where((operacion) => operacion.estado == 'conflicto')
        .length;
    final bloqueadas = operaciones
        .where((operacion) => operacion.estado == 'bloqueada')
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operaciones guardadas localmente',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF172B4D),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ParkControl enviará estas acciones al servidor respetando el orden en que fueron hechas.',
            style: TextStyle(color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (pendientes > 0) _chip('$pendientes pendiente(s)'),
              if (enviando > 0) _chip('$enviando enviando'),
              if (conflictos > 0) _chip('$conflictos conflicto(s)'),
              if (bloqueadas > 0) _chip('$bloqueadas bloqueada(s)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaOperacion(OperacionSincronizacionOffline operacion) {
    final estilo = _estilo(operacion.estado);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: estilo.borde),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: estilo.fondo,
                  child: Icon(estilo.icono, color: estilo.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        operacion.titulo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172B4D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${operacion.estado} · ${operacion.intentos} intento(s)',
                        style: TextStyle(color: estilo.color),
                      ),
                    ],
                  ),
                ),
                Text(
                  _hora(operacion.actualizadaEn),
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ],
            ),
            if (operacion.ultimoError != null &&
                operacion.ultimoError!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: estilo.fondo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  operacion.ultimoError!,
                  style: TextStyle(color: estilo.color),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '${operacion.metodo} ${operacion.ruta}',
              style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
            ),
            if (operacion.estado == 'conflicto') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _procesando
                      ? null
                      : () => _descartarConflicto(operacion),
                  icon: const Icon(Icons.playlist_remove_outlined),
                  label: const Text('Descartar operación local'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9A3412),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _filaComprobante(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _crearFolio(Object? valor) {
    final id = _numero(valor).round();
    if (id < 1) {
      return 'Pendiente';
    }
    return 'PC-${id.toString().padLeft(6, '0')}';
  }

  String _fechaHoraVisible(Object? valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '');
    if (fecha == null) {
      return '-';
    }

    final local = fecha.toLocal();
    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final anio = local.year.toString();
    return '$dia/$mes/$anio ${_hora(local)}';
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

    return '\$${resultado.toString()}';
  }

  double _numero(Object? valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _hora(DateTime fecha) {
    final local = fecha.toLocal();
    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');
    return '$hora:$minuto';
  }

  _EstiloOperacion _estilo(String estado) {
    switch (estado) {
      case 'conflicto':
        return const _EstiloOperacion(
          icono: Icons.warning_amber_rounded,
          color: Color(0xFF9A3412),
          fondo: Color(0xFFFFF7ED),
          borde: Color(0xFFFED7AA),
        );
      case 'bloqueada':
        return const _EstiloOperacion(
          icono: Icons.lock_clock_outlined,
          color: Color(0xFF92400E),
          fondo: Color(0xFFFFFBEB),
          borde: Color(0xFFFDE68A),
        );
      case 'enviando':
        return const _EstiloOperacion(
          icono: Icons.cloud_sync_outlined,
          color: Color(0xFF155E75),
          fondo: Color(0xFFEFFBFF),
          borde: Color(0xFFA5F3FC),
        );
      default:
        return const _EstiloOperacion(
          icono: Icons.cloud_queue_outlined,
          color: Color(0xFF1D4ED8),
          fondo: Color(0xFFEAF2FF),
          borde: Color(0xFFBFDBFE),
        );
    }
  }

  String _mensajeError(Object error) {
    final texto = error.toString();
    final prefijo = RegExp(r'^ErrorOperacionOffline:\s*');
    return texto.replaceFirst(prefijo, '').trim();
  }
}

class _EstiloOperacion {
  const _EstiloOperacion({
    required this.icono,
    required this.color,
    required this.fondo,
    required this.borde,
  });

  final IconData icono;
  final Color color;
  final Color fondo;
  final Color borde;
}
