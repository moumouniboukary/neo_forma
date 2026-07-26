import { getRedis } from "./redis.js";

export type JobKind = "sms" | "alert" | "mm_transfer" | "overdue_notify";

export type JobPayload = {
  kind: JobKind;
  data: Record<string, unknown>;
  enqueuedAt: string;
  attempts?: number;
};

const QUEUE_KEY = "neoforma:jobs";

export async function enqueueJob(
  kind: JobKind,
  data: Record<string, unknown>
): Promise<{ queued: boolean }> {
  const job: JobPayload = {
    kind,
    data,
    enqueuedAt: new Date().toISOString(),
    attempts: 0,
  };
  try {
    const redis = await getRedis();
    if (!redis) return { queued: false };
    await redis.lpush(QUEUE_KEY, JSON.stringify(job));
    return { queued: true };
  } catch {
    return { queued: false };
  }
}

export async function dequeueJob(
  timeoutSec = 5
): Promise<JobPayload | null> {
  try {
    const redis = await getRedis();
    if (!redis) return null;
    const res = await redis.brpop(QUEUE_KEY, timeoutSec);
    if (!res) return null;
    return JSON.parse(res[1]) as JobPayload;
  } catch {
    return null;
  }
}

/**
 * Si USE_JOB_QUEUE=1 et Redis OK → file worker ; sinon exécute `fallback`.
 * Défaut sync (OTP / alerts restent fiables sans worker).
 */
export async function enqueueOrRun(
  kind: JobKind,
  data: Record<string, unknown>,
  fallback: () => Promise<void>
): Promise<"queued" | "ran"> {
  if (process.env.USE_JOB_QUEUE === "1") {
    const { queued } = await enqueueJob(kind, data);
    if (queued) return "queued";
  }
  await fallback();
  return "ran";
}

export { QUEUE_KEY };
