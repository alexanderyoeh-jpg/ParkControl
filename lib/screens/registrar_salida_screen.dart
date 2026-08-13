 import 'dart:convert';

 import 'package:shared_preferences/shared_preferences.dart';
 import 'package:flutter/material.dart';

class RegistrarSalidaScreen extends StatefulWidget {
  const RegistrarSalidaScreen({super.key});

  @override
  State<RegistrarSalidaScreen> createState() =>
      _RegistrarSalidaScreenState();
}

class _RegistrarSalidaScreenState
    extends State<RegistrarSalidaScreen> {
  final TextEditingController patenteController =
      TextEditingController();
 
 bool vehiculoEncontrado = false;
 double montocalculado = 0;
  Map<String, dynamic>? vehiculoactual;
  @override
  void dispose() {
    patenteController.dispose();
    super.dispose();
  }

void buscarVehiculo() async {
  final patente =
      patenteController.text.trim().toUpperCase();

  if (patente.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ingresa una patente'),
      ),
    );
    return;
  }
 final prefs = await SharedPreferences.getInstance();

  final datosGuardados =
      prefs.getStringList('vehiculos_dentro') ?? [];
Map<String, dynamic>? vehiculoencontradoActual; 
  for (final dato in datosGuardados) {
  final vehiculo = jsonDecode(dato) as Map<String, dynamic>;

  if (vehiculo['patente'].toString().toUpperCase() == patente) {
      vehiculoencontradoActual =  vehiculo;
    break;
  }
}
   final encontrado = vehiculoencontradoActual != null;
       setState(() {
      vehiculoEncontrado = encontrado;
      vehiculoactual =
          vehiculoencontradoActual;
    });
    if (!encontrado) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se encontró el vehículo $patente'),
        ),
      );
      return;
       }
        
  

 

  }

  Future<void> registrarSalida() async {
  final patente = patenteController.text.trim().toUpperCase();

  if (patente.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ingresa una patente'),
      ),
    );
    return;
  }


 final prefs = await SharedPreferences.getInstance();

final datosGuardados =
    prefs.getStringList('vehiculos_dentro') ?? [];
final tarifaPorMinuto =
    prefs.getDouble('tarifa_por_minuto') ?? 38.0;
Map<String, dynamic>? vehiculoActual;

for (final dato in datosGuardados) {
  final vehiculo = jsonDecode(dato) as Map<String, dynamic>;

  if (vehiculo['patente'].toString().toUpperCase() == patente) {
    vehiculoActual = vehiculo;
    break;
  }
}

if (vehiculoActual == null) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('No se encontró el vehículo $patente'),
    ),
  );
  return;
}
final horaEntrada = DateTime.parse(
  vehiculoActual['horaEntrada'].toString(),
);

final horaSalida = DateTime.now();

final minutosEstacionado =
    horaSalida.difference(horaEntrada).inMinutes;
    final montoTotal =
    minutosEstacionado * tarifaPorMinuto;  
    final historial = prefs.getStringList('historial_salidas') ?? [];

final registroSalida = {
  'patente': patente,
  'tipo': vehiculoActual['tipo'],
  'color': vehiculoActual['color'],
  'horaEntrada': vehiculoActual['horaEntrada'],
  'horaSalida': horaSalida.toIso8601String(),
  'minutosEstacionado': minutosEstacionado,
  'tarifaPorMinuto': tarifaPorMinuto,
  'montoTotal': montoTotal,
};

historial.add(jsonEncode(registroSalida));

await prefs.setStringList(
  'historial_salidas',
  historial,
);
    setState(() {
  montocalculado = montoTotal;
});     

final datosActualizados = datosGuardados.where((dato) {
  final vehiculo = jsonDecode(dato) as Map<String, dynamic>;

  return vehiculo['patente'].toString().toUpperCase() != patente;
}).toList();

  await prefs.setStringList(
    'vehiculos_dentro',
    datosActualizados,
  );

  if (!mounted) return;

  setState(() {
    vehiculoEncontrado = false;
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Salida registrada para $patente'),
    ),
  );

  patenteController.clear();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Registrar salida',
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
              'Salida de vehículo',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Busca el vehículo mediante su patente.',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Patente',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: patenteController,
              textCapitalization:
                  TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Ejemplo: ABCD12',
                prefixIcon:
                    const Icon(Icons.directions_car),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: buscarVehiculo,
                icon: const Icon(Icons.search),
                label: const Text(
                  'Buscar vehículo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            if (vehiculoEncontrado) ...[
              const SizedBox(height: 24),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vehículo encontrado',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 16),

                      _dato(
                        'Patente',
                        patenteController.text
                            .trim()
                            .toUpperCase(),
                      ),

                      _dato(
                        'Tipo',
                        'Auto',
                      ),

                      _dato(
                        'Color',
                        'Blanco',
                      ),

                      _dato(
                        'Hora de entrada',
                        '18:35',
                      ),

                      const Divider(height: 24),

                      const Text(
                        'Monto a pagar',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 4),

                       Text(
                        '\$${montocalculado.toStringAsFixed(0)}',
                        style: const TextStyle(
                        fontSize: 28,
                    fontWeight: FontWeight.bold,
                          ),
                          ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: registrarSalida,
                          icon: const Icon(Icons.logout),
                          label: const Text(
                            'Registrar salida',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          style:
                              ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFD92D20),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dato(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
          Text(
            valor,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}