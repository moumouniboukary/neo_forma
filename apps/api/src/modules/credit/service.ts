import type { PrismaClient, SnapshotScore } from "@prisma/client";
import type { SubmitCredit } from "@neoforma/shared";
import { ConsentService } from "../consent/service.js";
import { ScoringService } from "../scoring/service.js";
import { hashPartnerApiKey } from "../../lib/partner-keys.js";
import { createNotification } from "../../lib/notifications.js";

export class CreditError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400,
    public readonly details?: unknown
  ) {
    super(message);
    this.name = "CreditError";
  }
}

export function isCreditError(err: unknown): err is CreditError {
  return err instanceof CreditError;
}

function creditRef(): string {
  const n = Math.floor(1000 + Math.random() * 9000);
  return `NF-${new Date().getFullYear()}-${n}`;
}

export class CreditService {
  private readonly scoring: ScoringService;
  private readonly consents: ConsentService;

  constructor(private readonly prisma: PrismaClient) {
    this.scoring = new ScoringService(prisma);
    this.consents = new ConsentService(prisma);
  }

  async getOffer(travailleurId: string) {
    const { result, offre } = await this.scoring.recalculate(travailleurId, {
      persistOffer: true,
    });
    if (!offre) {
      throw new CreditError("offer", "Offre indisponible", 500);
    }
    return {
      id: offre.id,
      minFcfa: offre.montantMinFcfa,
      maxFcfa: offre.montantMaxFcfa,
      suggestedFcfa: offre.montantSuggereFcfa,
      durationMonths: offre.dureeMois,
      monthlyRatePct: offre.tauxMensuelIndicatif,
      eligible: offre.eligible,
      score: result.score,
      validUntil: offre.valideJusqua?.toISOString() ?? null,
    };
  }

  async listApplications(travailleurId: string) {
    return this.prisma.demandeCredit.findMany({
      where: { travailleurId },
      include: { snapshotScore: true },
      orderBy: { createdAt: "desc" },
    });
  }

  async getApplication(travailleurId: string, id: string) {
    const row = await this.prisma.demandeCredit.findFirst({
      where: { id, travailleurId },
      include: { snapshotScore: true },
    });
    if (!row) {
      throw new CreditError("not_found", "Demande introuvable", 404);
    }
    return row;
  }

  /**
   * Soumet une demande : onboarding + consentement + score + offre + snapshot.
   */
  async submit(travailleurId: string, input: SubmitCredit) {
    const user = await this.prisma.travailleur.findUnique({
      where: { id: travailleurId },
    });
    if (!user) {
      throw new CreditError("not_found", "Utilisateur introuvable", 404);
    }
    if (!user.onboardingTermine || user.statutCompte === "suspendu") {
      throw new CreditError(
        "onboarding_required",
        "Onboarding terminé et compte actif requis",
        403
      );
    }

    const partageOk = await this.consents.hasConsent(
      travailleurId,
      "partage_imf"
    );
    if (!partageOk) {
      throw new CreditError(
        "consent_required",
        "Consentement de partage avec les IMF requis (partage_imf)",
        403
      );
    }

    const { result, offre, features } = await this.scoring.recalculate(travailleurId, {
      persistOffer: true,
    });
    if (!offre) {
      throw new CreditError("offer", "Offre indisponible", 500);
    }
    if (!result.eligible || !offre.eligible) {
      throw new CreditError(
        "not_eligible",
        "NeoScore insuffisant (seuil 50)",
        403,
        { score: result.score }
      );
    }

    let offer = offre;
    if (input.offreId) {
      const chosen = await this.prisma.offreCredit.findFirst({
        where: { id: input.offreId, travailleurId },
      });
      if (!chosen) {
        throw new CreditError("offer_not_found", "Offre introuvable", 404);
      }
      if (
        chosen.valideJusqua &&
        chosen.valideJusqua < new Date()
      ) {
        throw new CreditError("offer_expired", "Offre expirée", 400);
      }
      offer = chosen;
    }

    if (
      input.amountFcfa < offer.montantMinFcfa ||
      input.amountFcfa > offer.montantMaxFcfa
    ) {
      throw new CreditError(
        "amount",
        `Montant hors offre (${offer.montantMinFcfa}–${offer.montantMaxFcfa} FCFA)`,
        400
      );
    }

    const imf = await this.prisma.imf.findFirst({
      where: { statutPartenariat: "actif" },
      orderBy: { createdAt: "asc" },
    });

    const snapshot = await this.createSnapshot(result);

    return this.prisma.demandeCredit.create({
      data: {
        reference: creditRef(),
        travailleurId,
        offreId: offer.id,
        snapshotScoreId: snapshot.id,
        imfId: imf?.id ?? null,
        montantDemandeFcfa: input.amountFcfa,
        usage: input.purpose,
        modaliteRemboursement: input.repayment,
        statut: "soumise",
        dateSoumission: new Date(),
        featuresSnapshot: features as object,
      },
      include: { snapshotScore: true },
    });
  }

