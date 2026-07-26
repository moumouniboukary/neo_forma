import { z } from "zod";
import { NeoSegmentSchema } from "./enums.js";

export const ScoreCriteriaSchema = z.object({
  regularite: z.number().min(0).max(100),
  volume: z.number().min(0).max(100),
  dettes: z.number().min(0).max(100),
  croissance: z.number().min(0).max(100),
});
export type ScoreCriteria = z.infer<typeof ScoreCriteriaSchema>;

export const NeoScoreResultSchema = z.object({
  score: z.number().int().min(0).max(100),
  segment: NeoSegmentSchema,
  eligible: z.boolean(),
  threshold: z.literal(50),
  criteria: ScoreCriteriaSchema,
  history: z.array(
    z.object({
      month: z.string(),
      score: z.number().int().min(0).max(100),
    })
  ),
  computedAt: z.string().datetime(),
});
export type NeoScoreResult = z.infer<typeof NeoScoreResultSchema>;

/** Features alignées sur le modèle terrain / KoboCollect */
export const ScoreFeaturesSchema = z.object({
  anciennete: z.number().min(1).max(5),
  caJour: z.number().min(1).max(6),
  partCredit: z.number().min(1).max(4).default(1),
  impayes: z.number().min(0).max(4).default(0),
  tontine: z.boolean(),
  tontineAns: z.number().int().nonnegative().default(0),
  mobileMoney: z.number().min(0).max(3),
  telephone: z.number().min(0).max(2).default(2),
  compte: z.number().min(0).max(2).default(0),
  creditHist: z.number().min(0).max(2).default(0),
  opsLast30Days: z.number().int().nonnegative().default(0),
  salesLast30Fcfa: z.number().int().nonnegative().default(0),
  openDebtsFcfa: z.number().int().nonnegative().default(0),
  overdueDebtsCount: z.number().int().nonnegative().default(0),
});
export type ScoreFeatures = z.infer<typeof ScoreFeaturesSchema>;
