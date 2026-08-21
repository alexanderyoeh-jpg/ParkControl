const path = require('path');
const fs = require('fs');
const net = require('net');

function leerLista(valor) {
  return String(valor || '')
    .split(',')
    .map(elemento => elemento.trim())
    .filter(Boolean);
}

function leerBooleano(valor) {
  return ['1', 'true', 'yes', 'si', 'sí'].includes(
    String(valor || '').trim().toLowerCase()
  );
}

function leerTexto(valor) {
  const texto = String(valor || '').trim();
  return texto || null;
}

function leerUrlPublica(valor, nombre) {
  const texto = leerTexto(valor);

  if (!texto) {
    return null;
  }

  let url;

  try {
    url = new URL(texto);
  } catch (_) {
    throw new Error(`${nombre} debe ser una URL HTTP o HTTPS válida`);
  }

  if (!['http:', 'https:'].includes(url.protocol) ||
      url.username ||
      url.password ||
      url.search ||
      url.hash) {
    throw new Error(`${nombre} debe ser una URL HTTP o HTTPS pública sin credenciales`);
  }

  return url.toString().replace(/\/$/, '');
}

function leerDireccionCorreo(valor, nombre, { permitirNombre = false } = {}) {
  const texto = leerTexto(valor);

  if (!texto) {
    return null;
  }

  if (texto.length > 320 || /[\r\n]/.test(texto)) {
    throw new Error(`${nombre} no tiene un formato de correo seguro`);
  }

  const direccion = permitirNombre
    ? (texto.match(/<([^<>]+)>$/)?.[1] || texto)
    : texto;

  if (!/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(direccion)) {
    throw new Error(`${nombre} debe ser una dirección de correo válida`);
  }

  return texto;
}

function leerEnteroPositivo(valor, predeterminado, nombre) {
  if (valor == null || String(valor).trim() === '') {
    return predeterminado;
  }

  const numero = Number(valor);

  if (!Number.isInteger(numero) || numero < 1) {
    throw new Error(`${nombre} debe ser un número entero positivo`);
  }

  return numero;
}

function leerEnteroEnRango(
  valor,
  predeterminado,
  nombre,
  minimo,
  maximo
) {
  const numero = leerEnteroPositivo(valor, predeterminado, nombre);

  if (numero < minimo || numero > maximo) {
    throw new Error(
      `${nombre} debe estar entre ${minimo} y ${maximo}`
    );
  }

  return numero;
}

function esHostLoopback(host) {
  return [
    '127.0.0.1',
    '::1',
    '::ffff:127.0.0.1',
    'localhost'
  ].includes(host);
}

function leerHostServidor(valor, esProduccion) {
  const predeterminado = esProduccion ? '127.0.0.1' : '0.0.0.0';
  const host = (leerTexto(valor) || predeterminado).toLowerCase();

  // Un host puede ser una interfaz IP o localhost. No se aceptan URLs ni
  // nombres DNS arbitrarios: en producción el API debe quedar detrás de
  // Nginx en loopback y no exponerse accidentalmente a Internet.
  if (host !== 'localhost' && net.isIP(host) === 0) {
    throw new Error(
      'PARKCONTROL_HOST debe ser una dirección IP válida o localhost'
    );
  }

  if (esProduccion && !esHostLoopback(host)) {
    throw new Error(
      'PARKCONTROL_HOST en producción debe ser una dirección loopback (127.0.0.1, ::1 o localhost)'
    );
  }

  return host;
}

const entorno = String(process.env.NODE_ENV || 'development')
  .trim()
  .toLowerCase();
