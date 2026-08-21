import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';

class SuscripcionMetodoPagoScreen extends StatefulWidget {
  const SuscripcionMetodoPagoScreen({super.key});

  @override
  State<SuscripcionMetodoPagoScreen> createState() =>
      _SuscripcionMetodoPagoScreenState();
}

class _SuscripcionMetodoPagoScreenState
    extends State<SuscripcionMetodoPagoScreen> {
  Map<String, dynamic>? _suscripcion;
  String? _error;
  bool _cargando = true;

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
        Uri.parse('${ApiConfig.baseUrl}/api/cuenta/suscripcion'),
      );
      final datos = jsonDecode(respuesta.body);

      if (respuesta.statusCode != 200 || datos is! Map) {
        throw Exception(
          datos is Map
              ? datos['mensaje']?.toString() ??
                    'No se pudo cargar la suscripción'
              : 'No se pudo cargar la suscripción',
        );
      }

      if (!mounted) return;
      setState(() {
        _suscripcion = Map<String, dynamic>.from(datos);
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

  String _fecha(dynamic valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '');
    if (fecha == null) return 'Sin fecha definida';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String _metodo(dynamic valor) {
    switch (valor?.toString().toLowerCase()) {
      case 'efectivo':
        return 'Efectivo';
      case 'transferencia':
        return 'Transferencia bancaria';
      case 'tarjeta':
        return 'Tarjeta';
      default:
        return 'Aún no configurado';
    }
  }

  String _estadoRenovacion(dynamic valor) {
    switch (valor?.toString().trim().toLowerCase()) {
      case 'activa':
      case 'authorized':
        return 'Renovación automática activa';
      case 'pausada':
      case 'cancelada':
      case 'cancelled':
        return 'Renovación automática pausada';
      case 'preparado':
        return 'Mercado Pago preparado';
      case 'no_configurado':
      default:
        return 'Mercado Pago aún no habilitado';
    }
  }

  void _mostrarConfiguracionPendiente() {
    final mensaje =
        _suscripcion?['mensajeConfiguracion']?.toString() ??
        'La pasarela todavía no está configurada.';

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pago automático pendiente'),
        content: Text(
          '$mensaje\n\nPor seguridad, ParkControl abrirá el formulario alojado de la pasarela. Nunca se escribirá ni almacenará aquí el número de tarjeta o CVV.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
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
        title: const Text('Suscripción y método de pago'),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            tooltip: 'Actualizar',
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
              'Suscripción ParkControl',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Administra el método con el que tu estacionamiento paga el servicio.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 22),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _errorCard()
            else ...[
              _estadoCard(),
              const SizedBox(height: 14),
              _metodoCard(),
              const SizedBox(height: 14),
              _manualCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _estadoCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Plan ${_suscripcion?['plan'] ?? '-'}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 9),
        Text(
          'Próximo vencimiento: ${_fecha(_suscripcion?['fechaVencimiento'])}',
        ),
        const SizedBox(height: 5),
        Text('Último pago: ${_fecha(_suscripcion?['fechaUltimoPago'])}'),
      ],
    ),
  );

  Widget _metodoCard() => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.credit_card_outlined, color: Color(0xFF2B6EEF)),
              SizedBox(width: 9),
              Text(
                'Renovación automática',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Proveedor: Mercado Pago',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            _estadoRenovacion(_suscripcion?['estadoPagoAutomatico']),
            style: const TextStyle(color: Colors.blueGrey),
          ),
          if (_suscripcion?['tarjeta'] is Map) ...[
            const SizedBox(height: 8),
            Text(
              '${(_suscripcion?['tarjeta'] as Map)['marca'] ?? 'Tarjeta'} terminada en ${(_suscripcion?['tarjeta'] as Map)['ultimos4'] ?? '••••'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Si se activa, la tarjeta se registrará únicamente en el sitio seguro de Mercado Pago. ParkControl nunca verá ni almacenará su número o CVV.',
          ),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: _mostrarConfiguracionPendiente,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Configurar con Mercado Pago'),
          ),
          const SizedBox(height: 8),
          const Text(
            'El checkout se habilitará después de la prueba controlada de la pasarela.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    ),
  );

  Widget _manualCard() => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_outlined, color: Color(0xFF168A4C)),
              SizedBox(width: 9),
              Text(
                'Pago manual',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'También puedes pagar por transferencia bancaria o efectivo. El pago se activará cuando ParkControl confirme el abono.',
          ),
          const SizedBox(height: 7),
          Text(
            'Último pago registrado: ${_metodo(_suscripcion?['metodoUltimoPago'])}',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    ),
  );

  Widget _errorCard() => Container(
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
