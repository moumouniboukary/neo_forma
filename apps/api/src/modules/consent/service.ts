import type { Consentement, PrismaClient } from "@prisma/client";
import type { ConsentType, UpdateConsent, UpdateConsentsBatch } from "@neoforma/shared";
import { CURRENT_PRIVACY_POLICY_VERSION } from "@neoforma/shared";

export class ConsentError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "ConsentError";
  }
}

export function isConsentError(err: unknown): err is ConsentError {
  return err instanceof ConsentError;
}

const ALL_TYPES: ConsentType[] = [
  "anonymisation_recherche",
  "partage_imf",
  "marketing_partenaires",
];

/** Défauts prudents à l'inscription (RM). */
const DEFAULTS: Record<ConsentType, boolean> = {
  anonymisation_recherche: true,
  partage_imf: false,
  marketing_partenaires: false,
};

const LEGACY_KEY_TO_TYPE: Record<
  keyof Omit<UpdateConsentsBatch, "versionPolitique">,
  ConsentType
> = {
  consentAnonymized: "anonymisation_recherche",
  consentCreditPartners: "partage_imf",
  consentMarketing: "marketing_partenaires",
};

export class ConsentService {
  constructor(private readonly prisma: PrismaClient) {}

  /** Crée les 3 consentements par défaut si absents. */
  async ensureDefaults(
    travailleurId: string,
    versionPolitique = CURRENT_PRIVACY_POLICY_VERSION
  ): Promise<Consentement[]> {
    const existing = await this.prisma.consentement.findMany({
      where: { travailleurId },
    });
    const have = new Set(existing.map((c) => c.type));

    for (const type of ALL_TYPES) {
      if (have.has(type)) continue;
      await this.prisma.consentement.create({
        data: {
          travailleurId,
          type,
          accorde: DEFAULTS[type],
          versionPolitique,
          retractable: true,
          dateDecision: new Date(),
        },
      });
    }

    return this.prisma.consentement.findMany({
      where: { travailleurId },
      orderBy: { type: "asc" },
    });
  }

  async list(travailleurId: string): Promise<Consentement[]> {
    await this.ensureDefaults(travailleurId);
    return this.prisma.consentement.findMany({
      where: { travailleurId },
      orderBy: { type: "asc" },
    });
  }

  async getByType(
    travailleurId: string,
    type: ConsentType
  ): Promise<Consentement> {
    await this.ensureDefaults(travailleurId);
    const row = await this.prisma.consentement.findUnique({
      where: { travailleurId_type: { travailleurId, type } },
    });
    if (!row) {
      throw new ConsentError("not_found", `Consentement ${type} introuvable`, 404);
    }
    return row;
  }

  /** RM-C01 — true seulement si partage_imf accordé. */
  async hasConsent(travailleurId: string, type: ConsentType): Promise<boolean> {
    const row = await this.getByType(travailleurId, type);
    return row.accorde === true;
  }

  async setConsent(
    travailleurId: string,
    type: ConsentType,
    input: UpdateConsent
  ): Promise<Consentement> {
    await this.ensureDefaults(travailleurId);
    const current = await this.getByType(travailleurId, type);

    if (
      current.accorde === true &&
      input.accorde === false &&
      !current.retractable
    ) {
      throw new ConsentError(
        "not_retractable",
        "Ce consentement ne peut pas être retiré",
        403
      );
    }

    return this.prisma.consentement.update({
      where: { travailleurId_type: { travailleurId, type } },
      data: {
        accorde: input.accorde,
        dateDecision: new Date(),
        versionPolitique:
          input.versionPolitique ??
          current.versionPolitique ??
          CURRENT_PRIVACY_POLICY_VERSION,
      },
    });
  }

  /** RM-C03 — révocation = accorde false (bloque nouveaux accès IMF). */
  async revoke(
    travailleurId: string,
    type: ConsentType
  ): Promise<Consentement> {
    return this.setConsent(travailleurId, type, { accorde: false });
  }

  /** Mapping clés API legacy → table consentements. */
  async applyLegacyBatch(
    travailleurId: string,
    batch: UpdateConsentsBatch
  ): Promise<Consentement[]> {
    const version =
      batch.versionPolitique ?? CURRENT_PRIVACY_POLICY_VERSION;

    for (const [key, type] of Object.entries(LEGACY_KEY_TO_TYPE) as Array<
      [keyof typeof LEGACY_KEY_TO_TYPE, ConsentType]
    >) {
      const value = batch[key];
      if (value === undefined) continue;
      await this.setConsent(travailleurId, type, {
        accorde: value,
        versionPolitique: version,
      });
    }

    return this.list(travailleurId);
  }

  /** Flags plats pour UserProfile (compat API). */
  async toLegacyFlags(travailleurId: string): Promise<{
    consentAnonymized: boolean;
    consentCreditPartners: boolean;
    consentMarketing: boolean;
  }> {
    const items = await this.list(travailleurId);
    const byType = Object.fromEntries(items.map((c) => [c.type, c.accorde]));
    return {
      consentAnonymized: byType.anonymisation_recherche ?? true,
      consentCreditPartners: byType.partage_imf ?? false,
      consentMarketing: byType.marketing_partenaires ?? false,
    };
  }
}

export function toConsentDto(row: Consentement) {
  return {
    id: row.id,
    type: row.type as ConsentType,
    accorde: row.accorde,
    dateDecision: row.dateDecision.toISOString(),
    versionPolitique: row.versionPolitique,
    retractable: row.retractable,
    updatedAt: row.updatedAt.toISOString(),
  };
}
