import 'package:flutter/material.dart';

import '../models/abonado.dart';
import '../services/abonados_service.dart';

class AbonadosScreen extends StatefulWidget {
  final bool puedeEditar;

  const AbonadosScreen({super.key, this.puedeEditar = true});

  @override
  State<AbonadosScreen> createState() => _AbonadosScreenState();
}

class _AbonadosScreenState extends State<AbonadosScreen> {
  final _servicio = const AbonadosService();
  final _buscarController = TextEditingController();

  List<Abonado> _abonados = [];
  bool _cargando = true;
  String? _error;
  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _cargarAbonados();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargarAbonados() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final list = await _servicio.obtenerAbonados(
        buscar: _buscarController.text,
        estado: _filtro,
      );
      if (!mounted) return;
      setState(() {
        _abonados = list;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  List<Abonado> get _abonadosFiltrados {
    final q = _buscarController.text.trim().toLowerCase();
    return _abonados.where((a) {
      final matchQuery = q.isEmpty ||
          a.patente.toLowerCase().contains(q) ||
          a.nombreTitular.toLowerCase().contains(q) ||
          (a.rut?.toLowerCase().contains(q) ?? false);

      if (!matchQuery) return false;

      switch (_filtro) {
        case 'al_dia':
          return a.estadoComercial == 'al_dia';
        case 'por_vencer':
          return a.estadoComercial == 'por_vencer';
        case 'vencido':
          return a.estadoComercial == 'vencido';
        case 'suspendido':
          return a.estadoComercial == 'suspendido';
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _abrirFormulario({Abonado? abonado}) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AbonadoFormDialog(abonado: abonado),
    );

    if (resultado == true) {
      _cargarAbonados();
    }
  }

  Future<void> _renovarMes(Abonado abonado) async {
    try {
      await _servicio.renovarMesAbonado(abonado.id, abonado.fechaVencimiento);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Abono de ${abonado.nombreTitular} renovado por 30 días'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      _cargarAbonados();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al renovar: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _confirmarEliminar(Abonado abonado) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar abonado?'),
        content: Text(
          'Se eliminará a "${abonado.nombreTitular}" (${abonado.patente}) del listado de convenios. Los registros históricos de entradas previas se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _servicio.eliminarAbonado(abonado.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abonado eliminado correctamente')),
      );
      _cargarAbonados();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _abonadosFiltrados;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Abonados y Convenios',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: _cargarAbonados,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      floatingActionButton: widget.puedeEditar
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0F5ED7),
              foregroundColor: Colors.white,
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Nuevo Abonado'),
            )
          : null,
      body: Column(
        children: [
          // Barra de búsqueda y filtros
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _buscarController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por patente, titular o RUT...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _buscarController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _buscarController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chipFiltro('todos', 'Todos (${_abonados.length})'),
                      _chipFiltro('al_dia', 'Al día'),
                      _chipFiltro('por_vencer', 'Por vencer (≤7d)'),
                      _chipFiltro('vencido', 'Vencidos'),
                      _chipFiltro('suspendido', 'Suspendidos'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Lista de resultados
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _cargarAbonados,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : lista.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    _buscarController.text.isNotEmpty || _filtro != 'todos'
                                        ? 'No se encontraron abonados con este filtro'
                                        : 'No hay abonados registrados',
                                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 12),
                                  if (widget.puedeEditar && _buscarController.text.isEmpty && _filtro == 'todos')
                                    FilledButton.icon(
                                      onPressed: () => _abrirFormulario(),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Registrar Primer Abonado'),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                            itemCount: lista.length,
                            itemBuilder: (ctx, index) {
                              final abonado = lista[index];
                              return _AbonadoCard(
                                abonado: abonado,
                                puedeEditar: widget.puedeEditar,
                                onRenovar: () => _renovarMes(abonado),
                                onEditar: () => _abrirFormulario(abonado: abonado),
                                onEliminar: () => _confirmarEliminar(abonado),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _chipFiltro(String valor, String texto) {
    final seleccionado = _filtro == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(texto, style: TextStyle(fontSize: 12, fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal)),
        selected: seleccionado,
        onSelected: (_) {
          setState(() => _filtro = valor);
        },
        selectedColor: const Color(0xFF0F5ED7).withValues(alpha: 0.15),
        checkmarkColor: const Color(0xFF0F5ED7),
      ),
    );
  }
}

class _AbonadoCard extends StatelessWidget {
  final Abonado abonado;
  final bool puedeEditar;
  final VoidCallback onRenovar;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _AbonadoCard({
    required this.abonado,
    required this.puedeEditar,
    required this.onRenovar,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Badge de Patente
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2B52),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    abonado.patente,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  abonado.tipoVehiculo,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const Spacer(),
                // Estado badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: abonado.colorEstado.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: BorderSide(color: abonado.colorEstado, width: 0.8),
                  ),
                  child: Text(
                    abonado.etiquetaEstado,
                    style: TextStyle(
                      color: abonado.colorEstado,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              abonado.nombreTitular,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (abonado.rut != null && abonado.rut!.isNotEmpty)
              Text('RUT: ${abonado.rut}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            if (abonado.telefono != null && abonado.telefono!.isNotEmpty)
              Text('Tel: ${abonado.telefono}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Vence: ${abonado.fechaVencimiento}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (abonado.montoMensual > 0)
                  Text(
                    '\$${abonado.montoMensual.toStringAsFixed(0)} / mes',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F5ED7)),
                  ),
              ],
            ),
            if (abonado.observacion != null && abonado.observacion!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Nota: ${abonado.observacion}',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
              ),
            ],
            if (puedeEditar) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onRenovar,
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Renovar +30d', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: onEditar,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade600),
                    tooltip: 'Eliminar',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEliminar,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AbonadoFormDialog extends StatefulWidget {
  final Abonado? abonado;

  const _AbonadoFormDialog({this.abonado});

  @override
  State<_AbonadoFormDialog> createState() => _AbonadoFormDialogState();
}

class _AbonadoFormDialogState extends State<_AbonadoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _servicio = const AbonadosService();

  late final TextEditingController _titularCtrl;
  late final TextEditingController _patenteCtrl;
  late final TextEditingController _rutCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _montoCtrl;
  late final TextEditingController _vencimientoCtrl;
  late final TextEditingController _observacionCtrl;
  String _tipoVehiculo = 'Auto';
  String _estado = 'activo';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final a = widget.abonado;
    _titularCtrl = TextEditingController(text: a?.nombreTitular ?? '');
    _patenteCtrl = TextEditingController(text: a?.patente ?? '');
    _rutCtrl = TextEditingController(text: a?.rut ?? '');
    _telefonoCtrl = TextEditingController(text: a?.telefono ?? '');
    _emailCtrl = TextEditingController(text: a?.email ?? '');
    _montoCtrl = TextEditingController(text: a != null ? a.montoMensual.toStringAsFixed(0) : '0');
    _observacionCtrl = TextEditingController(text: a?.observacion ?? '');
    _tipoVehiculo = a?.tipoVehiculo ?? 'Auto';
    _estado = a?.estado ?? 'activo';

    final hoy = DateTime.now();
    final unMes = DateTime(hoy.year, hoy.month + 1, hoy.day);
    _vencimientoCtrl = TextEditingController(
      text: a?.fechaVencimiento ?? unMes.toIso8601String().substring(0, 10),
    );
  }

  @override
  void dispose() {
    _titularCtrl.dispose();
    _patenteCtrl.dispose();
    _rutCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _montoCtrl.dispose();
    _vencimientoCtrl.dispose();
    _observacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFechaVencimiento() async {
    DateTime inicial;
    try {
      inicial = DateTime.parse(_vencimientoCtrl.text);
    } catch (_) {
      inicial = DateTime.now().add(const Duration(days: 30));
    }

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );

    if (seleccionada != null) {
      _vencimientoCtrl.text = seleccionada.toIso8601String().substring(0, 10);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      final hoyStr = DateTime.now().toIso8601String().substring(0, 10);
      final monto = double.tryParse(_montoCtrl.text.trim()) ?? 0.0;

      if (widget.abonado == null) {
        // Crear
        await _servicio.crearAbonado(
          nombreTitular: _titularCtrl.text,
          patente: _patenteCtrl.text,
          rut: _rutCtrl.text.isEmpty ? null : _rutCtrl.text,
          telefono: _telefonoCtrl.text.isEmpty ? null : _telefonoCtrl.text,
          email: _emailCtrl.text.isEmpty ? null : _emailCtrl.text,
          tipoVehiculo: _tipoVehiculo,
          montoMensual: monto,
          fechaInicio: hoyStr,
          fechaVencimiento: _vencimientoCtrl.text,
          observacion: _observacionCtrl.text.isEmpty ? null : _observacionCtrl.text,
        );
      } else {
        // Actualizar
        await _servicio.actualizarAbonado(
          id: widget.abonado!.id,
          nombreTitular: _titularCtrl.text,
          rut: _rutCtrl.text.isEmpty ? null : _rutCtrl.text,
          telefono: _telefonoCtrl.text.isEmpty ? null : _telefonoCtrl.text,
          email: _emailCtrl.text.isEmpty ? null : _emailCtrl.text,
          tipoVehiculo: _tipoVehiculo,
          montoMensual: monto,
          fechaVencimiento: _vencimientoCtrl.text,
          estado: _estado,
          observacion: _observacionCtrl.text.isEmpty ? null : _observacionCtrl.text,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = widget.abonado != null;

    return AlertDialog(
      title: Text(esEdicion ? 'Editar Abonado' : 'Nuevo Abonado / Convenio'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titularCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Titular o Empresa *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'El nombre es obligatorio' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _patenteCtrl,
                        enabled: !esEdicion,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Patente *',
                          prefixIcon: Icon(Icons.credit_card),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Patente obligatoria' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _tipoVehiculo,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Auto', child: Text('Auto')),
                          DropdownMenuItem(value: 'Camioneta', child: Text('Camioneta')),
                          DropdownMenuItem(value: 'Moto', child: Text('Moto')),
                          DropdownMenuItem(value: 'Furgón', child: Text('Furgón')),
                        ],
                        onChanged: (v) => setState(() => _tipoVehiculo = v ?? 'Auto'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _rutCtrl,
                        decoration: const InputDecoration(
                          labelText: 'RUT',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _montoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Monto mensual (\$) *',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _vencimientoCtrl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Vence el *',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: _seleccionarFechaVencimiento,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (esEdicion) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _estado,
                    decoration: const InputDecoration(
                      labelText: 'Estado de la suscripción',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'activo', child: Text('Activo (Habilitado)')),
                      DropdownMenuItem(value: 'suspendido', child: Text('Suspendido (Inhabilitar paso libre)')),
                    ],
                    onChanged: (v) => setState(() => _estado = v ?? 'activo'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observacionCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observación (n° estacionamiento, etc.)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(esEdicion ? 'Guardar Cambios' : 'Registrar Abonado'),
        ),
      ],
    );
  }
}
