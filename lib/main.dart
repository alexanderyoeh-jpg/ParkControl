import 'package:flutter/material.dart';

import 'services/api_client.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.inicializarSesion();
  runApp(const ParkControlApp());
}

class ParkControlApp extends StatelessWidget {
  const ParkControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ParkControl',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565FF)),
      ),
      home: const LoginScreen(),
    );
  }
}
