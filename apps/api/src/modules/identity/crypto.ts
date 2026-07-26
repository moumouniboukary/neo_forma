import { createHash, randomBytes, randomInt, timingSafeEqual } from "node:crypto";

export function normalizePhone(phone: string): string {
  return phone.replace(/\s+/g, " ").trim();
}

export function generateOtpCode(): string {
  return String(randomInt(1000, 10000));
}

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/** Refresh token opaque cryptographiquement fort (OWASP). */
export function generateRefreshToken(): string {
  return randomBytes(48).toString("base64url");
}

export function generateFamilyId(): string {
  return randomBytes(16).toString("hex");
}

/** Comparaison constante pour hashes hex. */
export function safeEqualHex(a: string, b: string): boolean {
  try {
    const ba = Buffer.from(a, "hex");
    const bb = Buffer.from(b, "hex");
    if (ba.length !== bb.length) return false;
    return timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}
