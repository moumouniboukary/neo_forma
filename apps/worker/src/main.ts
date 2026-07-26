/**
 * Worker NeoForma — consomme la file Redis (SMS, alertes, MM).
 * Usage : npm run worker — nécessite REDIS_URL.
 */
import { dequeueJob, type JobPayload } from "../../api/src/lib/jobs.js";
import { createSmsGateway } from "../../api/src/lib/sms.js";
import { createMobileMoneyGateway } from "../../api/src/lib/mobile-money.js";
import { sendAlert } from "../../api/src/lib/observability.js";

async function handle(job: JobPayload): Promise<void> {
  switch (job.kind) {
    case "sms": {
      const to = String(job.data.to ?? "");
      const body = String(job.data.body ?? "");
      if (!to || !body) throw new Error("sms: to/body requis");
      await createSmsGateway().send({ to, body });
      console.info(`[worker] sms → ${to}`);
      return;
    }
    case "alert": {
      await sendAlert(String(job.data.text ?? "alerte"), job.data);
      console.info("[worker] alert envoyée");
      return;
    }
    case "mm_transfer": {
      const provider = (job.data.provider as "orange" | "moov" | "stub") ?? "stub";
      const gw = createMobileMoneyGateway(provider);
      const result = await gw.transfer({
        provider,
        phone: String(job.data.phone ?? ""),
        amountFcfa: Number(job.data.amountFcfa ?? 0),
        reference: String(job.data.reference ?? `mm-${Date.now()}`),
        direction: (job.data.direction as "cash_in" | "cash_out") ?? "cash_in",
      });
      console.info(`[worker] mm ${result.status} ${result.externalId}`);
      return;
    }
    default:
      console.warn("[worker] kind inconnu", job);
  }
}

async function main(): Promise<void> {
  if (!process.env.REDIS_URL) {
    console.error("[worker] REDIS_URL requis");
    process.exit(1);
  }
  console.info("[worker] démarré — écoute neoforma:jobs");
  for (;;) {
    try {
      const job = await dequeueJob(5);
      if (!job) continue;
      await handle(job);
    } catch (err) {
      console.error("[worker] erreur", err);
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
}

main();
