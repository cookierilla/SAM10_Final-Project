// Gets the Gemini API key at runtime: from an env var locally, or from
// SSM Parameter Store (SecureString) on AWS. The key is cached in memory for
// 15 minutes, so a rotated key is picked up without a restart.

import { config } from './config.js';

let cached = { value: '', fetchedAt: 0 };
const TTL_MS = 15 * 60 * 1000;

export async function getGeminiKey() {
  if (config.keySource !== 'ssm') {
    if (!config.geminiKey) throw new Error('GEMINI_API_KEY is not set');
    return config.geminiKey;
  }
  if (cached.value && Date.now() - cached.fetchedAt < TTL_MS) return cached.value;
  const { SSMClient, GetParameterCommand } = await import('@aws-sdk/client-ssm');
  const ssm = new SSMClient({ region: config.awsRegion });
  const out = await ssm.send(new GetParameterCommand({ Name: config.ssmKeyName, WithDecryption: true }));
  cached = { value: out.Parameter.Value, fetchedAt: Date.now() };
  return cached.value;
}
