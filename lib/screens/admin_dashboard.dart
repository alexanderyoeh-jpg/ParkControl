import 'package:flutter/material.dart';
import 'package:parkcontrol/screens/users_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tarifas_screen.dart';
import 'reportes_screen.dart';
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Map<String, dynamic>? usuarioGuardado;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: const Color(0xFF061A36),
        foregroundColor: Colors.white,
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
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
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ESTACIONAMIENTO
            const Text(
              'Estacionamiento Central',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Resumen de operaciones',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 24),

            // RECAUDACIÓN
            _tarjetaEstadistica(
              titulo: 'Recaudación de hoy',
              valor: '\$352.600',
              icono: Icons.attach_money,
            ),

            const SizedBox(height: 12),

            // ENTRADAS Y SALIDAS
            Row(
              children: [
                Expanded(
                  child: _tarjetaEstadistica(
                    titulo: 'Entradas',
                    valor: '126',
                    icono: Icons.login,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: _tarjetaEstadistica(
                    titulo: 'Salidas',
                    valor: '118',
                    icono: Icons.logout,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // VEHÍCULOS DENTRO
            _tarjetaEstadistica(
              titulo: 'Vehículos dentro',
              valor: '48',
              icono: Icons.directions_car,
            ),

            const SizedBox(height: 28),

            const Text(
              'Administración',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 14),

            _opcionMenu(
              icono: Icons.people_outline,
              titulo: 'Usuarios y permisos',
              subtitulo: 'Administrar cajeros',
          onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const UsersScreen(),
    ),
  );
   }, 
 ),           
 _opcionMenu(
              icono: Icons.attach_money,
              titulo: 'Tarifas',
              subtitulo: 'Modificar valores y minutos',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TarifasScreen(),
                  ),
                );
              },
            ),

            _opcionMenu(
              icono: Icons.bar_chart,
              titulo: 'Reportes',
              subtitulo: 'Consultar ingresos y operaciones',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ReportesScreen(),
                  ),
                );
              },
            ),

            _opcionMenu(
              icono: Icons.settings_outlined,
              titulo: 'Configuración',
              subtitulo: 'Configurar estacionamiento',
              onTap: () {},
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Reportes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Alertas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'Más',
          ),
        ],
      ),
    );
  }

  Widget _tarjetaEstadistica({
    required String titulo,
    required String valor,
    required IconData icono,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,

            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(12),
            ),

            child: Icon(
              icono,
              color: const Color(0xFF1565FF),
            ),
          ),

          const SizedBox(width: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                valor,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _opcionMenu({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,

      child: ListTile(
        onTap: onTap,

        leading: Icon(
          icono,
          color: const Color(0xFF1565FF),
        ),

        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),

        subtitle: Text(subtitulo),

        trailing: const Icon(
          Icons.chevron_right,
        ),
      ),
    );
  }
}