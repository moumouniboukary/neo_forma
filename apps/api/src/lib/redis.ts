/**
 * Redis optionnel — rate-limit OTP quand REDIS_URL est défini.
 * Sinon Identity reste 100 % Postgres (OK pour MVP).
 */
import { createRequire } from "node:module";

type RedisClient = {
  incr(key: string): Promise<number>;
  expire(key: string, seconds: number): Promise<number>;
  ping(): Promise<string>;
  lpush(key: string, ...values: string[]): Promise<number>;
  brpop(key: string, timeout: number): Promise<[string, string] | null>;
  on(event: string, listener: (err: Error) => void): void;
  quit(): Promise<string>;
  disconnect(): void;
};

let client: RedisClient | null | undefined;

function createRedis(url: string): RedisClient {
  const require = createRequire(import.meta.url);
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const IORedis = require("ioredis") as new (
    url: string,
    opts?: { maxRetriesPerRequest?: number }
  ) => RedisClient;
  return new IORedis(url, { maxRetriesPerRequest: 1 });
}

export async function getRedis(): Promise<RedisClient | null> {
  if (client !== undefined) return client;
  const url = process.env.REDIS_URL;
  if (!url) {
    client = null;
    return null;
  }
  try {
    const redis = createRedis(url);
    redis.on("error", (err: Error) => {
      console.warn("[redis]", err.message);
    });
    client = redis;
    return redis;
  } catch (err) {
    console.warn("[redis] indisponible — fallback Postgres", err);
    client = null;
    return null;
  }
}

/** Readiness Redis : "ok" | "skip" (non configuré) | "down". */
export async function checkRedis(): Promise<"ok" | "skip" | "down"> {
  if (!process.env.REDIS_URL) return "skip";
  try {
    const redis = await getRedis();
    if (!redis) return "down";
    const pong = await Promise.race([
      redis.ping(),
      new Promise<string>((_, rej) =>
        setTimeout(() => rej(new Error("timeout")), 2000)
      ),
    ]);
    return pong === "PONG" || pong === "pong" ? "ok" : "down";
  } catch {
    return "down";
  }
}

export async function closeRedis(): Promise<void> {
  if (!client) {
    client = undefined;
    return;
  }
  const redis = client;
  client = undefined;
  try {
    await redis.quit();
  } catch {
    try {
      redis.disconnect();
    } catch {
      /* ignore */
    }
  }
}

/** Compteur TTL (ex. OTP / téléphone). Retourne le compte après incrément. */
export async function redisIncrWithTtl(
  key: string,
  ttlSeconds: number
): Promise<number | null> {
  try {
    const redis = await getRedis();
    if (!redis) return null;
    const n = await redis.incr(key);
    if (n === 1) await redis.expire(key, ttlSeconds);
    return n;
  } catch {
    return null;
  }
}
