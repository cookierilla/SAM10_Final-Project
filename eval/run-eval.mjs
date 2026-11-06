// Scores Lumen against the labelled test questions (WS-A.8 "one honest number", E-04).
//
// Usage:
//   GATEWAY_URL=http://127.0.0.1:8080 GATEWAY_TOKEN=... node eval/run-eval.mjs [questions.json] [--delay=7000] [--json=out.json]
//
// Locally the gateway isn't published to the host, so run it inside the gateway container:
//   docker cp eval/. brew-gateway:/tmp/eval
//   docker exec brew-gateway node /tmp/eval/run-eval.mjs /tmp/eval/test-questions.json
//
// A question PASSES if the answer contains at least one "expect_any" phrase and none of the
// "expect_none" phrases (case-insensitive). Upstream errors (429/503 etc.) are counted separately
// as ERRORS, so a quota problem isn't mistaken for a wrong answer.

import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--')) ?? new URL('./test-questions.json', import.meta.url);
const delayMs = Number(args.find((a) => a.startsWith('--delay='))?.split('=')[1] ?? 7000);
const jsonOut = args.find((a) => a.startsWith('--json='))?.split('=')[1];
const url = (process.env.GATEWAY_URL ?? 'http://127.0.0.1:8080') + '/v1/chat/completions';
const token = process.env.GATEWAY_TOKEN ?? '';

const { questions } = JSON.parse(readFileSync(file, 'utf8'));
const results = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

for (const [i, q] of questions.entries()) {
  if (i > 0) await sleep(delayMs); // stay under the model's free-tier requests-per-minute limit
  const started = Date.now();
  let status = 0, answer = '', error = '';
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: JSON.stringify({ messages: [{ role: 'user', content: q.question }] }),
      signal: AbortSignal.timeout(90000),
    });
    status = res.status;
    const body = await res.json();
    if (res.ok) answer = body.choices?.[0]?.message?.content ?? '';
    else error = body.error?.message ?? `HTTP ${status}`;
  } catch (err) {
    error = err.message;
  }
  const low = answer.toLowerCase();
  const outcome = error
    ? 'ERROR'
    : (q.expect_any ?? []).some((p) => low.includes(p.toLowerCase())) && !(q.expect_none ?? []).some((p) => low.includes(p.toLowerCase()))
      ? 'PASS'
      : 'FAIL';
  const r = { id: q.id, category: q.category, question: q.question, outcome, status, ms: Date.now() - started, answer, error };
  results.push(r);
  console.log(`${outcome.padEnd(5)} ${q.id} ${String(r.ms).padStart(5)}ms  ${q.question}`);
  console.log(`      -> ${(answer || error).replace(/\s+/g, ' ').slice(0, 220)}`);
}

const count = (o) => results.filter((r) => r.outcome === o).length;
const summary = {
  ts: new Date().toISOString(),
  total: results.length,
  pass: count('PASS'),
  fail: count('FAIL'),
  error: count('ERROR'),
};
summary.passRate = summary.total ? Math.round((summary.pass / summary.total) * 1000) / 10 : 0;
console.log(`\nSCORE ${summary.pass}/${summary.total} correct (${summary.passRate}%) · ${summary.fail} wrong · ${summary.error} errors · ${summary.ts}`);
if (jsonOut) writeFileSync(jsonOut, JSON.stringify({ summary, results }, null, 2));
process.exitCode = summary.pass === summary.total ? 0 : 1;
