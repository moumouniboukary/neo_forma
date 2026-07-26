import { getRedis } from "./redis.js";

export type JobKind = "sms" | "alert" | "mm_transfer";

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

export { QUEUE_KEY };
