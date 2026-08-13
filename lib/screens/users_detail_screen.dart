import 'package:flutter/material.dart';

class UserDetailScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;

  const UserDetailScreen({
    super.key,
    required this.usuario,
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;

  late bool registrarEntradas;
  late bool registrarSalidas;
  late bool verReportes;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.usuario['nombre']?.toString() ?? '',
    );

    emailController = TextEditingController(
      text: widget.usuario['email']?.toString() ?? '',
    );

    passwordController = TextEditingController(
      text: widget.usuario['password']?.toString() ?? '',
    );

    registrarEntradas =
        widget.usuario['registrarEntradas'] == true;

    registrarSalidas =
        widget.usuario['registrarSalidas'] == true;

    verReportes =
        widget.usuario['verReportes'] == true;
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos del usuario'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Información del cajero',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 24),

          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Permisos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          SwitchListTile(
            title: const Text('Registrar entradas'),
            value: registrarEntradas,
            onChanged: (value) {
              setState(() {
                registrarEntradas = value;
              });
            },
          ),

          SwitchListTile(
            title: const Text('Registrar salidas'),
            value: registrarSalidas,
            onChanged: (value) {
              setState(() {
                registrarSalidas = value;
              });
            },
          ),

          SwitchListTile(
            title: const Text('Ver reportes'),
            value: verReportes,
            onChanged: (value) {
              setState(() {
                verReportes = value;
              });
            },
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'nombre': nameController.text.trim(),
                  'email': emailController.text.trim(),
                  'password': passwordController.text,
                  'registrarEntradas': registrarEntradas,
                  'registrarSalidas': registrarSalidas,
                  'verReportes': verReportes,
                });
              },
              child: const Text(
                'Guardar cambios',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}