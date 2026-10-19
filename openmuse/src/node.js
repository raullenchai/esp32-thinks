import { serve } from '@hono/node-server';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import app from './index.js';

const port = Number(process.env.PORT ?? 8787);
const file = process.env.MEMORY_FILE ?? join(process.cwd(), 'data', 'memories.json');
let cache;

async function get() {
  if (cache) return cache;
  try {
    cache = JSON.parse(await readFile(file, 'utf8'));
  } catch {
    cache = [];
  }
  return cache;
}

async function put(arr) {
  cache = arr;
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(arr, null, 2));
}

globalThis.__memStore = { get, put };

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`openmuse listening on http://localhost:${info.port} (memory: ${file})`);
});
