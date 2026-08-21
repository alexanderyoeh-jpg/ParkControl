import 'dart:async';

import 'package:flutter/material.dart';

import '../offline/offline_app_service.dart';
import '../screens/sincronizacion_offline_screen.dart';

class IndicadorSincronizacionOffline extends StatefulWidget {
  const IndicadorSincronizacionOffline({super.key});

  @override
  State<IndicadorSincronizacionOffline> createState() =>
      _IndicadorSincronizacionOfflineState();
}

class _IndicadorSincronizacionOfflineState
    extends State<IndicadorSincronizacionOffline> {
  late final Stream<ResumenSincronizacionOffline> _resumenes;
  Timer? _temporizador;
  bool _sincronizando = false;
  int _comprobantesPendientes = 0;

  @override
  void initState() {
    super.initState();
    _resumenes = OfflineAppService.instancia.observarResumenSincronizacion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarComprobantesPendientes();
      _intentarSincronizar(silencioso: true);
    });
    _temporizador = Timer.periodic(const Duration(seconds: 45), (_) {
      _cargarComprobantesPendientes();
      _intentarSincronizar(silencioso: true);
    });
  }

  void _abrirDetalle() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SincronizacionOfflineScreen()),
    );
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> _intentarSincronizar({required bool silencioso}) async {
    if (!mounted || _sincronizando) {
      return;
    }

    setState(() {
      _sincronizando = true;
    });

    try {
      final completadas = await OfflineAppService.instancia
          .procesarPendientesDisponibles(forzarAhora: !silencioso);

      if (!mounted || silencioso) {
        return;
      }

      final mensaje = completadas > 0
          ? 'Se sincronizaron $completadas operación(es).'
          : 'No hay operaciones listas para enviar o aún no hay conexión.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
    } catch (_) {
      if (!mounted || silencioso) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar la sincronización.'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      await _cargarComprobantesPendientes();

      if (mounted) {
        setState(() {
          _sincronizando = false;
        });
      }
    }
  }

  Future<void> _cargarComprobantesPendientes() async {
    final total = await OfflineAppService.instancia
        .contarComprobantesSincronizadosPendientes();

    if (!mounted) {
      return;
    }

    setState(() {
      _comprobantesPendientes = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResumenSincronizacionOffline>(
      stream: _resumenes,
      builder: (context, snapshot) {
        final resumen =
            snapshot.data ?? const ResumenSincronizacionOffline.vacio();

        if (!resumen.hayOperaciones && _comprobantesPendientes == 0) {
          return const SizedBox.shrink();
        }

        final estilo = _estilo(resumen, _comprobantesPendientes);

        return Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: estilo.fondo,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: estilo.borde),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(estilo.icono, color: estilo.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          estilo.titulo,
                          style: TextStyle(
                            color: estilo.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          estilo.descripcion,
                          style: TextStyle(color: estilo.colorTexto),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sincronizar ahora',
                    onPressed: _sincronizando
                        ? null
                        : () => _intentarSincronizar(silencioso: false),
                    icon: _sincronizando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    color: estilo.color,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (resumen.pendientes > 0)
                    _etiqueta('${resumen.pendientes} pendiente(s)'),
                  if (resumen.enviando > 0)
                    _etiqueta('${resumen.enviando} enviando'),
                  if (resumen.conflictos > 0)
                    _etiqueta('${resumen.conflictos} conflicto(s)'),
                  if (resumen.bloqueadas > 0)
                    _etiqueta('${resumen.bloqueadas} bloqueada(s)'),
                  if (resumen.otras > 0)
                    _etiqueta('${resumen.otras} por revisar'),
                  if (_comprobantesPendientes > 0)
                    _etiqueta('$_comprobantesPendientes comprobante(s)'),
                ],
              ),
              if (resumen.ultimoMensaje != null) ...[
                const SizedBox(height: 10),
                Text(
                  resumen.ultimoMensaje!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: estilo.colorTexto, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _abrirDetalle,
                  icon: const Icon(Icons.manage_search_outlined),
                  label: const Text('Ver detalle'),
                  style: TextButton.styleFrom(foregroundColor: estilo.color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _etiqueta(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  _EstiloIndicador _estilo(
    ResumenSincronizacionOffline resumen,
    int comprobantesPendientes,
  ) {
    if (resumen.conflictos > 0) {
      return const _EstiloIndicador(
        icono: Icons.warning_amber_rounded,
        titulo: 'Sincronización requiere revisión',
        descripcion:
            'Hay operaciones guardadas en este dispositivo que el servidor no aceptó automáticamente.',
        color: Color(0xFF9A3412),
        colorTexto: Color(0xFF7C2D12),
        fondo: Color(0xFFFFF7ED),
        borde: Color(0xFFFED7AA),
      );
    }

    if (resumen.bloqueadas > 0) {
      return const _EstiloIndicador(
        icono: Icons.lock_clock_outlined,
        titulo: 'Sincronización bloqueada',
        descripcion:
            'ParkControl necesita una sesión válida o permisos activos para enviar estas operaciones.',
        color: Color(0xFF92400E),
        colorTexto: Color(0xFF78350F),
        fondo: Color(0xFFFFFBEB),
        borde: Color(0xFFFDE68A),
      );
    }

    if (resumen.enviando > 0 || _sincronizando) {
      return const _EstiloIndicador(
        icono: Icons.cloud_sync_outlined,
        titulo: 'Sincronizando operaciones',
        descripcion: 'Estamos enviando al servidor los movimientos pendientes.',
        color: Color(0xFF155E75),
        colorTexto: Color(0xFF164E63),
        fondo: Color(0xFFEFFBFF),
        borde: Color(0xFFA5F3FC),
      );
    }

    if (!resumen.hayOperaciones && comprobantesPendientes > 0) {
      return const _EstiloIndicador(
        icono: Icons.receipt_long,
        titulo: 'Comprobante offline listo',
        descripcion:
            'Una salida guardada sin conexión ya fue confirmada por el servidor.',
        color: Color(0xFF168A4C),
        colorTexto: Color(0xFF166534),
        fondo: Color(0xFFE8F7EF),
        borde: Color(0xFFBBF7D0),
      );
    }

    return const _EstiloIndicador(
      icono: Icons.cloud_queue_outlined,
      titulo: 'Operaciones pendientes',
      descripcion:
          'Estas acciones quedaron guardadas localmente y se enviarán cuando vuelva la conexión.',
      color: Color(0xFF1D4ED8),
      colorTexto: Color(0xFF1E3A8A),
      fondo: Color(0xFFEAF2FF),
      borde: Color(0xFFBFDBFE),
    );
  }
}

class _EstiloIndicador {
  const _EstiloIndicador({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.color,
    required this.colorTexto,
    required this.fondo,
    required this.borde,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color color;
  final Color colorTexto;
  final Color fondo;
  final Color borde;
}
