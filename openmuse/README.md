# openmuse (in this repo)

A tiny agent layer between the Muse gadget and any OpenAI-compatible LLM. Same
wire protocol (chat completions + SSE), so the device can't tell the difference
— except the answers now know where you are, what time it is, and what you told
it last week.

This is the optional "own brain" path. QuickSilver alone is the fastest setup;
openmuse adds location, weather, time, memory, and a single TLS session for
STT + chat.

## What it does

- **Location + clock** — detects the host's city/timezone (ipwho.is, cached) and
  puts it in every system prompt. "What's the weather?" works with no city;
  "What time is it?" works with no timezone. Override with `DEFAULT_CITY` /
  `DEFAULT_TZ`.
- **Weather** — open-meteo (free, no key): current temperature, feels-like,
  conditions, wind, today's range and rain chance. Named cities work in EN/中文.
- **Memory** — "remember that ..." / "记住..." is stored on disk (Node) or KV
  (Workers) and injected into later turns.
- **Time/date** — answered from the detected or configured timezone.
- **Web search** — optional Tavily, only for explicit search/latest-news asks.
- **STT proxy** — `/v1/audio/transcriptions` forwards to your STT provider, so
  the gadget keeps one TLS session for both transcription and chat.
- Everything else is a pure streaming passthrough — no extra LLM round trip.

Tools are routed by pattern, so tool answers are as fast as plain chat, and any
OpenAI-compatible upstream works — no function-calling support required.

## Quick start (from the repo root)

```bash
./openmuse/run.sh                # first run writes openmuse/.env, then exits
$EDITOR openmuse/.env            # set UPSTREAM_API_KEY + OPENMUSE_TOKEN
./openmuse/run.sh --funnel       # starts it and (if Tailscale is present) exposes HTTPS
./apply.sh ../muse-gadget-sdk --preset openmuse   # chat URL: https://<host>/v1, token: OPENMUSE_TOKEN
```

`run.sh` uses Docker when available (`docker compose up -d --build`) and falls
back to Node (`npm install --omit=dev` + background process, pid in
`openmuse/openmuse.pid`). Memory persists in `openmuse/data/memories.json`.

Stop it with `docker compose down` (from `openmuse/`) or `kill $(cat openmuse/openmuse.pid)`.

## Expose it to the gadget

The firmware talks **HTTPS only** and pins Let's Encrypt roots, so the endpoint
needs a real certificate. Easiest options, in order:

1. **Tailscale Funnel** (no domain needed):
   ```bash
   sudo tailscale funnel --bg 8787   # → https://<machine>.<tailnet>.ts.net
   ```
   `./openmuse/run.sh --funnel` does this for you.
2. **Cloudflare named tunnel** (needs a domain on Cloudflare):
   `cloudflared tunnel --url http://localhost:8787`
3. **ngrok** (free static domain): `ngrok http 8787`

Cloudflare *quick* tunnels (`trycloudflare.com`) are not reliable for devices:
the hostname is only served by the edge node cloudflared is attached to, so a
device resolving to another edge gets a fatal TLS alert (`-0x2700`).

## Config (`openmuse/.env`)

| Variable | Required | Purpose |
|---|---|---|
| `UPSTREAM_BASE_URL` | yes | LLM endpoint (with or without `/v1`) |
| `UPSTREAM_API_KEY` | yes | key for that endpoint |
| `OPENMUSE_TOKEN` | recommended | token the gadget must present |
| `STT_UPSTREAM_URL` | for STT proxy | full transcription endpoint URL |
| `STT_UPSTREAM_KEY` | no | defaults to `UPSTREAM_API_KEY` |
| `DEFAULT_MODEL` | no | overrides the model the gadget asks for |
| `DEFAULT_CITY` / `DEFAULT_TZ` | no | override auto-detection |
| `MEMORY_FILE` | no | Node only; defaults to `./data/memories.json` |
| `TAVILY_API_KEY` | no | enables web search |

## Endpoints

- `POST /v1/chat/completions` — the brain (SSE passthrough + tools)
- `POST /v1/audio/transcriptions` — STT proxy
- `GET /v1/models` — static list, for clients that probe
- `GET /healthz` — detected location, timezone, config flags
- `GET /` — liveness text

## Deploy to Cloudflare Workers (optional)

```bash
cd openmuse
npx wrangler kv namespace create MEMKV   # put the id in wrangler.jsonc
npx wrangler secret put UPSTREAM_BASE_URL
npx wrangler secret put UPSTREAM_API_KEY
npx wrangler secret put OPENMUSE_TOKEN
npx wrangler secret put STT_UPSTREAM_URL
npx wrangler secret put TAVILY_API_KEY   # optional
npm run deploy
```

On Workers, location comes from Cloudflare's `cf-ipcity` / `cf-timezone`
headers instead of ipwho.is (which would geolocate the edge, not the user).

## Tests

```bash
npm test
```

Runs the Hono smoke tests: liveness, `/healthz` with edge location headers,
bearer-token enforcement, and clear errors when the upstream or STT proxy is
not configured. No network access or credentials are needed.

## See also

- [docs/OPENMUSE.md](../docs/OPENMUSE.md) — protocol, deployment, the
  CopilotKit/OpenMuse AG-UI boundary, and troubleshooting.
- [README.md](../README.md) — firmware quick start, presets, and performance.
