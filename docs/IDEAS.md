# Ideas: what the ESP32 community is building

A snapshot of the projects getting attention in October 2026, and what fits this
device. Star counts are approximate and move; the links are the point.

## What people are playing with

- **MCP voice assistants.** [xiaozhi-esp32](https://github.com/78/xiaozhi-esp32)
  (~31k stars) is the reference: offline wake word, WebSocket or MQTT + UDP,
  Opus streaming, streaming ASR/LLM/TTS and realtime speech-to-speech, camera
  vision on supported boards, speaker recognition, 39 languages, 171 board
  variants, and MCP on both sides — device tools (speaker, LED, servo, GPIO)
  and cloud tools (smart home, PC desktop, email, search).
- **Realtime speech-to-speech.** [ElatoAI](https://github.com/akdeb/ElatoAI)
  (~2.1k) runs OpenAI Realtime, Gemini Live, Grok Voice, ElevenLabs, and Hume
  over secure WebSockets on ESP32, with 20+ minute conversations, server VAD,
  and 100+ Pipecat pipelines. It also has a local-AI-toys path.
- **An agent that uses a phone.** [esp32-iphone-agent](https://github.com/onehumanbeing/esp32-iphone-agent)
  (~3.3k) turns a $7 ESP32 into an AirPlay receiver and USB HID mouse/keyboard,
  so a vision model can operate a real iPhone.
- **AirPlay and Bluetooth speakers.** [airplay-esp32](https://github.com/rbouteiller/airplay-esp32)
  (~600) makes an ESP32 an AirPlay 2 / A2DP speaker for about $10.
- **Wi-Fi sensing.** [RuView](https://github.com/ruvnet/RuView) (~99k) and
  [ESPectre](https://github.com/francescopace/espectre) (~9.6k) use Wi-Fi CSI
  for motion, presence, breathing, and heart-rate sensing — no camera, no
  wearable; Home Assistant, MQTT, and Matter frontends.
- **Fully offline voice.** [esp_ai](https://github.com/iamankushpandit/esp_ai)
  and [cardputer-ai](https://github.com/therezor/cardputer-ai) run wake word,
  STT, a tiny LLM (8–20M parameters), and TTS entirely on an ESP32-S3, with no
  network after NTP.
- **Home Assistant satellites.** ESPHome voice satellites (Koala-Satellite,
  Waveshare audio boards, Voice PE) combine local wake word, music and
  announcements, timers, and a status ring.
- **Music and radio.** [xiaozhi-esp32-music](https://github.com/Maggotxy/xiaozhi-esp32-music)
  adds playback to the voice assistant; the ESP32-S3 MP3 decoder is enough for
  internet radio and podcasts.
- **Tiny LLMs and clusters.** [esp32-llm](https://github.com/DaveBben/esp32-llm),
  a [56M model split across three S3 boards](https://github.com/wladimiravila/esp32s3-distributed-ai),
  and a [0.4B BitNet cluster](https://github.com/Low-Zi-Hong/ESP32s3-LLM-Cluster)
  explore how far on-device inference can go.
- **Desk pets and agent status.** [tokpet](https://github.com/grpcer/tokpet),
  [headroom](https://github.com/michellzappa/headroom), and
  [cursor_agent_status_light](https://github.com/JasonLam08/cursor_agent_status_light)
  put AI usage, quotas, and coding-agent state on a small display or LED.
- **Robots and wearables.** [rig_omni](https://github.com/LuwuDynamics/rig_omni),
  [MindPaw](https://github.com/ace-trump-tech/MindPaw), and AI pendants show
  voice + motion + emotion on small boards.

## What fits this device

The SenseCAP Watcher has an ESP32-S3, 8 MB PSRAM, a 1.45" round touch LCD, a
knob, mic, speaker, and a Himax WiseEye2 camera (640×480 stills, 416×416
preview). The Muse SDK already exposes `watcher_camera_capture()` behind
`CONFIG_MUSE_WATCHER_CAMERA`, currently off by default.

| Idea | Why it fits | Effort | Impact |
|---|---|---|---|
| **Vision mode** — "what am I looking at?" | Camera is already on the board; SDK captures JPEG; send it to a multimodal chat endpoint and speak the answer. | Medium–high | High |
| **Smart-home / MCP tools** | Add an MCP client or Home Assistant tool routing to the `openmuse` gateway; the device only speaks the result. "Turn off the lights." | Medium | High |
| **Local timers and alarms** | `esp_timer` + NTP; works offline; chime or TTS; show the countdown on the round LCD. | Low | High |
| **Music and radio** | The MP3 decoder already exists; stream a URL, duck for speech, resume. "Play some jazz." | Medium | High fun |
| **Realtime voice** | WebSocket + Opus/PCM to OpenAI Realtime / Gemini Live; lower latency, natural barge-in. | High | High |
| **OpenMuse AG-UI bridge** | Map the device's OpenAI-compatible chat to OpenMuse's AG-UI run/stop/history; see [OPENMUSE.md](OPENMUSE.md). | Medium–high | High |
| **Custom wake word** | "Hey Muse" via Espressif's WakeNet custom model; keep "Hi ESP" as a fallback. | Medium | Medium |
| **OTA updates** | HTTPS firmware updates for deployed devices; keep the NVS backup path. | Medium | High |
| **Multi-device satellite** | Several Watchers, one brain; route by room; share memory. | Medium–high | Medium |
| **Voice notes / export** | "Take a note" → openmuse memory, Obsidian, or Notion; read it back later. | Low–medium | Medium |
| **Presence via Wi-Fi CSI** | ESPectre-style motion/presence; wake or dim when someone is near. Research-heavy. | High | Medium |
| **AirPlay / Bluetooth speaker** | Reuse the speaker when idle; a separate firmware mode, not the voice path. | High | Medium |
| **Offline tiny LLM fallback** | Timers and simple commands when the network is down; 8–20M parameters. | High | Low–medium |
| **Speaker recognition** | Identify family members server-side and personalize replies. | High | Medium |
| **Games and storytelling** | 20 questions, trivia, bedtime stories, language tutor; prompt + TTS, no new hardware. | Low | Medium |
| **Accessibility / navigation** | Camera + audio description for blind or low-vision users. | High | High impact |

## Recommended next three

1. **Vision mode.** It is the biggest differentiator and the hardware is already
   there. Start with a wheel long-press or a "look" command: power the camera,
   capture one JPEG, send it as an image part to a multimodal model, speak the
   answer. The SDK's `watcher_camera_capture()` already returns base64 JPEG.
2. **Smart-home tools in `openmuse`.** Add an MCP client or a Home Assistant
   adapter to the gateway and route "turn on the lamp" / "set the thermostat"
   through it. No firmware change; the device keeps its OpenAI-compatible wire
   format.
3. **Local timers and music.** Timers are offline and immediately useful;
   music/radio uses the existing MP3 decoder and makes the device feel less like
   a Q&A box. Both are small enough to ship in one release.

Realtime voice and the OpenMuse AG-UI bridge are the two larger bets: realtime
needs a new WebSocket/Opus path, and the bridge needs a server-side translator.
Both are worth a design note before code.

## Sources

- [xiaozhi-esp32](https://github.com/78/xiaozhi-esp32) — MCP, realtime, camera,
  speaker recognition, board matrix.
- [ElatoAI](https://github.com/akdeb/ElatoAI) — realtime voice models on ESP32.
- [esp32-iphone-agent](https://github.com/onehumanbeing/esp32-iphone-agent) —
  AirPlay + USB HID agent.
- [airplay-esp32](https://github.com/rbouteiller/airplay-esp32) — AirPlay 2 /
  Bluetooth speaker.
- [ESPectre](https://github.com/francescopace/espectre) and
  [RuView](https://github.com/ruvnet/RuView) — Wi-Fi CSI sensing.
- [esp_ai](https://github.com/iamankushpandit/esp_ai) and
  [cardputer-ai](https://github.com/therezor/cardputer-ai) — offline voice.
- [Muse gadget skills](https://github.com/facebookincubator/muse-gadget-sdk/tree/main/skills)
  — 43 local device skills already in the SDK.
