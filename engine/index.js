#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');
const express = require('express');
const bodyParser = require('body-parser');
const YAML = require('yaml');

const argv = require('minimist')(process.argv.slice(2));
const configPath = argv.config || '/opt/iii-stack/deploy/config/config.yaml';

const config = fs.existsSync(configPath) ? YAML.parse(fs.readFileSync(configPath, 'utf8')) : {};
const httpConf = (config.workers || []).find(w => w.name === 'iii-http') || { config: { port: 3111, host: '0.0.0.0' } };
const httpPort = httpConf.config?.port || 3111;
const wsPort = 49134;

// Function registry: function_id -> { workerId, ws }
const functions = new Map();
const workers = new Map();

const wss = new WebSocket.Server({ port: wsPort });
console.log(`III Engine placeholder: WebSocket RPC listening on ws://0.0.0.0:${wsPort}`);

wss.on('connection', (ws) => {
  const id = Math.random().toString(36).slice(2,10);
  workers.set(id, ws);
  console.log('worker connected', id);

  ws.on('message', async (msg) => {
    try {
      const data = JSON.parse(msg.toString());
      if (data.type === 'register') {
        console.log('register function', data.function_id, 'from', id);
        functions.set(data.function_id, { workerId: id, ws });
        ws.send(JSON.stringify({ type: 'registered', function_id: data.function_id }));
      } else if (data.type === 'trigger') {
        const target = functions.get(data.function_id);
        if (!target) {
          ws.send(JSON.stringify({ type: 'error', id: data.id, message: 'function not found' }));
          return;
        }
        // forward to target worker
        const call = { type: 'call', id: data.id, function_id: data.function_id, payload: data.payload };
        const targetWs = target.ws;
        const promise = new Promise((resolve) => {
          const onResp = (m) => {
            try {
              const d = JSON.parse(m.toString());
              if (d.type === 'response' && d.id === data.id) {
                resolve(d);
              }
            } catch (e) {}
          };
          targetWs.on('message', onResp);
          // Timeout
          setTimeout(() => resolve({ type: 'error', id: data.id, message: 'timeout' }), 10000);
          targetWs.send(JSON.stringify(call));
        });

        const resp = await promise;
        ws.send(JSON.stringify(resp));
      } else if (data.type === 'response') {
        // ignore: responses are handled by waiting promises
      }
    } catch (e) {
      console.error('bad msg', e);
    }
  });

  ws.on('close', () => {
    console.log('worker disconnected', id);
    // drop functions registered by this worker
    for (const [fid, entry] of functions.entries()) {
      if (entry.workerId === id) functions.delete(fid);
    }
    workers.delete(id);
  });
});

// Simple HTTP to trigger functions by routing to the function registered
const app = express();
app.use(bodyParser.json());

app.post('/v1/chat/completions', async (req, res) => {
  // Find function for HTTP trigger - expect caller-worker registered http::run_inference_over_http
  const func = functions.get('http::run_inference_over_http') || functions.get('inference::get_response');
  if (!func) return res.status(503).json({ error: 'no handler registered' });

  const ws = [...workers.values()][0]; // assume single caller connected
  const id = Math.random().toString(36).slice(2,10);
  const payload = { body: req.body };

  // send trigger from a local temporary socket by reusing engine's internal mechanism
  // emulate trigger from an external invoker
  const callerWs = {
    send: (m) => {},
  };

  // Forward to function worker directly
  const call = { type: 'call', id, function_id: func.function_id || 'inference::get_response', payload };
  const targetWs = func.ws;

  const promise = new Promise((resolve) => {
    const onResp = (m) => {
      try {
        const d = JSON.parse(m.toString());
        if (d.type === 'response' && d.id === id) {
          resolve(d);
        }
      } catch (e) {}
    };
    targetWs.on('message', onResp);
    setTimeout(() => resolve({ type: 'error', id, message: 'timeout' }), 10000);
    targetWs.send(JSON.stringify(call));
  });

  const resp = await promise;
  if (resp.type === 'error') return res.status(500).json(resp);
  return res.status(200).json(resp.payload || resp);
});

app.get('/health', (req, res) => res.send('ok'));

app.listen(httpPort, '0.0.0.0', () => console.log(`HTTP trigger listening on http://0.0.0.0:${httpPort}`));
