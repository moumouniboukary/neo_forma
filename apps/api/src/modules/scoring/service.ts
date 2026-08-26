import type {
  NeoScore,
  NeoScoreHistorique,
  OffreCredit,
  PrismaClient,
} from "@prisma/client";
import {
  buildOfferAmount,
  computeNeoScore,
  ELIGIBILITY_THRESHOLD,
  finalizeNeoScoreResult,
} from "@neoforma/neoscore";
import type { NeoScoreResult, ScoreFeatures } from "@neoforma/shared";
import {
  isMlScoringEnabled,
  mlScore,
  mlToNeoScoreResult,
} from "../../lib/ml-scoring.js";
import { featuresFromProfilAndOps } from "./features.js";

export class ScoringError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "ScoringError";
  }
}

export function isScoringError(err: unknown): err is ScoringError {
  return err instanceof ScoringError;
}

const OFFER_TTL_MS = 7 * 24 * 60 * 60 * 1000;
/** Score affiché : pas de recalcul si plus frais que ce TTL. */
const SCORE_CACHE_TTL_MS = 60 * 60 * 1000;
const DUREE_MOIS = 3;
const TAUX_MENSUEL = 2.5;

function monthLabel(d = new Date()): string {
  return d.toLocaleDateString("fr-FR", { month: "long", year: "numeric" });
}

function toResultPartial(
  neoscore: NeoScore,
  history: Array<{ month: string; score: number }>
): Pick<
  NeoScoreResult,
  "score" | "segment" | "criteria" | "history" | "engine" | "modelVersion"
> &
  Partial<NeoScoreResult> {
  return {
    score: neoscore.valeur,
    segment: neoscore.segment as NeoScoreResult["segment"],
    eligible: neoscore.eligible,
    threshold: ELIGIBILITY_THRESHOLD,
    criteria: {
      regularite: neoscore.critereRegularite,
      volume: neoscore.critereVolume,
      dettes: neoscore.critereGestionCreances,
      croissance: neoscore.critereCroissance,
    },
    history,
    computedAt: neoscore.dateCalcul.toISOString(),
    engine: (neoscore.moteur === "ml" ? "ml" : "heuristic") as
      | "ml"
      | "heuristic",
    modelVersion: neoscore.modelVersion ?? null,
  };
}

export class ScoringService {
  constructor(private readonly prisma: PrismaClient) {}

