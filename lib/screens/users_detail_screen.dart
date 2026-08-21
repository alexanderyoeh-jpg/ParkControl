import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:parkcontrol/config/api_config.dart';
import 'package:parkcontrol/services/api_client.dart';

class UserDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? usuario;

  const UserDetailScreen({
    super.key,
    this.usuario,
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;

  late String rol;
  late bool registrarEntradas;
  late bool registrarSalidas;
  late bool verReportes;

  bool guardando = false;
  bool eliminando = false;

  bool get esNuevo => widget.usuario == null;

  @override
  void initState() {
    super.initState();

    final u = widget.usuario;
    nameController = TextEditingController(text: u?['nombre']?.toString() ?? '');
    emailController = TextEditingController(text: u?['email']?.toString() ?? '');
    passwordController = TextEditingController();

    rol = u?['rol']?.toString().toLowerCase() ?? 'cajero';
    if (rol != 'admin' && rol != 'cajero') {
      rol = 'cajero';
    }

    registrarEntradas = u?['registrarEntradas'] != false;
    registrarSalidas = u?['registrarSalidas'] != false;
    verReportes = u?['verReportes'] == true;
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      guardando = true;
    });

    final datos = <String, dynamic>{
      'nombre': nameController.text.trim(),
      'email': emailController.text.trim(),
      'rol': rol,
      'registrarEntradas': registrarEntradas,
      'registrarSalidas': registrarSalidas,
      'verReportes': verReportes,
    };

    final pass = passwordController.text;
    if (pass.isNotEmpty || esNuevo) {
      datos['password'] = pass;
    }

    try {
      final url = esNuevo
          ? Uri.parse('${ApiConfig.baseUrl}/api/usuarios')
          : Uri.parse('${ApiConfig.baseUrl}/api/usuarios/${widget.usuario!['id']}');

      final response = esNuevo
          ? await ApiClient.post(url, body: jsonEncode(datos))
          : await ApiClient.put(url, body: jsonEncode(datos));

      final statusEsperado = esNuevo ? 201 : 200;

      if (!mounted) return;

      if (response.statusCode != statusEsperado) {
        setState(() {
          guardando = false;
        });

        final mensajeError = ApiClient.extraerMensajeError(
          response,
          mensajePredeterminado: esNuevo
              ? 'No se pudo crear el usuario'
              : 'No se pudieron guardar los cambios',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensajeError),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            esNuevo
                ? 'Usuario creado exitosamente'
                : 'Usuario actualizado correctamente',
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        guardando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo conectar con el servidor'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> eliminar() async {
    if (esNuevo) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar usuario?'),
        content: Text(
          '¿Estás seguro de que deseas desactivar a ${nameController.text}? '
          'No podrá volver a ingresar al sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() {
      eliminando = true;
    });

    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/usuarios/${widget.usuario!['id']}',
      );
      final response = await ApiClient.delete(url);

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          eliminando = false;
        });

        final mensajeError = ApiClient.extraerMensajeError(
          response,
          mensajePredeterminado: 'No se pudo eliminar el usuario',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensajeError),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario desactivado correctamente')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        eliminando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo conectar con el servidor'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(esNuevo ? 'Nuevo usuario' : 'Editar usuario'),
        actions: [
          if (!esNuevo)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: 'Eliminar usuario',
              onPressed: eliminando || guardando ? null : eliminar,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              esNuevo ? 'Crear credenciales de acceso' : 'Modificar credenciales',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresa un nombre' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Ingresa un correo';
                }
                if (!v.contains('@') || !v.contains('.')) {
                  return 'Ingresa un correo válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: esNuevo
                    ? 'Contraseña (mínimo 6 caracteres)'
                    : 'Nueva contraseña (dejar en blanco para no cambiar)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
              ),
              validator: (v) {
                if (esNuevo && (v == null || v.length < 6)) {
                  return 'La contraseña debe tener al menos 6 caracteres';
                }
                if (!esNuevo && v != null && v.isNotEmpty && v.length < 6) {
                  return 'La contraseña debe tener al menos 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Rol en el estacionamiento',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'cajero',
                  label: Text('Cajero'),
                  icon: Icon(Icons.badge),
                ),
                ButtonSegment(
                  value: 'admin',
                  label: Text('Administrador'),
                  icon: Icon(Icons.admin_panel_settings),
                ),
              ],
              selected: {rol},
              onSelectionChanged: (nuevaSeleccion) {
                setState(() {
                  rol = nuevaSeleccion.first;
                  if (rol == 'admin') {
                    registrarEntradas = true;
                    registrarSalidas = true;
                    verReportes = true;
                  }
                });
              },
            ),
            const SizedBox(height: 24),
            if (rol == 'cajero') ...[
              const Text(
                'Permisos operativos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Registrar entradas'),
                value: registrarEntradas,
                onChanged: (val) => setState(() => registrarEntradas = val),
              ),
              SwitchListTile(
                title: const Text('Registrar salidas'),
                value: registrarSalidas,
                onChanged: (val) => setState(() => registrarSalidas = val),
              ),
              SwitchListTile(
                title: const Text('Ver reportes'),
                value: verReportes,
                onChanged: (val) => setState(() => verReportes = val),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: guardando || eliminando ? null : guardar,
                icon: guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  guardando
                      ? 'Guardando...'
                      : esNuevo
                          ? 'Crear usuario'
                          : 'Guardar cambios',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}