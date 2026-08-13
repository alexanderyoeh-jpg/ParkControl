import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegistrarEntradaScreen extends StatefulWidget {
  const RegistrarEntradaScreen({super.key});

  @override
  State<RegistrarEntradaScreen> createState() =>
      _RegistrarEntradaScreenState();
}

class _RegistrarEntradaScreenState
    extends State<RegistrarEntradaScreen> {
  final TextEditingController patenteController =
      TextEditingController();

  final TextEditingController colorController =
      TextEditingController();

  final TextEditingController observacionController =
      TextEditingController();

  String tipoVehiculo = 'Auto';

  @override
  void dispose() {
    patenteController.dispose();
    colorController.dispose();
    observacionController.dispose();
    super.dispose();
  }

  Future<void> registrarEntrada() async {
  final patente =
      patenteController.text.trim().toUpperCase();

  if (patente.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ingresa la patente del vehículo'),
      ),
    );
    return;
  }

  final prefs = await SharedPreferences.getInstance();

  final datosGuardados =
      prefs.getStringList('vehiculos_dentro') ?? [];
      // Verificar si la patente ya está dentro del estacionamiento
for (final data in datosGuardados) {
  final vehiculoExistente =
      jsonDecode(data) as Map<String, dynamic>;

  final patenteExistente =
      vehiculoExistente['patente']
          .toString()
          .trim()
          .toUpperCase();

  if (patenteExistente == patente) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Esta patente ya se encuentra dentro del estacionamiento',
        ),
      ),
    );

    return;
  }
}

  final vehiculo = {
    'patente': patente,
    'tipo': tipoVehiculo,
    'color': colorController.text.trim(),
    'observacion': observacionController.text.trim(),
    'horaEntrada': DateTime.now().toIso8601String(),
  };

  datosGuardados.add(jsonEncode(vehiculo));

  await prefs.setStringList(
    'vehiculos_dentro',
    datosGuardados,
  );

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Entrada registrada para $patente',
      ),
    ),
  );

  patenteController.clear();
  colorController.clear();
  observacionController.clear();

  setState(() {
    tipoVehiculo = 'Auto';
  });
}
  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();

    final fecha =
        '${ahora.day.toString().padLeft(2, '0')}/'
        '${ahora.month.toString().padLeft(2, '0')}/'
        '${ahora.year}';

    final hora =
        '${ahora.hour.toString().padLeft(2, '0')}:'
        '${ahora.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Registrar entrada',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Text(
              'Ingreso de vehículo',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Completa los datos para registrar la entrada.',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Patente *',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: patenteController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'ABCD12',
                prefixIcon: const Icon(Icons.directions_car),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Tipo de vehículo *',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              initialValue: tipoVehiculo,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Auto',
                  child: Text('Auto'),
                ),
                DropdownMenuItem(
                  value: 'Moto',
                  child: Text('Moto'),
                ),
                DropdownMenuItem(
                  value: 'Camioneta',
                  child: Text('Camioneta'),
                ),
                DropdownMenuItem(
                  value: 'Camión',
                  child: Text('Camión'),
                ),
              ],
              onChanged: (valor) {
                if (valor != null) {
                  setState(() {
                    tipoVehiculo = valor;
                  });
                }
              },
            ),

            const SizedBox(height: 18),

            const Text(
              'Color (opcional)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: colorController,
              decoration: InputDecoration(
                hintText: 'Blanco',
                prefixIcon: const Icon(Icons.palette_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Observación (opcional)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: observacionController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Ej.: Cliente habitual',
                prefixIcon: const Icon(Icons.notes),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 22),

            const Text(
              'Fecha y hora de ingreso',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    readOnly: true,
                    controller: TextEditingController(
                      text: fecha,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.calendar_today_outlined,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: TextField(
                    readOnly: true,
                    controller: TextEditingController(
                      text: hora,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.access_time,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: registrarEntrada,
                icon: const Icon(Icons.login),
                label: const Text(
                  'Registrar entrada',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF20B46A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F7EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF20B46A),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Verifica la patente antes de registrar.',
                      style: TextStyle(
                        color: Color(0xFF26734D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}