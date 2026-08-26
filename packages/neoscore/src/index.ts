import type {
  DataQuality,
  NeoScoreResult,
  NeoSegment,
  RepaymentCapacity,
  ScoreCriteria,
  ScoreFeatures,
} from "@neoforma/shared";

const ELIGIBILITY_THRESHOLD = 50;
const MIN_OPS_LAST_30 = 5;
const MIN_ACTIVE_WEEKS = 4;
const REPAYMENT_CAPACITY_RATIO = 0.35;
const LOAN_DURATION_MONTHS = 3;
const LOAN_MONTHLY_RATE = 0.025;
const DECLARED_VS_ACTUAL_MIN = 0.5;
const DECLARED_VS_ACTUAL_MAX = 2.0;
const MIN_OFFER_FCFA = 50_000;
const MAX_OFFER_FCFA = 500_000;

const CA_MIDPOINT_FCFA: Record<number, number> = {
  1: 2_500,
  2: 10_000,
  3: 22_500,
  4: 45_000,
  5: 80_000,
  6: 120_000,
};

const SEASONAL_FACTOR: Record<string, number> = {
  stable: 1,
  moderee: 0.92,
  forte: 0.85,
};

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

export function declaredCaMidpointFcfa(caJour: number): number {
  return CA_MIDPOINT_FCFA[caJour] ?? 22_500;
}

function maxPrincipalFromPayment(
  payment: number,
  months: number,
  rate: number
): number {
  if (payment <= 0) return 0;
  if (rate <= 0) return payment * months;
  const factor = Math.pow(1 + rate, months);
  return Math.round((payment * (factor - 1)) / (rate * factor));
}

/** Qualité des données terrain + cohérence déclaratif / cahier */
export function assessDataQuality(features: ScoreFeatures): DataQuality {
  const ratio = features.salesVsDeclaredRatio ?? 1;
  const hasLedgerSales = features.salesLast30Fcfa > 0;
  const declaredOk =
    !hasLedgerSales ||
    (ratio >= DECLARED_VS_ACTUAL_MIN && ratio <= DECLARED_VS_ACTUAL_MAX);
  const minActivityMet =
    features.opsLast30Days >= MIN_OPS_LAST_30 ||
    (features.activeWeeksLast30 ?? 0) >= MIN_ACTIVE_WEEKS;

  const warnings: string[] = [];
  if (!minActivityMet) {
    warnings.push(
      "Activité insuffisante sur 30 jours (min. 5 opérations ou 4 semaines actives)."
    );
  }
  if (!declaredOk) {
    const pct = Math.round(ratio * 100);
    warnings.push(
      `Ventes cahier = ${pct}% du CA déclaré (hors plage 50–200%). Vérification recommandée.`
    );
  }
  if (
    hasLedgerSales &&
    (features.expensesLast30Fcfa ?? 0) > features.salesLast30Fcfa
  ) {
    warnings.push("Dépenses supérieures aux ventes sur 30 jours.");
  }

  return {
    minActivityMet,
    declaredVsActualOk: declaredOk,
    declaredVsActualRatio: hasLedgerSales ? ratio : undefined,
    warnings,
  };
}

/**
 * Capacité de remboursement : mensualité ≤ 35 % du revenu mensuel estimé net.
 * - Priorité au cahier (ventes observées) ; le CA déclaré ne sert qu’à défaut.
 * - Jamais d’inflation via max(déclaré, réel).
 * - Net = (ventes − dépenses variables) × saisonnalité − charges fixes / tontine.
 */
