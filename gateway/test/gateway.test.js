// Tests run the real gateway against a fake "Gemini" server, so no API key or internet is needed.
// Run: npm test

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

let fake, gateway, gatewayUrl, lastUpstreamBody, upstreamMode = 'ok';

before(async () => {
  fake = http.createServer(async (req, res) => {
    let raw = '';
    for await (const c of req) raw += c;
    lastUpstreamBody = JSON.parse(raw);
    if (upstreamMode === '429') {
      res.writeHead(429, { 'content-type': 'application/json' });
      return res.end('{"error":{"message":"quota"}}');
    }
    const answer = upstreamMode === 'empty' ? '' : 'We open at 8:00 AM on Saturday.';
    if (lastUpstreamBody.stream) {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      for (const part of answer ? ['We open ', 'at 8:00 AM.'] : ['']) {
        res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: part } }] })}\n\n`);
      }
      return res.end('data: [DONE]\n\n');
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ model: 'gemini-x', choices: [{ message: { role: 'assistant', content: answer } }] }));
  });
  await new Promise((r) => fake.listen(0, r));

  process.env.UPSTREAM_BASE_URL = `http://127.0.0.1:${fake.address().port}`;
  process.env.GEMINI_API_KEY = 'test-key-not-real';
  process.env.GATEWAY_TOKEN = 'test-token';
  process.env.CONTENT_REFRESH_SECONDS = '0';

  const { createServer } = await import('../src/server.js');
  const { reloadContent } = await import('../src/content.js');
  await reloadContent();
  gateway = createServer();
  await new Promise((r) => gateway.listen(0, r));
  gatewayUrl = `http://127.0.0.1:${gateway.address().port}`;
});

after(() => { gateway?.close(); fake?.close(); });

const auth = { authorization: 'Bearer test-token', 'content-type': 'application/json' };
const chat = (body, headers = auth) =>
  fetch(`${gatewayUrl}/v1/chat/completions`, { method: 'POST', headers, body: JSON.stringify(body) });

test('health reports the café documents as loaded', async () => {
  const res = await fetch(`${gatewayUrl}/health`);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.status, 'ok');
  assert.ok(body.docs >= 5, `expected the 5 café docs, got ${body.docs}`);
});

test('requests without the gateway token are rejected', async () => {
  const res = await chat({ messages: [{ role: 'user', content: 'hi' }] }, { 'content-type': 'application/json' });
  assert.equal(res.status, 401);
});

test('café knowledge is sent first as the system prompt, and the model name is rewritten', async () => {
  upstreamMode = 'ok';
  const res = await chat({ model: 'lumen-barista', user: 'x', messages: [{ role: 'user', content: 'Saturday hours?' }] });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.match(body.choices[0].message.content, /8:00/);
  assert.equal(lastUpstreamBody.messages[0].role, 'system');
  assert.match(lastUpstreamBody.messages[0].content, /Session Road/);
  assert.equal(lastUpstreamBody.messages.at(-1).content, 'Saturday hours?');
  assert.equal(lastUpstreamBody.user, undefined, 'unsupported fields must not be forwarded');
  assert.notEqual(lastUpstreamBody.model, 'lumen-barista');
});

test('streaming answers are passed through', async () => {
  upstreamMode = 'ok';
  const res = await chat({ stream: true, messages: [{ role: 'user', content: 'Saturday hours?' }] });
  assert.equal(res.status, 200);
  const text = await res.text();
  assert.match(text, /8:00 AM/);
  assert.match(text, /\[DONE\]/);
});

test('a rate-limited model gives a friendly 429', async () => {
  upstreamMode = '429';
  const res = await chat({ messages: [{ role: 'user', content: 'hi' }] });
  assert.equal(res.status, 429);
  assert.match((await res.json()).error.message, /busy/);
});

test('bad input gives a 400', async () => {
  const res = await chat({ messages: [] });
  assert.equal(res.status, 400);
});
