class ErrorTransporteCorreo extends Error {
  constructor({ codigo, mensaje, reintentable = false, estadoProveedor = null }) {
    super(mensaje);
    this.name = 'ErrorTransporteCorreo';
    this.codigo = codigo;
    this.reintentable = reintentable;
    this.estadoProveedor = estadoProveedor;
  }
}

function textoSeguro(valor, maximo = 512) {
  return String(valor ?? '')
    .replace(/[\r\n]/g, ' ')
    .trim()
    .slice(0, maximo);
}

function normalizarAdjuntos(adjuntos) {
  return (Array.isArray(adjuntos) ? adjuntos : [])
    .map(adjunto => {
      const nombre = textoSeguro(adjunto?.nombre, 120);
      const contenido = Buffer.isBuffer(adjunto?.contenido)
        ? adjunto.contenido
        : Buffer.from(String(adjunto?.contenido ?? ''), 'utf8');

      if (!nombre || contenido.length === 0) {
        return null;
      }

      return {
        filename: nombre,
        content: contenido.toString('base64')
      };
    })
    .filter(Boolean);
}

function crearTransporteCorreo({ configuracionCorreo, fetchImpl = global.fetch }) {
  const correo = configuracionCorreo || {};

  if (correo.modo !== 'resend' || !correo.configuracionCompleta) {
    return Object.freeze({
      disponible: false,
      proveedor: 'no_configurado',
      async enviar() {
        throw new ErrorTransporteCorreo({
          codigo: 'CORREO_NO_CONFIGURADO',
          mensaje: 'El correo programado aún no está configurado en ParkControl',
          reintentable: false
        });
      }
    });
  }

  if (typeof fetchImpl !== 'function') {
    throw new Error('El transporte de correo requiere fetch');
  }

  return Object.freeze({
    disponible: true,
    proveedor: 'resend',
    async enviar({ para, asunto, html, texto, adjuntos, claveIdempotencia }) {
      const controlador = new AbortController();
      const temporizador = setTimeout(
        () => controlador.abort(),
        Number(correo.timeoutMs || 15000)
      );

      try {
        const respuesta = await fetchImpl('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${correo.resendApiKey}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': textoSeguro(claveIdempotencia, 256)
          },
          body: JSON.stringify({
            from: correo.remitente,
            to: [textoSeguro(para, 254)],
            ...(correo.respuestaA
              ? { reply_to: correo.respuestaA }
              : {}),
            subject: textoSeguro(asunto, 180),
            html: String(html || ''),
            text: String(texto || ''),
            attachments: normalizarAdjuntos(adjuntos)
          }),
          signal: controlador.signal
        });

        let cuerpo = null;

        try {
          cuerpo = await respuesta.json();
        } catch (_) {
          // El detalle del proveedor no se expone ni se persiste; basta el
          // estado HTTP para decidir si el trabajo puede reintentarse.
        }

        if (!respuesta.ok) {
          throw new ErrorTransporteCorreo({
            codigo: respuesta.status === 429
              ? 'CORREO_LIMITE_PROVEEDOR'
              : 'CORREO_PROVEEDOR_RECHAZO',
            mensaje: respuesta.status >= 500 || respuesta.status === 429
              ? 'El proveedor de correo no está disponible temporalmente'
              : 'El proveedor de correo rechazó el informe',
            reintentable:
              respuesta.status === 408 ||
              respuesta.status === 409 ||
              respuesta.status === 425 ||
              respuesta.status === 429 ||
              respuesta.status >= 500,
            estadoProveedor: respuesta.status
          });
        }

        const mensajeId = textoSeguro(
          cuerpo?.id || cuerpo?.data?.id,
          180
        );

        if (!mensajeId) {
          throw new ErrorTransporteCorreo({
            codigo: 'CORREO_RESPUESTA_INVALIDA',
            mensaje: 'El proveedor no confirmó el identificador del envío',
            reintentable: true
          });
        }

        return {
          mensajeId
        };
      } catch (error) {
        if (error instanceof ErrorTransporteCorreo) {
          throw error;
        }

        throw new ErrorTransporteCorreo({
          codigo: error?.name === 'AbortError'
            ? 'CORREO_TIMEOUT'
            : 'CORREO_CONEXION_FALLIDA',
          mensaje: 'No fue posible comunicarse con el proveedor de correo',
          reintentable: true
        });
      } finally {
        clearTimeout(temporizador);
      }
    }
  });
}

module.exports = {
  ErrorTransporteCorreo,
  crearTransporteCorreo
};