export function assessRepaymentCapacity(features: ScoreFeatures): RepaymentCapacity {
  const declaredDaily =
    features.declaredCaMidpointFcfa > 0
      ? features.declaredCaMidpointFcfa
      : declaredCaMidpointFcfa(features.caJour);
  const declaredMonthly = declaredDaily * 30;
  const actualMonthly = features.salesLast30Fcfa;
  const expenses = Math.max(0, features.expensesLast30Fcfa ?? 0);

  const seasonal = SEASONAL_FACTOR[features.saisonnalite ?? "stable"] ?? 1;
  const charges =
    (features.monthlyFixedChargesFcfa ?? 0) +
    (features.tontineCotisations30Fcfa ?? 0);

  /** Cold-start sans cahier : proxy déclaratif. Sinon : ventes observées uniquement. */
  const grossBase = actualMonthly > 0 ? actualMonthly : declaredMonthly;
  const variableCosts = actualMonthly > 0 ? Math.min(expenses, grossBase) : 0;
  const grossMargin = Math.max(0, grossBase - variableCosts);

  const estimatedMonthlyRevenueFcfa = Math.max(
    0,
    Math.round(grossMargin * seasonal - charges)
  );
  const maxMonthlyPaymentFcfa = Math.round(
    estimatedMonthlyRevenueFcfa * REPAYMENT_CAPACITY_RATIO
  );
  const maxPrincipalFcfa = maxPrincipalFromPayment(
    maxMonthlyPaymentFcfa,
    LOAN_DURATION_MONTHS,
    LOAN_MONTHLY_RATE
  );

  return {
    estimatedMonthlyRevenueFcfa,
    maxMonthlyPaymentFcfa,
    capacityRatio: REPAYMENT_CAPACITY_RATIO,
    maxPrincipalFcfa,
  };
}

export function isEligible(
  score: number,
  features: ScoreFeatures,
  capacity: RepaymentCapacity,
  quality: DataQuality
): boolean {
  if (score < ELIGIBILITY_THRESHOLD) return false;
  if (!quality.minActivityMet) return false;
  if (capacity.maxPrincipalFcfa < MIN_OFFER_FCFA) return false;
  /** Trop d’impayés / retards : non éligible même si le score dépasse le seuil. */
  if ((features.overdueDebtsCount ?? 0) >= 2) return false;
  if ((features.impayes ?? 0) >= 3) return false;
  if ((features.openDebtsFcfa ?? 0) > features.salesLast30Fcfa * 1.2) return false;
  return true;
}

