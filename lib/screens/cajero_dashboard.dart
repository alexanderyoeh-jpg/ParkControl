import 'package:flutter/material.dart';
import 'registrar_entrada_screen.dart';
import 'registrar_salida_screen.dart';
import 'historial_screen.dart';

class CajeroDashboard extends StatelessWidget {
  final Map<String, dynamic> usuario;

  const CajeroDashboard({
    super.key,
    required this.usuario,
  });

  @override
  Widget build(BuildContext context) {
    final bool puedeVerReportes =
        usuario['verReportes'] == true;

    final String nombre =
        usuario['nombre']?.toString() ?? 'Cajero';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Estacionamiento Central',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              'Hola, $nombre',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 4),

            const Text(
              'Resumen de operaciones',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 20),

            // ENTRADA
_accionPrincipal(
  context,
  icono: Icons.login,
  color: Colors.green,
  titulo: 'ENTRADA',
  subtitulo: 'Registrar vehículo',
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RegistrarEntradaScreen(),
      ),
    );
  },
),

            const SizedBox(height: 12),

            // SALIDA
            _accionPrincipal(
              context,
              icono: Icons.logout,
              color: Colors.red,
              titulo: 'SALIDA',
              subtitulo: 'Cobrar y retirar vehículo',
              onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const RegistrarSalidaScreen(),
    ),
  );
},
            ),

            const SizedBox(height: 12),

            // MODIFICAR
            _accionPrincipal(
              context,
              icono: Icons.key,
              color: Colors.orange,
              titulo: 'MODIFICAR',
              subtitulo: 'Corregir registros',
              onTap: () {
                _mensaje(context, 'Modificar registro');
              },
            ),

            const SizedBox(height: 24),

            const Text(
              'Resumen de hoy',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _resumen(
                    icono: Icons.directions_car,
                    titulo: '48',
                    subtitulo: 'Vehículos dentro',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _resumen(
                    icono: Icons.login,
                    titulo: '126',
                    subtitulo: 'Entradas hoy',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            const Text(
              'Accesos rápidos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF172B4D),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
               Expanded(
  child: _accesoRapido(
    context,
    Icons.history,
    'Historial',
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const HistorialScreen(),
        ),
      );
    },
  ),
),
                const SizedBox(width: 10),
                Expanded(
                  child: _accesoRapido(
                    context,
                    Icons.directions_car,
                    'Vehículos',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _accesoRapido(
                    context,
                    Icons.receipt_long,
                    'Boletas',
                  ),
                ),

                if (puedeVerReportes) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _accesoRapido(
                      context,
                      Icons.bar_chart,
                      'Reportes',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: const Color(0xFF0F5ED7),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'Vehículos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'Más',
          ),
        ],
      ),
    );
  }

  Widget _accionPrincipal(
    BuildContext context, {
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icono,
                  color: color,
                  size: 30,
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resumen({
    required IconData icono,
    required String titulo,
    required String subtitulo,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icono,
              color: const Color(0xFF0F5ED7),
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accesoRapido(
    BuildContext context,
    IconData icono,
    String titulo, {
    VoidCallback? onTap,    
   } ) { 
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap ?? () {
          _mensaje(context, titulo);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 16,

            horizontal: 8,
          ),
          child: Column(
            children: [
              Icon(
                icono,
                color: const Color(0xFF0F5ED7),
                size: 25,
              ),
              const SizedBox(height: 8),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mensaje(BuildContext context, String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$texto próximamente'),
      ),
    );
  }
}