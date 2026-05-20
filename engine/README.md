III Engine placeholder

This is a minimal development placeholder for the III Engine used in the internship assignment.

It implements a WebSocket RPC broker at port 49134 and an HTTP trigger endpoint configured in `deploy/config/config.yaml`.

Usage (local):

```bash
cd engine
npm ci
node index.js --config ../deploy/config/config.yaml
```

The placeholder understands messages:
- {type: 'register', function_id}
- {type: 'trigger', id, function_id, payload}
- {type: 'call', id, function_id, payload}
- {type: 'response', id, payload}

This is intended for demos only, not production.