  /**
   * Décision IMF : en_examen | approuvee | refusee | decaissee.
   * Crée une commission à l'approbation / décaissement.
   * Au décaissement : outcome=en_cours + dates échéance.
   */
  async decide(
    demandeId: string,
    input: {
      statut: "en_examen" | "approuvee" | "refusee" | "decaissee";
      motifDecision?: string;
      imfId?: string;
      /** Durée en mois pour dateEcheance (défaut 3). */
      dureeMois?: number;
    }
  ) {
    const demande = await this.prisma.demandeCredit.findUnique({
      where: { id: demandeId },
    });
    if (!demande) {
      throw new CreditError("not_found", "Demande introuvable", 404);
    }

    const now = new Date();
    const extra: {
      dateDecaissement?: Date;
      dateEcheance?: Date;
      outcome?: string;
    } = {};
    if (input.statut === "decaissee") {
      const mois = Math.max(1, Math.min(24, input.dureeMois ?? 3));
      const echeance = new Date(now);
      echeance.setMonth(echeance.getMonth() + mois);
      extra.dateDecaissement = now;
      extra.dateEcheance = echeance;
      extra.outcome = "en_cours";
    }

    const updated = await this.prisma.demandeCredit.update({
      where: { id: demandeId },
      data: {
        statut: input.statut,
        motifDecision: input.motifDecision?.slice(0, 500) ?? null,
        ...(input.imfId ? { imfId: input.imfId } : {}),
        ...extra,
      },
      include: { snapshotScore: true },
    });

    if (
      (input.statut === "approuvee" || input.statut === "decaissee") &&
      updated.imfId
    ) {
      await this.ensureCommission(updated.id, updated.imfId, updated.montantDemandeFcfa);
    }

    await this.notifyDecision(updated.travailleurId, updated.reference, input.statut);

    return updated;
  }

  /** Notifie le travailleur d'une décision de crédit (approuvée / refusée / etc.). */
  private async notifyDecision(
    travailleurId: string,
    reference: string,
    statut: "en_examen" | "approuvee" | "refusee" | "decaissee"
  ): Promise<void> {
    const messages: Record<typeof statut, { titre: string; corps: string }> = {
      en_examen: {
        titre: "Demande en examen",
        corps: `Votre demande ${reference} est en cours d'examen par l'IMF.`,
      },
      approuvee: {
        titre: "Crédit approuvé",
        corps: `Bonne nouvelle — votre demande ${reference} a été approuvée.`,
      },
      refusee: {
        titre: "Demande refusée",
        corps: `Votre demande ${reference} n'a pas été retenue.`,
      },
      decaissee: {
        titre: "Crédit décaissé",
        corps: `Les fonds pour la demande ${reference} ont été décaissés.`,
      },
    };
    const { titre, corps } = messages[statut];
    await createNotification(this.prisma, {
      travailleurId,
      type: "credit_decision",
      titre,
      corps,
      meta: { reference, statut },
    });
  }

  /**
   * Clôture solvabilité : rembourse_ok | defaut.
   * Alimente le dataset d'entraînement ML.
   */
  async recordOutcome(
    demandeId: string,
    input: {
      outcome: "rembourse_ok" | "defaut";
      motif?: string;
    }
  ) {
    const demande = await this.prisma.demandeCredit.findUnique({
      where: { id: demandeId },
    });
    if (!demande) {
      throw new CreditError("not_found", "Demande introuvable", 404);
    }
    if (demande.statut !== "decaissee" && demande.outcome !== "en_cours") {
      throw new CreditError(
        "invalid_state",
        "Outcome réservé aux crédits décaissés / en cours",
        400
      );
    }

    return this.prisma.demandeCredit.update({
      where: { id: demandeId },
      data: {
        outcome: input.outcome,
        statut: "cloturee",
        dateCloture: new Date(),
        motifDecision: input.motif?.slice(0, 500) ?? demande.motifDecision,
      },
      include: { snapshotScore: true },
    });
  }

