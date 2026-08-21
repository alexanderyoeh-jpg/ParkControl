const assert = require('node:assert/strict');

const {
  ErrorTransporteCorreo,
  crearTransporteCorreo
} = require('../servicios/transporte_correo');

async function ejecutar() {
  const deshabilitado = crearTransporteCorreo({
    configuracionCorreo: { modo: 'no_configurado' }
  });
  assert.equal(deshabilitado.disponible, false);

  await assert.rejects(
    deshabilitado.enviar({}),
    error => error instanceof ErrorTransporteCorreo &&
      error.codigo === 'CORREO_NO_CONFIGURADO' &&
      error.reintentable === false
  );

  let solicitud;
  const transporte = crearTransporteCorreo({
    configuracionCorreo: {
      modo: 'resend',
      configuracionCompleta: true,
      resendApiKey: 're_prueba_solo_test',
      remitente: 'ParkControl <informes@prueba.cl>',
      respuestaA: 'soporte@prueba.cl',
      timeoutMs: 1000
    },
    fetchImpl: async (url, opciones) => {
      solicitud = { url, opciones };
      return new Response(JSON.stringify({ id: 'correo-prueba-001' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  });

  const enviado = await transporte.enviar({
    para: 'administrador@prueba.cl',
    asunto: 'Informe de prueba',
    html: '<p>Informe</p>',
    texto: 'Informe',
    adjuntos: [
      { nombre: 'detalle.csv', contenido: Buffer.from('a,b\n1,2\n') }
    ],
    claveIdempotencia: 'informe-correo/123'
  });
  assert.equal(enviado.mensajeId, 'correo-prueba-001');
  assert.equal(solicitud.url, 'https://api.resend.com/emails');
  assert.equal(
    solicitud.opciones.headers['Idempotency-Key'],
    'informe-correo/123'
  );
  const cuerpo = JSON.parse(solicitud.opciones.body);
  assert.deepEqual(cuerpo.to, ['administrador@prueba.cl']);
  assert.equal(cuerpo.attachments[0].filename, 'detalle.csv');
  assert.equal(
    Buffer.from(cuerpo.attachments[0].content, 'base64').toString('utf8'),
    'a,b\n1,2\n'
  );

  const temporalmenteCaido = crearTransporteCorreo({
    configuracionCorreo: {
      modo: 'resend',
      configuracionCompleta: true,
      resendApiKey: 're_prueba_solo_test',
      remitente: 'informes@prueba.cl',
      timeoutMs: 1000
    },
    fetchImpl: async () => new Response('{}', { status: 503 })
  });

  await assert.rejects(
    temporalmenteCaido.enviar({
      para: 'administrador@prueba.cl',
      asunto: 'Informe',
      html: '<p>Informe</p>',
      texto: 'Informe',
      claveIdempotencia: 'informe-correo/124'
    }),
    error => error instanceof ErrorTransporteCorreo &&
      error.codigo === 'CORREO_PROVEEDOR_RECHAZO' &&
      error.reintentable === true
  );

  console.log('Transporte de correo verificado sin proveedor externo.');
}

ejecutar().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
