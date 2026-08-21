import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/cliente_parkcontrol.dart';
import 'api_client.dart';

class ApiSuperAdminException implements Exception {
  const ApiSuperAdminException(this.mensaje, {this.codigo});

  final String mensaje;
  final int? codigo;

  @override
  String toString() => mensaje;
}

class SuperAdminService {
  const SuperAdminService();

  static final String _baseUrl = ApiConfig.baseUrl;

  Future<bool> requiereConfiguracionInicial() async {
    final respuesta = await ApiClient.getPublico(
      Uri.parse('$_baseUrl/api/setup/estado'),
    );

    if (respuesta.statusCode != 200) {
      throw _errorDesdeRespuesta(
        respuesta,
        'No se pudo comprobar la configuración inicial.',
      );
    }

    final datos = _mapa(respuesta.body);

    if (datos['requiereConfiguracion'] is bool) {
      return datos['requiereConfiguracion'] == true;
    }

    if (datos['requiereSuperAdmin'] is bool) {
      return datos['requiereSuperAdmin'] == true;
    }

    if (datos['configurado'] is bool) {
      return datos['configurado'] != true;
    }

    if (datos['superAdminConfigurado'] is bool) {
      return datos['superAdminConfigurado'] != true;
    }

    return false;
  }

  Future<void> configurarSuperAdmin({
    required String nombre,
    required String email,
    required String password,
    required String claveConfiguracion,
  }) async {
    final respuesta = await ApiClient.postPublico(
      Uri.parse('$_baseUrl/api/setup/superadmin'),
      body: jsonEncode({
        'nombre': nombre,
        'email': email,
        'password': password,
        'claveConfiguracion': claveConfiguracion,
      }),
    );

    _aceptar(
      respuesta,
      codigos: const {200, 201},
      mensajeAlternativo: 'No se pudo crear el SuperAdministrador.',
    );
  }

  Future<Map<String, dynamic>> obtenerResumen() async {
    final respuesta = await ApiClient.get(
      Uri.parse('$_baseUrl/api/superadmin/resumen'),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo cargar el resumen general.',
    );

    final datos = _mapa(respuesta.body);
    final resumen = datos['resumen'];

    return resumen is Map ? Map<String, dynamic>.from(resumen) : datos;
  }

