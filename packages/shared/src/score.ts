import { z } from "zod";
import { NeoSegmentSchema } from "./enums.js";

export const ScoreCriteriaSchema = z.object({
  regularite: z.number().min(0).max(100),
  volume: z.number().min(0).max(100),
  dettes: z.number().min(0).max(100),
  croissance: z.number().min(0).max(100),
});
export type ScoreCriteria = z.infer<typeof ScoreCriteriaSchema>;

export const DataQualitySchema = z.object({
  minActivityMet: z.boolean(),
  declaredVsActualOk: z.boolean(),
  declaredVsActualRatio: z.number().optional(),
  warnings: z.array(z.string()).default([]),
});
export type DataQuality = z.infer<typeof DataQualitySchema>;

export const RepaymentCapacitySchema = z.object({
  estimatedMonthlyRevenueFcfa: z.number().int().nonnegative(),
  maxMonthlyPaymentFcfa: z.number().int().nonnegative(),
  capacityRatio: z.number().min(0).max(1),
  maxPrincipalFcfa: z.number().int().nonnegative(),
});
export type RepaymentCapacity = z.infer<typeof RepaymentCapacitySchema>;

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
  /** heuristic (défaut) | ml */
  engine: z.enum(["heuristic", "ml"]).optional().default("heuristic"),
  modelVersion: z.string().nullable().optional(),
  dataQuality: DataQualitySchema.optional(),
  repaymentCapacity: RepaymentCapacitySchema.optional(),
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
  /** Dépenses cahier sur 30 j — marge nette */
  expensesLast30Fcfa: z.number().int().nonnegative().default(0),
  /** Charges fixes mensuelles (loyer, famille…) */
  monthlyFixedChargesFcfa: z.number().int().nonnegative().default(0),
  /** Cotisations tontine enregistrées sur 30 j */
  tontineCotisations30Fcfa: z.number().int().nonnegative().default(0),
  /** Milieu de la tranche CA journalier déclarée (FCFA/j) */
  declaredCaMidpointFcfa: z.number().int().nonnegative().default(0),
  /** Ratio ventes 30 j / (CA déclaré × 30) */
  salesVsDeclaredRatio: z.number().nonnegative().default(1),
  /** Semaines distinctes avec au moins une opération sur 30 j */
  activeWeeksLast30: z.number().int().nonnegative().default(0),
  /** stable | moderee | forte */
  saisonnalite: z.enum(["stable", "moderee", "forte"]).default("stable"),
  garantieSolidaire: z.boolean().default(false),
});
export type ScoreFeatures = z.infer<typeof ScoreFeaturesSchema>;

/** Reco graduée DigiCoop — jamais accepté/refusé automatique. */
export const AgentRecommendationSchema = z.enum([
  "recommande",
  "analyse_complementaire",
  "a_reexaminer",
]);
export type AgentRecommendation = z.infer<typeof AgentRecommendationSchema>;

/** Catégorie de risque affichée à côté de la décision. */
export const AgentRiskCategorySchema = z.enum(["faible", "modere", "eleve"]);
export type AgentRiskCategory = z.infer<typeof AgentRiskCategorySchema>;

export const AgentScoreDriverSchema = z.object({
  key: z.string(),
  label: z.string(),
  delta: z.number(),
});
export type AgentScoreDriver = z.infer<typeof AgentScoreDriverSchema>;

/** Saisie terrain agent (formulaire DigiCoop). */
export const AgentScoreInputSchema = z.object({
  clientNom: z.string().min(1).max(120),
  clientTelephone: z.string().min(8).max(20).optional(),
  /** false = primo-demandeur : l’historique coopérative est ignoré. */
  clientConnu: z.boolean().default(false),
  secteurActivite: z
    .enum([
      "commerce",
      "artisanat",
      "agriculture",
      "elevage",
      "transport",
      "restauration",
      "autre",
    ])
    .default("commerce"),
  tailleMenage: z.number().int().min(1).max(30).default(1),
  /** 0 aucun, 1 quelques-uns, 2 nombreux. */
  incidentsPaiement: z.number().int().min(0).max(2).default(0),
  /** Couche transactionnelle (optionnelle — primo-demandeur sans historique). */
  regulariteDepots: z.number().int().min(0).max(4).default(0),
  ancienneteCompteMois: z.number().int().nonnegative().default(0),
  remboursementsAnterieurs: z.number().int().min(0).max(3).default(0),
  /** Couche proxy. */
  ancienneteActiviteAns: z.number().int().min(0).max(30).default(0),
  tontine: z.boolean().default(false),
  tontineAns: z.number().int().nonnegative().default(0),
  nbGarants: z.number().int().min(0).max(10).default(0),
  ancienneteCoopAns: z.number().int().nonnegative().default(0),
  saisonnalite: z.enum(["stable", "moderee", "forte"]).default("stable"),
  actifTerrain: z.boolean().default(false),
  actifBetail: z.boolean().default(false),
  actifMateriel: z.boolean().default(false),
  /** Capacité — fourchettes déclaratives (FCFA). */
  revenuMensuelFcfa: z.number().int().nonnegative(),
  chargesMensuellesFcfa: z.number().int().nonnegative().default(0),
  montantDemandeFcfa: z.number().int().positive(),
  dureeMois: z.number().int().min(1).max(24).default(3),
});
export type AgentScoreInput = z.infer<typeof AgentScoreInputSchema>;

export const AgentScoreResultSchema = z.object({
  /** Échelle 300–850 (les anciens dossiers 0–100 restent acceptés). */
  score: z.number().int().min(0).max(850),
  recommendation: AgentRecommendationSchema,
  riskCategory: AgentRiskCategorySchema.default("modere"),
  drivers: z.array(AgentScoreDriverSchema).max(3),
  chargeRate: z.number().min(0),
  montantSoutenableFcfa: z.number().int().nonnegative(),
  echeanceEstimeeFcfa: z.number().int().nonnegative(),
  revenuMensuelFcfa: z.number().int().nonnegative(),
  computedAt: z.string().datetime(),
});
export type AgentScoreResult = z.infer<typeof AgentScoreResultSchema>;

/** Payload sync dossier agent (saisie + résultat figé). */
export const CreateAgentDossierSchema = z.object({
  input: AgentScoreInputSchema,
  result: AgentScoreResultSchema,
  note: z.string().max(500).optional(),
});
export type CreateAgentDossier = z.infer<typeof CreateAgentDossierSchema>;