/** Critères 0–100 dérivés des features terrain + activité app */
export function computeCriteria(features: ScoreFeatures): ScoreCriteria {
  const marginLast30 =
    features.salesLast30Fcfa - (features.expensesLast30Fcfa ?? 0);
  const marginBonus = Math.min(25, Math.max(-20, marginLast30 / 8_000));

  const ratio = features.salesVsDeclaredRatio ?? 1;
  const coherencePenalty =
    features.salesLast30Fcfa > 0 &&
    (ratio < DECLARED_VS_ACTUAL_MIN || ratio > DECLARED_VS_ACTUAL_MAX)
      ? 15
      : 0;

  const seasonalAdj =
    features.saisonnalite === "forte"
      ? -8
      : features.saisonnalite === "moderee"
        ? -4
        : 0;

  const chargeBurden =
    features.salesLast30Fcfa > 0 &&
    (features.monthlyFixedChargesFcfa ?? 0) > features.salesLast30Fcfa * 0.5
      ? 10
      : 0;

  /** Ops plafonnées : éviter la saturation à 100 dès ~20 opérations. */
  const opsRegularite = Math.min(55, features.opsLast30Days * 3);

  const regularite = clamp(
    opsRegularite +
      (features.tontine ? 15 : 0) +
      features.mobileMoney * 8 +
      features.anciennete * 6 +
      Math.min(10, (features.tontineCotisations30Fcfa ?? 0) / 5_000)
  );

  /**
   * Volume d’activité : CA déclaré + ventes cahier + marge.
   * partCredit (part ventes à crédit) n’augmente plus le volume — risque, pas signal positif.
   */
  const volume = clamp(
    features.caJour * 12 +
      Math.min(40, features.salesLast30Fcfa / 5_000) +
      features.telephone * 5 +
      marginBonus +
      seasonalAdj -
      coherencePenalty -
      Math.max(0, features.partCredit - 1) * 4
  );

  const debtRatio =
    features.salesLast30Fcfa > 0
      ? features.openDebtsFcfa / features.salesLast30Fcfa
      : features.openDebtsFcfa > 0
        ? 2
        : 0;
  /** Pénalité stock : ratio créances/ventes + plafond absolu (différencie 70 k vs 450 k). */
  const debtStockPenalty = Math.min(
    50,
    Math.min(25, features.openDebtsFcfa / 3_000) + debtRatio * 28
  );

  const dettes = clamp(
    100 -
      features.impayes * 18 -
      debtStockPenalty -
      features.overdueDebtsCount * 12 +
      features.compte * 5 -
      chargeBurden -
      Math.max(0, features.partCredit - 1) * 3
  );

  const croissance = clamp(
    features.opsLast30Days * 3 +
      features.anciennete * 8 +
      (features.tontine ? features.tontineAns * 3 : 0) +
      features.creditHist * 10 +
      (features.garantieSolidaire ? 8 : 0)
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
  const juniorStrong =
    features.anciennete <= 2 &&
    score >= 85 &&
    features.opsLast30Days >= 15;

  let segment: NeoSegment;
  if (score < 40 && features.opsLast30Days < 5) segment = "D";
  else if (score < 55 && features.anciennete <= 2) segment = "C";
  else if (score >= 65 && features.impayes <= 1) {
    /** Junior (< 3 ans) : pas de segment A sauf score très élevé et activité dense. */
    segment =
      features.anciennete <= 2 && !juniorStrong ? "B" : "A";
  } else segment = "B";

  if (features.garantieSolidaire) {
    if (segment === "C" && score >= 55) segment = "B";
    else if (segment === "B" && score >= 65) {
      /** La garantie ne contourne pas le plafond junior → A. */
      if (features.anciennete > 2 || juniorStrong) segment = "A";
    }
  }
  return segment;
}

export function buildOfferAmount(
  score: number,
  features: ScoreFeatures
): {
  minFcfa: number;
  maxFcfa: number;
  suggestedFcfa: number;
} {
  const capacity = assessRepaymentCapacity(features);
  const quality = assessDataQuality(features);

  if (!isEligible(score, features, capacity, quality)) {
    return { minFcfa: 0, maxFcfa: 0, suggestedFcfa: 0 };
  }

  const scoreMax = Math.min(MAX_OFFER_FCFA, MIN_OFFER_FCFA + score * 3_000);
  const maxFcfa = Math.min(scoreMax, capacity.maxPrincipalFcfa);
  if (maxFcfa < MIN_OFFER_FCFA) {
    return { minFcfa: 0, maxFcfa: 0, suggestedFcfa: 0 };
  }

  const minFcfa = MIN_OFFER_FCFA;
  const suggestedFcfa =
    Math.round((minFcfa + maxFcfa) / 2 / 1_000) * 1_000;
  return {
    minFcfa,
    maxFcfa,
    suggestedFcfa: Math.max(minFcfa, Math.min(maxFcfa, suggestedFcfa)),
  };
}

/** Applique règles d'éligibilité et métadonnées solvabilité à un résultat partiel (heuristic ou ML). */
export function finalizeNeoScoreResult(
  partial: Pick<
    NeoScoreResult,
    "score" | "segment" | "criteria" | "history" | "engine" | "modelVersion"
  > &
    Partial<NeoScoreResult>,
  features: ScoreFeatures
): NeoScoreResult {
  const quality = assessDataQuality(features);
  const capacity = assessRepaymentCapacity(features);
  const eligible = isEligible(partial.score, features, capacity, quality);

  return {
    score: partial.score,
    segment: partial.segment,
    eligible,
    threshold: ELIGIBILITY_THRESHOLD,
    criteria: partial.criteria,
    history: partial.history,
    computedAt: partial.computedAt ?? new Date().toISOString(),
    engine: partial.engine ?? "heuristic",
    modelVersion: partial.modelVersion ?? null,
    dataQuality: quality,
    repaymentCapacity: capacity,
  };
}

export function computeNeoScore(
  features: ScoreFeatures,
  history: Array<{ month: string; score: number }> = []
): NeoScoreResult {
  const criteria = computeCriteria(features);
  const score = computeScore(criteria);
  const segment = assignSegment(score, features);

  return finalizeNeoScoreResult(
    {
      score,
      segment,
      criteria,
      history,
      engine: "heuristic",
      modelVersion: null,
    },
    features
  );
}

export {
  ELIGIBILITY_THRESHOLD,
  MIN_OPS_LAST_30,
  MIN_ACTIVE_WEEKS,
  REPAYMENT_CAPACITY_RATIO,
  LOAN_DURATION_MONTHS,
  LOAN_MONTHLY_RATE,
};
