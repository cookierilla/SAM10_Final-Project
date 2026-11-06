// brew-gateway: an OpenAI-compatible endpoint that LibreChat calls as a "custom endpoint".
// For each chat request it:
//   1. puts the café knowledge (from local files or S3) first as the system prompt,
//   2. forwards the conversation to Gemini's OpenAI-compatible API, using a key read at runtime,
//   3. streams the answer back to LibreChat,
//   4. writes one JSON log line (question, duration, success, versions) that also becomes CloudWatch metrics.
//
// Routes:
//   GET  /health               -> 200 if content is loaded (used by Docker, Caddy and the health-check automation)
//   GET  /v1/models            -> the one model name LibreChat should show
//   POST /v1/chat/completions  -> the chat proxy

import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { config } from './config.js';
import { log, logRequest } from './log.js';
import { getContent, reloadContent, startContentRefresh } from './content.js';
import { getGeminiKey } from './secrets.js';

const MAX_BODY_BYTES = 2 * 1024 * 1024;
// Only these request fields are forwarded. Gemini's compatibility layer rejects some
// OpenAI-only fields that LibreChat may send.
const FORWARDED_FIELDS = ['temperature', 'top_p', 'max_tokens', 'max_completion_tokens', 'stop', 'n'];

function sendJson(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data) });
  res.end(data);
}

function openAiError(res, status, message, type = 'gateway_error') {
  sendJson(res, status, { error: { message, type, code: status } });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('request body too large'), { status: 413 }));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.filter((p) => p?.type === 'text').map((p) => p.text).join(' ');
  return '';
}

export function lastUserQuestion(messages) {
  const last = [...messages].reverse().find((m) => m.role === 'user');
  return last ? textOf(last.content) : '';
}

export function buildUpstreamBody(body, systemPrompt) {
  const out = { model: config.upstreamModel, stream: Boolean(body.stream) };
  for (const f of FORWARDED_FIELDS) if (body[f] !== undefined) out[f] = body[f];
  // Our café prompt always comes first. Any system message LibreChat adds (e.g. a preset) follows it.
  const messages = body.messages.map((m) => ({ role: m.role, content: m.content }));
  out.messages = [{ role: 'system', content: systemPrompt }, ...messages];
  return out;
}

function authorised(req) {
  if (!config.gatewayToken) return true;
  return req.headers.authorization === `Bearer ${config.gatewayToken}`;
}

