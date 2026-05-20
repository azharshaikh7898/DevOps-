import os
import json
import threading
import websocket

class InitOptions:
    def __init__(self, worker_name=None):
        self.worker_name = worker_name

class WorkerShim:
    def __init__(self, url, options=None):
        self.url = url
        self.functions = {}
        self.ws = websocket.WebSocketApp(url,
                                         on_message=self._on_message)
        self.thread = threading.Thread(target=self.ws.run_forever, daemon=True)
        self.thread.start()

    def _on_message(self, ws, message):
        try:
            data = json.loads(message)
            if data.get('type') == 'call':
                func = self.functions.get(data.get('function_id'))
                if func:
                    res = func(data.get('payload'))
                    ws.send(json.dumps({'type': 'response', 'id': data.get('id'), 'payload': res}))
        except Exception:
            pass

    def register_function(self, function_id, fn):
        self.functions[function_id] = fn
        # notify engine
        def notify():
            try:
                # send after connection established
                import time
                time.sleep(0.5)
                self.ws.send(json.dumps({'type': 'register', 'function_id': function_id}))
            except Exception:
                pass
        threading.Thread(target=notify, daemon=True).start()

    def trigger(self, function_id, payload, timeout=10):
        # send a trigger message and wait for response
        id = os.urandom(6).hex()
        event = threading.Event()
        resp = {}
        def on_resp(ws, message):
            try:
                data = json.loads(message)
                if data.get('id') == id:
                    resp['data'] = data
                    event.set()
            except Exception:
                pass
        # temporary hook
        orig = self.ws.on_message
        self.ws.on_message = on_resp
        self.ws.send(json.dumps({'type': 'trigger', 'id': id, 'function_id': function_id, 'payload': payload}))
        event.wait(timeout)
        self.ws.on_message = orig
        return resp.get('data')


def register_worker(url=None, init_options=None):
    return WorkerShim(url)
