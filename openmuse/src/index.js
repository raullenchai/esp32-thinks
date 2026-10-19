import { Hono } from 'hono';

const WMO = {
  0: 'clear sky', 1: 'mainly clear', 2: 'partly cloudy', 3: 'overcast',
  45: 'fog', 48: 'rime fog',
  51: 'light drizzle', 53: 'drizzle', 55: 'heavy drizzle',
  61: 'light rain', 63: 'rain', 65: 'heavy rain',
  66: 'freezing rain', 67: 'heavy freezing rain',
  71: 'light snow', 73: 'snow', 75: 'heavy snow', 77: 'snow grains',
  80: 'light showers', 81: 'showers', 82: 'violent showers',
  85: 'snow showers', 86: 'heavy snow showers',
  95: 'thunderstorm', 96: 'thunderstorm with hail', 99: 'severe thunderstorm',
};

const CN_CITIES = '北京|上海|广州|深圳|杭州|成都|重庆|西安|武汉|南京|天津|苏州|长沙|郑州|青岛|大连|厦门|福州|合肥|昆明|香港|澳门|台北|高雄';

const WEATHER_RE = /weather|forecast|temperature|rain|snow|umbrella|jacket|coat|humid|windy|sunny|cloudy|outside|hot|cold|天气|气温|下雨|下雪|带伞|穿什么|冷不冷|热不热|温度/i;
const TIME_RE = /what time|current time|today'?s date|what day|几点|现在.*时间|今天.*几号|今天.*星期/i;
const RECALL_RE = /what (do|have) you (remember|know) about me|what have i told you|do you remember|你知道我什么|你还记得什么|我之前说过什么/i;
const SEARCH_RE = /\b(search for|search the web|look up|latest|news|headlines)\b|搜索|查一下|最新/i;
const REMEMBER_RE = /^remember (?:that )?(.+?)[.?]*$/is;
const REMEMBER_ZH_RE = /^记住(.+)$/s;

function pickEnv(c, key) {
  const v = c.env?.[key] ?? (typeof process !== 'undefined' ? process.env?.[key] : undefined);
  return typeof v === 'string' && v.length ? v : undefined;
}

const localMem = new Map();
async function memGet(c) {
  const kv = c.env?.MEMKV;
  if (kv?.get) return (await kv.get('memories', 'json')) ?? [];
  const store = globalThis.__memStore;
  if (store) return store.get();
  return localMem.get('memories') ?? [];
}
async function memPut(c, arr) {
  const kv = c.env?.MEMKV;
  if (kv?.put) return void (await kv.put('memories', 'json', arr));
  const store = globalThis.__memStore;
  if (store) return store.put(arr);
  localMem.set('memories', arr);
}

let locCache;
async function detectLocation(c) {
  if (locCache) return locCache;
  const city = c.req.header('cf-ipcity');
  if (city) {
    locCache = {
      city,
      country: c.req.header('cf-ipcountry') ?? '',
      tz: c.req.header('cf-timezone') ?? 'UTC',
    };
    return locCache;
  }
  try {
    const r = await fetch('https://ipwho.is/', { signal: AbortSignal.timeout(5000) }).then((r) => r.json());
    if (r?.success) {
      locCache = {
        city: r.city,
        region: r.region,
        country: r.country,
        lat: r.latitude,
        lon: r.longitude,
        tz: r.timezone?.id,
      };
    }
  } catch {
    /* no location available */
  }
  return locCache;
}

async function geocode(city) {
  const lang = /[^\x00-\x7F]/.test(city) ? 'zh' : 'en';
  const r = await fetch(
    `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city)}&count=1&language=${lang}&format=json`,
    { signal: AbortSignal.timeout(6000) }
  ).then((r) => r.json());
  const g = r.results?.[0];
  return g ? { lat: g.latitude, lon: g.longitude, name: g.name, country: g.country } : null;
}

