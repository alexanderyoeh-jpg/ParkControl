import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TarifasScreen extends StatefulWidget {
  const TarifasScreen({super.key});

  @override
  State<TarifasScreen> createState() => _TarifasScreenState();
}

class _TarifasScreenState extends State<TarifasScreen> {
  final TextEditingController tarifaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    cargarTarifa();
  }

  Future<void> cargarTarifa() async {
    final prefs = await SharedPreferences.getInstance();

    final tarifa = prefs.getDouble('tarifa_por_minuto') ?? 38.0;

    tarifaController.text = tarifa.toStringAsFixed(0);
  }

  Future<void> guardarTarifa() async {
    final valor = double.tryParse(tarifaController.text.trim());

    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una tarifa válida'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble('tarifa_por_minuto', valor);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tarifa guardada: \$${valor.toStringAsFixed(0)} por minuto',
        ),
      ),
    );
  }

  @override
  void dispose() {
    tarifaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Tarifas',
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
              'Tarifa de estacionamiento',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Define cuánto se cobrará por cada minuto de estacionamiento.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 25),

            TextField(
              controller: tarifaController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Tarifa por minuto',
                prefixText: '\$ ',
                suffixText: ' CLP/min',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: guardarTarifa,
                icon: const Icon(Icons.save),
                label: const Text(
                  'Guardar tarifa',
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
          ],
        ),
      ),
    );
  }
}