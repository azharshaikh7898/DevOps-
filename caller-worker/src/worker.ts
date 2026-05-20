import { registerWorker } from 'iii-sdk';

const iii = registerWorker(process.env.III_URL ?? 'ws://iii-engine.iii.internal:49134');

iii.registerFunction('inference::get_response', async (payload: any) => {
  const result = await iii.trigger({
    function_id: 'inference::run_inference',
    payload,
  });

  return {
    ...result,
    success: true,
    message: 'Workers interoperating',
  };
});

iii.registerFunction('http::run_inference_over_http', async (payload: any) => {
  const result = await iii.trigger({
    function_id: 'inference::get_response',
    payload: payload.body,
  });

  return {
    status_code: 200,
    body: { result },
    headers: { 'Content-Type': 'application/json' },
  };
});

iii.registerTrigger({
  type: 'http',
  function_id: 'http::run_inference_over_http',
  config: {
    api_path: '/v1/chat/completions',
    http_method: 'POST',
  },
});
