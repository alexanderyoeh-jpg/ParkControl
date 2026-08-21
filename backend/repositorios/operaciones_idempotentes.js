const crypto = require('crypto');

function crearRepositorioOperacionesIdempotentes({ db }) {
  function identificar(claveRecibida, datos) {
    const clave = String(claveRecibida || '').trim();

    if (clave && !/^[A-Za-z0-9._:-]{8,128}$/.test(clave)) {
      return {
        error: {
          estadoHttp: 400,
          cuerpo: {
            codigo: 'CLAVE_IDEMPOTENCIA_INVALIDA',
            mensaje:
              'Idempotency-Key debe tener entre 8 y 128 caracteres seguros'
          },
          reutilizada: false
        }
      };
    }

    return {
      clave,
      hashSolicitud: crypto
        .createHash('sha256')
        .update(JSON.stringify(datos))
        .digest('hex')
    };
  }

  function consultar({
    estacionamientoId,
    clave,
    tipo,
    datos
  }) {
    const identidad = identificar(clave, datos);

    if (identidad.error) {
      return identidad.error;
    }

    if (!identidad.clave) {
      return null;
    }

    const existente = db.prepare(`
      SELECT
        hash_solicitud,
        estado_http,
        respuesta_json
      FROM operaciones_idempotentes
      WHERE estacionamiento_id = ?
        AND tipo = ?
        AND clave = ?
    `).get(
      estacionamientoId,
      tipo,
      identidad.clave
    );

    if (!existente) {
      return null;
    }

    if (existente.hash_solicitud !== identidad.hashSolicitud) {
      return {
        estadoHttp: 409,
        cuerpo: {
          codigo: 'CLAVE_IDEMPOTENCIA_REUTILIZADA',
          mensaje: 'La clave de idempotencia ya fue usada con otros datos'
        },
        reutilizada: false
      };
    }

    return {
      estadoHttp: Number(existente.estado_http),
      cuerpo: JSON.parse(existente.respuesta_json),
      reutilizada: true
    };
  }

  function ejecutar({
    estacionamientoId,
    usuarioId,
    clave,
    tipo,
    datos,
    operacion
  }) {
    const identidad = identificar(clave, datos);

    if (identidad.error) {
      return identidad.error;
    }

    const transaccion = db.transaction(() => {
      const existente = consultar({
        estacionamientoId,
        clave: identidad.clave,
        tipo,
        datos
      });

      if (existente) {
        return existente;
      }

      const resultado = operacion();

      if (identidad.clave &&
          resultado.estadoHttp >= 200 &&
          resultado.estadoHttp < 300) {
        db.prepare(`
          INSERT INTO operaciones_idempotentes
          (
            estacionamiento_id,
            tipo,
            clave,
            hash_solicitud,
            estado_http,
            respuesta_json,
            usuario_id,
            creado_en
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          estacionamientoId,
          tipo,
          identidad.clave,
          identidad.hashSolicitud,
          resultado.estadoHttp,
          JSON.stringify(resultado.cuerpo),
          usuarioId,
          new Date().toISOString()
        );
      }

      return {
        ...resultado,
        reutilizada: false
      };
    });

    return transaccion.immediate();
  }

  return {
    consultar,
    ejecutar
  };
}

module.exports = {
  crearRepositorioOperacionesIdempotentes
};