  /**
   * Calcule features + score (ML si SCORING_ML_URL, sinon heuristique).
   * Persiste NeoScore + historique.
   * Crée / rafraîchit une offre uniquement si `persistOffer` (défaut true pour crédit).
   */
  async recalculate(
    travailleurId: string,
    opts: { persistOffer?: boolean } = {}
  ): Promise<{
    result: NeoScoreResult;
    neoscore: NeoScore;
    offre: OffreCredit | null;
    features: ScoreFeatures;
  }> {
    const persistOffer = opts.persistOffer ?? true;

    const user = await this.prisma.travailleur.findUnique({
      where: { id: travailleurId },
      include: { profilActivite: true },
    });
    if (!user) {
      throw new ScoringError("not_found", "Utilisateur introuvable", 404);
    }

    const [ops, demandes, existing, tontineCotisations] = await Promise.all([
      this.prisma.operation.findMany({
        where: { travailleurId },
        orderBy: { dateOperation: "desc" },
        take: 500,
      }),
      this.prisma.demandeCredit.findMany({
        where: { travailleurId },
        select: { statut: true },
        take: 50,
      }),
      this.prisma.neoScore.findUnique({
        where: { travailleurId },
        include: {
          historique: { orderBy: { enregistreAt: "desc" }, take: 6 },
        },
      }),
      this.sumTontineCotisations30d(travailleurId),
    ]);

    const history = (existing?.historique ?? [])
      .slice()
      .reverse()
      .map((h: NeoScoreHistorique) => ({ month: h.periode, score: h.valeur }));

    const features = featuresFromProfilAndOps({
      profil: user.profilActivite,
      ops,
      hasSmartphone: Boolean(user.telephone),
      demandes,
      tontineCotisations30Fcfa: tontineCotisations,
    });

    let result: NeoScoreResult = computeNeoScore(features, history);
    let moteur: "heuristic" | "ml" = "heuristic";
    let modelVersion: string | null = null;

    if (isMlScoringEnabled()) {
      const ml = await mlScore(features);
      if (ml) {
        const mlPartial = mlToNeoScoreResult(ml, history);
        result = finalizeNeoScoreResult(
          {
            score: mlPartial.score,
            segment: mlPartial.segment,
            criteria: mlPartial.criteria,
            history,
            engine: "ml",
            modelVersion: mlPartial.modelVersion ?? ml.modelVersion ?? null,
            computedAt: mlPartial.computedAt,
          },
          features
        );
        moteur = "ml";
        modelVersion = result.modelVersion ?? null;
      }
    }

    const neoscore = await this.prisma.neoScore.upsert({
      where: { travailleurId },
      create: {
        travailleurId,
        valeur: result.score,
        seuilEligibilite: ELIGIBILITY_THRESHOLD,
        eligible: result.eligible,
        segment: result.segment,
        critereRegularite: Math.round(result.criteria.regularite),
        critereVolume: Math.round(result.criteria.volume),
        critereGestionCreances: Math.round(result.criteria.dettes),
        critereCroissance: Math.round(result.criteria.croissance),
        periodeAnalyseJours: 30,
        moteur,
        modelVersion,
        dateCalcul: new Date(),
      },
      update: {
        valeur: result.score,
        eligible: result.eligible,
        segment: result.segment,
        critereRegularite: Math.round(result.criteria.regularite),
        critereVolume: Math.round(result.criteria.volume),
        critereGestionCreances: Math.round(result.criteria.dettes),
        critereCroissance: Math.round(result.criteria.croissance),
        moteur,
        modelVersion,
        dateCalcul: new Date(),
      },
    });

    await this.appendHistoryIfNeeded(neoscore.id, result.score);

    const historique = await this.prisma.neoScoreHistorique.findMany({
      where: { neoscoreId: neoscore.id },
      orderBy: { enregistreAt: "asc" },
      take: 12,
    });

    const resultWithHistory: NeoScoreResult = {
      ...result,
      engine: moteur,
      modelVersion,
      history: historique.map((h: NeoScoreHistorique) => ({
        month: h.periode,
        score: h.valeur,
      })),
      computedAt: neoscore.dateCalcul.toISOString(),
    };

    const offre = persistOffer
      ? await this.upsertOffer(travailleurId, neoscore.id, resultWithHistory, features)
      : null;

    return { result: resultWithHistory, neoscore, offre, features };
  }

  /** Features actuelles (profil + ops) — pour enrichir un score en cache. */
  private async loadFeatures(travailleurId: string): Promise<ScoreFeatures> {
    const user = await this.prisma.travailleur.findUnique({
      where: { id: travailleurId },
      include: { profilActivite: true },
    });
    const [ops, demandes, tontineCotisations] = await Promise.all([
      this.prisma.operation.findMany({
        where: { travailleurId },
        orderBy: { dateOperation: "desc" },
        take: 500,
      }),
      this.prisma.demandeCredit.findMany({
        where: { travailleurId },
        select: { statut: true },
        take: 50,
      }),
      this.sumTontineCotisations30d(travailleurId),
    ]);
    return featuresFromProfilAndOps({
      profil: user?.profilActivite ?? null,
      ops,
      hasSmartphone: Boolean(user?.telephone),
      demandes,
      tontineCotisations30Fcfa: tontineCotisations,
    });
  }

  /** Lecture score : cache TTL, sinon recalcul sans créer d'offre. */
  async getCurrent(travailleurId: string): Promise<NeoScoreResult> {
    const existing = await this.prisma.neoScore.findUnique({
      where: { travailleurId },
      include: {
        historique: { orderBy: { enregistreAt: "asc" }, take: 12 },
      },
    });

    const fresh =
      existing &&
      Date.now() - existing.dateCalcul.getTime() < SCORE_CACHE_TTL_MS;

    if (fresh && existing) {
      const partial = toResultPartial(
        existing,
        existing.historique.map((h: NeoScoreHistorique) => ({
          month: h.periode,
          score: h.valeur,
        }))
      );
      const features = await this.loadFeatures(travailleurId);
      return finalizeNeoScoreResult(partial, features);
    }

    const { result } = await this.recalculate(travailleurId, {
      persistOffer: false,
    });
    return result;
  }

