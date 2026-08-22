import 'package:flutter/material.dart';

import '../models/cliente_parkcontrol.dart';
import '../services/api_client.dart';
import '../services/superadmin_service.dart';
import 'cliente_detalle_screen.dart';
import 'cliente_form_screen.dart';
import 'clientes_screen.dart';
import 'login_screen.dart';
import 'superadmin_comunicados_screen.dart';
import 'superadmin_contabilidad_screen.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  final _servicio = const SuperAdminService();

  int _totalClientes = 0;
  int _clientesActivos = 0;
  int _clientesSuspendidos = 0;
  int _clientesVencidos = 0;
  int _clientesPorVencer = 0;
  double _ingresosMes = 0;
  List<ClienteParkControl> _vencimientos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final resumen = await _servicio.obtenerResumen();
      final vencimientosJson = resumen['vencimientosProximos'];
      final vencimientos = vencimientosJson is List
          ? vencimientosJson
                .whereType<Map>()
                .map(
                  (item) => ClienteParkControl.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : <ClienteParkControl>[];

      if (!mounted) return;
      setState(() {
        _totalClientes = _entero(resumen['totalClientes']);
        _clientesActivos = _entero(resumen['clientesActivos']);
        _clientesSuspendidos = _entero(resumen['clientesSuspendidos']);
        _clientesVencidos = _entero(resumen['clientesVencidos']);
        _clientesPorVencer = _entero(resumen['clientesPorVencer']);
        _ingresosMes = _numero(resumen['ingresosMes']);
        _vencimientos = vencimientos;
        _cargando = false;
      });
    } on ApiSuperAdminException catch (error) {
      if (!mounted) return;

      if (error.codigo == 401 || error.codigo == 403) {
        await _cerrarSesion(mensaje: error.mensaje);
        return;
      }

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

  int _entero(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
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

    return r'$' + resultado.toString();
  }

  Future<void> _cerrarSesion({String? mensaje}) async {
    await ApiClient.cerrarSesion();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );

    if (mensaje != null && mensaje.trim().isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
    }
  }

  Future<void> _abrirClientes() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ClientesScreen()),
    );
    if (mounted) await _cargar();
  }

  Future<void> _nuevoCliente() async {
    final cliente = await Navigator.push<ClienteParkControl>(
      context,
      MaterialPageRoute(builder: (_) => const ClienteFormScreen()),
    );
    if (cliente == null || !mounted) return;
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

  Future<void> _cambiarPassword() async {
    final formKey = GlobalKey<FormState>();
    final actualController = TextEditingController();
    final nuevaController = TextEditingController();
    final confirmarController = TextEditingController();

    final datos = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cambiar mi contraseña'),
        content: Form(
          key: formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: actualController,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña actual',
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) => (valor ?? '').isEmpty
                      ? 'Ingresa tu contraseña actual'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: nuevaController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña',
                    helperText: 'Mínimo 12 caracteres.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) => (valor ?? '').length < 12
                      ? 'Usa al menos 12 caracteres'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: confirmarController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) => valor != nuevaController.text
                      ? 'Las contraseñas no coinciden'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, {
                'actual': actualController.text,
                'nueva': nuevaController.text,
              });
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );

    actualController.dispose();
    nuevaController.dispose();
    confirmarController.dispose();

    if (datos == null || !mounted) return;

    try {
      await _servicio.cambiarPasswordPropia(
        passwordActual: datos['actual']!,
        passwordNueva: datos['nueva']!,
      );
      await ApiClient.borrarSesion();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Contraseña actualizada. Inicia sesión nuevamente.'),
        ),
      );
    } on ApiSuperAdminException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(error.mensaje),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ParkControl', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Control general',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            onSelected: (opcion) {
              if (opcion == 'cambiar_password') {
                _cambiarPassword();
              }
              if (opcion == 'cerrar_sesion') _cerrarSesion();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'cambiar_password',
                child: Row(
                  children: [
                    Icon(Icons.password_outlined),
                    SizedBox(width: 10),
                    Text('Cambiar contraseña'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'cerrar_sesion',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 10),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _bienvenida(),
                    const SizedBox(height: 20),
                    if (_error != null) _mensajeError(),
                    if (_cargando)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 70),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      _indicadores(),
                      const SizedBox(height: 24),
                      _acciones(),
                      const SizedBox(height: 24),
                      _proximosVencimientos(),
                    ],
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

  Widget _bienvenida() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2B52), Color(0xFF1565FF)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white24,
            child: Icon(
              Icons.admin_panel_settings_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Panel del SuperAdministrador',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Administra clientes, vencimientos y accesos desde un solo lugar.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mensajeError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(child: Text(_error!)),
          TextButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _indicadores() {
    final datos = [
      (
        'Clientes totales',
        _totalClientes.toString(),
        Icons.apartment,
        const Color(0xFF1565FF),
      ),
      (
        'Activos',
        _clientesActivos.toString(),
        Icons.check_circle_outline,
        const Color(0xFF168A4C),
      ),
      (
        'Suspendidos',
        _clientesSuspendidos.toString(),
        Icons.pause_circle_outline,
        Colors.red.shade700,
      ),
      (
        'Vencidos',
        _clientesVencidos.toString(),
        Icons.warning_amber_outlined,
        Colors.orange.shade800,
      ),
      (
        'Por vencer',
        _clientesPorVencer.toString(),
        Icons.event_busy_outlined,
        Colors.deepPurple,
      ),
      (
        'Ingresos del mes',
        _pesos(_ingresosMes),
        Icons.account_balance_wallet_outlined,
        const Color(0xFF087E8B),
      ),
    ];

    return LayoutBuilder(
      builder: (context, restricciones) {
        final columnas = restricciones.maxWidth >= 950
            ? 3
            : restricciones.maxWidth >= 570
            ? 2
            : 1;
        final ancho =
            (restricciones.maxWidth - ((columnas - 1) * 12)) / columnas;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: datos
              .map(
                (dato) => SizedBox(
                  width: ancho,
                  child: _TarjetaIndicador(
                    titulo: dato.$1,
                    valor: dato.$2,
                    icono: dato.$3,
                    color: dato.$4,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _acciones() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Acciones principales',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _nuevoCliente,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Crear cliente'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF168A4C)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SuperadminContabilidadScreen()),
                  ),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Finanzas y Suscripciones SaaS'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F2B52)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SuperadminComunicadosScreen()),
                  ),
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text('Comunicados Masivos (Correo)'),
                ),
                OutlinedButton.icon(
                  onPressed: _abrirClientes,
                  icon: const Icon(Icons.manage_search_outlined),
                  label: const Text('Administrar clientes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _proximosVencimientos() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Próximos vencimientos',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF172B4D),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _abrirClientes,
                  child: const Text('Ver todos'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_vencimientos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(
                  child: Text(
                    'No hay vencimientos cercanos.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
              )
            else
              ..._vencimientos
                  .take(6)
                  .map(
                    (cliente) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => _abrirCliente(cliente),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFF3E0),
                        child: Icon(
                          Icons.event_busy_outlined,
                          color: Color(0xFFF08A24),
                        ),
                      ),
                      title: Text(
                        cliente.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('Plan ${cliente.plan}'),
                      trailing: Text(
                        _fecha(cliente.fechaVencimiento),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  String _fecha(DateTime? fecha) {
    if (fecha == null) return 'Sin fecha';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }
}

class _TarjetaIndicador extends StatelessWidget {
  const _TarjetaIndicador({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
  });

  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF172B4D),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(titulo, style: const TextStyle(color: Colors.blueGrey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
