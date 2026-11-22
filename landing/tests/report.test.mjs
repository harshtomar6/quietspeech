import test from 'node:test';
import assert from 'node:assert/strict';
import handler, { parseReport, slackMessage, slackEscape, reportID } from '../api/report.mjs';

function response() { return { headers:{}, setHeader(k,v){this.headers[k]=v;}, status(n){this.code=n;return this;}, json(x){this.body=x;return this;} }; }
const report = { description: 'Nothing pasted in Yab', app: 'Yab', email: 'a@b.co', version: '0.3.9', summary: ['QuietSpeech 0.3.9'], log: ['12:00 [insert] ok'] };
const KEY = 'SLACK_REPORT_WEBHOOK_URL';

test('parseReport trims fields and rejects bad input', () => {
  assert.equal(parseReport(null), null);
  assert.equal(parseReport([]), null);
  assert.equal(parseReport({ description: '' }), null);
  assert.equal(parseReport({ ...report, email: 'not an email' }), null);
  const long = parseReport({ ...report, description: 'x'.repeat(9000), log: Array.from({ length: 500 }, (_, i) => `line ${i}`) });
  assert.equal(long.description.length, 5000);
  assert.equal(long.log.length, 200);
  assert.equal(long.log.at(-1), 'line 499');
  assert.deepEqual(parseReport({ description: 'hi', summary: [1, 'a'] }).summary, ['a']);
});

test('Slack text cannot mention or link', () => {
  assert.equal(slackEscape('<!channel> & <https://x|y> ```'), "&lt;!channel&gt; &amp; &lt;https://x|y&gt; '''");
  const msg = JSON.stringify(slackMessage({ ...report, description: '<!here> help' }, 'QS-ABCDEF'));
  assert.ok(!msg.includes('<!here>'));
});

test('long diagnostics stay within Slack limits and keep the newest lines', () => {
  const log = Array.from({ length: 200 }, (_, i) => `line ${i} ` + 'x'.repeat(900));
  const msg = slackMessage(parseReport({ ...report, log }), 'QS-ABCDEF');
  assert.ok(msg.blocks.length <= 50);
  for (const b of msg.blocks) if (b.text?.type === 'mrkdwn') assert.ok(b.text.text.length <= 3000);
  const all = JSON.stringify(msg);
  assert.ok(all.includes('line 199 ') && all.includes('QuietSpeech 0.3.9'));
});

test('report IDs look like QS-XXXXXX', () => assert.match(reportID(), /^QS-[2-9A-HJ-NP-Z]{6}$/));

function withEnv(value, fn) {
  const env = globalThis.process.env;
  const saved = env[KEY];
  if (value === undefined) delete env[KEY]; else env[KEY] = value;
  return fn().finally(() => { if (saved === undefined) delete env[KEY]; else env[KEY] = saved; });
}

test('handler rejects browsers, bad methods and bodies, and fails closed without a webhook', () => withEnv(undefined, async () => {
  let res = response(); await handler({ method: 'GET', headers: {} }, res); assert.equal(res.code, 405);
  res = response(); await handler({ method: 'POST', headers: { origin: 'https://evil.test' }, body: report }, res); assert.equal(res.code, 403);
  res = response(); await handler({ method: 'POST', headers: {}, body: '{bad' }, res); assert.equal(res.code, 400);
  res = response(); await handler({ method: 'POST', headers: {}, body: { description: 'x'.repeat(130000) } }, res); assert.equal(res.code, 413);
  res = response(); await handler({ method: 'POST', headers: {}, body: report }, res); assert.equal(res.code, 503);
}));

test('handler posts to the webhook and returns the reference', () => withEnv('https://hooks.slack.test/x', async () => {
  const savedFetch = globalThis.fetch;
  let sent;
  globalThis.fetch = async (url, init) => { sent = { url, body: JSON.parse(init.body) }; return { ok: true }; };
  try {
    const res = response(); await handler({ method: 'POST', headers: {}, body: report }, res);
    assert.equal(res.code, 200);
    assert.match(res.body.id, /^QS-/);
    assert.equal(sent.url, 'https://hooks.slack.test/x');
    assert.ok(sent.body.text.includes(res.body.id));
    globalThis.fetch = async () => ({ ok: false });
    const failed = response(); await handler({ method: 'POST', headers: {}, body: report }, failed);
    assert.equal(failed.code, 502);
  } finally { globalThis.fetch = savedFetch; }
}));
