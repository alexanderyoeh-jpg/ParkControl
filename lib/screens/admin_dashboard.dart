import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_client.dart';
import '../services/capacidades_plan_service.dart';
import '../widgets/indicador_sincronizacion_offline.dart';
import 'abonados_screen.dart';
import 'auditoria_screen.dart';
import 'auditoria_cajeros_pro_screen.dart';
import 'alertas_pro_screen.dart';
import 'analitica_pro_screen.dart';
import 'boletas_screen.dart';
import 'configuracion_impresion_screen.dart';
import 'contabilidad_screen.dart';
import 'historial_screen.dart';
import 'informes_programados_pro_screen.dart';
import 'login_screen.dart';
import 'modificar_screen.dart';
import 'morosidad_screen.dart';
import 'reportes_screen.dart';
import 'suscripcion_metodo_pago_screen.dart';
import 'tarifas_screen.dart';
import 'users_screen.dart';
import 'vehiculos_dentro_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static final String _apiUrl = ApiConfig.baseUrl;

  double _recaudacionHoy = 0;
  int _entradasHoy = 0;
  int _salidasHoy = 0;
  int _vehiculosDentro = 0;
  List<Map<String, dynamic>> _actividad = [];
  CapacidadesPlan? _capacidades;

  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDashboard();
  }

  Future<void> _cargarDashboard() async {
    if (!mounted) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final respuestas = await Future.wait([
        ApiClient.get(Uri.parse('$_apiUrl/api/resumen')),
        ApiClient.get(Uri.parse('$_apiUrl/api/historial')),
      ]);

      CapacidadesPlan? capacidades;

      try {
        capacidades = await CapacidadesPlan.obtenerActuales();
      } catch (_) {
        // Sin conexión no se muestran accesos Pro hasta que el servidor
        // confirme las capacidades vigentes. Las rutas siguen protegidas.
      }

      final respuestaResumen = respuestas[0];
      final respuestaHistorial = respuestas[1];

      if (respuestaResumen.statusCode != 200 ||
          respuestaHistorial.statusCode != 200) {
        throw Exception('No se pudieron cargar los datos del tablero');
      }

      final resumen = jsonDecode(respuestaResumen.body);
      final historial = jsonDecode(respuestaHistorial.body);

      if (resumen is! Map || historial is! List) {
        throw Exception('La API devolvió información inválida');
      }

      final actividad = historial
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .take(5)
          .toList();

      if (!mounted) return;

      setState(() {
        _recaudacionHoy = _numero(resumen['recaudacionHoy']);
        _entradasHoy = _entero(resumen['entradasHoy']);
        _salidasHoy = _entero(resumen['salidasHoy']);
        _vehiculosDentro = _entero(resumen['vehiculosDentro']);
        _actividad = actividad;
        _capacidades = capacidades;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los datos del estacionamiento.';
      });
    }
  }

  double _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0;
  }

  int _entero(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
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

    return String.fromCharCode(36) + resultado.toString();
  }

  String _fechaHoy() {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final hoy = DateTime.now();
    return '${hoy.day} de ${meses[hoy.month - 1]}';
  }

  String _hora(dynamic valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '');
    if (fecha == null) return '-';

    final local = fecha.toLocal();
    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');
    return '$hora:$minuto';
  }

  Future<void> _abrirPantalla(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));

    if (mounted) {
      await _cargarDashboard();
    }
  }

  Future<void> _cerrarSesion() async {
    await ApiClient.cerrarSesion();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _abrirMenuCompleto() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.9,
            builder: (_, controlador) {
              return ListView(
                controller: controlador,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  const Text(
                    'Administración del estacionamiento',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Herramientas disponibles para este estacionamiento.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 14),
                  _opcionMenu(
                    icono: Icons.people_outline,
                    titulo: 'Usuarios y permisos',
                    subtitulo: 'Crear y administrar cajeros',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const UsersScreen());
                    },
                  ),
                  _opcionMenu(
                    icono: Icons.payments_outlined,
                    titulo: 'Tarifas',
                    subtitulo: 'Cambiar el valor por minuto',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const TarifasScreen());
                    },
                  ),
                  _opcionMenu(
                    icono: Icons.credit_card_outlined,
                    titulo: 'Suscripción y método de pago',
                    subtitulo: 'Plan, vencimiento y renovación automática',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const SuscripcionMetodoPagoScreen());
                    },
                  ),
                  _opcionMenu(
                    icono: Icons.print_outlined,
                    titulo: 'Impresora térmica',
                    subtitulo: 'Formato 58mm/80mm, automatización y pruebas',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const ConfiguracionImpresionScreen());
                    },
                  ),
                  _opcionMenu(
                    icono: Icons.badge_outlined,
                    titulo: 'Abonados y convenios',
                    subtitulo: 'Planes mensuales, tarifas planas y vecinos',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const AbonadosScreen(puedeEditar: true));
                    },
                  ),
                  _opcionMenu(
                    icono: Icons.directions_car_outlined,
                    titulo: 'Vehículos dentro',
                    subtitulo: 'Ver operaciones actualmente activas',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const VehiculosDentroScreen());
                    },
                  ),
                  _opcionMenu(
                    icono: Icons.history_outlined,
                    titulo: 'Historial',
                    subtitulo: 'Consultar salidas y cobros registrados',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const HistorialScreen());
                    },
                  ),
                  if (_capacidades?.boletasPdf ?? false)
                    _opcionMenu(
                      icono: Icons.receipt_long_outlined,
                      titulo: 'Comprobantes',
                      subtitulo: 'Consultar y abrir comprobantes PDF',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _abrirPantalla(const BoletasScreen());
                      },
                    ),
                  if (_capacidades?.contabilidadAvanzada ?? false)
                    _opcionMenu(
                      icono: Icons.account_balance_wallet_outlined,
                      titulo: 'Contabilidad y analítica',
                      subtitulo: 'Ingresos, gráficos e indicadores Pro',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _abrirPantalla(const AnaliticaProScreen());
                      },
                    ),
                  if (_capacidades?.exportacionDatos ?? false)
                    _opcionMenu(
                      icono: Icons.file_download_outlined,
                      titulo: 'Informes y exportaciones',
                      subtitulo:
                          'Descargar o compartir la contabilidad en Excel',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _abrirPantalla(const ContabilidadScreen());
                      },
                    ),
                  if (_capacidades?.reportesPorCorreo ?? false)
                    _opcionMenu(
                      icono: Icons.schedule_send_outlined,
                      titulo: 'Informes por correo Pro',
                      subtitulo:
                          'Programar reportes contables en tu correo administrativo',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _abrirPantalla(const InformesProgramadosProScreen());
                      },
                    ),
                  _opcionMenu(
                    icono: Icons.edit_note_outlined,
                    titulo: 'Corregir operaciones',
                    subtitulo: 'Modificar o anular de forma auditada',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const ModificarScreen());
                    },
                  ),
                  _opcionMenu(
                    icono: Icons.manage_search_outlined,
                    titulo: 'Auditoría',
                    subtitulo: 'Ver quién modificó cada operación',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _abrirPantalla(const AuditoriaScreen());
                    },
                  ),
                  if (_capacidades?.cierreCaja ?? false)
                    _opcionMenu(
                      icono: Icons.point_of_sale_outlined,
                      titulo: 'Auditoría de cajeros Pro',
                      subtitulo:
                          'Turnos, cierres de caja y desempeño por cajero',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _abrirPantalla(const AuditoriaCajerosProScreen());
                      },
                    ),
                  if (_capacidades?.cierreCaja ?? false)
                    _opcionMenu(
                      icono: Icons.notification_important_outlined,
                      titulo: 'Alertas administrativas Pro',
                      subtitulo:
                          'Revisar diferencias de caja y cierres pendientes',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _abrirPantalla(const AlertasProScreen());
                      },
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _salirDeModoSoporte() async {
    await ApiClient.salirDeModoSoporte();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ParkControl',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (ApiClient.estaEnModoSoporte)
              const Text(
                'Modo Soporte SuperAdmin',
                style: TextStyle(fontSize: 11, color: Color(0xFFFFD54F)),
              ),
          ],
        ),
        actions: [
          if (ApiClient.estaEnModoSoporte)
            IconButton(
              tooltip: 'Salir del modo soporte',
              icon: const Icon(Icons.exit_to_app, color: Color(0xFFFFD54F)),
              onPressed: _salirDeModoSoporte,
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargarDashboard,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            onSelected: (valor) {
              if (valor == 'cerrar_sesion') {
                _cerrarSesion();
              }
            },
            itemBuilder: (_) => [
              if (ApiClient.estaEnModoSoporte)
                const PopupMenuItem(
                  value: 'salir_soporte',
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: Colors.orange),
                      SizedBox(width: 10),
                      Text('Salir a SuperAdmin'),
                    ],
                  ),
                ),
              const PopupMenuItem(
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
        onRefresh: _cargarDashboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (ApiClient.estaEnModoSoporte) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Color(0xFFF57F17)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modo Auditoría / Soporte Activo',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF57F17),
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Operando con permisos delegados de SuperAdmin. Las acciones quedan auditadas.',
                            style: TextStyle(
                              color: Color(0xFF5D4037),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: _salirDeModoSoporte,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFECB3),
                        foregroundColor: const Color(0xFFE65100),
                      ),
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              'Panel del estacionamiento',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Resumen operativo de hoy · ${_fechaHoy()}',
              style: const TextStyle(color: Colors.blueGrey),
            ),
            const IndicadorSincronizacionOffline(),
            const SizedBox(height: 20),
            if (_error != null) _mensajeError(),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 52),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _tarjetaRecaudacion(),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, restricciones) {
                  final ancho = restricciones.maxWidth;
                  final anchoTarjeta = ancho >= 700
                      ? (ancho - 24) / 3
                      : (ancho - 12) / 2;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _tarjetaIndicador(
                        ancho: anchoTarjeta,
                        titulo: 'Entradas',
                        valor: _entradasHoy.toString(),
                        icono: Icons.login_rounded,
                        color: const Color(0xFF1565FF),
                      ),
                      _tarjetaIndicador(
                        ancho: anchoTarjeta,
                        titulo: 'Salidas',
                        valor: _salidasHoy.toString(),
                        icono: Icons.logout_rounded,
                        color: const Color(0xFF168A4C),
                      ),
                      _tarjetaIndicador(
                        ancho: anchoTarjeta,
                        titulo: 'Vehículos dentro',
                        valor: _vehiculosDentro.toString(),
                        icono: Icons.local_parking_outlined,
                        color: const Color(0xFFF08A24),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 30),
              _tituloSeccion('Acciones rápidas'),
              const SizedBox(height: 12),
              _accionesRapidas(),
              const SizedBox(height: 30),
              _tituloSeccion('Actividad reciente'),
              const SizedBox(height: 12),
              _actividadReciente(),
              const SizedBox(height: 30),
              _tituloSeccion('Gestión del estacionamiento'),
              const SizedBox(height: 12),
              _opcionMenu(
                icono: Icons.people_outline,
                titulo: 'Usuarios y permisos',
                subtitulo: 'Administrar cajeros y sus accesos',
                onTap: () => _abrirPantalla(const UsersScreen()),
              ),
              _opcionMenu(
                icono: Icons.payments_outlined,
                titulo: 'Tarifas',
                subtitulo: 'Cambiar el cobro por minuto',
                onTap: () => _abrirPantalla(const TarifasScreen()),
              ),
              _opcionMenu(
                icono: Icons.bar_chart_outlined,
                titulo: 'Reportes',
                subtitulo: 'Revisar el resumen diario',
                onTap: () => _abrirPantalla(const ReportesScreen()),
              ),
              _opcionMenu(
                icono: Icons.manage_search_outlined,
                titulo: 'Auditoría',
                subtitulo: 'Revisar cambios y anulaciones',
                onTap: () => _abrirPantalla(const AuditoriaScreen()),
              ),
              _opcionMenu(
                icono: Icons.gavel_rounded,
                titulo: 'Gestión de Morosos y Multas',
                subtitulo: 'Vehículos con fuga, cobro de multas y reglas',
                onTap: () => _abrirPantalla(const MorosidadScreen()),
              ),
              if (_capacidades?.cierreCaja ?? false)
                _opcionMenu(
                  icono: Icons.point_of_sale_outlined,
                  titulo: 'Auditoría de cajeros Pro',
                  subtitulo: 'Turnos, cierres y trazabilidad de caja',
                  onTap: () =>
                      _abrirPantalla(const AuditoriaCajerosProScreen()),
                ),
              if (_capacidades?.cierreCaja ?? false)
                _opcionMenu(
                  icono: Icons.notification_important_outlined,
                  titulo: 'Alertas administrativas Pro',
                  subtitulo: 'Diferencias de caja y cierres pendientes',
                  onTap: () => _abrirPantalla(const AlertasProScreen()),
                ),
              const SizedBox(height: 22),
              _estadoApi(),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1565FF),
        unselectedItemColor: Colors.blueGrey,
        onTap: (indice) {
          switch (indice) {
            case 0:
              _cargarDashboard();
              break;
            case 1:
              _abrirPantalla(const VehiculosDentroScreen());
              break;
            case 2:
              _abrirPantalla(const ReportesScreen());
              break;
            case 3:
              _abrirMenuCompleto();
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_parking_outlined),
            label: 'Operación',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Reportes',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Más'),
        ],
      ),
    );
  }

  Widget _tarjetaRecaudacion() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2B52), Color(0xFF1E4D88)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recaudación de hoy',
                  style: TextStyle(color: Color(0xFFCCDCF4)),
                ),
                const SizedBox(height: 4),
                Text(
                  _pesos(_recaudacionHoy),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaIndicador({
    required double ancho,
    required String titulo,
    required String valor,
    required IconData icono,
    required Color color,
  }) {
    return SizedBox(
      width: ancho,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color),
            const SizedBox(height: 16),
            Text(
              valor,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172B4D),
              ),
            ),
            const SizedBox(height: 2),
            Text(titulo, style: const TextStyle(color: Colors.blueGrey)),
          ],
        ),
      ),
    );
  }

  Widget _tituloSeccion(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: Color(0xFF172B4D),
      ),
    );
  }

  Widget _accionesRapidas() {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final ancho = restricciones.maxWidth;
        final anchoBoton = ancho >= 620 ? (ancho - 24) / 3 : (ancho - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _accionRapida(
              ancho: anchoBoton,
              icono: Icons.local_parking_outlined,
              titulo: 'Vehículos dentro',
              color: const Color(0xFFF08A24),
              onTap: () => _abrirPantalla(const VehiculosDentroScreen()),
            ),
            _accionRapida(
              ancho: anchoBoton,
              icono: Icons.history_outlined,
              titulo: 'Historial',
              color: const Color(0xFF1565FF),
              onTap: () => _abrirPantalla(const HistorialScreen()),
            ),
            if (_capacidades?.boletasPdf ?? false)
              _accionRapida(
                ancho: anchoBoton,
                icono: Icons.receipt_long_outlined,
                titulo: 'Comprobantes',
                color: const Color(0xFF168A4C),
                onTap: () => _abrirPantalla(const BoletasScreen()),
              ),
            if (_capacidades?.contabilidadAvanzada ?? false)
              _accionRapida(
                ancho: anchoBoton,
                icono: Icons.insights_rounded,
                titulo: 'Rendimiento Pro',
                color: const Color(0xFF7B3FBB),
                onTap: () => _abrirPantalla(const AnaliticaProScreen()),
              ),
            _accionRapida(
              ancho: anchoBoton,
              icono: Icons.edit_note_outlined,
              titulo: 'Corregir operación',
              color: const Color(0xFFE05A47),
              onTap: () => _abrirPantalla(const ModificarScreen()),
            ),
          ],
        );
      },
    );
  }

  Widget _accionRapida({
    required double ancho,
    required IconData icono,
    required String titulo,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: ancho,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icono, color: color),
                const SizedBox(height: 14),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF172B4D),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actividadReciente() {
    if (_actividad.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            Icon(Icons.history_toggle_off, color: Colors.blueGrey, size: 38),
            SizedBox(height: 10),
            Text('Aún no hay salidas registradas para mostrar.'),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: _actividad.map((registro) {
          final patente = registro['patente']?.toString() ?? '-';
          final monto = _numero(registro['monto']);

          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8F7EF),
              child: Icon(
                Icons.directions_car_outlined,
                color: Color(0xFF168A4C),
              ),
            ),
            title: Text(
              patente,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text("Salida a las ${_hora(registro['horaSalida'])}"),
            trailing: Text(
              _pesos(monto),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF168A4C),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _opcionMenu({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEAF2FF),
          child: Icon(icono, color: const Color(0xFF1565FF)),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _mensajeError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!)),
          TextButton(
            onPressed: _cargarDashboard,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _estadoApi() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_done_outlined, color: Color(0xFF1565FF)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Los indicadores se actualizan con los datos reales almacenados en ParkControl.',
              style: TextStyle(color: Color(0xFF315B9B)),
            ),
          ),
        ],
      ),
    );
  }
}
