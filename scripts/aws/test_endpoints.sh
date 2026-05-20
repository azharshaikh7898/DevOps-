#!/usr/bin/env bash
set -euo pipefail

# Usage: TEST_HOST=34.12.23.45 ./scripts/aws/test_endpoints.sh
HOST=${TEST_HOST:-}
if [ -z "$HOST" ]; then
  echo "Please set TEST_HOST to the public IP or DNS of the public API instance. Example: TEST_HOST=1.2.3.4 $0"
  exit 2
fi

echo "Checking /health"
curl -sSf "http://$HOST:${HTTP_PORT:-3111}/health" && echo " -> OK"

echo "Posting a sample request to /v1/chat/completions"
curl -sS -X POST "http://$HOST:${HTTP_PORT:-3111}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"hello"}], "max_tokens":5}' | jq -C '.' || true

echo

# For internal RPC validation, you can SSH into the public instance and use docker logs or connect locally to ws://localhost:49134

echo "Done. If the POST returned a valid response, the engine routed requests to a worker." 
