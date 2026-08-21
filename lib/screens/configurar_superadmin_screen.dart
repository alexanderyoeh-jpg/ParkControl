import 'package:flutter/material.dart';

import '../services/superadmin_service.dart';

class ConfigurarSuperAdminScreen extends StatefulWidget {
  const ConfigurarSuperAdminScreen({super.key, required this.onConfigurado});

  final VoidCallback onConfigurado;

  @override
  State<ConfigurarSuperAdminScreen> createState() =>
      _ConfigurarSuperAdminScreenState();
}

class _ConfigurarSuperAdminScreenState
    extends State<ConfigurarSuperAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _claveConfiguracionController = TextEditingController();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _servicio = const SuperAdminService();

  bool _guardando = false;
  bool _ocultarPassword = true;
  bool _ocultarConfirmacion = true;

  @override
  void dispose() {
    _claveConfiguracionController.dispose();
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _configurar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      await _servicio.configurarSuperAdmin(
        nombre: _nombreController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
        claveConfiguracion: _claveConfiguracionController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF168A4C),
          content: Text('SuperAdministrador creado. Ya puedes iniciar sesión.'),
        ),
      );

      widget.onConfigurado();
    } on ApiSuperAdminException catch (error) {
      if (!mounted) return;
      _mostrarError(error.mensaje);
    } catch (_) {
      if (!mounted) return;
      _mostrarError('No se pudo conectar con la API de ParkControl.');
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade700, content: Text(mensaje)),
      );
  }

  String? _validarPassword(String? valor) {
    final password = valor ?? '';
    if (password.length < 12) {
      return 'Usa al menos 12 caracteres';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Incluye mayúscula, minúscula y número';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                elevation: 2,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      color: const Color(0xFF0F2B52),
                      child: const Column(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: Color(0xFF1565FF),
                            child: Icon(
                              Icons.admin_panel_settings_outlined,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Configurar ParkControl',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            'Crea la cuenta propietaria que administrará a todos los futuros clientes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _AvisoSeguridad(),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _claveConfiguracionController,
                              textCapitalization: TextCapitalization.characters,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'Código de configuración',
                                helperText:
                                    'Aparece al iniciar el servidor y permanece válido hasta crear tu cuenta.',
                                prefixIcon: Icon(Icons.key_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (valor) =>
                                  (valor ?? '').trim().length < 8
                                  ? 'Ingresa el código mostrado por el servidor'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nombreController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Tu nombre',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                              validator: (valor) {
                                if ((valor ?? '').trim().length < 3) {
                                  return 'Ingresa tu nombre';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Correo del propietario',
                                prefixIcon: Icon(Icons.email_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: (valor) {
                                final email = (valor ?? '').trim();
                                if (!RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(email)) {
                                  return 'Ingresa un correo válido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _ocultarPassword,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: 'Contraseña segura',
                                helperText:
                                    'Mínimo 12 caracteres, con mayúscula, minúscula y número.',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _ocultarPassword = !_ocultarPassword,
                                  ),
                                  icon: Icon(
                                    _ocultarPassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              validator: _validarPassword,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmarController,
                              obscureText: _ocultarConfirmacion,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: 'Confirmar contraseña',
                                prefixIcon: const Icon(
                                  Icons.verified_user_outlined,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _ocultarConfirmacion =
                                        !_ocultarConfirmacion,
                                  ),
                                  icon: Icon(
                                    _ocultarConfirmacion
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (valor) {
                                if (valor != _passwordController.text) {
                                  return 'Las contraseñas no coinciden';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) {
                                if (!_guardando) _configurar();
                              },
                            ),
                            const SizedBox(height: 26),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: _guardando ? null : _configurar,
                                icon: _guardando
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.shield_outlined),
                                label: Text(
                                  _guardando
                                      ? 'Creando cuenta...'
                                      : 'Crear cuenta propietaria',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvisoSeguridad extends StatelessWidget {
  const _AvisoSeguridad();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xFF1565FF)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Esta configuración solo se permite una vez. El código temporal evita que otra persona reclame la cuenta propietaria.',
              style: TextStyle(color: Color(0xFF173E78), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
