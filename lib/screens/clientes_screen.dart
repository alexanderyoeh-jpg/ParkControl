import 'package:flutter/material.dart';

import '../models/cliente_parkcontrol.dart';
import '../services/superadmin_service.dart';
import 'cliente_detalle_screen.dart';
import 'cliente_form_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _servicio = const SuperAdminService();
  final _buscarController = TextEditingController();

  List<ClienteParkControl> _clientes = [];
  String _filtro = 'todos';
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final clientes = await _servicio.obtenerClientes();
      if (!mounted) return;
      setState(() {
        _clientes = clientes;
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

  List<ClienteParkControl> get _clientesFiltrados {
    final busqueda = _buscarController.text.trim().toLowerCase();

    return _clientes.where((cliente) {
      final coincideBusqueda =
          busqueda.isEmpty ||
          cliente.nombre.toLowerCase().contains(busqueda) ||
          cliente.razonSocial.toLowerCase().contains(busqueda) ||
          cliente.rut.toLowerCase().contains(busqueda) ||
          cliente.email.toLowerCase().contains(busqueda);

      if (!coincideBusqueda) return false;

      switch (_filtro) {
        case 'activos':
          return cliente.estaActivo && !cliente.estaVencido;
        case 'suspendidos':
          return cliente.estaSuspendido;
        case 'vencidos':
          return cliente.estaVencido;
        case 'por_vencer':
          return cliente.estaPorVencer;
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _nuevoCliente() async {
    final creado = await Navigator.push<ClienteParkControl>(
      context,
      MaterialPageRoute(builder: (_) => const ClienteFormScreen()),
    );

    if (creado == null || !mounted) return;
    await _cargar();
  }

  Future<void> _abrirCliente(ClienteParkControl cliente) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClienteDetalleScreen(clienteId: cliente.id),
      ),
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
        title: const Text(
          'Clientes de ParkControl',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoCliente,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nuevo cliente'),
      ),
      body: Column(
        children: [
          _barraBusqueda(),
          Expanded(child: _contenido()),
        ],
      ),
    );
  }

  Widget _barraBusqueda() {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _buscarController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, RUT o correo',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscarController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar',
                            onPressed: () {
                              _buscarController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chipFiltro('todos', 'Todos'),
                      _chipFiltro('activos', 'Activos'),
                      _chipFiltro('suspendidos', 'Suspendidos'),
                      _chipFiltro('vencidos', 'Vencidos'),
                      _chipFiltro('por_vencer', 'Por vencer'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipFiltro(String valor, String texto) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(texto),
        selected: _filtro == valor,
        onSelected: (_) => setState(() => _filtro = valor),
      ),
    );
  }

  Widget _contenido() {
    if (_cargando && _clientes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _clientes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 90),
            const Icon(Icons.cloud_off_outlined, size: 58, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 18),
            Center(
              child: FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ),
          ],
        ),
      );
    }

    final clientes = _clientesFiltrados;
    if (clientes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 90),
            const Icon(
              Icons.apartment_outlined,
              size: 62,
              color: Colors.blueGrey,
            ),
            const SizedBox(height: 16),
            Text(
              _clientes.isEmpty
                  ? 'Todavía no hay clientes registrados.'
                  : 'No hay clientes que coincidan con el filtro.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blueGrey),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, restricciones) {
        final columnas = restricciones.maxWidth >= 1050
            ? 3
            : restricciones.maxWidth >= 700
            ? 2
            : 1;

        return RefreshIndicator(
          onRefresh: _cargar,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columnas,
              mainAxisExtent: 235,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: clientes.length,
            itemBuilder: (_, indice) => _tarjetaCliente(clientes[indice]),
          ),
        );
      },
    );
  }

  Widget _tarjetaCliente(ClienteParkControl cliente) {
    final color = cliente.estaSuspendido
        ? Colors.red
        : cliente.estaVencido
        ? Colors.orange.shade800
        : const Color(0xFF168A4C);
    final estado = cliente.estaSuspendido
        ? 'Suspendido'
        : cliente.estaVencido
        ? 'Vencido'
        : 'Activo';

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirCliente(cliente),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(Icons.local_parking, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cliente.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _dato(
                Icons.badge_outlined,
                cliente.rut.isEmpty ? 'Sin RUT' : cliente.rut,
              ),
              const SizedBox(height: 7),
              _dato(
                Icons.person_outline,
                cliente.administradorPrincipal?.email ??
                    (cliente.email.isEmpty ? 'Sin contacto' : cliente.email),
              ),
              const SizedBox(height: 7),
              _dato(
                Icons.event_outlined,
                cliente.fechaVencimiento == null
                    ? 'Sin vencimiento'
                    : 'Vence ${_fecha(cliente.fechaVencimiento!)}',
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
                          estado,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    cliente.plan,
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: Colors.blueGrey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dato(IconData icono, String texto) {
    return Row(
      children: [
        Icon(icono, size: 18, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.blueGrey),
          ),
        ),
      ],
    );
  }

  String _fecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }
}
