class AdministradorCliente {
  const AdministradorCliente({
    required this.id,
    required this.nombre,
    required this.email,
    this.activo = true,
  });

  final int id;
  final String nombre;
  final String email;
  final bool activo;

  factory AdministradorCliente.fromJson(Map<String, dynamic> json) {
    return AdministradorCliente(
      id: _entero(json['id'] ?? json['usuarioId']),
      nombre: _texto(json['nombre']),
      email: _texto(json['email']),
      activo: _booleano(json['activo'] ?? json['estado'], valorInicial: true),
    );
  }
}

class ClienteParkControl {
  const ClienteParkControl({
    required this.id,
    required this.nombre,
    required this.estado,
    this.codigo = '',
    this.razonSocial = '',
    this.rut = '',
    this.email = '',
    this.telefono = '',
    this.direccion = '',
    this.plan = 'LITE',
    this.fechaInicio,
    this.fechaVencimiento,
    this.fechaUltimoPago,
    this.referenciaPago = '',
    this.observacion = '',
    this.estadoComercial = '',
    this.zonaHoraria = 'America/Santiago',
    this.motivoSuspension = '',
    this.totalUsuarios = 0,
    this.tarjetaMarca = '',
    this.tarjetaUltimos4 = '',
    this.renovacionAutomatica = false,
    this.administradores = const [],
    this.pagos = const [],
  });

  final int id;
  final String codigo;
  final String nombre;
  final String razonSocial;
  final String rut;
  final String email;
  final String telefono;
  final String direccion;
  final String plan;
  final String estado;
  final DateTime? fechaInicio;
  final DateTime? fechaVencimiento;
  final DateTime? fechaUltimoPago;
  final String referenciaPago;
  final String observacion;
  final String estadoComercial;
  final String zonaHoraria;
  final String motivoSuspension;
  final int totalUsuarios;
  final String tarjetaMarca;
  final String tarjetaUltimos4;
  final bool renovacionAutomatica;
  final List<AdministradorCliente> administradores;
  final List<Map<String, dynamic>> pagos;

  bool get tieneTarjetaAsociada =>
      tarjetaUltimos4.isNotEmpty && tarjetaMarca.isNotEmpty;

  bool get estaActivo => estado.toLowerCase() == 'activo';

  bool get estaSuspendido => estado.toLowerCase() == 'suspendido';

  bool get estaVencido {
    final vencimiento = fechaVencimiento;
    if (vencimiento == null) return false;

    final hoy = DateTime.now();
    final fechaHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final fechaLimite = DateTime(
      vencimiento.year,
      vencimiento.month,
      vencimiento.day,
    );

    return fechaLimite.isBefore(fechaHoy);
  }

  bool get estaPorVencer {
    final vencimiento = fechaVencimiento;
    if (vencimiento == null || estaVencido) return false;

    final hoy = DateTime.now();
    final fechaHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final fechaLimite = DateTime(
      vencimiento.year,
      vencimiento.month,
      vencimiento.day,
    );

    return fechaLimite.difference(fechaHoy).inDays <= 7;
  }

  AdministradorCliente? get administradorPrincipal {
    if (administradores.isEmpty) return null;
    return administradores.first;
  }

  factory ClienteParkControl.fromJson(Map<String, dynamic> json) {
    final administradoresJson = json['administradores'];
    final administradorJson =
        json['administrador'] ?? json['administradorPrincipal'];
    final administradores = <AdministradorCliente>[];

    if (administradoresJson is List) {
      administradores.addAll(
        administradoresJson.whereType<Map>().map(
          (item) =>
              AdministradorCliente.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
    } else if (administradorJson is Map) {
      administradores.add(
        AdministradorCliente.fromJson(
          Map<String, dynamic>.from(administradorJson),
        ),
      );
    }

    final suscripcion = json['suscripcionAutomatica'] is Map
        ? Map<String, dynamic>.from(json['suscripcionAutomatica'] as Map)
        : null;

    return ClienteParkControl(
      id: _entero(json['id'] ?? json['clienteId']),
      codigo: _texto(json['codigo']),
      nombre: _texto(json['nombre'] ?? json['nombreEstacionamiento']),
      razonSocial: _texto(json['razonSocial'] ?? json['razon_social']),
      rut: _texto(json['rut']),
      email: _texto(
        json['emailContacto'] ?? json['email'] ?? json['correoContacto'],
      ),
      telefono: _texto(json['telefono']),
      direccion: _texto(json['direccion']),
      plan: _texto(json['plan'], valorInicial: 'LITE'),
      estado: _texto(json['estado'], valorInicial: 'activo'),
      fechaInicio: _fecha(json['fechaInicio'] ?? json['fecha_inicio']),
      fechaVencimiento: _fecha(
        json['fechaVencimiento'] ?? json['fecha_vencimiento'],
      ),
      fechaUltimoPago: _fecha(
        json['fechaUltimoPago'] ?? json['fecha_ultimo_pago'],
      ),
      referenciaPago: _texto(json['referenciaPago'] ?? json['referencia_pago']),
      observacion: _texto(json['observacion']),
      estadoComercial: _texto(json['estadoComercial']),
      zonaHoraria: _texto(
        json['zonaHoraria'],
        valorInicial: 'America/Santiago',
      ),
      motivoSuspension: _texto(json['motivoSuspension']),
      totalUsuarios: _entero(json['totalUsuarios']),
      tarjetaMarca: _texto(suscripcion?['tarjetaMarca']),
      tarjetaUltimos4: _texto(suscripcion?['tarjetaUltimos4']),
      renovacionAutomatica: _booleano(
        suscripcion?['renovacionAutomatica'],
        valorInicial: false,
      ),
      administradores: administradores,
      pagos: json['pagos'] is List
          ? (json['pagos'] as List)
                .whereType<Map>()
                .map(Map<String, dynamic>.from)
                .toList()
          : const [],
    );
  }
}

int _entero(dynamic valor) {
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor?.toString() ?? '') ?? 0;
}

String _texto(dynamic valor, {String valorInicial = ''}) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? valorInicial : texto;
}

DateTime? _fecha(dynamic valor) {
  final texto = valor?.toString().trim() ?? '';
  if (texto.isEmpty) return null;

  // Inicio y vencimiento son fechas civiles, no instantes horarios. Leer sus
  // primeros componentes evita que la conversión UTC de Chile muestre el día
  // anterior y que una edición vaya descontando días.
  final calendario = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(texto);

  if (calendario != null) {
    return DateTime(
      int.parse(calendario.group(1)!),
      int.parse(calendario.group(2)!),
      int.parse(calendario.group(3)!),
    );
  }

  return DateTime.tryParse(texto)?.toLocal();
}

bool _booleano(dynamic valor, {required bool valorInicial}) {
  if (valor is bool) return valor;
  if (valor is num) return valor != 0;

  final texto = valor?.toString().toLowerCase().trim();
  if (texto == 'true' || texto == 'activo' || texto == '1') return true;
  if (texto == 'false' || texto == 'inactivo' || texto == '0') return false;
  return valorInicial;
}
