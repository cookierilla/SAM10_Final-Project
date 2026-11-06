// Loads the café knowledge base (markdown files) from a local folder or from S3,
// and turns it into the system prompt. It keeps the last good copy if a reload fails,
// so a brief S3 hiccup doesn't take the assistant down.

import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { config } from './config.js';
import { log } from './log.js';

let state = { docs: [], prompt: '', contentVersion: 'none', loadedAt: null, lastError: null };

async function loadLocal() {
  const files = (await readdir(config.contentDir)).filter((f) => f.endsWith('.md')).sort();
  return Promise.all(
    files.map(async (name) => ({ name, text: await readFile(join(config.contentDir, name), 'utf8') })),
  );
}

async function loadS3() {
  const { S3Client, ListObjectsV2Command, GetObjectCommand } = await import('@aws-sdk/client-s3');
  const s3 = new S3Client({ region: config.awsRegion });
  const list = await s3.send(new ListObjectsV2Command({ Bucket: config.s3Bucket, Prefix: config.s3Prefix }));
  const keys = (list.Contents ?? []).map((o) => o.Key).filter((k) => k.endsWith('.md')).sort();
  return Promise.all(
    keys.map(async (Key) => {
      const obj = await s3.send(new GetObjectCommand({ Bucket: config.s3Bucket, Key }));
      return { name: Key.slice(config.s3Prefix.length), text: await obj.Body.transformToString('utf8') };
    }),
  );
}

export function buildSystemPrompt(docs) {
  const knowledge = docs.map((d) => `### Document: ${d.name}\n${d.text.trim()}`).join('\n\n');
  return `You are "Lumen", the virtual barista of Kapé Lumen, a café with two branches.
You answer customers' questions about the menu, prices, branches, opening hours, the Lumen Stamps loyalty card and house policies.

Rules:
1. Answer ONLY from the CAFÉ KNOWLEDGE below. If the answer is not there, say you don't know and suggest asking the counter staff or emailing hello@kapelumen.example.
2. Never say that any food or drink is safe for someone's allergy, intolerance or medical condition. Explain that everything is made in a shared kitchen and that they should speak to the staff in person.
3. You cannot take orders, take payments, make reservations, check loyalty stamps or reveal the Wi-Fi password. Say so politely and explain what the customer can do instead.
4. Politely decline anything unrelated to Kapé Lumen.
5. Keep answers short (1–4 sentences or a short list), warm and friendly. Quote prices in pesos (₱) exactly as written. You may reply in English or Filipino, matching the customer.
6. Do not ask customers for personal information.

CAFÉ KNOWLEDGE
==============
${knowledge}`;
}

export async function reloadContent() {
  try {
    const docs = config.contentSource === 's3' ? await loadS3() : await loadLocal();
    if (docs.length === 0) throw new Error(`no .md documents found (source=${config.contentSource})`);
    const prompt = buildSystemPrompt(docs);
    const contentVersion = createHash('sha256').update(prompt).digest('hex').slice(0, 12);
    if (contentVersion !== state.contentVersion) {
      log({ event: 'content_loaded', source: config.contentSource, docs: docs.map((d) => d.name), contentVersion });
    }
    state = { docs, prompt, contentVersion, loadedAt: new Date().toISOString(), lastError: null };
  } catch (err) {
    state = { ...state, lastError: err.message };
    log({ event: 'content_load_failed', level: 'error', source: config.contentSource, error: err.message });
  }
  return state;
}

export function getContent() {
  return state;
}

export function startContentRefresh() {
  if (config.contentRefreshSeconds > 0) {
    setInterval(reloadContent, config.contentRefreshSeconds * 1000).unref();
  }
}
