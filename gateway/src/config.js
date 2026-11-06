// All settings come from environment variables, so no secret is ever written in code.
// Locally: CONTENT_SOURCE=local, KEY_SOURCE=env (key in a gitignored .env).
// On AWS:  CONTENT_SOURCE=s3,    KEY_SOURCE=ssm (key in Parameter Store, read at runtime).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

function env(name, fallback) {
  const v = process.env[name];
  return v === undefined || v === '' ? fallback : v;
}

export const config = {
  version: pkg.version,
  port: Number(env('PORT', '8080')),

  // Shared token LibreChat sends so random callers can't use our Gemini quota.
  gatewayToken: env('GATEWAY_TOKEN', ''),

  // Upstream model (Gemini's OpenAI-compatible API)
  upstreamBaseUrl: env('UPSTREAM_BASE_URL', 'https://generativelanguage.googleapis.com/v1beta/openai'),
  upstreamModel: env('GEMINI_MODEL', 'gemini-3.5-flash-lite'),
  upstreamTimeoutMs: Number(env('UPSTREAM_TIMEOUT_MS', '60000')),

  // Where the Gemini key comes from
  keySource: env('KEY_SOURCE', 'env'), // env | ssm
  geminiKey: env('GEMINI_API_KEY', ''),
  ssmKeyName: env('SSM_KEY_NAME', '/kape-lumen/gemini-api-key'),

  // Where the café documents come from
  contentSource: env('CONTENT_SOURCE', 'local'), // local | s3
  contentDir: env('CONTENT_DIR', fileURLToPath(new URL('../../content', import.meta.url))),
  s3Bucket: env('CONTENT_BUCKET', ''),
  s3Prefix: env('CONTENT_PREFIX', 'content/'),
  contentRefreshSeconds: Number(env('CONTENT_REFRESH_SECONDS', '300')),

  awsRegion: env('AWS_REGION', 'ap-southeast-1'),
  metricsNamespace: env('METRICS_NAMESPACE', 'KapeLumen'),
  // Only the first N characters of each question are logged.
  logQuestionChars: Number(env('LOG_QUESTION_CHARS', '300')),

  // Name LibreChat sees in its model list
  publicModelName: env('PUBLIC_MODEL_NAME', 'lumen-barista'),
};
