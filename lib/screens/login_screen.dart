import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';
import '../services/superadmin_service.dart';
import '../services/actualizacion_service.dart';
import '../widgets/modal_descargas.dart';
import 'admin_dashboard.dart';
import 'cajero_dashboard.dart';
import 'configurar_superadmin_screen.dart';
import 'superadmin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  bool cargando = false;
  bool ocultarPassword = true;
  bool verificandoConfiguracion = true;
  bool requiereConfiguracion = false;

  @override
  void initState() {
    super.initState();
    verificarConfiguracionInicial();
    _verificarActualizacionesApp();
  }

  Future<void> _verificarActualizacionesApp() async {
    try {
      final info = await const ActualizacionService().consultarUltimaVersion();
      if (info != null && const ActualizacionService().hayNuevaVersion(info)) {
        if (!mounted) return;
        _mostrarDialogoActualizacion(info);
      }
    } catch (_) {}
  }

  void _mostrarDialogoActualizacion(InfoVersion info) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: Color(0xFF0F5ED7)),
            SizedBox(width: 10),
            Text('Actualización disponible'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hay una nueva versión de ParkControl (v${info.version}) lista con mejoras.',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            if (info.novedades.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Novedades:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              ...info.novedades.map((n) => Text('• $n', style: const TextStyle(fontSize: 12, color: Colors.black87))),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Más tarde'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F5ED7)),
            onPressed: () {
              Navigator.pop(ctx);
              ModalDescargas.mostrar(context);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Actualizar Ahora'),
          ),
        ],
      ),
    );
  }

  Future<void> verificarConfiguracionInicial() async {
    try {
      final requiere = await const SuperAdminService()
          .requiereConfiguracionInicial();

      if (!mounted) return;
      setState(() {
        requiereConfiguracion = requiere;
        verificandoConfiguracion = false;
      });
    } catch (_) {
      // Conserva el acceso normal si el backend todavía no expone la ruta de
      // configuración o está temporalmente sin conexión.
      if (!mounted) return;
      setState(() {
        requiereConfiguracion = false;
        verificandoConfiguracion = false;
      });
    }
  }

  // ============================================================
  // INICIAR SESIÓN
  // ============================================================

  Future<void> iniciarSesion() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    // Validar campos
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa correo y contraseña')),
      );
      return;
    }

    setState(() {
      cargando = true;
    });

    try {
      final response = await ApiClient.postPublico(
        Uri.parse('${ApiConfig.baseUrl}/api/login'),
        body: jsonEncode({'email': email, 'password': password}),
      );

      final decoded = jsonDecode(response.body);
      final result = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};

      // ========================================================
      // LOGIN CORRECTO
      // ========================================================

      if (response.statusCode == 200) {
        final usuario = Map<String, dynamic>.from(result['usuario']);

        final token = result['token']?.toString().trim();

        if (token == null || token.isEmpty) {
          throw Exception('La API no entregó una sesión válida');
        }

        final usuarioId = _enteroPositivo(usuario['id']);
        final estacionamientoId = _enteroPositivo(usuario['estacionamientoId']);
        final rol = usuario['rol']?.toString();

        if (usuarioId == null ||
            (rol != 'superadmin' && estacionamientoId == null)) {
          throw Exception('La API no entregó el contexto de sesión completo');
        }

        await ApiClient.guardarSesion(
          token: token,
          usuarioId: usuarioId,
          estacionamientoId: estacionamientoId,
        );

        if (!mounted) return;

        setState(() {
          cargando = false;
        });

        // ======================================================
        // ADMINISTRADOR
        // ======================================================

        if (usuario['rol'] == 'admin' ||
            usuario['rol'] == 'admin_estacionamiento') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminDashboard()),
          );

          return;
        }

        // ======================================================
        // SUPERADMINISTRADOR
        // ======================================================

        if (usuario['rol'] == 'superadmin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SuperAdminDashboard(),
            ),
          );

          return;
        }

        // ======================================================
        // CAJERO
        // ======================================================

        if (usuario['rol'] == 'cajero') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => CajeroDashboard(usuario: usuario),
            ),
          );

          return;
        }

        // ======================================================
        // ROL NO RECONOCIDO
        // ======================================================

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El usuario no tiene un rol válido')),
        );

        return;
      }

      // ========================================================
      // DATOS FALTANTES
      // ========================================================

      if (response.statusCode == 400) {
        if (!mounted) return;

        setState(() {
          cargando = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['mensaje'] ?? 'Email y contraseña son obligatorios',
            ),
          ),
        );

        return;
      }

      // ========================================================
      // CREDENCIALES INCORRECTAS
      // ========================================================

      if (response.statusCode == 401) {
        if (!mounted) return;

        setState(() {
          cargando = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['mensaje'] ?? 'Correo o contraseña incorrectos',
            ),
          ),
        );

        return;
      }

      // ========================================================
      // CUENTA SUSPENDIDA O SIN AUTORIZACIÓN
      // ========================================================

      if (response.statusCode == 403) {
        if (!mounted) return;

        setState(() {
          cargando = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(
              result['mensaje'] ??
                  'La cuenta está suspendida o no tiene autorización.',
            ),
          ),
        );

        return;
      }

      // ========================================================
      // OTRO ERROR DEL SERVIDOR
      // ========================================================

      if (!mounted) return;

      setState(() {
        cargando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['mensaje']?.toString() ?? 'Error inesperado del servidor',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        cargando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar con la API')),
      );
    }
  }

  // ============================================================
  // LIBERAR CONTROLADORES
  // ============================================================

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    super.dispose();
  }

  // ============================================================
  // INTERFAZ
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (verificandoConfiguracion) {
      return const Scaffold(
        backgroundColor: Color(0xFF061A36),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (requiereConfiguracion) {
      return ConfigurarSuperAdminScreen(
        onConfigurado: () {
          if (!mounted) return;
          setState(() => requiereConfiguracion = false);
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF061A36),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                // =================================================
                // LOGO
                // =================================================
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.local_parking_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),

                const SizedBox(height: 24),

                // =================================================
                // NOMBRE
                // =================================================
                const Text(
                  'ParkControl',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Gestión inteligente de estacionamientos',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),

                const SizedBox(height: 45),

                // =================================================
                // CORREO
                // =================================================
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Correo electrónico',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'ejemplo@parkcontrol.cl',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(
                        color: Color(0xFF2979FF),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // =================================================
                // CONTRASEÑA
                // =================================================
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Contraseña',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                TextField(
                  controller: passwordController,
                  obscureText: ocultarPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.white70,
                    ),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          ocultarPassword = !ocultarPassword;
                        });
                      },
                      icon: Icon(
                        ocultarPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.white70,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(
                        color: Color(0xFF2979FF),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: Colors.white54),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Por seguridad, la sesión se cierra al salir de la aplicación.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // =================================================
                // BOTÓN INGRESAR
                // =================================================
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: cargando ? null : iniciarSesion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565FF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFF1565FF,
                      ).withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: cargando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Ingresar',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                // =================================================
                // SECCIÓN DESCARGA DIRECTA INTELIGENTE
                // =================================================
                _seccionDescargaDirecta(context),

                const SizedBox(height: 25),

                // =================================================
                // VERSIÓN
                // =================================================
                InkWell(
                  onTap: () => ModalDescargas.mostrar(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Versión 1.0.0 (Oficial)',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seccionDescargaDirecta(BuildContext context) {
    final bool esAndroid = defaultTargetPlatform == TargetPlatform.android;
    final bool esIos = defaultTargetPlatform == TargetPlatform.iOS;
    final bool esWindows = defaultTargetPlatform == TargetPlatform.windows;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.install_mobile_rounded, color: Color(0xFF3DDC84), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Descargar la App oficial',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2979FF).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Modo Offline', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Botón principal según dispositivo detectado
          if (esAndroid)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3DDC84),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _descargar('https://api.neatspace.cl/downloads/parkcontrol.apk'),
              icon: const Icon(Icons.android, size: 20),
              label: const Text('Descargar APK para Android', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else if (esIos)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => ModalDescargas.mostrar(context),
              icon: const Icon(Icons.apple, size: 20),
              label: const Text('Instalar en iPhone / iPad (PWA)', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else if (esWindows)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0078D4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _descargar('https://api.neatspace.cl/downloads/parkcontrol-windows.zip'),
              icon: const Icon(Icons.desktop_windows, size: 20),
              label: const Text('Descargar para Windows (PC)', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3DDC84),
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _descargar('https://api.neatspace.cl/downloads/parkcontrol.apk'),
              icon: const Icon(Icons.android, size: 20),
              label: const Text('Descargar APK para Android', style: TextStyle(fontWeight: FontWeight.bold)),
            ),

          const SizedBox(height: 8),

          // Enlaces directos a todas las plataformas
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact),
                onPressed: () => _descargar('https://api.neatspace.cl/downloads/parkcontrol.apk'),
                icon: const Icon(Icons.android, size: 14, color: Color(0xFF3DDC84)),
                label: const Text('APK Android', style: TextStyle(fontSize: 11)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact),
                onPressed: () => _descargar('https://api.neatspace.cl/downloads/parkcontrol-windows.zip'),
                icon: const Icon(Icons.desktop_windows, size: 14, color: Color(0xFF0078D4)),
                label: const Text('Windows PC', style: TextStyle(fontSize: 11)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact),
                onPressed: () => ModalDescargas.mostrar(context),
                icon: const Icon(Icons.apple, size: 14),
                label: const Text('iOS (Safari)', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _descargar(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static int? _enteroPositivo(Object? valor) {
    final entero = valor is int
        ? valor
        : int.tryParse(valor?.toString().trim() ?? '');
    return entero != null && entero > 0 ? entero : null;
  }
}
