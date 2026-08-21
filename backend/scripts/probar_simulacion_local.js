#!/usr/bin/env node
const assert = require('assert');
const crypto = require('crypto');
const http = require('http');
const Database = require('better-sqlite3');

/**
 * Prueba y demostración automatizada de simulación de Webhooks de Mercado Pago
 * en entorno local para ParkControl.
 */

const SECRETO_PRUEBA = 'secreto-webhook-mercadopago-prueba-2026';

function generarFirma({ dataId, requestId, ts, secret }) {
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  return crypto.createHmac('sha256', secret).update(manifest).digest('hex');
}

async function ejecutar() {
  console.log('===========================================================');
  console.log('  EJECUTANDO SIMULACIÓN LOCAL DE WEBHOOKS MERCADO PAGO     ');
  console.log('===========================================================');

  // 1. Configurar base temporal en memoria
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE IF NOT EXISTS eventos_pasarela (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      proveedor TEXT NOT NULL,
      evento_externo_id TEXT NOT NULL,
      tipo TEXT,
      recurso_externo_id TEXT,
      estacionamiento_id INTEGER,
      firma_valida INTEGER NOT NULL DEFAULT 0,
      estado_procesamiento TEXT NOT NULL DEFAULT 'pendiente_verificacion',
      hash_payload TEXT NOT NULL,
      recibido_en TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_eventos_pasarela_externo
    ON eventos_pasarela (proveedor, evento_externo_id);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_eventos_pasarela_hash
    ON eventos_pasarela (proveedor, hash_payload);
  `);

  // 2. Mock ligero del endpoint del webhook
  const server = http.createServer(async (req, res) => {
    if (req.url.startsWith('/api/webhooks/mercadopago') && req.method === 'POST') {
      let bodyRaw = '';
      for await (const chunk of req) {
        bodyRaw += chunk;
      }

      const sigHeader = req.headers['x-signature'] || '';
      const reqId = req.headers['x-request-id'] || '';

      const matchTs = sigHeader.match(/ts=(\d+)/);
      const matchV1 = sigHeader.match(/v1=([a-f0-9]{64})/i);

      if (!matchTs || !matchV1 || !reqId) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ codigo: 'FIRMA_INVALIDA' }));
      }

      const urlObj = new URL(req.url, 'http://localhost');
      const dataId = urlObj.searchParams.get('data.id') || '';

      const firmaCalculada = generarFirma({
        dataId,
        requestId: reqId,
        ts: matchTs[1],
        secret: SECRETO_PRUEBA
      });

      if (firmaCalculada !== matchV1[1]) {
        res.writeHead(401, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ codigo: 'FIRMA_NO_COINCIDE' }));
      }

      const payload = JSON.parse(bodyRaw);
      const hashPayload = crypto.createHash('sha256').update(bodyRaw).digest('hex');

      try {
        const stmt = db.prepare(`
          INSERT INTO eventos_pasarela
          (proveedor, evento_externo_id, tipo, recurso_externo_id, firma_valida, hash_payload, recibido_en)
          VALUES (?, ?, ?, ?, 1, ?, ?)
        `);
        stmt.run(
          'mercadopago',
          `notificacion:${payload.id}`,
          payload.type,
          dataId,
          hashPayload,
          new Date().toISOString()
        );

        res.writeHead(202, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ recibido: true, duplicado: false, procesado: false }));
      } catch (err) {
        if (err.code === 'SQLITE_CONSTRAINT_UNIQUE' || String(err.message).includes('UNIQUE')) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ recibido: true, duplicado: true, procesado: false }));
        }
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: err.message }));
      }
    }

    res.writeHead(404);
    res.end();
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;

  console.log(`[1/3] Servidor temporal iniciado en puerto ${port}`);

  // Simulación 1: Enviar suscripción válida
  const subId = 'sub_preapproval_987654';
  const reqId1 = 'req_test_001';
  const ts1 = Math.floor(Date.now() / 1000).toString();
  const firma1 = generarFirma({ dataId: subId, requestId: reqId1, ts: ts1, secret: SECRETO_PRUEBA });

  const payload1 = JSON.stringify({
    id: 'evt_mercadopago_001',
    type: 'subscription_preapproval',
    action: 'subscription_preapproval.created',
    data: { id: subId }
  });

  console.log('[2/3] Enviando evento de creación de suscripción (Plan Pro $119.990)...');
  const res1 = await fetch(`${baseUrl}/api/webhooks/mercadopago?data.id=${subId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-request-id': reqId1,
      'x-signature': `ts=${ts1},v1=${firma1}`
    },
    body: payload1
  });

  const json1 = await res1.json();
  console.log(`      Respuesta HTTP: ${res1.status} ->`, json1);
  assert.equal(res1.status, 202, 'El primer evento debe ser aceptado con 202');
  assert.equal(json1.recibido, true);
  assert.equal(json1.duplicado, false);

  // Simulación 2: Reenvío idéntico (Idempotencia / deduplicación)
  console.log('[3/3] Reenviando el mismo evento (prueba de deduplicación idempotente)...');
  const res2 = await fetch(`${baseUrl}/api/webhooks/mercadopago?data.id=${subId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-request-id': reqId1,
      'x-signature': `ts=${ts1},v1=${firma1}`
    },
    body: payload1
  });

  const json2 = await res2.json();
  console.log(`      Respuesta HTTP: ${res2.status} ->`, json2);
  assert.equal(res2.status, 200, 'El evento duplicado debe responder 200 con duplicado=true');
  assert.equal(json2.duplicado, true);

  // Verificar estado en la base de datos
  const eventosRegistrados = db.prepare('SELECT * FROM eventos_pasarela').all();
  console.log('\n-----------------------------------------------------------');
  console.log(`Eventos guardados en la tabla 'eventos_pasarela' (Total: ${eventosRegistrados.length}):`);
  console.table(eventosRegistrados.map(e => ({
    id: e.id,
    proveedor: e.proveedor,
    evento: e.evento_externo_id,
    tipo: e.tipo,
    recurso: e.recurso_externo_id,
    firma_ok: e.firma_valida === 1,
    estado: e.estado_procesamiento
  })));

  server.close();
  console.log('>> SIMULACIÓN LOCAL COMPLETADA EXITOSAMENTE (0 fallos).');
  console.log('===========================================================\n');
}

ejecutar().catch((err) => {
  console.error('ERROR EN SIMULACIÓN:', err);
  process.exit(1);
});
