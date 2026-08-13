import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_dashboard.dart';
import 'cajero_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController =
      TextEditingController();

  final TextEditingController passwordController =
      TextEditingController();
Future<void> iniciarSesion() async {
  final email = emailController.text.trim();
  final password = passwordController.text.trim();

  // Acceso administrador
  if (email == 'admin@parkcontrol.cl' && password == '123456') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminDashboard(),
      ),
    );
    return;
  }

  // Buscar cajero en los usuarios guardados
  final prefs = await SharedPreferences.getInstance();
  final datos = prefs.getString('usuarios');

  if (datos != null) {
    final List<dynamic> usuarios = jsonDecode(datos);

    final usuarioEncontrado = usuarios.cast<Map<String, dynamic>?>().firstWhere(
      (usuario) =>
          usuario?['email'] == email &&
          usuario?['password'] == password,
      orElse: () => null,
    );

  if (usuarioEncontrado != null) {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) => CajeroDashboard(
        usuario: usuarioEncontrado,
      ),
    ),
  );
  return;
}
  }

  // Datos incorrectos
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Correo o contraseña incorrectos'),
    ),
  );
}

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061A36),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
            ),
            child: Column(
              children: [
                // LOGO
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.local_parking_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),

                const SizedBox(height: 24),

                // NOMBRE
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
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 45),

                // CORREO
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
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                  keyboardType:
                      TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText:
                        'ejemplo@parkcontrol.cl',
                    hintStyle: const TextStyle(
                      color: Colors.white54,
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor:
                        Colors.white.withOpacity(0.08),
                    enabledBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color:
                            Colors.white.withOpacity(0.15),
                      ),
                    ),
                    focusedBorder:
                        const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(
                        Radius.circular(12),
                      ),
                      borderSide: BorderSide(
                        color: Color(0xFF2979FF),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // CONTRASEÑA
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
                  obscureText: true,
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: const TextStyle(
                      color: Colors.white54,
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor:
                        Colors.white.withOpacity(0.08),
                    enabledBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color:
                            Colors.white.withOpacity(0.15),
                      ),
                    ),
                    focusedBorder:
                        const OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(
                        Radius.circular(12),
                      ),
                      borderSide: BorderSide(
                        color: Color(0xFF2979FF),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // RECORDAR SESIÓN
                Row(
                  children: [
                    Checkbox(
                      value: true,
                      onChanged: (_) {},
                      checkColor: Colors.white,
                      activeColor:
                          const Color(0xFF1565FF),
                    ),
                    const Text(
                      'Recordar sesión',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(
                          color: Color(0xFF64B5FF),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // INGRESAR
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: iniciarSesion,
                    style:
                        ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF1565FF),
                      foregroundColor:
                          Colors.white,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Ingresar',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 45),

                const Text(
                  'Versión 1.0.0',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}