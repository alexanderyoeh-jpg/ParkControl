import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';
import '../widgets/indicador_sincronizacion_offline.dart';
import 'login_screen.dart';
import 'registrar_entrada_screen.dart';
import 'registrar_salida_screen.dart';
import 'historial_screen.dart';
import 'vehiculos_dentro_screen.dart';
import 'reportes_screen.dart';
import 'abonados_screen.dart';
import 'boletas_screen.dart';
import 'configuracion_impresion_screen.dart';
import 'modificar_screen.dart';
import 'turno_caja_screen.dart';

class CajeroDashboard extends StatefulWidget {
  final Map<String, dynamic> usuario;

  const CajeroDashboard({super.key, required this.usuario});

  @override
  State<CajeroDashboard> createState() => _CajeroDashboardState();
}

class _CajeroDashboardState extends State<CajeroDashboard> {
  // ============================================================
  // API
  // ============================================================

  static final String apiUrl = ApiConfig.baseUrl;

  // ============================================================
  // DATOS DEL RESUMEN
  // ============================================================

  bool cargandoResumen = true;

  int vehiculosDentro = 0;

  int entradasHoy = 0;

  int salidasHoy = 0;

  // ============================================================
  // NAVEGACIÓN
  // ============================================================

  int indiceSeleccionado = 0;

  // ============================================================
  // INICIO
  // ============================================================

  @override
  void initState() {
    super.initState();

    cargarResumen();
  }

  // ============================================================
  // CARGAR RESUMEN
  // ============================================================

