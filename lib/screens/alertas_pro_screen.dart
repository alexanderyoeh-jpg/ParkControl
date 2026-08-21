import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';
import 'auditoria_cajeros_pro_screen.dart';

/// Centro de alertas operativas para administradores con plan Pro.
///
/// La información se consulta siempre al backend; esta pantalla no persiste
/// alertas ni datos de caja en el dispositivo.
class AlertasProScreen extends StatefulWidget {
  const AlertasProScreen({super.key});

  @override
  State<AlertasProScreen> createState() => _AlertasProScreenState();
}

class _AlertasProScreenState extends State<AlertasProScreen> {
  List<Map<String, dynamic>> _alertas = [];
  Map<String, dynamic> _resumen = {};
  String? _actualizadoEn;
  bool _cargando = true;
  String? _error;

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
        Uri.parse('${ApiConfig.baseUrl}/api/pro/alertas'),
      ).timeout(const Duration(seconds: 12));
      final datos = jsonDecode(respuesta.body);

      if (respuesta.statusCode != 200 || datos is! Map) {
        throw Exception(
          ApiClient.extraerMensajeError(
            respuesta,
            mensajePredeterminado: 'No se pudieron cargar las alertas.',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _alertas = (datos['alertas'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _resumen = datos['resumen'] is Map
            ? Map<String, dynamic>.from(datos['resumen'] as Map)
            : <String, dynamic>{};
        _actualizadoEn = datos['actualizadoEn']?.toString();
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



  int _entero(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _pesos(dynamic valor) {
    final numero = _numero(valor).round();
    final negativo = numero < 0;
    final texto = numero.abs().toString();
    final salida = StringBuffer(negativo ? '-\$' : '\$');
    for (var indice = 0; indice < texto.length; indice++) {
      if (indice > 0 && (texto.length - indice) % 3 == 0) salida.write('.');
      salida.write(texto[indice]);
    }
    return salida.toString();
  }

  String _fecha(dynamic valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '')?.toLocal();
    if (fecha == null) return '-';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} · ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _abrirAuditoria() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuditoriaCajerosProScreen()),
    );
    if (mounted) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text('Alertas administrativas Pro'),
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
              'Alertas operativas',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Revisa diferencias de caja que requieren atención.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            if (_actualizadoEn != null) ...[
              const SizedBox(height: 5),
              Text(
                'Actualizado: ${_fecha(_actualizadoEn)}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
            const SizedBox(height: 18),
            if (_error != null)
              _tarjetaError()
            else if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 72),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _resumenAlertas(),
              const SizedBox(height: 22),
              Text(
                'Alertas recientes',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF172B4D),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (_alertas.isEmpty)
                _sinAlertas()
              else
                ..._alertas.map(_tarjetaAlerta),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resumenAlertas() {
    final pendientes = _entero(_resumen['pendientes']);
    final criticas = _entero(_resumen['criticas']);

    return Row(
      children: [
        Expanded(
          child: _tarjetaResumen(
            etiqueta: 'Pendientes',
            valor: pendientes,
            icono: Icons.pending_actions_outlined,
            color: const Color(0xFFB76B00),
            fondo: const Color(0xFFFFF4DB),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tarjetaResumen(
            etiqueta: 'Críticas',
            valor: criticas,
            icono: Icons.warning_amber_rounded,
            color: const Color(0xFFB3261E),
            fondo: const Color(0xFFFFE9E7),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaResumen({
    required String etiqueta,
    required int valor,
    required IconData icono,
    required Color color,
    required Color fondo,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color),
          const SizedBox(height: 10),
          Text(
            valor.toString(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(etiqueta, style: const TextStyle(color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _tarjetaAlerta(Map<String, dynamic> alerta) {
    final estado = alerta['estado']?.toString() ?? 'pendiente';
    final revisada = estado == 'revisada';
    final resuelta = estado == 'resuelta';
    final severidad = alerta['severidad']?.toString() ?? '';
    final alta = severidad == 'alta' || severidad == 'critica';
    final color = resuelta
        ? const Color(0xFF0F7A4A)
        : revisada
        ? const Color(0xFF215A9D)
        : alta
        ? const Color(0xFFB3261E)
        : const Color(0xFFB76B00);
    final detalle = alerta['detalle']?.toString().trim();
    final titulo = alerta['titulo']?.toString().trim();
    final observacionRevision = alerta['observacionRevision']
        ?.toString()
        .trim();
    final diferencia = _numero(alerta['montoDiferencia']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alta ? const Color(0xFFF5C6C2) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resuelta
                    ? Icons.task_alt_outlined
                    : revisada
                    ? Icons.rate_review_outlined
                    : alta
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo == null || titulo.isEmpty
                      ? 'Alerta administrativa'
                      : titulo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172B4D),
                  ),
                ),
              ),
              _estadoAlerta(estado, color),
            ],
          ),
          if (detalle != null && detalle.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(detalle, style: const TextStyle(color: Colors.blueGrey)),
          ],
          const SizedBox(height: 10),
          Text(
            'Registrada: ${_fecha(alerta['ocurridaEn'])}',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          if (revisada || resuelta) ...[
            const SizedBox(height: 3),
            Text(
              '${revisada ? 'Revisada' : 'Resuelta'}: ${_fecha(revisada ? alerta['revisadaEn'] : alerta['resueltaEn'])}',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ],
          if (observacionRevision != null &&
              observacionRevision.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Observación: $observacionRevision',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ],
          if (diferencia.abs() > 0.009) ...[
            const SizedBox(height: 8),
            Text(
              'Diferencia de caja: ${_pesos(diferencia)}',
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _abrirAuditoria,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Abrir auditoría de cajeros'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoAlerta(String estado, Color color) {
    final etiqueta = switch (estado) {
      'revisada' => 'Revisada',
      'resuelta' => 'Resuelta',
      _ => 'Pendiente',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        etiqueta,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _sinAlertas() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: const Column(
      children: [
        Icon(Icons.task_alt_outlined, size: 42, color: Color(0xFF0F7A4A)),
        SizedBox(height: 10),
        Text(
          'No hay alertas administrativas pendientes.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 4),
        Text(
          'Los cierres de caja y su revisión están al día.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.blueGrey),
        ),
      ],
    ),
  );

  Widget _tarjetaError() => Container(
    padding: const EdgeInsets.all(18),
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