async function weather(loc, cityOverride) {
  let g;
  if (cityOverride) g = await geocode(cityOverride);
  else if (loc?.lat != null) g = { lat: loc.lat, lon: loc.lon, name: loc.city, country: loc.country };
  if (!g) return null;
  const r = await fetch(
    `https://api.open-meteo.com/v1/forecast?latitude=${g.lat}&longitude=${g.lon}` +
      `&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m` +
      `&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&forecast_days=1&timezone=auto`,
    { signal: AbortSignal.timeout(6000) }
  ).then((r) => r.json());
  const cur = r.current, day = r.daily;
  return (
    `Weather in ${g.name}${g.country ? `, ${g.country}` : ''}: ` +
    `${Math.round(cur.temperature_2m)}°C (feels like ${Math.round(cur.apparent_temperature)}°C), ` +
    `${WMO[cur.weather_code] ?? 'unknown'}, wind ${Math.round(cur.wind_speed_10m)} km/h; ` +
    `today ${Math.round(day.temperature_2m_min[0])}–${Math.round(day.temperature_2m_max[0])}°C, ` +
    `${day.precipitation_probability_max?.[0] ?? 0}% chance of rain.`
  );
}

function clock(tz) {
  const now = new Date();
  return now.toLocaleString('en-US', {
    timeZone: tz,
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

async function tavily(key, query) {
  const r = await fetch('https://api.tavily.com/search', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ api_key: key, query, max_results: 3 }),
    signal: AbortSignal.timeout(8000),
  }).then((r) => r.json());
  const items = (r.results ?? []).map((x, i) => `[${i + 1}] ${x.title}: ${x.content?.slice(0, 300)}`);
  return items.length ? `Web search results for "${query}":\n${items.join('\n')}` : null;
}

