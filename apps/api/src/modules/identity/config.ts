export const identityConfig = {
  /** OTP TTL (ms) — OWASP : courte durée. */
  otpTtlMs: 5 * 60 * 1000,
  /** Preuve OTP JWT après verify (s). */
  otpProofTtlSec: 10 * 60,
  /** Access JWT (s) — court (architecture : 15–60 min). */
  accessTokenTtlSec: 15 * 60,
  /** Refresh opaque TTL (ms). */
  refreshTokenTtlMs: 7 * 24 * 60 * 60 * 1000,
  otpMaxAttempts: 5,
  /** bcrypt cost — OWASP ≥ 10 ; 12 recommandé. */
  bcryptRounds: 12,
  otpRateWindowMs: 15 * 60 * 1000,
  otpRateMax: 5,
  /** Seuil PIN incorrects avant verrouillage temporaire (UML). */
  pinMaxAttempts: 5,
  /** Durée verrouillage PIN (ms). */
  pinLockMs: 15 * 60 * 1000,
  /** PIN trivialement faibles rejetés (OWASP). */
  weakPins: new Set([
    "0000",
    "1111",
    "2222",
    "3333",
    "4444",
    "5555",
    "6666",
    "7777",
    "8888",
    "9999",
    "1234",
    "4321",
    "1212",
  ]),
};