  Future<void> cargarResumen() async {
    if (!mounted) return;

    setState(() {
      cargandoResumen = true;
    });

    try {
      final response = await ApiClient.get(
        Uri.parse('$apiUrl/api/resumen'),
      ).timeout(const Duration(seconds: 10));

      debugPrint('STATUS RESUMEN: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is! Map) {
          setState(() {
            cargandoResumen = false;
          });

          _mostrarMensaje('La API devolvió un formato inválido', esError: true);

          return;
        }

        final datos = Map<String, dynamic>.from(decoded);

        setState(() {
          vehiculosDentro = _convertirEntero(datos['vehiculosDentro']);

          entradasHoy = _convertirEntero(datos['entradasHoy']);

          salidasHoy = _convertirEntero(datos['salidasHoy']);

          cargandoResumen = false;
        });

        return;
      }

      setState(() {
        cargandoResumen = false;
      });

      _mostrarMensaje(_mensajeError(response.body), esError: true);
    } catch (e) {
      debugPrint('ERROR RESUMEN: $e');

      if (!mounted) return;

      setState(() {
        cargandoResumen = false;
      });

      _mostrarMensaje('No se pudo conectar con la API', esError: true);
    }
  }

  // ============================================================
  // CONVERTIR ENTERO
  // ============================================================

  int _convertirEntero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString()) ?? 0;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool puedeRegistrarEntradas = _booleanoUsuario('registrarEntradas');

    final bool puedeRegistrarSalidas = _booleanoUsuario('registrarSalidas');
    final bool puedeVerBoletas = _capacidadUsuario('boletasPdf');
    final bool puedeCerrarCaja = _capacidadUsuario('cierreCaja');

    final nombreEstacionamiento = widget.usuario['estacionamientoNombre']
        ?.toString()
        .trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),

        foregroundColor: Colors.white,

        title: Text(
          nombreEstacionamiento == null || nombreEstacionamiento.isEmpty
              ? 'Estacionamiento'
              : nombreEstacionamiento,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),

        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AbonadosScreen(puedeEditar: false),
                ),
              );
            },
            icon: const Icon(Icons.badge_outlined),
            tooltip: 'Abonados y convenios',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ConfiguracionImpresionScreen(),
                ),
              );
            },
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Configurar impresora',
          ),
          IconButton(
            onPressed: cargarResumen,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),

      // ========================================================
      // CONTENIDO
      // ========================================================
      body: RefreshIndicator(
        onRefresh: cargarResumen,

        child: _contenidoPrincipal(
          puedeRegistrarEntradas: puedeRegistrarEntradas,
          puedeRegistrarSalidas: puedeRegistrarSalidas,
          puedeVerBoletas: puedeVerBoletas,
          puedeCerrarCaja: puedeCerrarCaja,
        ),
      ),

      // ========================================================
      // MENÚ INFERIOR
      // ========================================================
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: indiceSeleccionado,

        type: BottomNavigationBarType.fixed,

        selectedItemColor: const Color(0xFF0F5ED7),

        unselectedItemColor: Colors.grey,

        onTap: _seleccionarMenu,

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car_outlined),
            activeIcon: Icon(Icons.directions_car),
            label: 'Vehículos',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Más'),
        ],
      ),
    );
  }

  // ============================================================
  // CONTENIDO PRINCIPAL
  // ============================================================

  Widget _contenidoPrincipal({
    required bool puedeRegistrarEntradas,
    required bool puedeRegistrarSalidas,
    required bool puedeVerBoletas,
    required bool puedeCerrarCaja,
  }) {
    final nombre = widget.usuario['nombre']?.toString() ?? 'Cajero';

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),

      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // ======================================================
          // SALUDO
          // ======================================================
          Text(
            'Hola, $nombre',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF172B4D),
            ),
          ),

          const SizedBox(height: 4),

          const Text(
            'Resumen de operaciones',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),

          const IndicadorSincronizacionOffline(),

          const SizedBox(height: 20),

          // ======================================================
          // ENTRADA
          // ======================================================
          if (puedeRegistrarEntradas)
            _accionPrincipal(
              icono: Icons.login,
              color: Colors.green,
              titulo: 'ENTRADA',
              subtitulo: 'Registrar vehículo',
              onTap: _abrirEntrada,
            ),

          if (puedeRegistrarEntradas && puedeRegistrarSalidas)
            const SizedBox(height: 12),

          // ======================================================
          // SALIDA
          // ======================================================
          if (puedeRegistrarSalidas)
            _accionPrincipal(
              icono: Icons.logout,
              color: Colors.red,
              titulo: 'SALIDA',
              subtitulo: 'Cobrar y retirar vehículo',
              onTap: _abrirSalida,
            ),

          if (puedeRegistrarEntradas || puedeRegistrarSalidas)
            const SizedBox(height: 12),

          // ======================================================
          // MODIFICAR
          // ======================================================
          _accionPrincipal(
            icono: Icons.edit_note,
            color: Colors.orange,
            titulo: 'MODIFICAR',
            subtitulo: 'Corregir registros',
            onTap: _abrirModificar,
          ),

          const SizedBox(height: 24),

          // ======================================================
          // RESUMEN
          // ======================================================
          const Text(
            'Resumen de hoy',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF172B4D),
            ),
          ),

          const SizedBox(height: 12),

          if (cargandoResumen)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _resumen(
                    icono: Icons.directions_car,
                    titulo: vehiculosDentro.toString(),
                    subtitulo: 'Vehículos dentro',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _resumen(
                    icono: Icons.login,
                    titulo: entradasHoy.toString(),
                    subtitulo: 'Entradas hoy',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _resumen(
                    icono: Icons.logout,
                    titulo: salidasHoy.toString(),
                    subtitulo: 'Salidas hoy',
                  ),
                ),
                const Spacer(),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // ======================================================
          // ACCESOS
          // ======================================================
          const Text(
            'Accesos rápidos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF172B4D),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _accesoRapido(
                  icono: Icons.history,
                  titulo: 'Historial',
                  onTap: _abrirHistorial,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _accesoRapido(
                  icono: Icons.directions_car,
                  titulo: 'Vehículos',
                  onTap: _abrirVehiculos,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          _accesoRapido(
            icono: Icons.bar_chart,
            titulo: 'Reporte diario',
            onTap: _abrirReportes,
          ),

          if (puedeVerBoletas) ...[
            const SizedBox(height: 10),
            _accesoRapido(
              icono: Icons.receipt_long_outlined,
              titulo: 'Comprobantes',
              onTap: _abrirBoletas,
            ),
          ],

          if (puedeCerrarCaja) ...[
            const SizedBox(height: 10),
            _accesoRapido(
              icono: Icons.point_of_sale_outlined,
              titulo: 'Turno y cierre de caja',
              onTap: _abrirTurnoCaja,
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ============================================================
  // SELECCIONAR MENÚ
  // ============================================================

  void _seleccionarMenu(int indice) {
    if (indice == 0) {
      setState(() {
        indiceSeleccionado = 0;
      });

      return;
    }

    if (indice == 1) {
      setState(() {
        indiceSeleccionado = 1;
      });

      _abrirHistorial();

      return;
    }

    if (indice == 2) {
      setState(() {
        indiceSeleccionado = 2;
      });

      _abrirVehiculos();

      return;
    }

    if (indice == 3) {
      setState(() {
        indiceSeleccionado = 3;
      });

      _mostrarMenuMas();

      return;
    }
  }

  // ============================================================
  // ENTRADA
  // ============================================================

  Future<void> _abrirEntrada() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegistrarEntradaScreen()),
    );

    if (!mounted) return;

    setState(() {
      indiceSeleccionado = 0;
    });

    cargarResumen();
  }

  // ============================================================
  // SALIDA
  // ============================================================

  Future<void> _abrirSalida() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegistrarSalidaScreen(
          permitirComprobantePdf: _capacidadUsuario('boletasPdf'),
          permitirSeleccionMedioPago: _capacidadUsuario('cierreCaja'),
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      indiceSeleccionado = 0;
    });

    cargarResumen();
  }

  // ============================================================
  // MODIFICAR
  // ============================================================

  Future<void> _abrirModificar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ModificarScreen()),
    );

    if (!mounted) return;

    setState(() {
      indiceSeleccionado = 0;
    });

    cargarResumen();
  }

  // ============================================================
  // HISTORIAL
  // ============================================================

  Future<void> _abrirHistorial() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistorialScreen()),
    );

    if (!mounted) return;

    setState(() {
      indiceSeleccionado = 0;
    });

    cargarResumen();
  }

  // ============================================================
  // VEHÍCULOS
  // ============================================================

  Future<void> _abrirVehiculos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VehiculosDentroScreen()),
    );

    if (!mounted) return;

    setState(() {
      indiceSeleccionado = 0;
    });

    cargarResumen();
  }

  Future<void> _abrirBoletas() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BoletasScreen()),
    );

    if (!mounted) return;
    setState(() => indiceSeleccionado = 0);
  }

  Future<void> _abrirTurnoCaja() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TurnoCajaScreen()),
    );

    if (!mounted) return;
    setState(() => indiceSeleccionado = 0);
    cargarResumen();
  }

  // ============================================================
  // REPORTES
  // ============================================================

  Future<void> _abrirReportes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ReportesScreen(mostrarFinanzas: false),
      ),
    );

    if (!mounted) return;

    setState(() {
      indiceSeleccionado = 0;
    });

    cargarResumen();
  }

  // ============================================================
  // MENÚ MÁS
  // ============================================================

  void _mostrarMenuMas() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Sesión de trabajo',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF172B4D),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _opcionMenu(
                    icono: Icons.logout,
                    titulo: 'Cerrar sesión',
                    subtitulo: 'Salir de la cuenta actual',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);

                      _confirmarCerrarSesion();
                    },
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // CONFIRMAR CIERRE DE SESIÓN
  // ============================================================

  void _confirmarCerrarSesion() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text('¿Seguro que deseas cerrar la sesión actual?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);

                _cerrarSesion();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // CERRAR SESIÓN
  // ============================================================

  Future<void> _cerrarSesion() async {
    try {
      await ApiClient.cerrarSesion();
    } catch (e) {
      debugPrint('ERROR CERRAR SESIÓN: $e');
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  // ============================================================
  // OPCIÓN DEL MENÚ
  // ============================================================

  Widget _opcionMenu({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    Color color = const Color(0xFF172B4D),
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icono, color: color),
      ),
      title: Text(
        titulo,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      subtitle: Text(
        subtitulo,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  // ============================================================
  // ACCIÓN PRINCIPAL
  // ============================================================

  Widget _accionPrincipal({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // RESUMEN
  // ============================================================

  Widget _resumen({
    required IconData icono,
    required String titulo,
    required String subtitulo,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: const Color(0xFF0F5ED7), size: 28),
            const SizedBox(height: 10),
            Text(
              titulo,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ACCESO RÁPIDO
  // ============================================================

  Widget _accesoRapido({
    required IconData icono,
    required String titulo,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icono, color: const Color(0xFF0F5ED7), size: 25),
              const SizedBox(height: 8),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BOOLEANO USUARIO
  // ============================================================

  bool _booleanoUsuario(String campo) {
    final valor = widget.usuario[campo];

    if (valor == true || valor == 1) {
      return true;
    }

    if (valor is String) {
      return valor.toLowerCase() == 'true' || valor == '1';
    }

    return false;
  }

  bool _capacidadUsuario(String campo) {
    final capacidades = widget.usuario['capacidades'];

    if (capacidades is Map) {
      final valor = capacidades[campo];
      return valor == true || valor == 1 || valor?.toString() == 'true';
    }

    return false;
  }

  // ============================================================
  // ERROR API
  // ============================================================

  String _mensajeError(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is Map) {
        if (decoded['mensaje'] != null) {
          return decoded['mensaje'].toString();
        }

        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }

        if (decoded['error'] != null) {
          return decoded['error'].toString();
        }
      }
    } catch (_) {}

    return 'No se pudo completar la operación';
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: esError ? Colors.red : const Color(0xFF20B46A),
        behavior: SnackBarBehavior.floating,
        content: Text(mensaje),
      ),
    );
  }
}
