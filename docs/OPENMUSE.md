# OpenMuse integration

There are two different projects called openmuse, and they sit on opposite
sides of the device:

1. **`openmuse/` in this repo** — a small OpenAI-compatible gateway. It gives
   the gadget a location, a clock, weather, persistent memory, optional web
   search, and an STT proxy, then forwards chat to any OpenAI-compatible LLM.
   This is the path the firmware's `openmuse` preset uses.
2. **[CopilotKit/OpenMuse](https://github.com/CopilotKit/openmuse)** — a
   personal-agent application with an AG-UI runtime, a browser, a terminal, and
   durable tasks. It is **not** an OpenAI-compatible endpoint. The gadget
   cannot talk to it directly.

This document covers the first path end to end, then describes the boundary and
the gateway contract needed for the second. The firmware side is the same in
both cases: three independent OpenAI-compatible endpoints over HTTPS.

## What the device speaks

| Stage | Request | Response |
|---|---|---|
| STT | `POST /v1/audio/transcriptions`, multipart WAV (optionally IMA ADPCM) | JSON `{"text": "..."}` |
| Chat | `POST /v1/chat/completions`, JSON, `stream: true` | SSE `chat.completion.chunk` deltas |
| TTS | `POST /v1/audio/speech`, JSON (`model`, `voice`, `input`, `response_format`) | MP3 bytes |

- Auth is `Authorization: Bearer <token>` on every endpoint.
- The firmware is **HTTPS only** and pins public roots (Google Trust Services
  and Let's Encrypt). Self-signed certificates on the LAN do not work.
- STT and chat may share one TLS session; TTS is a separate connection in the
  `openmuse` preset. The gateway's STT proxy is what makes the shared session
  possible.
- The device splits the chat stream at sentence boundaries and starts TTS for
  each sentence while the rest of the reply is still arriving.

## The in-repo gateway (`openmuse/`)

### Quick start

```bash
./openmuse/run.sh              # first run writes openmuse/.env, then exits
$EDITOR openmuse/.env          # set UPSTREAM_API_KEY + OPENMUSE_TOKEN
./openmuse/run.sh --funnel     # Docker or Node; --funnel exposes HTTPS via Tailscale
./apply.sh ../muse-gadget-sdk --preset openmuse
#   chat URL: https://<host>/v1
#   token:    OPENMUSE_TOKEN
```

`run.sh` uses Docker when available (`docker compose up -d --build`) and falls
back to Node (`npm install --omit=dev`, background process, pid in
`openmuse/openmuse.pid`). Memory persists in `openmuse/data/memories.json`.
Stop it with `docker compose down` (from `openmuse/`) or
`kill $(cat openmuse/openmuse.pid)`.

### What it adds

- **Location and clock** — detects the host's city/timezone (ipwho.is, cached)
  and injects them into the system prompt. "What's the weather?" works without
  a city; "What time is it?" works without a timezone. Override with
  `DEFAULT_CITY` / `DEFAULT_TZ`.
- **Weather** — open-meteo, free and keyless: current temperature, feels-like,
  conditions, wind, today's range, and rain chance. Named cities work in
  English and Chinese.
- **Memory** — "remember that ..." / "记住..." is stored on disk (Node) or KV
  (Workers) and injected into later turns.
- **Web search** — optional Tavily, only for explicit search or latest-news
  asks.
- **STT proxy** — `/v1/audio/transcriptions` forwards to the configured STT
  provider, so STT and chat share one TLS session.
- **Pass-through** — everything else is streamed from the upstream unchanged.
  No extra model round trip.

Tools are routed by pattern, so a tool answer is as fast as plain chat, and any
OpenAI-compatible upstream works without function-calling support.

### Endpoints

- `POST /v1/chat/completions` — chat (SSE pass-through plus tools)
- `POST /v1/audio/transcriptions` — STT proxy
- `GET /v1/models` — static list for clients that probe
- `GET /healthz` — detected location, timezone, and config flags
- `GET /` — liveness text

### Configuration (`openmuse/.env`)

| Variable | Required | Purpose |
|---|---|---|
| `UPSTREAM_BASE_URL` | yes | LLM endpoint (with or without `/v1`) |
| `UPSTREAM_API_KEY` | yes | key for that endpoint |
| `OPENMUSE_TOKEN` | recommended | bearer token the gadget must present |
| `STT_UPSTREAM_URL` | for STT proxy | full transcription endpoint URL |
| `STT_UPSTREAM_KEY` | no | defaults to `UPSTREAM_API_KEY` |
| `DEFAULT_MODEL` | no | overrides the model the gadget asks for |
| `DEFAULT_CITY` / `DEFAULT_TZ` | no | override auto-detection |
| `MEMORY_FILE` | no | Node only; defaults to `./data/memories.json` |
| `TAVILY_API_KEY` | no | enables web search |

### Expose it to the gadget

The firmware needs a publicly trusted certificate. In order of simplicity:

1. **Tailscale Funnel** — `./openmuse/run.sh --funnel` runs
   `sudo tailscale funnel --bg 8787` and prints `https://<machine>.<tailnet>.ts.net`.
2. **Cloudflare named tunnel** — `cloudflared tunnel --url http://localhost:8787`
   with a hostname on your own domain.
3. **ngrok** — `ngrok http 8787` with a static domain.

Cloudflare *quick* tunnels (`trycloudflare.com`) are not reliable here: the
hostname is served by one edge, and a device that resolves to another edge gets
a fatal TLS alert (`-0x2700`).

### Cloudflare Workers (optional)

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
headers instead of ipwho.is, which would geolocate the edge rather than the
user.

### Security

- Keep `UPSTREAM_API_KEY`, `STT_UPSTREAM_KEY`, and `TAVILY_API_KEY` on the
  gateway. The device only receives `OPENMUSE_TOKEN`.
- Use a long random token; it authenticates both chat and STT.
- Treat model output and tool results as data. The gateway does not grant
  actions or approvals to the device.
- The gateway is a personal service: bind it to localhost and expose only the
  TLS endpoint (Funnel or named tunnel).

### Troubleshooting

| Symptom | Likely cause |
|---|---|
| `-0x2700` during TLS handshake | quick tunnel on the wrong edge, or a self-signed cert |
| `401` from chat or STT | token mismatch between `OPENMUSE_TOKEN` and `BRAIN_CHAT_KEY` |
| `502` / empty stream | upstream base URL missing `/v1`, or the upstream key is wrong |
| Weather says the wrong city | set `DEFAULT_CITY` / `DEFAULT_TZ` |
| Memory does not survive a restart | Node: check `MEMORY_FILE`; Workers: check the KV binding |
| Docker and Node both running | `docker compose down` first, then check `openmuse.pid` |

## Connecting to CopilotKit/OpenMuse (upstream)

CopilotKit/OpenMuse is a personal-agent app, not a chat-completions server. Its
agent transport is AG-UI under `/api/copilotkit` (run, connect, stop, history),
and its runtime responses are Intelligence connection metadata rather than raw
OpenAI SSE. The ESP32 has no AG-UI client and no room for the CopilotKit
runtime, so a direct connection is not possible.

The integration pattern is a **server-side gateway**:

```text
ESP32 ── OpenAI Chat Completions (SSE) ──▶ gateway ── AG-UI RunAgentInput ──▶ OpenMuse
      ── multipart STT ──────────────────▶ gateway ── STT provider
      ── OpenAI audio/speech ────────────▶ TTS provider (direct)
```

The gateway must:

1. Accept `POST /v1/chat/completions` with `stream: true` and authenticate the
   device with a bearer token.
2. Map the request to an OpenMuse AG-UI run with a stable thread per device
   (for example, one thread per hardware ID). Preserve `threadId`, `runId`, and
   `forwardedProps` across reconnect.
3. Translate AG-UI text deltas into OpenAI `chat.completion.chunk` events and
   end with `data: [DONE]`.
4. Accept `POST /v1/audio/transcriptions`, forward the multipart audio to the
   configured STT provider, and return `{"text": "..."}`.
5. Pass cancellation through to OpenMuse's stop endpoint. The device cancels
   in-flight requests on barge-in.
6. Keep all OpenMuse and provider credentials server-side. The device only sees
   the gateway token.
7. Surface failures honestly: an unavailable agent or refused action must not
   be replaced by a fabricated success.

TTS stays on the device's configured speech endpoint. OpenMuse's roadmap lists
voice input/replies as a product extension; the gateway above is the smallest
useful bridge and does not require changes to the firmware.

### What is not implemented here

- No AG-UI client on the device and no direct OpenMuse connection.
- No device push notifications, voice notes, or generated media.
- Tool calls, approvals, and durable tasks stay on the OpenMuse server; the
  device only hears the spoken reply.
- The gateway contract above is a design, not a tested deployment. The tested
  path is the in-repo `openmuse/` gateway against an OpenAI-compatible LLM.

## Verification

Tested on a Seeed SenseCAP Watcher (ESP32-S3, 16 MB flash / 8 MB PSRAM) with the
in-repo gateway:

- `curl /healthz` returns the detected city/timezone and config flags.
- Typed turns exercise chat and TTS without microphone capture
  (`python3 scripts/tts_probe.py <sdk> <port> "question"`).
- Voice turns exercise wake word → STT proxy → chat → streaming TTS.
- Memory survives a gateway restart (`data/memories.json`).
- The gateway passes `node --check src/index.js src/node.js` and the repo CI
  shellcheck.

Not tested: a live CopilotKit/OpenMuse AG-UI bridge, its run/reconnect/stop
paths, and a real OpenMuse deployment. Treat the upstream section as an
integration boundary and a starting point, not a claim of a working connection.

## See also

- [openmuse/README.md](../openmuse/README.md) — gateway quick start, config, and
  Workers deployment.
- [README.md](../README.md) — firmware quick start, presets, and performance.
- [docs/REFERENCE.md](REFERENCE.md) — build, flash, provisioning, and the full
  configuration reference.
