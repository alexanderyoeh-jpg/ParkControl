import 'package:flutter/material.dart';

import '../models/cliente_parkcontrol.dart';
import '../services/api_client.dart';
import '../services/superadmin_service.dart';
import 'admin_dashboard.dart';
import 'cliente_form_screen.dart';

class ClienteDetalleScreen extends StatefulWidget {
  const ClienteDetalleScreen({super.key, required this.clienteId});

  final int clienteId;

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  final _servicio = const SuperAdminService();

  ClienteParkControl? _cliente;
  bool _cargando = true;
  bool _procesando = false;
  bool _huboCambios = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _entrarModoSoporte() async {
    final cliente = _cliente;
    if (cliente == null || _procesando) return;

    final motivoController = TextEditingController();

    final motivo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF0F2B52)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ingresar como Auditor / Soporte',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresarás al panel operativo de "${cliente.nombre}" con permisos delegados para auditar o prestar asistencia.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta acción queda registrada con fecha, hora y motivo en la auditoría global.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motivo de soporte / auditoría *',
                hintText: 'Ej.: Asistencia técnica por turno descuadrado o auditoría general.',
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
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F2B52),
            ),
            onPressed: () {
              final texto = motivoController.text.trim();
              if (texto.length < 5) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Indica un motivo de al menos 5 caracteres.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, texto);
            },
            icon: const Icon(Icons.login),
            label: const Text('Ingresar al estacionamiento'),
          ),
        ],
      ),
    );

    motivoController.dispose();
    if (motivo == null || !mounted) return;

    setState(() => _procesando = true);

    try {
      await _servicio.entrarModoSoporte(
        clienteId: cliente.id,
        motivo: motivo,
      );

      if (!mounted) return;

      setState(() => _procesando = false);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AdminDashboard(),
        ),
      );

      // Al volver, se asegura de haber salido del modo soporte y recargar
      await ApiClient.salirDeModoSoporte();
      if (mounted) {
        await _cargar();
      }
    } on ApiSuperAdminException catch (error) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarMensaje(error.mensaje, esError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _procesando = false);
      _mostrarMensaje('No se pudo iniciar el modo soporte.', esError: true);
    }
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final cliente = await _servicio.obtenerCliente(widget.clienteId);
      if (!mounted) return;
      setState(() {
        _cliente = cliente;
        _cargando = false;
      });
    } on ApiSuperAdminException catch (error) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = error.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo conectar con la API de ParkControl.';
      });
    }
  }

  Future<void> _editar() async {
    final cliente = _cliente;
    if (cliente == null) return;

    final actualizado = await Navigator.push<ClienteParkControl>(
      context,
      MaterialPageRoute(builder: (_) => ClienteFormScreen(cliente: cliente)),
    );

    if (actualizado == null || !mounted) return;
    _huboCambios = true;
    await _cargar();
  }

  Future<void> _cambiarEstado() async {
    final cliente = _cliente;
    if (cliente == null || _procesando) return;

    final nuevoEstado = cliente.estaSuspendido ? 'activo' : 'suspendido';
    final accion = nuevoEstado == 'suspendido' ? 'suspender' : 'reactivar';
    final motivoController = TextEditingController();

    final motivo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${accion[0].toUpperCase()}${accion.substring(1)} cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nuevoEstado == 'suspendido'
                  ? 'El cliente perderá acceso al sistema, pero conservará todos sus datos.'
                  : 'El cliente recuperará el acceso al sistema.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motivo *',
                hintText: 'Ej.: pago pendiente o pago confirmado',
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
          FilledButton(
            style: nuevoEstado == 'suspendido'
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                : null,
            onPressed: () {
              final texto = motivoController.text.trim();
              if (texto.isEmpty) return;
              Navigator.pop(dialogContext, texto);
            },
            child: Text(
              nuevoEstado == 'suspendido' ? 'Suspender' : 'Reactivar',
            ),
          ),
        ],
      ),
    );

    motivoController.dispose();
    if (motivo == null) return;

    await _ejecutar(
      () => _servicio.cambiarEstado(
        clienteId: cliente.id,
        estado: nuevoEstado,
        motivo: motivo,
      ),
      nuevoEstado == 'suspendido'
          ? 'Cliente suspendido correctamente.'
          : 'Cliente reactivado correctamente.',
    );
  }

  Future<void> _registrarPago() async {
    final cliente = _cliente;
    if (cliente == null || _procesando) return;

    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PagoDialog(vencimientoActual: cliente.fechaVencimiento),
    );

    if (resultado == null) return;

    await _ejecutar(
      () => _servicio.registrarPago(clienteId: cliente.id, datos: resultado),
      'Pago registrado correctamente.',
    );
  }

  Future<void> _anularPago(Map<String, dynamic> pago) async {
    final cliente = _cliente;
    final pagoId = pago['id'] is num
        ? (pago['id'] as num).toInt()
        : int.tryParse(pago['id']?.toString() ?? '') ?? 0;

    if (cliente == null || pagoId <= 0 || _procesando) return;

    final motivoController = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Anular pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El pago dejará de sumar en los ingresos y se conservará para auditoría. '
              'Si sigue siendo la última acción comercial, ParkControl también restaurará '
              'el vencimiento y acceso anteriores.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo de anulación *',
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () {
              final texto = motivoController.text.trim();
              if (texto.isEmpty) return;
              Navigator.pop(dialogContext, texto);
            },
            child: const Text('Anular pago'),
          ),
        ],
      ),
    );

    motivoController.dispose();
    if (motivo == null) return;

    await _ejecutar(
      () => _servicio.anularPago(
        clienteId: cliente.id,
        pagoId: pagoId,
        motivo: motivo,
      ),
      'Pago anulado correctamente.',
    );
  }

  Future<void> _crearAdministrador() async {
    final cliente = _cliente;
    if (cliente == null || _procesando) return;

    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _AdministradorDialog(),
    );

    if (resultado == null) return;

    await _ejecutar(
      () => _servicio.crearAdministrador(
        clienteId: cliente.id,
        nombre: resultado['nombre']!,
        email: resultado['email']!,
        password: resultado['password']!,
      ),
      'Administrador creado correctamente.',
    );
  }

  Future<void> _restablecerPassword(AdministradorCliente administrador) async {
    final cliente = _cliente;
    if (cliente == null || _procesando) return;

    final passwordController = TextEditingController();
    var ocultar = true;

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Contraseña temporal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Administrador: ${administrador.nombre}'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: ocultar,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nueva contraseña',
                  helperText: 'Mínimo 10 caracteres.',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setDialogState(() => ocultar = !ocultar),
                    icon: Icon(
                      ocultar
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (passwordController.text.length < 10) return;
                Navigator.pop(dialogContext, passwordController.text);
              },
              child: const Text('Restablecer'),
            ),
          ],
        ),
      ),
    );

    passwordController.dispose();
    if (password == null) return;

    await _ejecutar(
      () => _servicio.restablecerPassword(
        clienteId: cliente.id,
        usuarioId: administrador.id,
        password: password,
      ),
      'Contraseña restablecida correctamente.',
    );
  }

  Future<void> _ejecutar(
    Future<dynamic> Function() operacion,
    String mensajeExito,
  ) async {
    setState(() => _procesando = true);

    try {
      final resultado = await operacion();
      if (!mounted) return;
      _huboCambios = true;
      _mostrarMensaje(
        resultado is String && resultado.trim().isNotEmpty
            ? resultado
            : mensajeExito,
      );
      await _cargar();
    } on ApiSuperAdminException catch (error) {
      if (!mounted) return;
      _mostrarMensaje(error.mensaje, esError: true);
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje(
        'No se pudo conectar con la API de ParkControl.',
        esError: true,
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: esError
              ? Colors.red.shade700
              : const Color(0xFF168A4C),
          content: Text(mensaje),
        ),
      );
  }

  void _volver() {
    Navigator.pop(context, _huboCambios);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: _volver,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text(
          'Detalle del cliente',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _procesando
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando && _cliente == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _cliente == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 56),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final cliente = _cliente!;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _encabezado(cliente),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, restricciones) {
                      final datos = _datosCliente(cliente);
                      final suscripcion = _suscripcion(cliente);

                      if (restricciones.maxWidth < 760) {
                        return Column(
                          children: [
                            datos,
                            const SizedBox(height: 16),
                            suscripcion,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: datos),
                          const SizedBox(width: 16),
                          Expanded(child: suscripcion),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _administradores(cliente),
                  const SizedBox(height: 16),
                  _pagos(cliente),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado(ClienteParkControl cliente) {
    final suspendido = cliente.estaSuspendido;
    final color = suspendido ? Colors.red.shade700 : const Color(0xFF168A4C);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(Icons.local_parking, color: color, size: 30),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.nombre,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172B4D),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        cliente.razonSocial.isEmpty
                            ? 'Cliente ParkControl'
                            : cliente.razonSocial,
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
                _EtiquetaEstado(
                  texto: suspendido ? 'Suspendido' : 'Activo',
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2B52),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _procesando ? null : _entrarModoSoporte,
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Ingresar como Soporte / Auditor'),
                ),
                OutlinedButton.icon(
                  onPressed: _procesando ? null : _editar,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar datos'),
                ),
                FilledButton.icon(
                  onPressed: _procesando ? null : _registrarPago,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Registrar pago'),
                ),
                OutlinedButton.icon(
                  style: suspendido
                      ? null
                      : OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                        ),
                  onPressed: _procesando ? null : _cambiarEstado,
                  icon: Icon(
                    suspendido
                        ? Icons.play_circle_outline
                        : Icons.pause_circle_outline,
                  ),
                  label: Text(suspendido ? 'Reactivar' : 'Suspender'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _datosCliente(ClienteParkControl cliente) {
    return _TarjetaDetalle(
      titulo: 'Información comercial',
      icono: Icons.business_outlined,
      children: [
        _FilaDato('RUT', cliente.rut),
        _FilaDato('Correo', cliente.email),
        _FilaDato('Teléfono', cliente.telefono),
        _FilaDato('Dirección', cliente.direccion),
      ],
    );
  }

  Widget _suscripcion(ClienteParkControl cliente) {
    return _TarjetaDetalle(
      titulo: 'Suscripción',
      icono: Icons.calendar_month_outlined,
      children: [
        _FilaDato('Plan', cliente.plan),
        _FilaDato(
          'Estado comercial',
          _estadoComercialVisible(cliente.estadoComercial),
        ),
        _FilaDato(
          'Medio de cobro',
          cliente.tieneTarjetaAsociada
              ? '${cliente.tarjetaMarca.toUpperCase()} •••• ${cliente.tarjetaUltimos4}'
              : 'Transferencia bancaria / Manual',
        ),
        if (cliente.tieneTarjetaAsociada)
          _FilaDato(
            'Renovación automática',
            cliente.renovacionAutomatica
                ? 'Activa (Mercado Pago)'
                : 'Pausada / Inactiva',
          ),
        _FilaDato('Inicio', _fecha(cliente.fechaInicio)),
        _FilaDato(
          'Vencimiento',
          cliente.fechaVencimiento == null
              ? 'Sin vencimiento'
              : _fecha(cliente.fechaVencimiento),
        ),
        _FilaDato('Último pago', _fecha(cliente.fechaUltimoPago)),
        _FilaDato('Referencia', cliente.referenciaPago),
        if (cliente.observacion.isNotEmpty)
          _FilaDato('Observación', cliente.observacion),
        if (cliente.motivoSuspension.isNotEmpty)
          _FilaDato('Motivo de suspensión', cliente.motivoSuspension),
      ],
    );
  }

  String _estadoComercialVisible(String estado) {
    switch (estado.toLowerCase()) {
      case 'suspendido':
        return 'Suspendido';
      case 'vencido':
        return 'Vencido';
      case 'por_vencer':
        return 'Por vencer';
      case 'sin_vencimiento':
        return 'Sin vencimiento';
      default:
        return 'Al día';
    }
  }

  Widget _administradores(ClienteParkControl cliente) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.manage_accounts_outlined,
                  color: Color(0xFF1565FF),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Administradores del cliente',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF172B4D),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _procesando ? null : _crearAdministrador,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (cliente.administradores.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No hay administradores asociados.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
              )
            else
              ...cliente.administradores.map(
                (administrador) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F0FE),
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Color(0xFF1565FF),
                    ),
                  ),
                  title: Text(
                    administrador.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    administrador.activo
                        ? administrador.email
                        : '${administrador.email} · Inactivo',
                  ),
                  trailing: TextButton.icon(
                    onPressed:
                        administrador.id <= 0 ||
                            !administrador.activo ||
                            _procesando
                        ? null
                        : () => _restablecerPassword(administrador),
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('Contraseña'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pagos(ClienteParkControl cliente) {
    int? ultimoPagoConfirmadoId;

    for (final pago in cliente.pagos) {
      if (pago['estado']?.toString() != 'anulado') {
        final pagoId = pago['id'] is num
            ? (pago['id'] as num).toInt()
            : int.tryParse(pago['id']?.toString() ?? '');

        if (pagoId != null &&
            (ultimoPagoConfirmadoId == null ||
                pagoId > ultimoPagoConfirmadoId)) {
          ultimoPagoConfirmadoId = pagoId;
        }
      }
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_long_outlined, color: Color(0xFF1565FF)),
                SizedBox(width: 10),
                Text(
                  'Pagos de suscripción',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172B4D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (cliente.pagos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Todavía no hay pagos registrados.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
              )
            else
              ...cliente.pagos.map((pago) {
                final monto = pago['monto'] is num
                    ? (pago['monto'] as num).round()
                    : int.tryParse(pago['monto']?.toString() ?? '') ?? 0;
                final metodo = pago['metodo']?.toString() ?? 'Pago';
                final fecha = DateTime.tryParse(
                  pago['fechaPago']?.toString() ?? '',
                );
                final referencia = pago['referencia']?.toString().trim() ?? '';
                final anulado = pago['estado']?.toString() == 'anulado';
                final pagoId = pago['id'] is num
                    ? (pago['id'] as num).toInt()
                    : int.tryParse(pago['id']?.toString() ?? '');
                final puedeAnular =
                    !anulado && pagoId == ultimoPagoConfirmadoId;
                final motivoAnulacion =
                    pago['motivoAnulacion']?.toString().trim() ?? '';
                final detallePago = referencia.isEmpty
                    ? _tituloMetodo(metodo)
                    : '${_tituloMetodo(metodo)} · $referencia';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: anulado
                        ? const Color(0xFFFFEBEE)
                        : const Color(0xFFE8F7EF),
                    child: Icon(
                      anulado
                          ? Icons.money_off_outlined
                          : Icons.payments_outlined,
                      color: anulado
                          ? Colors.red.shade700
                          : const Color(0xFF168A4C),
                    ),
                  ),
                  title: Text(
                    _pesos(monto),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: anulado ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Text(
                    anulado
                        ? 'Anulado${motivoAnulacion.isEmpty ? '' : ' · $motivoAnulacion'}'
                        : detallePago,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_fecha(fecha)),
                      if (!anulado)
                        IconButton(
                          tooltip: puedeAnular
                              ? 'Anular pago'
                              : 'Anula primero el pago confirmado más reciente',
                          onPressed: _procesando || !puedeAnular
                              ? null
                              : () => _anularPago(pago),
                          icon: const Icon(Icons.block_outlined),
                          color: Colors.red.shade700,
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _pesos(int valor) {
    final numero = valor.toString();
    final resultado = StringBuffer();

    for (var indice = 0; indice < numero.length; indice++) {
      if (indice > 0 && (numero.length - indice) % 3 == 0) {
        resultado.write('.');
      }
      resultado.write(numero[indice]);
    }

    return r'$' + resultado.toString();
  }

  String _tituloMetodo(String metodo) {
    if (metodo.isEmpty) return 'Pago';
    return '${metodo[0].toUpperCase()}${metodo.substring(1)}';
  }

  String _fecha(DateTime? fecha) {
    if (fecha == null) return 'Sin registrar';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }
}

class _TarjetaDetalle extends StatelessWidget {
  const _TarjetaDetalle({
    required this.titulo,
    required this.icono,
    required this.children,
  });

  final String titulo;
  final IconData icono;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: const Color(0xFF1565FF)),
                const SizedBox(width: 10),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172B4D),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              etiqueta,
              style: const TextStyle(color: Colors.blueGrey),
            ),
          ),
          Expanded(
            child: Text(
              valor.trim().isEmpty ? 'Sin registrar' : valor,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaEstado extends StatelessWidget {
  const _EtiquetaEstado({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PagoDialog extends StatefulWidget {
  const _PagoDialog({this.vencimientoActual});

  final DateTime? vencimientoActual;

  @override
  State<_PagoDialog> createState() => _PagoDialogState();
}

class _PagoDialogState extends State<_PagoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _observacionController = TextEditingController();
  String _medio = 'transferencia';
  bool _reactivar = true;
  late DateTime _fechaPago;
  late DateTime _periodoDesde;
  late DateTime _proximoVencimiento;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _fechaPago = DateTime(hoy.year, hoy.month, hoy.day);
    _periodoDesde = _calcularInicioPeriodo(_fechaPago);
    _proximoVencimiento = _sumarUnMes(_periodoDesde);
  }

  @override
  void dispose() {
    _montoController.dispose();
    _referenciaController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha(bool vencimiento) async {
    final inicial = vencimiento ? _proximoVencimiento : _fechaPago;
    final fecha = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha == null || !mounted) return;
    setState(() {
      if (vencimiento) {
        _proximoVencimiento = fecha;
      } else {
        _fechaPago = fecha;
        _periodoDesde = _calcularInicioPeriodo(fecha);
        _proximoVencimiento = _sumarUnMes(_periodoDesde);
      }
    });
  }

  String _fechaApi(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  String _visible(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  DateTime _sumarUnMes(DateTime fecha) {
    final ultimoDiaDelMesDestino = DateTime(fecha.year, fecha.month + 2, 0).day;
    final dia = fecha.day > ultimoDiaDelMesDestino
        ? ultimoDiaDelMesDestino
        : fecha.day;

    return DateTime(fecha.year, fecha.month + 1, dia);
  }

  DateTime _calcularInicioPeriodo(DateTime fechaPago) {
    final vencimientoActual = widget.vencimientoActual;
    final fechaPagoCivil = DateTime(
      fechaPago.year,
      fechaPago.month,
      fechaPago.day,
    );

    if (vencimientoActual == null ||
        !vencimientoActual.isAfter(fechaPagoCivil)) {
      return fechaPagoCivil;
    }

    return DateTime(
      vencimientoActual.year,
      vencimientoActual.month,
      vencimientoActual.day,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar pago manual'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _montoController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monto pagado *',
                    prefixText: r'$ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) {
                    final normalizado = (valor ?? '')
                        .replaceAll('.', '')
                        .replaceAll(',', '.');
                    final monto = double.tryParse(normalizado);
                    return monto == null || monto <= 0
                        ? 'Ingresa un monto válido'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _medio,
                  decoration: const InputDecoration(
                    labelText: 'Medio de pago',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'transferencia',
                      child: Text('Transferencia bancaria'),
                    ),
                    DropdownMenuItem(
                      value: 'efectivo',
                      child: Text('Efectivo'),
                    ),
                  ],
                  onChanged: (valor) {
                    if (valor != null) setState(() => _medio = valor);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _referenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Referencia o comprobante',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _elegirFecha(false),
                        icon: const Icon(Icons.event_outlined),
                        label: Text('Pago ${_visible(_fechaPago)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _elegirFecha(true),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text('Vence ${_visible(_proximoVencimiento)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'El nuevo período comienza el ${_visible(_periodoDesde)}. '
                    'Si el cliente pagó antes de vencer, conserva sus días restantes.',
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _observacionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observación',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reactivar si está suspendido'),
                  subtitle: const Text(
                    'El pago puede devolver el acceso inmediatamente.',
                  ),
                  value: _reactivar,
                  onChanged: (valor) => setState(() => _reactivar = valor),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            if (_proximoVencimiento.isBefore(_periodoDesde)) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text(
                      'El vencimiento no puede ser anterior al inicio del período.',
                    ),
                  ),
                );
              return;
            }
            final normalizado = _montoController.text
                .replaceAll('.', '')
                .replaceAll(',', '.');
            Navigator.pop(context, {
              'monto': double.parse(normalizado),
              'metodo': _medio,
              'referencia': _referenciaController.text.trim(),
              'observacion': _observacionController.text.trim(),
              'fechaPago': _fechaApi(_fechaPago),
              'periodoDesde': _fechaApi(_periodoDesde),
              'periodoHasta': _fechaApi(_proximoVencimiento),
              'reactivar': _reactivar,
            });
          },
          icon: const Icon(Icons.check),
          label: const Text('Registrar'),
        ),
      ],
    );
  }
}

class _AdministradorDialog extends StatefulWidget {
  const _AdministradorDialog();

  @override
  State<_AdministradorDialog> createState() => _AdministradorDialogState();
}

class _AdministradorDialogState extends State<_AdministradorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _ocultar = true;

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo administrador'),
      content: SizedBox(
        width: 470,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) => (valor ?? '').trim().length < 3
                    ? 'El nombre es obligatorio'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo de acceso',
                  border: OutlineInputBorder(),
                ),
                validator: (valor) {
                  final email = (valor ?? '').trim();
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                      ? null
                      : 'Ingresa un correo válido';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                obscureText: _ocultar,
                decoration: InputDecoration(
                  labelText: 'Contraseña temporal',
                  helperText: 'Mínimo 10 caracteres.',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                    icon: Icon(
                      _ocultar
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (valor) => (valor ?? '').length < 10
                    ? 'Usa al menos 10 caracteres'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'nombre': _nombreController.text.trim(),
              'email': _emailController.text.trim().toLowerCase(),
              'password': _passwordController.text,
            });
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