  async getLatestOffer(travailleurId: string): Promise<OffreCredit> {
    const { offre } = await this.recalculate(travailleurId, {
      persistOffer: true,
    });
    if (!offre) {
      throw new ScoringError("offer", "Offre indisponible", 500);
    }
    return offre;
  }

  async getValidOffer(travailleurId: string): Promise<OffreCredit | null> {
    const now = new Date();
    const offer = await this.prisma.offreCredit.findFirst({
      where: {
        travailleurId,
        eligible: true,
        OR: [{ valideJusqua: null }, { valideJusqua: { gt: now } }],
      },
      orderBy: { dateGeneration: "desc" },
    });
    if (offer) return offer;
    const fresh = await this.recalculate(travailleurId, { persistOffer: true });
    return fresh.offre?.eligible ? fresh.offre : null;
  }

  /** Une offre valide par travailleur : mise à jour si encore dans le TTL. */
  private async upsertOffer(
    travailleurId: string,
    neoscoreId: string,
    result: NeoScoreResult,
    features: ScoreFeatures
  ): Promise<OffreCredit> {
    const amounts = buildOfferAmount(result.score, features);
    const now = new Date();
    const current = await this.prisma.offreCredit.findFirst({
      where: {
        travailleurId,
        OR: [{ valideJusqua: null }, { valideJusqua: { gt: now } }],
      },
      orderBy: { dateGeneration: "desc" },
    });

    if (current) {
      return this.prisma.offreCredit.update({
        where: { id: current.id },
        data: {
          neoscoreId,
          montantMinFcfa: amounts.minFcfa,
          montantMaxFcfa: amounts.maxFcfa,
          montantSuggereFcfa: amounts.suggestedFcfa,
          dureeMois: DUREE_MOIS,
          tauxMensuelIndicatif: TAUX_MENSUEL,
          eligible: result.eligible,
          dateGeneration: now,
          valideJusqua: new Date(Date.now() + OFFER_TTL_MS),
        },
      });
    }

    return this.prisma.offreCredit.create({
      data: {
        travailleurId,
        neoscoreId,
        montantMinFcfa: amounts.minFcfa,
        montantMaxFcfa: amounts.maxFcfa,
        montantSuggereFcfa: amounts.suggestedFcfa,
        dureeMois: DUREE_MOIS,
        tauxMensuelIndicatif: TAUX_MENSUEL,
        eligible: result.eligible,
        dateGeneration: now,
        valideJusqua: new Date(Date.now() + OFFER_TTL_MS),
      },
    });
  }

  private async appendHistoryIfNeeded(
    neoscoreId: string,
    valeur: number
  ): Promise<void> {
    const periode = monthLabel();
    const last = await this.prisma.neoScoreHistorique.findFirst({
      where: { neoscoreId },
      orderBy: { enregistreAt: "desc" },
    });
    if (last?.periode === periode) {
      await this.prisma.neoScoreHistorique.update({
        where: { id: last.id },
        data: { valeur, enregistreAt: new Date() },
      });
      return;
    }
    await this.prisma.neoScoreHistorique.create({
      data: { neoscoreId, periode, valeur },
    });
  }

  /** Cotisations tontine enregistrées sur les 30 derniers jours. */
  private async sumTontineCotisations30d(travailleurId: string): Promise<number> {
    const since = new Date();
    since.setDate(since.getDate() - 30);
    const rows = await this.prisma.tontineCotisation.findMany({
      where: {
        datePaiement: { gte: since },
        tontine: { travailleurId, actif: true },
      },
      select: { montantFcfa: true },
    });
    return rows.reduce(
      (s: number, r: { montantFcfa: number }) => s + r.montantFcfa,
      0
    );
  }
}

export type { NeoScore, NeoScoreHistorique, OffreCredit };
