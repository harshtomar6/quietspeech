import { randomInt } from 'node:crypto';

// Problem reports from the app's Report a Problem window, posted to Slack.
// The app sends what the user saw and approved in the window: a description,
// the target app, an optional reply email, and diagnostics that never
// contain audio or dictated text. Nothing is stored here.

const LIMITS = { description: 5000, app: 200, email: 254, version: 40, summaryLines: 40, logLines: 200, line: 1000, body: 120_000 };
const EMAIL = /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/;
const ID_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const BLOCK_TEXT = 2900; // Slack allows 3000 characters per section.
const MAX_BLOCKS = 45;   // Slack allows 50 per message.

const str = (v, max) => typeof v === 'string' ? v.slice(0, max) : '';
const lines = (v, count) => Array.isArray(v) ? v.filter(l => typeof l === 'string').slice(-count).map(l => l.slice(0, LIMITS.line)) : [];

/** Validates and trims a request body; null if it is not a report. */
export function parseReport(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  const report = {
    description: str(body.description, LIMITS.description).trim(),
    app: str(body.app, LIMITS.app).trim(),
    email: str(body.email, LIMITS.email).trim(),
    version: str(body.version, LIMITS.version).trim(),
    summary: lines(body.summary, LIMITS.summaryLines),
    log: lines(body.log, LIMITS.logLines),
  };
  if (!report.description && !report.summary.length) return null;
  if (report.email && !EMAIL.test(report.email)) return null;
  return report;
}

export function reportID() {
  let id = 'QS-';
  for (let i = 0; i < 6; i++) id += ID_ALPHABET[randomInt(ID_ALPHABET.length)];
  return id;
}

// Slack reads <...> as links and mentions (<!channel>), so escape them;
// a stray ``` would end a code block early.
export const slackEscape = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/```/g, "'''");

function chunks(text, size) {
  const out = [];
  let current = '';
  for (const line of text.split('\n')) {
    if (current && current.length + line.length + 1 > size) { out.push(current); current = ''; }
    current += (current ? '\n' : '') + line.slice(0, size);
  }
  if (current) out.push(current);
  return out;
}

/** The Slack webhook payload for a report. */
export function slackMessage(report, id) {
  const firstLine = report.description.split('\n')[0].slice(0, 80) || 'No description';
  const field = (label, value) => ({ type: 'mrkdwn', text: `*${label}*\n${value ? slackEscape(value) : '–'}` });
  const blocks = [
    { type: 'header', text: { type: 'plain_text', text: `Problem report ${id}` } },
    { type: 'section', text: { type: 'mrkdwn', text: `*What happened*\n${slackEscape(report.description || '(not described)').slice(0, BLOCK_TEXT)}` } },
    { type: 'section', fields: [field('App', report.app), field('Version', report.version), field('Reply to', report.email), field('Diagnostics', report.summary.length ? 'Included' : 'Not included')] },
  ];
  const diagnostics = [report.summary.join('\n'), report.log.length ? `Recent log:\n${report.log.join('\n')}` : ''].filter(Boolean).join('\n\n');
  if (diagnostics) {
    const parts = chunks(slackEscape(diagnostics), BLOCK_TEXT - 6);
    const room = MAX_BLOCKS - blocks.length - 1; // after the divider
    // Keep the summary (first part) and the newest log lines (last parts).
    const kept = parts.length > room ? [parts[0], ...parts.slice(parts.length - room + 1)] : parts;
    blocks.push({ type: 'divider' });
    for (const part of kept) blocks.push({ type: 'section', text: { type: 'mrkdwn', text: '```' + part + '```' } });
  }
  return { text: `Problem report ${id}: ${slackEscape(firstLine)}`, blocks, unfurl_links: false };
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ ok: false });
  }
  // Only the Mac app posts here; browsers always send an Origin.
  if (req.headers?.origin) return res.status(403).json({ ok: false });
  let body;
  try { body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body; }
  catch { return res.status(400).json({ ok: false }); }
  if (JSON.stringify(body ?? null).length > LIMITS.body) return res.status(413).json({ ok: false });
  const report = parseReport(body);
  if (!report) return res.status(400).json({ ok: false });
  const webhook = process.env.SLACK_REPORT_WEBHOOK_URL;
  if (!webhook) return res.status(503).json({ ok: false });
  const id = reportID();
  try {
    const response = await fetch(webhook, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(slackMessage(report, id)),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return res.status(502).json({ ok: false });
    return res.status(200).json({ ok: true, id });
  } catch {
    return res.status(502).json({ ok: false });
  }
}
