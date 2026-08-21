import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/impresion_config_service.dart';
import '../services/ticket_termico_service.dart';

class ConfiguracionImpresionScreen extends StatefulWidget {
  const ConfiguracionImpresionScreen({super.key});

  @override
  State<ConfiguracionImpresionScreen> createState() =>
      _ConfiguracionImpresionScreenState();
}

class _ConfiguracionImpresionScreenState
    extends State<ConfiguracionImpresionScreen> {
  bool _cargando = true;
  bool _guardando = false;
  bool _probando = false;

  List<Printer> _impresorasDisponibles = [];
  Printer? _impresoraSeleccionada;

  late AnchoPapelTermico _anchoPapel;
  late bool _entradaAuto;
  late bool _salidaAuto;
  late bool _codigoBarras;

  late TextEditingController _nombreEstController;
  late TextEditingController _encabezadoController;
  late TextEditingController _piePaginaController;

  @override
  void initState() {
    super.initState();
    _nombreEstController = TextEditingController();
    _encabezadoController = TextEditingController();
    _piePaginaController = TextEditingController();
    _cargar();
  }

  @override
  void dispose() {
    _nombreEstController.dispose();
    _encabezadoController.dispose();
    _piePaginaController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);

    try {
      final config = await ImpresionConfigService.obtenerConfiguracion();
      List<Printer> impresoras = [];

      try {
        impresoras = await Printing.listPrinters();
      } catch (e) {
        debugPrint('No se pudieron listar impresoras: $e');
      }

      Printer? seleccionada;
      if (config.impresoraUrl != null) {
        seleccionada = impresoras.cast<Printer?>().firstWhere(
              (p) => p?.url == config.impresoraUrl,
              orElse: () => null,
            );
      }
      seleccionada ??= impresoras.cast<Printer?>().firstWhere(
            (p) => p?.name == config.impresoraNombre,
            orElse: () => null,
          );

      if (!mounted) return;

      setState(() {
        _impresorasDisponibles = impresoras;
        _impresoraSeleccionada = seleccionada;
        _anchoPapel = config.anchoPapel;
        _entradaAuto = config.imprimirEntradaAutomatica;
        _salidaAuto = config.imprimirSalidaAutomatica;
        _codigoBarras = config.incluirCodigoBarras;

        _nombreEstController.text = config.nombreEstacionamiento;
        _encabezadoController.text = config.encabezadoPersonalizado;
        _piePaginaController.text = config.piePagina;

        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrarMensaje('Error al cargar la configuración de impresión', esError: true);
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);

    try {
      final nuevaConfig = ImpresionConfig(
        anchoPapel: _anchoPapel,
        imprimirEntradaAutomatica: _entradaAuto,
        imprimirSalidaAutomatica: _salidaAuto,
        nombreEstacionamiento: _nombreEstController.text.trim(),
        encabezadoPersonalizado: _encabezadoController.text.trim(),
        piePagina: _piePaginaController.text.trim(),
        impresoraNombre: _impresoraSeleccionada?.name,
        impresoraUrl: _impresoraSeleccionada?.url,
        incluirCodigoBarras: _codigoBarras,
      );

      await ImpresionConfigService.guardarConfiguracion(nuevaConfig);

      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarMensaje('Configuración de impresión guardada correctamente');
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarMensaje('Error al guardar la configuración', esError: true);
    }
  }

  Future<void> _probarImpresion() async {
    setState(() => _probando = true);

    try {
      await _guardar();
      await TicketTermicoService.imprimirTicketPrueba();

      if (!mounted) return;
      setState(() => _probando = false);
      _mostrarMensaje('Ticket de prueba enviado a la impresora');
    } catch (e) {
      if (!mounted) return;
      setState(() => _probando = false);
      _mostrarMensaje('No se pudo imprimir el ticket de prueba: $e', esError: true);
    }
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: esError ? Colors.red.shade700 : const Color(0xFF2E7D32),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B52),
        foregroundColor: Colors.white,
        title: const Text(
          'Configurar Impresora Térmica',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar impresoras',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _seccionImpresora(),
                  const SizedBox(height: 16),
                  _seccionFormato(),
                  const SizedBox(height: 16),
                  _seccionAutomatizacion(),
                  const SizedBox(height: 16),
                  _seccionTextos(),
                  const SizedBox(height: 24),
                  _botonesAccion(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _seccionImpresora() {
    return _TarjetaConfig(
      titulo: 'Impresora Térmica',
      icono: Icons.print_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selecciona la impresora térmica conectada (USB, Bluetooth, Red o Sistema):',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          if (_impresorasDisponibles.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFEEBA)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF856404), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No se detectaron impresoras directas. Se usará el diálogo nativo del sistema.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            DropdownButtonFormField<Printer?>(
              initialValue: _impresoraSeleccionada,
              decoration: const InputDecoration(
                labelText: 'Impresora Predeterminada',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print),
              ),
              items: [
                const DropdownMenuItem<Printer?>(
                  value: null,
                  child: Text('Diálogo del sistema (preguntar siempre)'),
                ),
                ..._impresorasDisponibles.map(
                  (p) => DropdownMenuItem<Printer?>(
                    value: p,
                    child: Text(
                      '${p.name} ${p.isDefault ? "(Predeterminada)" : ""}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (p) {
                setState(() => _impresoraSeleccionada = p);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _seccionFormato() {
    return _TarjetaConfig(
      titulo: 'Formato de Papel Térmico',
      icono: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ancho del rollo de la impresora:',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          SegmentedButton<AnchoPapelTermico>(
            segments: const [
              ButtonSegment(
                value: AnchoPapelTermico.mm58,
                label: Text('58 mm (POS portátil / común)'),
                icon: Icon(Icons.receipt),
              ),
              ButtonSegment(
                value: AnchoPapelTermico.mm80,
                label: Text('80 mm (Ancho grande)'),
                icon: Icon(Icons.feed),
              ),
            ],
            selected: {_anchoPapel},
            onSelectionChanged: (nueva) {
              setState(() => _anchoPapel = nueva.first);
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Incluir código de barras en ticket'),
            subtitle: const Text('Código Code128 para escanear patente a la salida'),
            value: _codigoBarras,
            onChanged: (v) => setState(() => _codigoBarras = v),
          ),
        ],
      ),
    );
  }

  Widget _seccionAutomatizacion() {
    return _TarjetaConfig(
      titulo: 'Automatización de Impresión',
      icono: Icons.bolt_outlined,
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Imprimir ticket al registrar ENTRADA'),
            subtitle: const Text('Emite el ticket de ingreso inmediatamente'),
            value: _entradaAuto,
            onChanged: (v) => setState(() => _entradaAuto = v),
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Imprimir comprobante al registrar SALIDA'),
            subtitle: const Text('Emite el comprobante de cobro al pagar'),
            value: _salidaAuto,
            onChanged: (v) => setState(() => _salidaAuto = v),
          ),
        ],
      ),
    );
  }

  Widget _seccionTextos() {
    return _TarjetaConfig(
      titulo: 'Contenido del Ticket',
      icono: Icons.edit_note_outlined,
      child: Column(
        children: [
          TextField(
            controller: _nombreEstController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del Estacionamiento',
              hintText: 'Ej.: Estacionamiento Central',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.store),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _encabezadoController,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Encabezado / Datos de contacto',
              hintText: 'RUT: 76.123.456-7 · Av. Providencia 1234 · Tel: +56 9 1234 5678',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _piePaginaController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Pie de página / Cláusula de responsabilidad',
              hintText: 'Conserve su ticket. No nos responsabilizamos por objetos de valor.',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.gavel_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonesAccion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F2B52),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _guardando ? null : _guardar,
          icon: const Icon(Icons.save),
          label: Text(_guardando ? 'Guardando...' : 'Guardar Configuración'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _probando ? null : _probarImpresion,
          icon: const Icon(Icons.print),
          label: Text(_probando ? 'Imprimiendo...' : 'Imprimir Ticket de Prueba'),
        ),
      ],
    );
  }
}

class _TarjetaConfig extends StatelessWidget {
  const _TarjetaConfig({
    required this.titulo,
    required this.icono,
    required this.child,
  });

  final String titulo;
  final IconData icono;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: const Color(0xFF0F2B52), size: 22),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F2B52),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