  Future<List<ClienteParkControl>> obtenerClientes() async {
    final respuesta = await ApiClient.get(
      Uri.parse('$_baseUrl/api/superadmin/clientes'),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo cargar la lista de clientes.',
    );

    final decoded = _decodificar(respuesta.body);
    final lista = decoded is List
        ? decoded
        : decoded is Map
        ? decoded['clientes']
        : null;

    if (lista is! List) return [];

    return lista
        .whereType<Map>()
        .map(
          (item) =>
              ClienteParkControl.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<ClienteParkControl> obtenerCliente(int id) async {
    final respuesta = await ApiClient.get(
      Uri.parse('$_baseUrl/api/superadmin/clientes/$id'),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo cargar el cliente.',
    );

    final datos = _mapa(respuesta.body);
    final cliente = _extraerEntidad(datos, 'cliente');

    if (datos['administradores'] is List) {
      cliente['administradores'] = datos['administradores'];
    }
    if (datos['pagos'] is List) {
      cliente['pagos'] = datos['pagos'];
    }

    return ClienteParkControl.fromJson(cliente);
  }

  Future<ClienteParkControl> crearCliente(Map<String, dynamic> datos) async {
    final respuesta = await ApiClient.post(
      Uri.parse('$_baseUrl/api/superadmin/clientes'),
      body: jsonEncode(datos),
    );

    _aceptar(
      respuesta,
      codigos: const {200, 201},
      mensajeAlternativo: 'No se pudo crear el cliente.',
    );

    return ClienteParkControl.fromJson(
      _extraerEntidad(_mapa(respuesta.body), 'cliente'),
    );
  }

  Future<ClienteParkControl> actualizarCliente(
    int id,
    Map<String, dynamic> datos,
  ) async {
    final respuesta = await ApiClient.put(
      Uri.parse('$_baseUrl/api/superadmin/clientes/$id'),
      body: jsonEncode(datos),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo actualizar el cliente.',
    );

    return ClienteParkControl.fromJson(
      _extraerEntidad(_mapa(respuesta.body), 'cliente'),
    );
  }

  Future<void> cambiarEstado({
    required int clienteId,
    required String estado,
    required String motivo,
  }) async {
    final respuesta = await ApiClient.patch(
      Uri.parse('$_baseUrl/api/superadmin/clientes/$clienteId/estado'),
      body: jsonEncode({'estado': estado, 'motivo': motivo}),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo cambiar el estado del cliente.',
    );
  }

  Future<String> registrarPago({
    required int clienteId,
    required Map<String, dynamic> datos,
  }) async {
    final respuesta = await ApiClient.post(
      Uri.parse('$_baseUrl/api/superadmin/clientes/$clienteId/pagos'),
      body: jsonEncode(datos),
    );

    _aceptar(
      respuesta,
      codigos: const {200, 201},
      mensajeAlternativo: 'No se pudo registrar el pago.',
    );

    final mensaje = _mapa(respuesta.body)['mensaje']?.toString().trim();
    return mensaje == null || mensaje.isEmpty
        ? 'Pago registrado correctamente.'
        : mensaje;
  }

  Future<String> anularPago({
    required int clienteId,
    required int pagoId,
    required String motivo,
  }) async {
    final respuesta = await ApiClient.post(
      Uri.parse(
        '$_baseUrl/api/superadmin/clientes/$clienteId/'
        'pagos/$pagoId/anular',
      ),
      body: jsonEncode({'motivo': motivo}),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo anular el pago.',
    );

    final mensaje = _mapa(respuesta.body)['mensaje']?.toString().trim();
    return mensaje == null || mensaje.isEmpty
        ? 'Pago anulado correctamente.'
        : mensaje;
  }

  Future<void> crearAdministrador({
    required int clienteId,
    required String nombre,
    required String email,
    required String password,
  }) async {
    final respuesta = await ApiClient.post(
      Uri.parse('$_baseUrl/api/superadmin/clientes/$clienteId/administradores'),
      body: jsonEncode({
        'nombre': nombre,
        'email': email,
        'password': password,
      }),
    );

    _aceptar(
      respuesta,
      codigos: const {200, 201},
      mensajeAlternativo: 'No se pudo crear el administrador.',
    );
  }

  Future<void> restablecerPassword({
    required int clienteId,
    required int usuarioId,
    required String password,
  }) async {
    final respuesta = await ApiClient.patch(
      Uri.parse(
        '$_baseUrl/api/superadmin/clientes/$clienteId/'
        'administradores/$usuarioId/password',
      ),
      body: jsonEncode({'password': password}),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo restablecer la contraseña.',
    );
  }

  Future<void> cambiarPasswordPropia({
    required String passwordActual,
    required String passwordNueva,
  }) async {
    final respuesta = await ApiClient.patch(
      Uri.parse('$_baseUrl/api/cuenta/password'),
      body: jsonEncode({
        'passwordActual': passwordActual,
        'passwordNueva': passwordNueva,
      }),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo cambiar la contraseña.',
    );
  }

  Future<Map<String, dynamic>> entrarModoSoporte({
    required int clienteId,
    required String motivo,
  }) async {
    final respuesta = await ApiClient.post(
      Uri.parse('$_baseUrl/api/superadmin/clientes/$clienteId/entrar-soporte'),
      body: jsonEncode({
        'motivo': motivo,
      }),
    );

    _aceptar(
      respuesta,
      codigos: const {200},
      mensajeAlternativo: 'No se pudo iniciar el modo soporte.',
    );

    final datos = _mapa(respuesta.body);
    final token = datos['token']?.toString();
    final usuario = datos['usuario'];
    final estacionamiento = datos['estacionamiento'];

    if (token != null && usuario is Map && estacionamiento is Map) {
      final uId = usuario['id'] is int
          ? usuario['id'] as int
          : int.tryParse(usuario['id'].toString()) ?? 1;
      final eId = estacionamiento['id'] is int
          ? estacionamiento['id'] as int
          : int.tryParse(estacionamiento['id'].toString()) ?? clienteId;

      await ApiClient.iniciarModoSoporte(
        tokenSoporte: token,
        usuarioId: uId,
        estacionamientoId: eId,
      );
    }

    return datos;
  }

  void _aceptar(
    http.Response respuesta, {
    required Set<int> codigos,
    required String mensajeAlternativo,
  }) {
    if (codigos.contains(respuesta.statusCode)) return;

    throw _errorDesdeRespuesta(respuesta, mensajeAlternativo);
  }

  ApiSuperAdminException _errorDesdeRespuesta(
    http.Response respuesta,
    String mensajeAlternativo,
  ) {
    final datos = _mapa(respuesta.body);
    final mensaje = datos['mensaje']?.toString().trim();

    return ApiSuperAdminException(
      mensaje == null || mensaje.isEmpty ? mensajeAlternativo : mensaje,
      codigo: respuesta.statusCode,
    );
  }

  Map<String, dynamic> _mapa(String body) {
    final decoded = _decodificar(body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  dynamic _decodificar(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _extraerEntidad(
    Map<String, dynamic> datos,
    String llave,
  ) {
    final entidad = datos[llave];
    return entidad is Map ? Map<String, dynamic>.from(entidad) : datos;
  }
}
