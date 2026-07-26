import type { ProfilActivite, Operation, DemandeCredit } from "@prisma/client";
import type { ScoreFeatures } from "@neoforma/shared";

const ANCIENNETE: Record<string, number> = {
  m1: 1,
  "1_2": 2,
  "3_5": 3,
  "6_10": 4,
  p10: 5,
};

const CA: Record<string, number> = {
  m5k: 1,
  "5_15k": 2,
  "15_30k": 3,
  "30_60k": 4,
  "60_100k": 5,
  p100k: 6,
};

const MM: Record<string, number> = {
  jamais: 0,
  occasionnel: 1,
  regulier: 2,
  quotidien: 3,
};

const COMPTE: Record<string, number> = {
  non: 0,
  oui_dormant: 1,
  oui_actif: 2,
};

/** Part des encaissements à crédit (créances) sur 30 j → échelle 1–4. */
function partCreditFromOps(
  salesFcfa: number,
  creditSalesFcfa: number
): number {
  const base = salesFcfa + creditSalesFcfa;
  if (base <= 0) return 1;
  const ratio = creditSalesFcfa / base;
  if (ratio < 0.25) return 1;
  if (ratio < 0.5) return 2;
  if (ratio < 0.75) return 3;
  return 4;
}

/**
 * Historique crédit : 0 aucun signal, 1 créances réglées, 2 demande
 * acceptée / remboursée (meilleur signal).
 */
function creditHistFromActivity(
  settledDebts: number,
  demandes: Pick<DemandeCredit, "statut">[]
): number {
  const strong = demandes.some((d) =>
    ["approuvee", "decaissee"].includes(d.statut)
  );
  if (strong) return 2;
  if (
    settledDebts > 0 ||
    demandes.some((d) => ["soumise", "en_examen"].includes(d.statut))
  ) {
    return 1;
  }
  return 0;
}

/** Ancienneté tontine approximée via cotisation (pas de champ années en profil). */
function tontineAnsFromProfil(profil: ProfilActivite | null | undefined): number {
  if (!profil?.participationTontine) return 0;
  const cotis = profil.cotisationTontine ?? 0;
  if (cotis <= 0) return 1;
  if (cotis < 5_000) return 2;
  if (cotis < 15_000) return 3;
  if (cotis < 30_000) return 4;
  return 5;
}

export type FeaturesInput = {
  profil: ProfilActivite | null | undefined;
  ops: Operation[];
  /** Utilisateur app mobile = smartphone (échelle terrain 0–2). */
  hasSmartphone?: boolean;
  demandes?: Pick<DemandeCredit, "statut">[];
};

/** Features NeoScore à partir du ProfilActivite + opérations ledger (+ crédit). */
export function featuresFromProfilAndOps(
  profilOrInput: ProfilActivite | null | undefined | FeaturesInput,
  opsArg?: Operation[]
): ScoreFeatures {
  const input: FeaturesInput =
    profilOrInput !== null &&
    typeof profilOrInput === "object" &&
    "ops" in (profilOrInput as FeaturesInput)
      ? (profilOrInput as FeaturesInput)
      : { profil: profilOrInput as ProfilActivite | null | undefined, ops: opsArg ?? [] };

  const { profil, ops, hasSmartphone = true, demandes = [] } = input;

  const since = new Date();
  since.setDate(since.getDate() - 30);
  const last30 = ops.filter((o) => o.dateOperation >= since);
  const sales = last30.filter((o) => o.type === "vente");
  const creditSales = last30.filter((o) => o.type === "creance");
  const debts = ops.filter(
    (o) =>
      o.type === "creance" &&
      o.statutCreance !== "reglee" &&
      o.statutCreance !== "annulee"
  );
  const overdue = debts.filter((o) => o.statutCreance === "en_retard");
  const settled = ops.filter(
    (o) => o.type === "creance" && o.statutCreance === "reglee"
  );

  const salesLast30Fcfa = sales.reduce((s, o) => s + o.montantFcfa, 0);
  const creditSalesFcfa = creditSales.reduce((s, o) => s + o.montantFcfa, 0);

  return {
    anciennete: ANCIENNETE[profil?.ancienneteActivite ?? "3_5"] ?? 3,
    caJour: CA[profil?.caJournalierEstime ?? "15_30k"] ?? 3,
    partCredit: partCreditFromOps(salesLast30Fcfa, creditSalesFcfa),
    impayes: Math.min(4, overdue.length),
    tontine: Boolean(profil?.participationTontine),
    tontineAns: tontineAnsFromProfil(profil),
    mobileMoney: MM[profil?.usageMobileMoney ?? "occasionnel"] ?? 1,
    telephone: hasSmartphone ? 2 : 1,
    compte: COMPTE[profil?.statutCompteBancaire ?? "non"] ?? 0,
    creditHist: creditHistFromActivity(settled.length, demandes),
    opsLast30Days: last30.length,
    salesLast30Fcfa,
    openDebtsFcfa: debts.reduce((s, o) => s + o.montantFcfa, 0),
    overdueDebtsCount: overdue.length,
  };
}

/** @deprecated alias */
export const featuresFromUserAndOps = featuresFromProfilAndOps;