function extractCity(text) {
  const zhM = text.match(new RegExp(`(${CN_CITIES})`));
  if (zhM) return zhM[1];
  const m = text.match(/\b(?:in|at|for)\s+([A-Za-z][A-Za-z\s.'-]{1,30}?)(?:\?|$|,| today| now| right| this)/i);
  return m ? m[1].trim() : null;
}

function sseChunk(content) {
  return (
    'data: ' +
    JSON.stringify({
      id: 'openmuse', object: 'chat.completion.chunk', created: Date.now() / 1000 | 0, model: 'openmuse',
      choices: [{ index: 0, delta: { role: 'assistant', content }, finish_reason: null }],
    }) +
    '\n\n'
  );
}
const SSE_HEADERS = {
  'content-type': 'text/event-stream',
  'cache-control': 'no-cache',
  connection: 'keep-alive',
};
function systemPrompt(loc, tz, memories) {
  let sys = `You are Muse, a warm voice assistant living in a small speaker.
Reply in the same language the user writes in (English if unsure or mixed).
Speak naturally: one or two short sentences, at most about 40 words or 60 Chinese characters, unless the user asks for more.
Never use markdown, lists, emoji, or stage directions — your answer is read aloud.
Never greet with "Hi ESP" or mention wake words.
If the input is nothing but a greeting or the wake phrase, reply exactly: Please ask.`;
  if (loc?.city) {
    sys += `\n\nThe user is in ${loc.city}${loc.region ? `, ${loc.region}` : ''}${loc.country ? `, ${loc.country}` : ''}. ` +
      `Local time: ${clock(tz)}. Use this context naturally when relevant — never claim you cannot know the time or the user's location.`;
  } else {
    sys += `\n\nLocal time: ${clock(tz)}.`;
  }
  if (memories.length) {
    sys += `\n\nThings you remember about the user (from earlier conversations):\n- ${memories.slice(0, 10).join('\n- ')}`;
  }
  return sys;
}

const app = new Hono();

app.use('/v1/*', async (c, next) => {
  const token = pickEnv(c, 'OPENMUSE_TOKEN');
  if (token) {
    const auth = c.req.header('authorization') ?? '';
    if (auth !== `Bearer ${token}`) return c.json({ error: 'unauthorized' }, 401);
  }
  await next();
});

app.get('/', (c) => c.text('openmuse is running. POST /v1/chat/completions'));

app.get('/healthz', async (c) => {
  const loc = await detectLocation(c);
  return c.json({
    ok: true,
    location: loc ? { city: loc.city, region: loc.region, country: loc.country, tz: loc.tz } : null,
    upstream: !!pickEnv(c, 'UPSTREAM_BASE_URL'),
    sttProxy: !!pickEnv(c, 'STT_UPSTREAM_URL'),
  });
});

app.get('/v1/models', (c) =>
  c.json({ object: 'list', data: [{ id: 'openmuse', object: 'model', owned_by: 'openmuse' }] })
);

app.post('/v1/audio/transcriptions', async (c) => {
  const url = pickEnv(c, 'STT_UPSTREAM_URL');
  if (!url) return c.json({ error: 'STT_UPSTREAM_URL not configured' }, 500);
  const headers = new Headers();
  const ct = c.req.header('content-type');
  if (ct) headers.set('content-type', ct);
  headers.set('authorization', `Bearer ${pickEnv(c, 'STT_UPSTREAM_KEY') ?? pickEnv(c, 'UPSTREAM_API_KEY') ?? ''}`);
  let upstream;
  try {
    upstream = await fetch(url, {
      method: 'POST',
      headers,
      body: c.req.raw.body,
      ...(typeof process !== 'undefined' ? { duplex: 'half' } : {}),
    });
  } catch (e) {
    return c.json({ error: 'stt upstream unreachable', detail: String(e).slice(0, 200) }, 502);
  }
  const out = new Headers();
  const upstreamCt = upstream.headers.get('content-type');
  if (upstreamCt) out.set('content-type', upstreamCt);
  return new Response(upstream.body, { status: upstream.status, headers: out });
});

app.post('/v1/chat/completions', async (c) => {
  const base = pickEnv(c, 'UPSTREAM_BASE_URL');
  if (!base) return c.json({ error: 'UPSTREAM_BASE_URL not configured' }, 500);
  const started = Date.now();
  const body = await c.req.json();
  const msgs = body.messages ?? [];
  const sysIdx = msgs.findIndex((m) => m.role === 'system');
  const userMsg = [...msgs].reverse().find((m) => m.role === 'user')?.content ?? '';
  const text = typeof userMsg === 'string' ? userMsg : '';

  const loc = await detectLocation(c);
  const tz = pickEnv(c, 'DEFAULT_TZ') ?? loc?.tz ?? 'UTC';
  const city0 = pickEnv(c, 'DEFAULT_CITY') ?? loc?.city;
  let memories = (await memGet(c)) ?? [];
  let tool = 'chat';
  let weatherData = null;
  let searchData = null;
  let remembered = null;

  const remember = text.match(REMEMBER_RE) ?? text.match(REMEMBER_ZH_RE);
  if (remember) {
    tool = 'remember';
    remembered = remember[1].trim();
    memories = [`${new Date().toISOString().slice(0, 10)}: ${remembered}`, ...memories];
    await memPut(c, memories.slice(0, 50));
  } else if (RECALL_RE.test(text)) {
    tool = 'recall';
  } else if (WEATHER_RE.test(text)) {
    tool = 'weather';
    try {
      weatherData = await weather(loc, extractCity(text));
    } catch {
      /* fall through */
    }
  } else if (TIME_RE.test(text)) {
    tool = 'time';
  } else if (SEARCH_RE.test(text)) {
    const tkey = pickEnv(c, 'TAVILY_API_KEY');
    if (tkey) {
      tool = 'search';
      try {
        searchData = await tavily(tkey, text.replace(/^search (?:for|the web(?: for)?)\s*/i, '').replace(/[?]/g, ''));
      } catch {
        /* ignore */
      }
    }
  }

  let sys = systemPrompt(loc, tz, memories);
  if (weatherData) sys += `\n\nREAL-TIME DATA:\n${weatherData}`;
  if (searchData) sys += `\n\nREAL-TIME DATA:\n${searchData}`;
  if (remembered) sys += `\n\nThe user just asked you to remember: "${remembered}". Acknowledge briefly and naturally.`;

  const out = [...msgs];
  out.splice(sysIdx >= 0 ? sysIdx : 0, sysIdx >= 0 ? 1 : 0, { role: 'system', content: sys });

  const url = base.replace(/\/+$/, '') + (base.endsWith('/v1') ? '' : '/v1') + '/chat/completions';
  const payload = { ...body, messages: out, stream: true };
  const dm = pickEnv(c, 'DEFAULT_MODEL');
  if (dm) payload.model = dm;
  let upstream;
  try {
    upstream = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${pickEnv(c, 'UPSTREAM_API_KEY') ?? ''}`,
      },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    return c.json({ error: 'upstream unreachable', detail: String(e).slice(0, 200) }, 502);
  }

  console.log(`[turn] ${Date.now() - started}ms tool=${tool} :: ${text.slice(0, 100)}`);

  if (!upstream.ok || !upstream.body) {
    const detail = await upstream.text().catch(() => '');
    return c.json({ error: 'upstream error', status: upstream.status, detail: detail.slice(0, 500) }, 502);
  }
  return new Response(upstream.body, { headers: SSE_HEADERS });
});

export default app;
