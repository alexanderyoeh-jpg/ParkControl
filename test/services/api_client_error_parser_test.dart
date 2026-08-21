import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parkcontrol/services/api_client.dart';

void main() {
  group('ApiClient.extraerMensajeError', () {
    test('extrae mensaje desde propiedad mensaje en JSON', () {
      final respuesta = http.Response(
        jsonEncode({'mensaje': 'Correo o contraseña incorrectos'}),
        401,
      );
      expect(
        ApiClient.extraerMensajeError(respuesta),
        equals('Correo o contraseña incorrectos'),
      );
    });

    test('extrae mensaje desde propiedad error en JSON', () {
      final respuesta = http.Response(
        jsonEncode({'error': 'Token inválido'}),
        401,
      );
      expect(
        ApiClient.extraerMensajeError(respuesta),
        equals('Token inválido'),
      );
    });

    test('extrae mensaje desde propiedad detalle en JSON', () {
      final respuesta = http.Response(
        jsonEncode({'detalle': 'La patente no cumple el formato esperado'}),
        400,
      );
      expect(
        ApiClient.extraerMensajeError(respuesta),
        equals('La patente no cumple el formato esperado'),
      );
    });

    test('mapea códigos de error conocidos si no viene mensaje explícito', () {
      final respuesta = http.Response(
        jsonEncode({'codigo': 'LIMITE_USUARIOS_PLAN'}),
        409,
      );
      expect(
        ApiClient.extraerMensajeError(respuesta),
        equals('Has alcanzado el límite máximo de usuarios permitidos por tu plan.'),
      );

      final respuesta2 = http.Response(
        jsonEncode({'codigo': 'FUNCION_NO_DISPONIBLE_PLAN'}),
        403,
      );
      expect(
        ApiClient.extraerMensajeError(respuesta2),
        equals('Esta función no está disponible en tu plan actual.'),
      );
    });

    test('aplica fallback según código HTTP si el cuerpo no es JSON', () {
      final respuesta429 = http.Response('Too Many Requests', 429);
      expect(
        ApiClient.extraerMensajeError(respuesta429),
        contains('Demasiadas solicitudes'),
      );

      final respuesta500 = http.Response('Internal Server Error', 500);
      expect(
        ApiClient.extraerMensajeError(respuesta500),
        contains('El servidor no está disponible'),
      );

      final respuesta403 = http.Response('Forbidden', 403);
      expect(
        ApiClient.extraerMensajeError(respuesta403),
        contains('No tienes permisos'),
      );
    });

    test('devuelve mensaje predeterminado cuando respuesta es nula o estado no mapeado', () {
      expect(
        ApiClient.extraerMensajeError(null, mensajePredeterminado: 'Fallo red'),
        equals('Fallo red'),
      );
    });
  });
}
