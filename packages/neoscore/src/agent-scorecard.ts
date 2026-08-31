import type {
  AgentRecommendation,
  AgentRiskCategory,
  AgentScoreDriver,
  AgentScoreInput,
  AgentScoreResult,
} from "@neoforma/shared";
import type { AgentScoreCalibration } from "./calibrate-agent-scorecard.js";

export type { AgentScoreCalibration };

/** Mensualité indicative : amortissement simple (capital+intérêts / durée). */
const LOAN_MONTHLY_RATE = 0.025;
/** Charge max raisonnable (PDF : capacité de remboursement). */
const MAX_CHARGE_RATE = 0.4;
const TARGET_CHARGE_RATE = 0.35;

function clamp(n: number, min = 0, max = 100): number {
  return Math.max(min, Math.min(max, n));
}

function toScale850(score100: number): number {
  return Math.round(300 + clamp(score100) * 5.5);
}

function estimatedInstallment(principal: number, months: number): number {
  if (principal <= 0 || months <= 0) return 0;
  const factor = Math.pow(1 + LOAN_MONTHLY_RATE, months);
  const payment =
    (principal * LOAN_MONTHLY_RATE * factor) / (factor - 1);
  return Math.round(payment);
}

function maxPrincipalFromPayment(payment: number, months: number): number {
  if (payment <= 0 || months <= 0) return 0;
  const factor = Math.pow(1 + LOAN_MONTHLY_RATE, months);
  return Math.round((payment * (factor - 1)) / (LOAN_MONTHLY_RATE * factor));
}

type ScoredPart = { key: string; label: string; points: number; max: number };

function riskFromScore(score850: number): AgentRiskCategory {
  if (score850 >= 700) return "faible";
  if (score850 >= 575) return "modere";
  return "eleve";
}

/**
 * Scorecard DigiCoop : somme pondérée par tranches + proxies primo-demandeurs.
 * Score affiché 300–850.
 * - Sans calibration : poids experts (hypothèses métier).
 * - Avec calibration : multiplicateurs statistiques (hybride long terme).
 */
