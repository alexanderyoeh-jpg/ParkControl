import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:parkcontrol/screens/users_detail_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> usuarios = [];

  @override
  void initState() {
    super.initState();
    cargarUsuarios();
  }

  Future<void> cargarUsuarios() async {
    final prefs = await SharedPreferences.getInstance();

    final datos = prefs.getString('usuarios');

    if (datos == null) {
      usuarios = [
        {
          'nombre': 'erick',
          'email': 'cajero@parkcontrol.cl',
          'password': '123456',
          'registrarEntradas': true,
          'registrarSalidas': true,
          'verReportes': false,
        }
      ];

      await guardarUsuarios();
    } else {
      final lista = jsonDecode(datos);

      usuarios = List<Map<String, dynamic>>.from(
        lista.map((usuario) => Map<String, dynamic>.from(usuario)),
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> guardarUsuarios() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'usuarios',
      jsonEncode(usuarios),
    );
  }

  Future<void> abrirDetalle(int indice) async {
    final resultado = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailScreen(
          usuario: usuarios[indice],
        ),
      ),
    );

    if (resultado != null) {
      setState(() {
        usuarios[indice] = resultado;
      });

      await guardarUsuarios();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios y permisos'),
      ),
      body: usuarios.isEmpty
          ? const Center(
              child: Text('No hay usuarios registrados'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: usuarios.length,
              itemBuilder: (context, index) {
                final usuario = usuarios[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    title: Text(
                      usuario['nombre'] ?? '',
                    ),
                    subtitle: Text(
                      usuario['email'] ?? '',
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                    ),
                    onTap: () => abrirDetalle(index),
                  ),
                );
              },
            ),
    );
  }
}