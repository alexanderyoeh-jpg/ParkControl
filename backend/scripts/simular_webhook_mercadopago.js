#!/usr/bin/env node
const crypto = require('crypto');

/**
 * Script de utilidad para simular y enviar eventos Webhook de Mercado Pago
 * al backend de ParkControl en desarrollo o pruebas locales.
 *
 * Uso:
 *   node scripts/simular_webhook_mercadopago.js [tipo] [idRecurso] [urlBase]
 *
 * Ejemplos:
 *   node scripts/simular_webhook_mercadopago.js subscription_preapproval 2c9380847291a localhost:3000
 *   node scripts/simular_webhook_mercadopago.js payment 123456789 http://127.0.0.1:3000
 */

const tipoEvento = process.argv[2] || 'subscription_preapproval';
const idRecurso = process.argv[3] || `sub-test-${Date.now()}`;
const urlBase = (process.argv[4] || process.env.PARKCONTROL_API_URL || 'http://localhost:3000')
  .replace(/\/+$/, '');

const secretoWebhook = process.env.PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET ||
  'secreto-webhook-mercadopago-prueba-2026';

function generarFirma({ dataId, requestId, ts, secret }) {
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  return crypto
    .createHmac('sha256', secret)
    .update(manifest)
    .digest('hex');
}

async function simularEnvio() {
  const requestId = `req-${crypto.randomUUID()}`;
  const ts = Math.floor(Date.now() / 1000).toString();
  const firma = generarFirma({
    dataId: idRecurso,
    requestId,
    ts,
    secret: secretoWebhook
  });

  const payload = {
    id: `evt-${crypto.randomUUID()}`,
    type: tipoEvento,
    action: `${tipoEvento}.updated`,
    api_version: 'v1',
    date_created: new Date().toISOString(),
    data: {
      id: idRecurso
    }
  };

  const urlDestino = `${urlBase}/api/webhooks/mercadopago?data.id=${encodeURIComponent(idRecurso)}`;

  console.log('====================================================');
  console.log('  SIMULADOR DE WEBHOOK MERCADO PAGO — PARKCONTROL  ');
  console.log('====================================================');
  console.log(`Destino:      ${urlDestino}`);
  console.log(`Tipo:         ${tipoEvento}`);
  console.log(`ID Recurso:   ${idRecurso}`);
  console.log(`Request ID:   ${requestId}`);
  console.log(`Timestamp:    ${ts}`);
  console.log(`Firma v1:     ${firma.substring(0, 16)}...`);
  console.log('----------------------------------------------------');

  try {
    const respuesta = await fetch(urlDestino, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-request-id': requestId,
        'x-signature': `ts=${ts},v1=${firma}`
      },
      body: JSON.stringify(payload)
    });

    const texto = await respuesta.text();
    let cuerpoJson;
    try {
      cuerpoJson = JSON.parse(texto);
    } catch (_) {
      cuerpoJson = texto;
    }

    console.log(`Estado HTTP:  ${respuesta.status} ${respuesta.statusText}`);
    console.log('Respuesta:', cuerpoJson);

    if (respuesta.status === 202 || respuesta.status === 200) {
      console.log('>> ÉXITO: Webhook recibido y procesado por la bandeja segura.');
    } else if (respuesta.status === 503) {
      console.log('>> AVISO: El servidor indica que PARKCONTROL_MERCADOPAGO_WEBHOOK_SECRET no está configurado en sus variables de entorno.');
    } else if (respuesta.status === 401) {
      console.log('>> ERROR: Firma inválida. Verifica que el secreto coincida con el configurado en el servidor.');
    }
    console.log('====================================================\n');
  } catch (error) {
    console.error(`>> ERROR DE CONEXIÓN: No se pudo conectar con ${urlBase}. ¿El servidor está corriendo?`);
    console.error(`   Detalle: ${error.message}\n`);
  }
}

simularEnvio();