export function computeAgentScorecard(
  input: AgentScoreInput,
  now = new Date(),
  calibration?: AgentScoreCalibration | null
): AgentScoreResult & { engine: string; modelVersion: string | null } {
  const parts: ScoredPart[] = [];
  const known = Boolean(input.clientConnu);
  const weights = calibration?.partWeights ?? {};

  if (known) {
    const depotsPts = [0, 6, 12, 18, 24][input.regulariteDepots] ?? 0;
    parts.push({
      key: "regulariteDepots",
      label: "Régularité des dépôts",
      points: depotsPts,
      max: 24,
    });

    const comptePts =
      input.ancienneteCompteMois >= 24
        ? 12
        : input.ancienneteCompteMois >= 12
          ? 8
          : input.ancienneteCompteMois >= 6
            ? 4
            : 0;
    parts.push({
      key: "ancienneteCompte",
      label: "Ancienneté du compte",
      points: comptePts,
      max: 12,
    });

    const rembPts = [0, 5, 10, 14][input.remboursementsAnterieurs] ?? 0;
    parts.push({
      key: "remboursements",
      label: "Remboursements antérieurs",
      points: rembPts,
      max: 14,
    });

    const incidentPts = [8, 4, 0][input.incidentsPaiement ?? 0] ?? 0;
    parts.push({
      key: "incidentsPaiement",
      label: "Incidents de paiement",
      points: incidentPts,
      max: 8,
    });
  }

  const actPts =
    input.ancienneteActiviteAns >= 5
      ? 16
      : input.ancienneteActiviteAns >= 3
        ? 12
        : input.ancienneteActiviteAns >= 1
          ? 7
          : 2;
  parts.push({
    key: "ancienneteActivite",
    label: "Ancienneté de l'activité",
    points: actPts,
    max: 16,
  });

  let tontinePts = 0;
  if (input.tontine) {
    tontinePts =
      input.tontineAns >= 3 ? 12 : input.tontineAns >= 1 ? 8 : 5;
  }
  parts.push({
    key: "tontine",
    label: "Appartenance à une tontine",
    points: tontinePts,
    max: 12,
  });

  const garantPts = Math.min(14, input.nbGarants * 5);
  parts.push({
    key: "garants",
    label: "Garants dans le réseau",
    points: garantPts,
    max: 14,
  });

  const coopPts =
    input.ancienneteCoopAns >= 3
      ? 10
      : input.ancienneteCoopAns >= 1
        ? 6
        : 0;
  parts.push({
    key: "ancienneteCoop",
    label: "Relation avec la coopérative",
    points: coopPts,
    max: 10,
  });

  const saisonPts =
    input.saisonnalite === "stable"
      ? 6
      : input.saisonnalite === "moderee"
        ? 3
        : 0;
  parts.push({
    key: "saisonnalite",
    label: "Saisonnalité du revenu",
    points: saisonPts,
    max: 6,
  });

  const actifsPts =
    (input.actifTerrain ? 4 : 0) +
    (input.actifBetail ? 3 : 0) +
    (input.actifMateriel ? 3 : 0);
  parts.push({
    key: "actifs",
    label: "Actifs simples (terrain, bétail, matériel)",
    points: actifsPts,
    max: 10,
  });

  /** Applique multiplicateurs calibrés (sinon 1). */
  const weighted = parts.map((p) => {
    const m = weights[p.key] ?? 1;
    return {
      ...p,
      points: Math.round(p.points * m * 10) / 10,
      max: Math.round(p.max * m * 10) / 10,
    };
  });

  const raw = weighted.reduce((s, p) => s + p.points, 0);
  const maxRaw = weighted.reduce((s, p) => s + p.max, 0);
  let score100 = Math.round(clamp((raw / maxRaw) * 100));

  const months = input.dureeMois || 3;
  const echeanceEstimeeFcfa = estimatedInstallment(
    input.montantDemandeFcfa,
    months
  );
  const revenu = Math.max(0, input.revenuMensuelFcfa);
  const charges = Math.max(0, input.chargesMensuellesFcfa);
  const chargeRate =
    revenu > 0 ? (charges + echeanceEstimeeFcfa) / revenu : 999;

  if (chargeRate > MAX_CHARGE_RATE) {
    score100 = clamp(score100 - 15);
  } else if (chargeRate > TARGET_CHARGE_RATE) {
    score100 = clamp(score100 - 8);
  }

  const score = toScale850(score100);

  const maxPayment = Math.round(revenu * TARGET_CHARGE_RATE - charges);
  const montantSoutenableFcfa = Math.max(
    0,
    maxPrincipalFromPayment(Math.max(0, maxPayment), months)
  );

  const drivers: AgentScoreDriver[] = [...weighted]
    .sort((a, b) => Math.abs(b.points) - Math.abs(a.points))
    .slice(0, 3)
    .map((p) => ({
      key: p.key,
      label: p.label,
      delta: p.points,
    }));

  const recommendMin = calibration?.recommendMin ?? 685;
  const analyseMin = calibration?.analyseMin ?? 575;

  let recommendation: AgentRecommendation;
  if (score >= recommendMin && chargeRate <= TARGET_CHARGE_RATE) {
    recommendation = "recommande";
  } else if (score >= analyseMin && chargeRate <= MAX_CHARGE_RATE) {
    recommendation = "analyse_complementaire";
  } else {
    recommendation = "a_reexaminer";
  }
  if (chargeRate > MAX_CHARGE_RATE && recommendation === "recommande") {
    recommendation = "analyse_complementaire";
  }

  return {
    score,
    recommendation,
    riskCategory: riskFromScore(score),
    drivers,
    chargeRate: Math.round(chargeRate * 1000) / 1000,
    montantSoutenableFcfa,
    echeanceEstimeeFcfa,
    revenuMensuelFcfa: revenu,
    computedAt: now.toISOString(),
    engine: calibration?.engine ?? "expert_scorecard",
    modelVersion: calibration?.version ?? null,
  };
}
