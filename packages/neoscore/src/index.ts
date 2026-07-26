import type { NeoScoreResult, NeoSegment, ScoreCriteria, ScoreFeatures } from "@neoforma/shared";

const ELIGIBILITY_THRESHOLD = 50;

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

/** Critères 0–100 dérivés des features terrain + activité app */
export function computeCriteria(features: ScoreFeatures): ScoreCriteria {
  const regularite = clamp(
    features.opsLast30Days * 4 +
      (features.tontine ? 15 : 0) +
      features.mobileMoney * 8 +
      features.anciennete * 6
  );

  const volume = clamp(
    features.caJour * 12 +
      Math.min(40, features.salesLast30Fcfa / 5000) +
      features.telephone * 5 +
      features.partCredit * 3
  );

  const dettes = clamp(
    100 -
      features.impayes * 18 -
      Math.min(35, features.openDebtsFcfa / 2000) -
      features.overdueDebtsCount * 12 +
      features.compte * 5
  );

  const croissance = clamp(
    features.opsLast30Days * 3 +
      features.anciennete * 8 +
      (features.tontine ? features.tontineAns * 3 : 0) +
      features.creditHist * 10
  );

  return { regularite, volume, dettes, croissance };
}

export function computeScore(criteria: ScoreCriteria): number {
  const raw =
    criteria.regularite * 0.3 +
    criteria.volume * 0.25 +
    criteria.dettes * 0.25 +
    criteria.croissance * 0.2;
  return Math.round(clamp(raw));
}

export function assignSegment(score: number, features: ScoreFeatures): NeoSegment {
  if (score < 40 && features.opsLast30Days < 5) return "D";
  if (score < 55 && features.anciennete <= 2) return "C";
  if (score >= 65 && features.impayes <= 1) return "A";
  return "B";
}

export function buildOfferAmount(score: number): {
  minFcfa: number;
  maxFcfa: number;
  suggestedFcfa: number;
} {
  if (score < ELIGIBILITY_THRESHOLD) {
    return { minFcfa: 0, maxFcfa: 0, suggestedFcfa: 0 };
  }
  const maxFcfa = Math.min(500_000, 50_000 + score * 3_000);
  const minFcfa = 50_000;
  const suggestedFcfa = Math.round((minFcfa + maxFcfa) / 2 / 1000) * 1000;
  return { minFcfa, maxFcfa, suggestedFcfa };
}

export function computeNeoScore(
  features: ScoreFeatures,
  history: Array<{ month: string; score: number }> = []
): NeoScoreResult {
  const criteria = computeCriteria(features);
  const score = computeScore(criteria);
  const segment = assignSegment(score, features);
  const now = new Date().toISOString();

  return {
    score,
    segment,
    eligible: score >= ELIGIBILITY_THRESHOLD,
    threshold: ELIGIBILITY_THRESHOLD,
    criteria,
    history,
    computedAt: now,
  };
}

export { ELIGIBILITY_THRESHOLD };