async function handleChat(req, res) {
  const started = Date.now();
  const requestId = randomUUID();
  const content = getContent();
  const record = {
    requestId,
    question: '',
    stream: false,
    contentVersion: content.contentVersion,
    success: false,
    emptyAnswer: false,
    answerChars: 0,
    httpStatus: 500,
  };
  const finish = (extra) => {
    Object.assign(record, extra, { durationMs: Date.now() - started });
    logRequest(record);
  };

  let body;
  try {
    body = JSON.parse(await readBody(req));
  } catch (err) {
    finish({ httpStatus: err.status ?? 400, error: 'invalid JSON body' });
    return openAiError(res, err.status ?? 400, 'Invalid request body', 'invalid_request_error');
  }
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    finish({ httpStatus: 400, error: 'messages missing' });
    return openAiError(res, 400, '"messages" must be a non-empty array', 'invalid_request_error');
  }
  record.question = lastUserQuestion(body.messages).slice(0, config.logQuestionChars);
  record.stream = Boolean(body.stream);

  if (!content.prompt) {
    finish({ httpStatus: 503, error: `café content not loaded: ${content.lastError}` });
    return openAiError(res, 503, 'The café knowledge base is not available right now. Please try again shortly.');
  }

  let key;
  try {
    key = await getGeminiKey();
  } catch (err) {
    finish({ httpStatus: 503, error: `api key unavailable: ${err.message}` });
    return openAiError(res, 503, 'The assistant is not configured correctly (model key unavailable).');
  }

  let upstream;
  try {
    upstream = await fetch(`${config.upstreamBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
      body: JSON.stringify(buildUpstreamBody(body, content.prompt)),
      signal: AbortSignal.timeout(config.upstreamTimeoutMs),
    });
  } catch (err) {
    const timedOut = err.name === 'TimeoutError';
    finish({ httpStatus: 504, error: timedOut ? 'upstream timeout' : `upstream unreachable: ${err.message}` });
    return openAiError(res, timedOut ? 504 : 502, 'The AI model did not respond. Please try again.');
  }

  if (!upstream.ok) {
    // Keep the upstream's error text in our log (it never contains our key), but give the user a short message.
    const detail = (await upstream.text()).slice(0, 500);
    finish({ httpStatus: upstream.status, error: `upstream ${upstream.status}: ${detail}` });
    const msg = upstream.status === 429
      ? 'The assistant is busy (model rate limit reached). Please try again in a minute.'
      : 'The AI model returned an error. Please try again.';
    return openAiError(res, upstream.status === 429 ? 429 : 502, msg, 'upstream_error');
  }

  if (!record.stream) {
    const json = await upstream.json();
    const answer = json?.choices?.[0]?.message?.content ?? '';
    json.model = config.publicModelName;
    sendJson(res, 200, json);
    return finish({ httpStatus: 200, success: true, answerChars: answer.length, emptyAnswer: answer.trim() === '' });
  }

  // Streaming: pass Server-Sent Events straight through, counting the answer text as it goes.
  res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
  let answerChars = 0;
  let buffer = '';
  const decoder = new TextDecoder();
  try {
    for await (const chunk of upstream.body) {
      res.write(chunk);
      buffer += decoder.decode(chunk, { stream: true });
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line.startsWith('data:') || line === 'data: [DONE]') continue;
        try {
          const delta = JSON.parse(line.slice(5)).choices?.[0]?.delta?.content;
          if (typeof delta === 'string') answerChars += delta.trim().length;
        } catch { /* partial or non-JSON line: ignore */ }
      }
    }
    res.end();
    finish({ httpStatus: 200, success: true, answerChars, emptyAnswer: answerChars === 0 });
  } catch (err) {
    res.end();
    finish({ httpStatus: 502, error: `stream interrupted: ${err.message}`, answerChars });
  }
}

export function createServer() {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    try {
      if (req.method === 'GET' && url.pathname === '/health') {
        const c = getContent();
        const ok = Boolean(c.prompt);
        return sendJson(res, ok ? 200 : 503, {
          status: ok ? 'ok' : 'degraded',
          gatewayVersion: config.version,
          model: config.upstreamModel,
          contentVersion: c.contentVersion,
          contentSource: config.contentSource,
          docs: c.docs.length,
          contentLoadedAt: c.loadedAt,
          lastContentError: c.lastError,
        });
      }
      if (!authorised(req)) return openAiError(res, 401, 'Unauthorized', 'auth_error');
      if (req.method === 'GET' && url.pathname === '/v1/models') {
        return sendJson(res, 200, { object: 'list', data: [{ id: config.publicModelName, object: 'model', owned_by: 'kape-lumen' }] });
      }
      if (req.method === 'POST' && url.pathname === '/v1/chat/completions') return await handleChat(req, res);
      return openAiError(res, 404, 'Not found', 'not_found');
    } catch (err) {
      log({ event: 'unhandled_error', level: 'error', error: err.message });
      if (!res.headersSent) openAiError(res, 500, 'Internal gateway error');
      else res.end();
    }
  });
}

// Start only when run directly (tests import createServer without starting a listener).
if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('server.js')) {
  await reloadContent();
  startContentRefresh();
  createServer().listen(config.port, () => {
    log({ event: 'started', port: config.port, gatewayVersion: config.version, model: config.upstreamModel,
      contentSource: config.contentSource, keySource: config.keySource, authRequired: Boolean(config.gatewayToken) });
  });
  for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => { log({ event: 'stopping', signal: sig }); process.exit(0); });
}
