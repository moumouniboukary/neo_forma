import { z } from "zod";
import { CreditStatusSchema } from "./enums.js";

export const CreditOfferSchema = z.object({
  id: z.string().uuid().optional(),
  minFcfa: z.number().int().nonnegative(),
  maxFcfa: z.number().int().nonnegative(),
  suggestedFcfa: z.number().int().nonnegative(),
  durationMonths: z.number().int().positive(),
  monthlyRatePct: z.number().nonnegative(),
  eligible: z.boolean(),
  score: z.number().int().min(0).max(100).optional(),
  validUntil: z.string().datetime().nullable().optional(),
});
export type CreditOffer = z.infer<typeof CreditOfferSchema>;

export const CreditRiskCriteriaSchema = z.object({
  regularite: z.number().int().min(0).max(100),
  volume: z.number().int().min(0).max(100),
  dettes: z.number().int().min(0).max(100),
  croissance: z.number().int().min(0).max(100),
});
export type CreditRiskCriteria = z.infer<typeof CreditRiskCriteriaSchema>;

export const CreditApplicationSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().uuid(),
  reference: z.string(),
  amountFcfa: z.number().int().positive(),
  purpose: z.enum(["stock", "equipement", "fonds_roulement", "autre"]),
  repayment: z.enum(["hebdo", "mensuel"]),
  status: CreditStatusSchema,
  scoreAtSubmit: z.number().int().min(0).max(100),
  offreId: z.string().uuid().optional().nullable(),
  imfId: z.string().uuid().optional().nullable(),
  dateSoumission: z.string().datetime().nullable().optional(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  /** Score figé à la soumission — aide à la décision IMF / coopérative */
  eligible: z.boolean().optional(),
  segment: z.string().nullable().optional(),
  threshold: z.number().int().min(0).max(100).nullable().optional(),
  criteria: CreditRiskCriteriaSchema.nullable().optional(),
  featuresSnapshot: z.record(z.unknown()).nullable().optional(),
  motifDecision: z.string().nullable().optional(),
  outcome: z.string().nullable().optional(),
});
export type CreditApplication = z.infer<typeof CreditApplicationSchema>;

export const SubmitCreditSchema = z.object({
  amountFcfa: z.number().int().positive(),
  purpose: z.enum(["stock", "equipement", "fonds_roulement", "autre"]),
  repayment: z.enum(["hebdo", "mensuel"]),
  offreId: z.string().uuid().optional(),
});
export type SubmitCredit = z.infer<typeof SubmitCreditSchema>;
