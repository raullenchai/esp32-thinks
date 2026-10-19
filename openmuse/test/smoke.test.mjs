import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import app from '../src/index.js';

before(() => {
  process.env.OPENMUSE_TOKEN = 'test-token';
  delete process.env.UPSTREAM_BASE_URL;
  delete process.env.STT_UPSTREAM_URL;
});

after(() => {
  delete process.env.OPENMUSE_TOKEN;
});

test('liveness text', async () => {
  const res = await app.request('/');
  assert.equal(res.status, 200);
  assert.match(await res.text(), /openmuse is running/);
});

test('healthz uses the edge location and reports config', async () => {
  const res = await app.request('/healthz', {
    headers: { 'cf-ipcity': 'Testville', 'cf-timezone': 'UTC' },
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.location.city, 'Testville');
  assert.equal(body.upstream, false);
  assert.equal(body.sttProxy, false);
});

test('models require the bearer token', async () => {
  const denied = await app.request('/v1/models');
  assert.equal(denied.status, 401);

  const allowed = await app.request('/v1/models', {
    headers: { authorization: 'Bearer test-token' },
  });
  assert.equal(allowed.status, 200);
  const body = await allowed.json();
  assert.equal(body.data[0].id, 'openmuse');
});

test('chat without an upstream is a clear 500', async () => {
  const res = await app.request('/v1/chat/completions', {
    method: 'POST',
    headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'x', messages: [{ role: 'user', content: 'hi' }] }),
  });
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.match(body.error, /UPSTREAM_BASE_URL/);
});

test('STT without a proxy target is a clear 500', async () => {
  const res = await app.request('/v1/audio/transcriptions', {
    method: 'POST',
    headers: { authorization: 'Bearer test-token' },
    body: new Uint8Array([0]),
  });
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.match(body.error, /STT_UPSTREAM_URL/);
});
