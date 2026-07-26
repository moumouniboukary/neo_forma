#!/usr/bin/env node
/**
 * Sonde /ready et envoie une alerte webhook si not_ready.
 * Usage:
 *   API_BASE=https://api.example.com ALERT_WEBHOOK_URL=https://hooks.slack.com/... node scripts/watch-ready.mjs
 * Cron : */5 * * * * node /path/to/scripts/watch-ready.mjs
 */
const base = (process.env.API_BASE || "http://localhost:3001").replace(/\/$/, "");
const webhook = process.env.ALERT_WEBHOOK_URL || "";

async function main() {
  const url = `${base}/ready`;
  let status = 0;
  let body = {};
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    status = res.status;
    body = await res.json().catch(() => ({}));
  } catch (err) {
    await alert(`NeoForma /ready injoignable (${base}) : ${err.message}`);
    process.exit(2);
  }

  if (status !== 200 || body.status !== "ready") {
    await alert(
      `NeoForma not_ready (${base}) HTTP ${status} checks=${JSON.stringify(body.checks ?? body)}`
    );
    process.exit(1);
  }
  console.log(`[watch-ready] ok ${new Date().toISOString()}`, body.checks);
}

async function alert(text) {
  console.error(text);
  if (!webhook) return;
  try {
    await fetch(webhook, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text, content: text }),
    });
  } catch (err) {
    console.error("[watch-ready] webhook failed", err.message);
  }
}

main();
