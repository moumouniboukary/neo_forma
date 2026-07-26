import type { PrismaClient } from "@prisma/client";
import { toClient, toOperation, toUserProfile } from "../../lib/mappers.js";
import { CURRENT_PRIVACY_POLICY_VERSION } from "@neoforma/shared";
import { toConsentDto } from "../consent/service.js";

export class PrivacyError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "PrivacyError";
  }
}

export function isPrivacyError(err: unknown): err is PrivacyError {
  return err instanceof PrivacyError;
}

/**
 * RGPD — export (droit d'accès) + suppression (droit à l'oubli).
 */
export class PrivacyService {
  constructor(private readonly prisma: PrismaClient) {}

  /** Pack JSON portable de toutes les données personnelles. */
  async exportData(travailleurId: string) {
    const user = await this.prisma.travailleur.findUnique({
      where: { id: travailleurId },
      include: {
        profilActivite: true,
        preferences: true,
        consentements: true,
        clientsInformels: true,
        operations: { include: { client: true }, orderBy: { dateOperation: "desc" } },
        neoscore: true,
        offresCredit: { orderBy: { dateGeneration: "desc" }, take: 20 },
        demandesCredit: {
          include: { snapshotScore: true },
          orderBy: { createdAt: "desc" },
          take: 50,
        },
      },
    });
    if (!user) {
      throw new PrivacyError("not_found", "Utilisateur introuvable", 404);
    }

    const { pinHash: _pin, ...safeUser } = user;

    return {
      exportedAt: new Date().toISOString(),
      policyVersion: CURRENT_PRIVACY_POLICY_VERSION,
      profile: toUserProfile(user),
      identity: {
        id: safeUser.id,
        telephone: safeUser.telephone,
        nomAffiche: safeUser.nomAffiche,
        genre: safeUser.genre,
        statutCompte: safeUser.statutCompte,
        onboardingTermine: safeUser.onboardingTermine,
        createdAt: safeUser.createdAt.toISOString(),
        updatedAt: safeUser.updatedAt.toISOString(),
      },
      consents: user.consentements.map(toConsentDto),
      clients: user.clientsInformels.map(toClient),
      operations: user.operations.map(toOperation),
      neoscore: user.neoscore
        ? {
            valeur: user.neoscore.valeur,
            segment: user.neoscore.segment,
            dateCalcul: user.neoscore.dateCalcul.toISOString(),
          }
        : null,
      creditOffers: user.offresCredit.map((o) => ({
        id: o.id,
        montantMinFcfa: o.montantMinFcfa,
        montantMaxFcfa: o.montantMaxFcfa,
        eligible: o.eligible,
        dateGeneration: o.dateGeneration.toISOString(),
      })),
      creditApplications: user.demandesCredit.map((d) => ({
        id: d.id,
        reference: d.reference,
        montantDemandeFcfa: d.montantDemandeFcfa,
        usage: d.usage,
        statut: d.statut,
        createdAt: d.createdAt.toISOString(),
      })),
    };
  }

  /**
   * Suppression définitive du compte et des données liées (RGPD art. 17).
   * Ordre manuel pour les relations Restrict (demandes crédit / accès IMF).
   */
  async deleteAccount(travailleurId: string): Promise<void> {
    const exists = await this.prisma.travailleur.findUnique({
      where: { id: travailleurId },
      select: { id: true },
    });
    if (!exists) {
      throw new PrivacyError("not_found", "Utilisateur introuvable", 404);
    }

    await this.prisma.$transaction(async (tx) => {
      const demandes = await tx.demandeCredit.findMany({
        where: { travailleurId },
        select: { id: true },
      });
      const demandeIds = demandes.map((d) => d.id);

      if (demandeIds.length > 0) {
        await tx.commission.deleteMany({
          where: { demandeCreditId: { in: demandeIds } },
        });
        await tx.accesProfilImf.deleteMany({
          where: { demandeCreditId: { in: demandeIds } },
        });
      }
      await tx.accesProfilImf.deleteMany({ where: { travailleurId } });
      // Restrict : demandes avant offres, opérations avant clients.
      await tx.demandeCredit.deleteMany({ where: { travailleurId } });
      await tx.offreCredit.deleteMany({ where: { travailleurId } });
      await tx.operation.deleteMany({ where: { travailleurId } });
      await tx.operationHorsLigne.deleteMany({ where: { travailleurId } });
      await tx.clientInformel.deleteMany({ where: { travailleurId } });

      // Cascade Prisma pour le reste (sessions, OTP, score, préférences…).
      await tx.travailleur.delete({ where: { id: travailleurId } });
    });
  }
}
