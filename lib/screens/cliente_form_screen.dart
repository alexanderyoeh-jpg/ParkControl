import 'package:flutter/material.dart';

import '../models/cliente_parkcontrol.dart';
import '../services/superadmin_service.dart';

class ClienteFormScreen extends StatefulWidget {
  const ClienteFormScreen({super.key, this.cliente});

  final ClienteParkControl? cliente;

  bool get esEdicion => cliente != null;

  @override
  State<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends State<ClienteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _servicio = const SuperAdminService();

  late final TextEditingController _nombreController;
  late final TextEditingController _razonSocialController;
  late final TextEditingController _rutController;
  late final TextEditingController _emailController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _direccionController;
  late final TextEditingController _adminNombreController;
  late final TextEditingController _adminEmailController;
  late final TextEditingController _adminPasswordController;

  late String _plan;
  late DateTime _fechaInicio;
  late DateTime? _fechaVencimiento;
  bool _guardando = false;
  bool _ocultarPassword = true;

  @override
  void initState() {
    super.initState();
    final cliente = widget.cliente;
    final hoy = DateTime.now();

    _nombreController = TextEditingController(text: cliente?.nombre ?? '');
    _razonSocialController = TextEditingController(
      text: cliente?.razonSocial ?? '',
    );
    _rutController = TextEditingController(text: cliente?.rut ?? '');
    _emailController = TextEditingController(text: cliente?.email ?? '');
    _telefonoController = TextEditingController(text: cliente?.telefono ?? '');
    _direccionController = TextEditingController(
      text: cliente?.direccion ?? '',
    );
    _adminNombreController = TextEditingController();
    _adminEmailController = TextEditingController();
    _adminPasswordController = TextEditingController();

    const planes = {'LITE', 'PRO', 'INICIAL', 'PROFESIONAL', 'EMPRESA'};
    final planCliente = cliente?.plan ?? '';
    _plan = planes.contains(planCliente.toUpperCase())
        ? planCliente.toUpperCase()
        : 'LITE';
    final fechaHoy = DateTime(hoy.year, hoy.month, hoy.day);
    _fechaInicio = cliente?.fechaInicio ?? fechaHoy;
    _fechaVencimiento = widget.esEdicion
        ? cliente?.fechaVencimiento
        : _sumarUnMes(fechaHoy);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _razonSocialController.dispose();
    _rutController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _adminNombreController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha({required bool esInicio}) async {
    final actual = esInicio
        ? _fechaInicio
        : (_fechaVencimiento ?? _sumarUnMes(_fechaInicio));
    final fecha = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: esInicio
          ? 'Fecha de inicio del servicio'
          : 'Fecha de vencimiento',
    );

    if (fecha == null || !mounted) return;

    setState(() {
      if (esInicio) {
        _fechaInicio = fecha;
        if (_fechaVencimiento != null && _fechaVencimiento!.isBefore(fecha)) {
          _fechaVencimiento = _sumarUnMes(fecha);
        }
      } else {
        _fechaVencimiento = fecha;
      }
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_fechaVencimiento != null &&
        _fechaVencimiento!.isBefore(_fechaInicio)) {
      _mostrarError('El vencimiento no puede ser anterior al inicio.');
      return;
    }

    setState(() => _guardando = true);

    final datos = <String, dynamic>{
      'nombre': _nombreController.text.trim(),
      'razonSocial': _razonSocialController.text.trim(),
      'rut': _rutController.text.trim(),
      'emailContacto': _emailController.text.trim().toLowerCase(),
      'telefono': _telefonoController.text.trim(),
      'direccion': _direccionController.text.trim(),
      'plan': _plan,
      'fechaInicio': _fechaApi(_fechaInicio),
      'fechaVencimiento': _fechaVencimiento == null
          ? ''
          : _fechaApi(_fechaVencimiento!),
    };

    if (!widget.esEdicion) {
      datos['administrador'] = {
        'nombre': _adminNombreController.text.trim(),
        'email': _adminEmailController.text.trim().toLowerCase(),
        'password': _adminPasswordController.text,
      };
    }

    try {
      final cliente = widget.esEdicion
          ? await _servicio.actualizarCliente(widget.cliente!.id, datos)
          : await _servicio.crearCliente(datos);

      if (!mounted) return;
      Navigator.pop(context, cliente);
    } on ApiSuperAdminException catch (error) {
      if (!mounted) return;
      _mostrarError(error.mensaje);
    } catch (_) {
      if (!mounted) return;
      _mostrarError('No se pudo conectar con la API de ParkControl.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade700, content: Text(mensaje)),
      );
  }

  String? _validarEmailOpcional(String? valor) {
    final email = (valor ?? '').trim();
    if (email.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Ingresa un correo válido';
    }
    return null;
  }

  String? _validarEmailObligatorio(String? valor) {
    final email = (valor ?? '').trim();
    if (email.isEmpty) return 'El correo es obligatorio';
    return _validarEmailOpcional(email);
  }

  String _fechaApi(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  String _fechaVisible(DateTime fecha) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: Text(
          widget.esEdicion ? 'Editar cliente' : 'Nuevo cliente',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _seccionEstacionamiento(),
                    const SizedBox(height: 18),
                    _seccionSuscripcion(),
                    if (!widget.esEdicion) ...[
                      const SizedBox(height: 18),
                      _seccionAdministrador(),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _guardando ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _guardando
                              ? 'Guardando...'
                              : widget.esEdicion
                              ? 'Guardar cambios'
                              : 'Crear cliente y administrador',
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccionEstacionamiento() {
    return _TarjetaFormulario(
      icono: Icons.local_parking_outlined,
      titulo: 'Datos del estacionamiento',
      subtitulo: 'Información comercial y de contacto del cliente.',
      child: Column(
        children: [
          TextFormField(
            controller: _nombreController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del estacionamiento *',
              border: OutlineInputBorder(),
            ),
            validator: (valor) => (valor ?? '').trim().length < 2
                ? 'El nombre es obligatorio'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _razonSocialController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Razón social',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, restricciones) {
              final rut = TextFormField(
                controller: _rutController,
                decoration: const InputDecoration(
                  labelText: 'RUT',
                  hintText: '12.345.678-9',
                  border: OutlineInputBorder(),
                ),
              );
              final telefono = TextFormField(
                controller: _telefonoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  border: OutlineInputBorder(),
                ),
              );

              if (restricciones.maxWidth < 600) {
                return Column(
                  children: [rut, const SizedBox(height: 14), telefono],
                );
              }

              return Row(
                children: [
                  Expanded(child: rut),
                  const SizedBox(width: 14),
                  Expanded(child: telefono),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo de contacto',
              border: OutlineInputBorder(),
            ),
            validator: _validarEmailOpcional,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _direccionController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Dirección',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionSuscripcion() {
    final planesDisponibles = <String>[
      if (_plan != 'LITE' && _plan != 'PRO') _plan,
      'LITE',
      'PRO',
    ];

    return _TarjetaFormulario(
      icono: Icons.calendar_month_outlined,
      titulo: 'Suscripción manual',
      subtitulo: 'Define el plan y el primer período de servicio.',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _plan,
            decoration: const InputDecoration(
              labelText: 'Plan',
              border: OutlineInputBorder(),
            ),
            items: planesDisponibles
                .map(
                  (plan) => DropdownMenuItem(
                    value: plan,
                    child: Text(_nombrePlan(plan)),
                  ),
                )
                .toList(),
            onChanged: (valor) {
              if (valor != null) setState(() => _plan = valor);
            },
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, restricciones) {
              final inicio = _BotonFecha(
                etiqueta: 'Inicio',
                fecha: _fechaVisible(_fechaInicio),
                onTap: () => _seleccionarFecha(esInicio: true),
              );
              final vencimiento = _BotonFecha(
                etiqueta: 'Vencimiento',
                fecha: _fechaVencimiento == null
                    ? 'Sin vencimiento'
                    : _fechaVisible(_fechaVencimiento!),
                onTap: () => _seleccionarFecha(esInicio: false),
              );

              if (restricciones.maxWidth < 600) {
                return Column(
                  children: [inicio, const SizedBox(height: 14), vencimiento],
                );
              }

              return Row(
                children: [
                  Expanded(child: inicio),
                  const SizedBox(width: 14),
                  Expanded(child: vencimiento),
                ],
              );
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _fechaVencimiento == null
                  ? null
                  : () => setState(() => _fechaVencimiento = null),
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Dejar sin vencimiento'),
            ),
          ),
        ],
      ),
    );
  }

  String _nombrePlan(String plan) {
    switch (plan) {
      case 'LITE':
        return 'Lite';
      case 'PRO':
        return 'Pro';
      case 'INICIAL':
        return 'Inicial (anterior)';
      case 'PROFESIONAL':
        return 'Profesional (anterior)';
      case 'EMPRESA':
        return 'Empresa (anterior)';
      default:
        return plan;
    }
  }

  Widget _seccionAdministrador() {
    return _TarjetaFormulario(
      icono: Icons.manage_accounts_outlined,
      titulo: 'Administrador inicial',
      subtitulo:
          'Esta persona administrará los cajeros y la operación del cliente.',
      child: Column(
        children: [
          TextFormField(
            controller: _adminNombreController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre completo *',
              border: OutlineInputBorder(),
            ),
            validator: (valor) => (valor ?? '').trim().length < 3
                ? 'El nombre es obligatorio'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _adminEmailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Correo de acceso *',
              border: OutlineInputBorder(),
            ),
            validator: _validarEmailObligatorio,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _adminPasswordController,
            obscureText: _ocultarPassword,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Contraseña temporal *',
              helperText: 'Mínimo 10 caracteres.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _ocultarPassword = !_ocultarPassword),
                icon: Icon(
                  _ocultarPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (valor) =>
                (valor ?? '').length < 10 ? 'Usa al menos 10 caracteres' : null,
          ),
        ],
      ),
    );
  }
}

class _TarjetaFormulario extends StatelessWidget {
  const _TarjetaFormulario({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.child,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Widget child;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icono, color: const Color(0xFF1565FF)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172B4D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitulo,
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

class _BotonFecha extends StatelessWidget {
  const _BotonFecha({
    required this.etiqueta,
    required this.fecha,
    required this.onTap,
  });

  final String etiqueta;
  final String fecha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(fecha),
      ),
    );
  }
}
