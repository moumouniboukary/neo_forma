import { createHash } from "node:crypto";

/** Hash déterministe pour lookup clé partenaire (clé haute entropie). */
export function hashPartnerApiKey(raw: string): string {
  return createHash("sha256").update(raw.trim(), "utf8").digest("hex");
}
