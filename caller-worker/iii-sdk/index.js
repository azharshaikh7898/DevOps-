const WebSocket = require('ws');

function registerWorker(url) {
  const ws = new WebSocket(url);
  const functions = new Map();

  ws.on('open', () => {
    // console.log('connected to engine', url);
  });

  ws.on('message', (msg) => {
    try {
      const data = JSON.parse(msg.toString());
      if (data.type === 'call') {
        const fn = functions.get(data.function_id);
        if (!fn) {
          ws.send(JSON.stringify({ type: 'response', id: data.id, type: 'error', message: 'function not found' }));
          return;
        }
        Promise.resolve(fn(data.payload)).then((result) => {
          ws.send(JSON.stringify({ type: 'response', id: data.id, payload: result }));
        });
      }
    } catch (e) {}
  });

  return {
    registerFunction(function_id, fn) {
      functions.set(function_id, fn);
      ws.on('open', () => {
        ws.send(JSON.stringify({ type: 'register', function_id }));
      });
    },
    registerTrigger(trigger) {
      // no-op here; triggers are registered as functions
    },
    trigger({ function_id, payload }) {
      return new Promise((resolve, reject) => {
        const id = Math.random().toString(36).slice(2,10);
        const onResp = (m) => {
          try {
            const data = JSON.parse(m.toString());
            if (data.id === id) {
              resolve(data.payload);
            }
          } catch (e) {}
        };
        ws.on('message', onResp);
        ws.send(JSON.stringify({ type: 'trigger', id, function_id, payload }));
        setTimeout(() => reject(new Error('timeout')), 10000);
      });
    }
  };
}

module.exports = { registerWorker };
