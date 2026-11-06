// One JSON line per event on stdout. Docker ships stdout to CloudWatch Logs.
//
// Request lines use CloudWatch Embedded Metric Format (EMF): the "_aws" block tells
// CloudWatch to turn the listed fields into metrics (Requests, AnswersFailed,
// EmptyAnswer, LatencyMs) without any extra API call or SDK. See
// https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format_Specification.html

import { config } from './config.js';

export function log(fields) {
  process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), service: 'brew-gateway', ...fields }) + '\n');
}

export function logRequest(r) {
  log({
    event: 'chat_request',
    level: r.success ? 'info' : 'error',
    requestId: r.requestId,
    question: r.question,
    durationMs: r.durationMs,
    httpStatus: r.httpStatus,
    success: r.success,
    emptyAnswer: r.emptyAnswer,
    stream: r.stream,
    answerChars: r.answerChars,
    error: r.error,
    // "which version answered": gateway code, café content and model
    gatewayVersion: config.version,
    contentVersion: r.contentVersion,
    model: config.upstreamModel,
    // EMF metric definitions + values
    Service: 'brew-gateway',
    Requests: 1,
    AnswersFailed: r.success ? 0 : 1,
    EmptyAnswer: r.success && r.emptyAnswer ? 1 : 0,
    LatencyMs: r.durationMs,
    _aws: {
      Timestamp: Date.now(),
      CloudWatchMetrics: [
        {
          Namespace: config.metricsNamespace,
          Dimensions: [['Service']],
          Metrics: [
            { Name: 'Requests', Unit: 'Count' },
            { Name: 'AnswersFailed', Unit: 'Count' },
            { Name: 'EmptyAnswer', Unit: 'Count' },
            { Name: 'LatencyMs', Unit: 'Milliseconds' },
          ],
        },
      ],
    },
  });
}
