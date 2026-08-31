/**
 * Recalibrage statistique du scorecard DigiCoop (couche long terme).
 *
 * Méthode : régression logistique simple (descente de gradient) sur des
 * dossiers labellisés rembourse_ok / defaut → multiplicateurs de poids
 * par critère + seuils de recommandation ajustés.
 *
 * Pas de dépendance ML externe : déterministe, auditable, offline-ready.
 */
import type { AgentScoreInput } from "@neoforma/shared";

export type AgentLabeledSample = {
  input: AgentScoreInput;
  /** rembourse_ok = 1 (bon), defaut = 0 */
  outcome: "rembourse_ok" | "defaut";
};

export type AgentScoreCalibration = {
  version: string;
  engine: "calibrated_scorecard";
  /** Multiplicateurs des points par critère (clé = part.key), bornés [0.5, 2]. */
  partWeights: Record<string, number>;
  /** Seuil score 300–850 pour « recommande ». */
  recommendMin: number;
  /** Seuil score 300–850 pour « analyse_complementaire ». */
  analyseMin: number;
  trainedAt: string;
  nSamples: number;
  nDefaults: number;
  /** AUC ROC approximative sur le jeu d’entraînement (null si < 2 classes). */
  auc: number | null;
  notes?: string;
};

const FEATURE_KEYS = [
  "regulariteDepots",
  "ancienneteCompte",
  "remboursements",
  "incidentsPaiement",
  "ancienneteActivite",
  "tontine",
  "garants",
  "ancienneteCoop",
  "saisonnalite",
  "actifs",
  "chargeHeadroom",
] as const;

type FeatureKey = (typeof FEATURE_KEYS)[number];

/** Vecteur de features normalisées 0–1 (aligné sur les critères scorecard). */
export function extractAgentFeatureVector(
  input: AgentScoreInput
): Record<FeatureKey, number> {
  const known = Boolean(input.clientConnu);
  const revenu = Math.max(0, input.revenuMensuelFcfa);
  const charges = Math.max(0, input.chargesMensuellesFcfa);
  const demande = Math.max(0, input.montantDemandeFcfa);
  const months = input.dureeMois || 3;
  /** Proxy charge : demande amortie grossièrement / revenu. */
  const roughInstallment = demande / Math.max(1, months);
  const chargeRate =
    revenu > 0 ? (charges + roughInstallment) / revenu : 1.5;
  const headroom = Math.max(0, Math.min(1, 1 - chargeRate / 0.5));

  return {
    regulariteDepots: known ? input.regulariteDepots / 4 : 0,
    ancienneteCompte: known
      ? Math.min(1, input.ancienneteCompteMois / 24)
      : 0,
    remboursements: known ? input.remboursementsAnterieurs / 3 : 0,
    /** Inversé : 0 incidents = 1. */
    incidentsPaiement: known ? 1 - input.incidentsPaiement / 2 : 0.5,
    ancienneteActivite: Math.min(1, input.ancienneteActiviteAns / 5),
    tontine: input.tontine
      ? Math.min(1, 0.4 + input.tontineAns / 5)
      : 0,
    garants: Math.min(1, input.nbGarants / 3),
    ancienneteCoop: Math.min(1, input.ancienneteCoopAns / 3),
    saisonnalite:
      input.saisonnalite === "stable"
        ? 1
        : input.saisonnalite === "moderee"
          ? 0.5
          : 0,
    actifs:
      (input.actifTerrain ? 0.4 : 0) +
      (input.actifBetail ? 0.3 : 0) +
      (input.actifMateriel ? 0.3 : 0),
    chargeHeadroom: headroom,
  };
}

function sigmoid(z: number): number {
  if (z > 20) return 1;
  if (z < -20) return 0;
  return 1 / (1 + Math.exp(-z));
}

function clampWeight(w: number): number {
  return Math.max(0.5, Math.min(2, w));
}

/** AUC ROC Mann–Whitney (1 = parfait). */
function computeAuc(
  scores: number[],
  labels: number[]
): number | null {
  const pos: number[] = [];
  const neg: number[] = [];
  for (let i = 0; i < labels.length; i++) {
    if (labels[i] === 1) pos.push(scores[i]!);
    else neg.push(scores[i]!);
  }
  if (pos.length === 0 || neg.length === 0) return null;
  let wins = 0;
  for (const p of pos) {
    for (const n of neg) {
      if (p > n) wins += 1;
      else if (p === n) wins += 0.5;
    }
  }
  return wins / (pos.length * neg.length);
}

