import { z } from "zod";
import { ConsentTypeSchema } from "./enums.js";

/** Version courante de la politique de confidentialité. */
export const CURRENT_PRIVACY_POLICY_VERSION = "neoforma-privacy-2026.1";

export const ConsentementSchema = z.object({
  id: z.string().uuid(),
  type: ConsentTypeSchema,
  accorde: z.boolean(),
  dateDecision: z.string().datetime(),
  versionPolitique: z.string().min(1).max(40),
  retractable: z.boolean(),
  updatedAt: z.string().datetime(),
});
export type ConsentementDto = z.infer<typeof ConsentementSchema>;

export const UpdateConsentSchema = z.object({
  accorde: z.boolean(),
  versionPolitique: z.string().min(1).max(40).optional(),
});
export type UpdateConsent = z.infer<typeof UpdateConsentSchema>;

/** Mise à jour groupée (onboarding) — clés API legacy. */
export const UpdateConsentsBatchSchema = z.object({
  consentAnonymized: z.boolean().optional(),
  consentCreditPartners: z.boolean().optional(),
  consentMarketing: z.boolean().optional(),
  versionPolitique: z.string().min(1).max(40).optional(),
});
export type UpdateConsentsBatch = z.infer<typeof UpdateConsentsBatchSchema>;

export const ConsentsListSchema = z.object({
  items: z.array(ConsentementSchema),
  policyVersion: z.string(),
});
export type ConsentsList = z.infer<typeof ConsentsListSchema>;
