function crearProteccionIntentos({
  maxIntentos,
  ventanaMs,
  maxClaves = 10000
}) {
  const registros = new Map();

  function obtenerEstado(clave, ahora = Date.now()) {
    const registro = registros.get(clave);

    if (!registro) {
      return { permitido: true, reintentarEnSegundos: 0 };
    }

    if (registro.expiraEn <= ahora) {
      registros.delete(clave);
      return { permitido: true, reintentarEnSegundos: 0 };
    }

    if (registro.intentos < maxIntentos) {
      return { permitido: true, reintentarEnSegundos: 0 };
    }

    return {
      permitido: false,
      reintentarEnSegundos: Math.max(
        1,
        Math.ceil((registro.expiraEn - ahora) / 1000)
      )
    };
  }

  function registrarFallo(clave, ahora = Date.now()) {
    const existente = registros.get(clave);

    if (!existente || existente.expiraEn <= ahora) {
      if (!registros.has(clave) && registros.size >= maxClaves) {
        const claveMasAntigua = registros.keys().next().value;
        registros.delete(claveMasAntigua);
      }

      registros.set(clave, {
        intentos: 1,
        expiraEn: ahora + ventanaMs
      });
    } else {
      existente.intentos += 1;
    }

    return obtenerEstado(clave, ahora);
  }

  function limpiar(clave) {
    registros.delete(clave);
  }

  return {
    obtenerEstado,
    registrarFallo,
    limpiar
  };
}

module.exports = {
  crearProteccionIntentos
};