const esProduccion = entorno === 'production';
// En producción nunca se aceptan las contraseñas cortas que se usaban en
// prototipos. Desarrollo y pruebas conservan seis caracteres para no romper
// cuentas demostrativas o fixtures locales ya existentes. El propietario
// global siempre mantiene un umbral mayor, sin importar el entorno.
const politicaPassword = Object.freeze({
  longitudMinimaUsuario: esProduccion ? 10 : 6,
  longitudMinimaSuperadmin: 12
});
const puerto = Number(process.env.PORT || 3000);
const host = leerHostServidor(process.env.PARKCONTROL_HOST, esProduccion);
const permitirConfiguracionInicialForzada = leerBooleano(
  process.env.PARKCONTROL_ALLOW_SETUP
);
const configuracionInicialDeshabilitada = String(
  process.env.PARKCONTROL_ALLOW_SETUP || ''
).trim().toLowerCase() === 'false';
const crearUsuariosDemo = leerBooleano(
  process.env.PARKCONTROL_CREAR_USUARIOS_DEMO
);
const rutaBaseDatosConfigurada = leerTexto(
  process.env.PARKCONTROL_DB_PATH
);
const rutaBaseDatos = path.resolve(
  rutaBaseDatosConfigurada || path.join(__dirname, 'parkcontrol.db')
);
const mercadoPagoAccessToken = leerTexto(
  process.env.PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN
);
const mercadoPagoWebhookSecret = leerTexto(
  process.env.PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET
);
const mercadoPagoUrlPublica = leerUrlPublica(
  process.env.PARKCONTROL_PUBLIC_URL,
  'PARKCONTROL_PUBLIC_URL'
);
const proveedorCorreo = String(
  leerTexto(process.env.PARKCONTROL_EMAIL_PROVIDER) || 'deshabilitado'
).toLowerCase();
const correoResendApiKey = leerTexto(
  process.env.PARKCONTROL_RESEND_API_KEY
);
const correoRemitente = leerDireccionCorreo(
  process.env.PARKCONTROL_EMAIL_FROM,
  'PARKCONTROL_EMAIL_FROM',
  { permitirNombre: true }
);
const correoRespuesta = leerDireccionCorreo(
  process.env.PARKCONTROL_EMAIL_REPLY_TO,
  'PARKCONTROL_EMAIL_REPLY_TO'
);

if (!Number.isInteger(puerto) || puerto < 1 || puerto > 65535) {
  throw new Error('PORT debe ser un número entero entre 1 y 65535');
}

const origenesPermitidos = leerLista(
  process.env.PARKCONTROL_ALLOWED_ORIGINS
);

if (esProduccion &&
    String(process.env.PARKCONTROL_AUTH_SECRET || '').trim().length < 32) {
  throw new Error(
    'En producción PARKCONTROL_AUTH_SECRET debe tener al menos 32 caracteres'
  );
}

// La configuración inicial HTTP y las cuentas demostrativas son ayudas de
// desarrollo. En un VPS no deben poder activarse por una variable heredada o
// mal escrita: el servidor debe detenerse antes de exponer una cuenta con
// credenciales conocidas o permitir reclamar la cuenta propietaria.
if (esProduccion && permitirConfiguracionInicialForzada) {
  throw new Error(
    'PARKCONTROL_ALLOW_SETUP no puede habilitarse en producción; crea el SuperAdministrador mediante variables de entorno antes de publicar la API'
  );
}

if (esProduccion && crearUsuariosDemo) {
  throw new Error(
    'PARKCONTROL_CREAR_USUARIOS_DEMO no puede habilitarse en producción'
  );
}

// better-sqlite3 crea un archivo vacío si la ruta no existe. Eso es práctico
// localmente, pero en producción podría ocultar un error de despliegue como si
// los datos del cliente se hubieran perdido. Se exige una ruta explícita y un
// archivo ya existente; la base debe copiarse/restaurarse antes de iniciar.
if (esProduccion) {
  if (!rutaBaseDatosConfigurada) {
    throw new Error(
      'PARKCONTROL_DB_PATH es obligatorio en producción y debe apuntar a una base SQLite existente'
    );
  }

  if (!path.isAbsolute(rutaBaseDatosConfigurada)) {
    throw new Error(
      'PARKCONTROL_DB_PATH debe ser una ruta absoluta en producción'
    );
  }

  let informacionBaseDatos;

  try {
    informacionBaseDatos = fs.statSync(rutaBaseDatos);
  } catch (_) {
    throw new Error(
      'PARKCONTROL_DB_PATH no existe; el despliegue se detuvo para no crear una base vacía'
    );
  }

  if (!informacionBaseDatos.isFile()) {
    throw new Error(
      'PARKCONTROL_DB_PATH debe apuntar a un archivo SQLite existente'
    );
  }
}

const configuracionMercadoPagoIncompleta = [
  mercadoPagoAccessToken,
  mercadoPagoWebhookSecret,
  mercadoPagoUrlPublica
].some(Boolean) && ![
  mercadoPagoAccessToken,
  mercadoPagoWebhookSecret,
  mercadoPagoUrlPublica
].every(Boolean);

if (esProduccion && configuracionMercadoPagoIncompleta) {
  throw new Error(
    'Mercado Pago requiere PARKCONTROL_MERCADOPAGO_ACCESS_TOKEN, PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET y PARKCONTROL_PUBLIC_URL en producción'
  );
}

