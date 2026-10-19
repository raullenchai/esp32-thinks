#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created openmuse/.env — set UPSTREAM_API_KEY and OPENMUSE_TOKEN, then run this again."
  exit 0
fi

if grep -q '^UPSTREAM_API_KEY=sk-\.\.\.' .env || grep -q '^OPENMUSE_TOKEN=choose-a-long-token' .env; then
  echo "Edit openmuse/.env first: replace the placeholder key/token." >&2
  exit 1
fi

PORT=$(awk -F= '/^PORT=/{print $2}' .env)
PORT=${PORT:-8787}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose up -d --build
  echo "openmuse running in Docker on http://localhost:${PORT}"
else
  if [ -f openmuse.pid ] && kill -0 "$(cat openmuse.pid)" 2>/dev/null; then
    echo "openmuse already running (pid $(cat openmuse.pid)) on http://localhost:${PORT}"
  else
    npm install --omit=dev
    nohup node --env-file=.env src/node.js > openmuse.log 2>&1 &
    echo $! > openmuse.pid
    echo "openmuse running (pid $(cat openmuse.pid)) on http://localhost:${PORT}"
  fi
fi

sleep 1
curl -fsS "http://localhost:${PORT}/healthz" || true
echo

if [ "${1:-}" = "--funnel" ]; then
  if command -v tailscale >/dev/null 2>&1; then
    sudo tailscale funnel --bg "$PORT"
    HOST=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
    echo "Public URL: https://$HOST"
  else
    echo "tailscale not found — expose port ${PORT} with a Cloudflare named tunnel or ngrok instead." >&2
  fi
fi

echo
echo "Next: ./apply.sh --preset openmuse"
echo "  chat URL: https://<host>/v1"
echo "  token:    $(awk -F= '/^OPENMUSE_TOKEN=/{print $2}' .env)"