/**
 * Calibre les poids du scorecard à partir de dossiers labellisés.
 * Requiert au moins 20 échantillons et les 2 classes.
 */
export function calibrateAgentScorecard(
  samples: AgentLabeledSample[],
  opts?: { version?: string; notes?: string; iterations?: number; lr?: number }
): AgentScoreCalibration {
  if (samples.length < 20) {
    throw new Error(
      `Calibrage impossible : ${samples.length} échantillons (min. 20).`
    );
  }
  const nDefaults = samples.filter((s) => s.outcome === "defaut").length;
  const nGoods = samples.length - nDefaults;
  if (nDefaults < 3 || nGoods < 3) {
    throw new Error(
      `Calibrage impossible : besoin d'au moins 3 rembourse_ok et 3 defaut (got ${nGoods}/${nDefaults}).`
    );
  }

  const X = samples.map((s) => extractAgentFeatureVector(s.input));
  const y = samples.map((s) => (s.outcome === "rembourse_ok" ? 1 : 0));

  const dim = FEATURE_KEYS.length;
  const w = new Array<number>(dim).fill(0);
  let b = 0;
  const lr = opts?.lr ?? 0.35;
  const iterations = opts?.iterations ?? 400;

  for (let iter = 0; iter < iterations; iter++) {
    const gradW = new Array<number>(dim).fill(0);
    let gradB = 0;
    for (let i = 0; i < X.length; i++) {
      const xi = X[i]!;
      let z = b;
      for (let j = 0; j < dim; j++) {
        z += w[j]! * xi[FEATURE_KEYS[j]!]!;
      }
      const pred = sigmoid(z);
      const err = pred - y[i]!;
      for (let j = 0; j < dim; j++) {
        gradW[j]! += err * xi[FEATURE_KEYS[j]!]!;
      }
      gradB += err;
    }
    const n = X.length;
    for (let j = 0; j < dim; j++) {
      w[j]! -= (lr * gradW[j]!) / n;
    }
    b -= (lr * gradB) / n;
  }

  /** Multiplicateurs : coef positif (prédictif de bon remboursement) → poids ↑. */
  const partWeights: Record<string, number> = {};
  for (let j = 0; j < dim; j++) {
    const key = FEATURE_KEYS[j]!;
    if (key === "chargeHeadroom") continue; // pénalité charge déjà hors barème points
    partWeights[key] = clampWeight(Math.exp(w[j]!));
  }

  /** Scores logistiques pour AUC + seuils empiriques. */
  const probs: number[] = [];
  for (let i = 0; i < X.length; i++) {
    const xi = X[i]!;
    let z = b;
    for (let j = 0; j < dim; j++) {
      z += w[j]! * xi[FEATURE_KEYS[j]!]!;
    }
    probs.push(sigmoid(z));
  }
  const auc = computeAuc(probs, y);

  /** Seuils : percentiles des bons / mixtes → mappés approx. sur 300–850. */
  const goodProbs = probs
    .filter((_, i) => y[i] === 1)
    .sort((a, b) => a - b);
  const p50 = goodProbs[Math.floor(goodProbs.length * 0.5)] ?? 0.6;
  const p25 = goodProbs[Math.floor(goodProbs.length * 0.25)] ?? 0.45;
  const recommendMin = Math.round(300 + Math.max(0.55, p50) * 550);
  const analyseMin = Math.round(300 + Math.max(0.4, Math.min(p25, p50 - 0.05)) * 550);

  const version =
    opts?.version ??
    `agent-cal-${new Date().toISOString().slice(0, 10)}-${samples.length}`;

  return {
    version,
    engine: "calibrated_scorecard",
    partWeights,
    recommendMin: Math.min(800, Math.max(650, recommendMin)),
    analyseMin: Math.min(700, Math.max(520, Math.min(analyseMin, recommendMin - 50))),
    trainedAt: new Date().toISOString(),
    nSamples: samples.length,
    nDefaults,
    auc,
    notes: opts?.notes,
  };
}