if (esProduccion &&
    mercadoPagoUrlPublica &&
    !mercadoPagoUrlPublica.startsWith('https://')) {
  throw new Error(
    'PARKCONTROL_PUBLIC_URL debe usar HTTPS en producción para Mercado Pago'
  );
}

if (!['deshabilitado', 'resend'].includes(proveedorCorreo)) {
  throw new Error(
    'PARKCONTROL_EMAIL_PROVIDER debe ser deshabilitado o resend'
  );
}

const configuracionCorreoIncompleta = proveedorCorreo === 'resend'
  ? !correoResendApiKey || !correoRemitente
  : Boolean(correoResendApiKey || correoRemitente || correoRespuesta);

if (configuracionCorreoIncompleta) {
  throw new Error(
    proveedorCorreo === 'resend'
      ? 'Resend requiere PARKCONTROL_RESEND_API_KEY y PARKCONTROL_EMAIL_FROM'
      : 'No configures claves de correo mientras PARKCONTROL_EMAIL_PROVIDER esté deshabilitado'
  );
}

// Flutter móvil y herramientas servidor-a-servidor no envían Origin.
// En desarrollo se conserva el comportamiento abierto para no interrumpir
// el trabajo local. En producción, un navegador debe estar expresamente
// incluido en PARKCONTROL_ALLOWED_ORIGINS.
function origenPermitido(origen) {
  if (!origen) {
    return true;
  }

  if (!esProduccion && origenesPermitidos.length === 0) {
    return true;
  }

  return origenesPermitidos.includes(origen);
}

module.exports = {
  entorno,
  esProduccion,
  politicaPassword,
  puerto,
  host,
  rutaBaseDatos,
  permitirConfiguracionInicialForzada,
  configuracionInicialDeshabilitada,
  crearUsuariosDemo,
  limiteJson: process.env.PARKCONTROL_JSON_LIMIT || '256kb',
  confiarProxy: leerBooleano(process.env.PARKCONTROL_TRUST_PROXY),
  maxIntentosLogin: leerEnteroPositivo(
    process.env.PARKCONTROL_LOGIN_MAX_ATTEMPTS,
    5,
    'PARKCONTROL_LOGIN_MAX_ATTEMPTS'
  ),
  ventanaIntentosLoginMs: leerEnteroPositivo(
    process.env.PARKCONTROL_LOGIN_WINDOW_MS,
    15 * 60 * 1000,
    'PARKCONTROL_LOGIN_WINDOW_MS'
  ),
  sqliteBusyTimeoutMs: leerEnteroEnRango(
    process.env.PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS,
    5000,
    'PARKCONTROL_SQLITE_BUSY_TIMEOUT_MS',
    1000,
    30000
  ),
  mercadoPago: Object.freeze({
    proveedor: 'mercadopago',
    accessToken: mercadoPagoAccessToken,
    webhookSecret: mercadoPagoWebhookSecret,
    urlPublica: mercadoPagoUrlPublica,
    urlWebhook: mercadoPagoUrlPublica
      ? `${mercadoPagoUrlPublica}/api/webhooks/mercadopago`
      : null,
    configuracionCompleta: !configuracionMercadoPagoIncompleta &&
      Boolean(
        mercadoPagoAccessToken &&
        mercadoPagoWebhookSecret &&
        mercadoPagoUrlPublica
      ),
    webhookHabilitado: Boolean(mercadoPagoWebhookSecret),
    modo: mercadoPagoAccessToken
      ? (mercadoPagoAccessToken.startsWith('TEST-')
          ? 'sandbox'
          : 'produccion')
      : 'no_configurado'
  }),
  correo: Object.freeze({
    proveedor: proveedorCorreo,
    resendApiKey: correoResendApiKey,
    remitente: correoRemitente,
    respuestaA: correoRespuesta,
    timeoutMs: leerEnteroEnRango(
      process.env.PARKCONTROL_EMAIL_TIMEOUT_MS,
      15000,
      'PARKCONTROL_EMAIL_TIMEOUT_MS',
      1000,
      60000
    ),
    configuracionCompleta: proveedorCorreo === 'resend' &&
      Boolean(correoResendApiKey && correoRemitente),
    modo: proveedorCorreo === 'resend'
      ? 'resend'
      : 'no_configurado'
  }),
  origenesPermitidos,
  origenPermitido
};