  /** Dataset labellisé pour ré-entraînement ML. */
  async exportMlTrainingSamples(limit = 2000) {
    const rows = await this.prisma.demandeCredit.findMany({
      where: {
        outcome: { in: ["rembourse_ok", "defaut"] },
      },
      orderBy: { dateCloture: "desc" },
      take: Math.min(limit, 5000),
      select: {
        id: true,
        reference: true,
        outcome: true,
        featuresSnapshot: true,
        montantDemandeFcfa: true,
        dateCloture: true,
      },
    });

    return rows
      .filter((r) => r.featuresSnapshot != null)
      .map((r) => ({
        demandeId: r.id,
        reference: r.reference,
        outcome: r.outcome,
        default: r.outcome === "defaut" ? 1 : 0,
        features: r.featuresSnapshot,
        montantDemandeFcfa: r.montantDemandeFcfa,
        dateCloture: r.dateCloture?.toISOString() ?? null,
      }));
  }

  /** Crée la commission NeoForma si absente (idempotent). */
  async ensureCommission(
    demandeCreditId: string,
    imfId: string,
    montantCreditFcfa: number
  ) {
    const existing = await this.prisma.commission.findUnique({
      where: { demandeCreditId },
    });
    if (existing) return existing;

    const imf = await this.prisma.imf.findUnique({ where: { id: imfId } });
    const taux = imf?.tauxCommission ?? 0.02;
    const montantCommissionFcfa = Math.round(montantCreditFcfa * taux);

    return this.prisma.commission.create({
      data: {
        demandeCreditId,
        imfId,
        montantCreditFcfa,
        tauxCommission: taux,
        montantCommissionFcfa,
        statut: "due",
      },
    });
  }

  async listCommissions(opts: { imfId?: string; statut?: string } = {}) {
    return this.prisma.commission.findMany({
      where: {
        ...(opts.imfId ? { imfId: opts.imfId } : {}),
        ...(opts.statut ? { statut: opts.statut } : {}),
      },
      orderBy: { createdAt: "desc" },
      take: 200,
      include: {
        demande: { select: { id: true, reference: true, statut: true } },
        imf: { select: { id: true, raisonSociale: true } },
      },
    });
  }

  async updateCommissionStatut(
    commissionId: string,
    statut: "due" | "facturee" | "payee"
  ) {
    const row = await this.prisma.commission.findUnique({
      where: { id: commissionId },
    });
    if (!row) {
      throw new CreditError("not_found", "Commission introuvable", 404);
    }
    return this.prisma.commission.update({
      where: { id: commissionId },
      data: { statut },
    });
  }

  private async createSnapshot(result: {
    score: number;
    segment: string;
    threshold: number;
    criteria: {
      regularite: number;
      volume: number;
      dettes: number;
      croissance: number;
    };
  }): Promise<SnapshotScore> {
    return this.prisma.snapshotScore.create({
      data: {
        valeur: result.score,
        segment: result.segment,
        seuilEligibilite: result.threshold,
        critereRegularite: Math.round(result.criteria.regularite),
        critereVolume: Math.round(result.criteria.volume),
        critereGestionCreances: Math.round(result.criteria.dettes),
        critereCroissance: Math.round(result.criteria.croissance),
        dateFigee: new Date(),
      },
    });
  }

  /** Seed minimal IMF pilote si aucune. */
  async ensurePilotImf(): Promise<void> {
    const count = await this.prisma.imf.count();
    if (count > 0) return;
    await this.prisma.imf.create({
      data: {
        raisonSociale: "IMF Pilote NeoForma",
        pays: "Burkina Faso",
        statutPartenariat: "actif",
        niveauAcces: "consultation",
        contactNom: "Partenariats",
        contactEmail: "partenariats@neoforma.bf",
        tauxCommission: 0.02,
        apiKeyHash: process.env.PARTNER_API_KEY
          ? hashPartnerApiKey(process.env.PARTNER_API_KEY)
          : null,
      },
    });
  }
}
