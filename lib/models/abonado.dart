import 'package:flutter/material.dart';

class Abonado {
  final int id;
  final String nombreTitular;
  final String? rut;
  final String? telefono;
  final String? email;
  final String patente;
  final String tipoVehiculo;
  final double montoMensual;
  final String fechaInicio;
  final String fechaVencimiento;
  final String estado; // 'activo' | 'suspendido'
  final String? observacion;
  final String estadoComercial; // 'al_dia' | 'por_vencer' | 'vencido' | 'suspendido'

  const Abonado({
    required this.id,
    required this.nombreTitular,
    this.rut,
    this.telefono,
    this.email,
    required this.patente,
    required this.tipoVehiculo,
    required this.montoMensual,
    required this.fechaInicio,
    required this.fechaVencimiento,
    required this.estado,
    this.observacion,
    required this.estadoComercial,
  });

  factory Abonado.fromJson(Map<String, dynamic> json) {
    return Abonado(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      nombreTitular: json['nombreTitular']?.toString() ?? '',
      rut: json['rut']?.toString(),
      telefono: json['telefono']?.toString(),
      email: json['email']?.toString(),
      patente: json['patente']?.toString() ?? '',
      tipoVehiculo: json['tipoVehiculo']?.toString() ?? 'Auto',
      montoMensual: (json['montoMensual'] is num)
          ? (json['montoMensual'] as num).toDouble()
          : double.tryParse(json['montoMensual']?.toString() ?? '0') ?? 0.0,
      fechaInicio: json['fechaInicio']?.toString() ?? '',
      fechaVencimiento: json['fechaVencimiento']?.toString() ?? '',
      estado: json['estado']?.toString() ?? 'activo',
      observacion: json['observacion']?.toString(),
      estadoComercial: json['estadoComercial']?.toString() ?? 'al_dia',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombreTitular': nombreTitular,
      'rut': rut,
      'telefono': telefono,
      'email': email,
      'patente': patente,
      'tipoVehiculo': tipoVehiculo,
      'montoMensual': montoMensual,
      'fechaInicio': fechaInicio,
      'fechaVencimiento': fechaVencimiento,
      'estado': estado,
      'observacion': observacion,
    };
  }

  bool get estaVigente => estado == 'activo' && estadoComercial != 'vencido';

  int get diasRestantes {
    try {
      final venc = DateTime.parse(fechaVencimiento);
      final hoy = DateTime.now();
      final diferencia = venc.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
      return diferencia;
    } catch (_) {
      return 0;
    }
  }

  String get etiquetaEstado {
    switch (estadoComercial) {
      case 'al_dia':
        return 'Al día (${diasRestantes}d)';
      case 'por_vencer':
        return 'Por vencer (${diasRestantes}d)';
      case 'vencido':
        return 'Vencido';
      case 'suspendido':
        return 'Suspendido';
      default:
        return estado;
    }
  }

  Color get colorEstado {
    switch (estadoComercial) {
      case 'al_dia':
        return const Color(0xFF2E7D32);
      case 'por_vencer':
        return const Color(0xFFF57F17);
      case 'vencido':
        return const Color(0xFFC62828);
      case 'suspendido':
        return const Color(0xFF616161);
      default:
        return Colors.blueGrey;
    }
  }
}
