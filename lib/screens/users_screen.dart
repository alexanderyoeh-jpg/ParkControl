import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:parkcontrol/config/api_config.dart';
import 'package:parkcontrol/services/api_client.dart';

import 'users_detail_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> usuarios = [];
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    cargarUsuarios();
  }

  Future<void> cargarUsuarios() async {
    setState(() {
      cargando = true;
      error = null;
    });

    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/api/usuarios'),
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          cargando = false;
          error = ApiClient.extraerMensajeError(
            response,
            mensajePredeterminado: 'No se pudieron cargar los usuarios',
          );
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        if (!mounted) return;
        setState(() {
          cargando = false;
          error = 'Respuesta inesperada del servidor';
        });
        return;
      }

      final lista = decoded.map<Map<String, dynamic>>((item) {
        return Map<String, dynamic>.from(item as Map);
      }).toList();

      if (!mounted) return;
      setState(() {
        usuarios = lista;
        cargando = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        cargando = false;
        error = 'No se pudo conectar con el servidor';
      });
    }
  }

  Future<void> abrirCrearUsuario() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const UserDetailScreen(usuario: null),
      ),
    );

    if (resultado == true) {
      cargarUsuarios();
    }
  }

  Future<void> abrirEditarUsuario(Map<String, dynamic> usuario) async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailScreen(usuario: usuario),
      ),
    );

    if (resultado == true) {
      cargarUsuarios();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: cargarUsuarios,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: abrirCrearUsuario,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo usuario'),
      ),
      body: Builder(
        builder: (context) {
          if (cargando) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: cargarUsuarios,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (usuarios.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.people_outline,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No hay usuarios adicionales registrados',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: abrirCrearUsuario,
                      icon: const Icon(Icons.add),
                      label: const Text('Registrar primer cajero'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: usuarios.length,
            itemBuilder: (context, index) {
              final usuario = usuarios[index];
              final rol = usuario['rol']?.toString().toLowerCase() ?? 'cajero';
              final esAdmin = rol == 'admin' || rol == 'admin_estacionamiento';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: esAdmin
                        ? Colors.indigo.shade100
                        : Colors.blue.shade100,
                    child: Icon(
                      esAdmin ? Icons.admin_panel_settings : Icons.person,
                      color: esAdmin
                          ? Colors.indigo.shade900
                          : Colors.blue.shade900,
                    ),
                  ),
                  title: Text(
                    usuario['nombre']?.toString() ?? 'Sin nombre',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(usuario['email']?.toString() ?? ''),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: esAdmin
                                  ? Colors.indigo.shade50
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: esAdmin
                                    ? Colors.indigo.shade300
                                    : Colors.blue.shade300,
                              ),
                            ),
                            child: Text(
                              esAdmin ? 'Administrador' : 'Cajero',
                              style: TextStyle(
                                fontSize: 12,
                                color: esAdmin
                                    ? Colors.indigo.shade800
                                    : Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => abrirEditarUsuario(usuario),
                ),
              );
            },
          );
        },
      ),
    );
  }
}