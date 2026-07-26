import type {
  PrismaClient,
  Travailleur,
  ProfilActivite,
  Preferences,
  Consentement,
} from "@prisma/client";
import type { OnboardingUpdate, UpdateActivite, UpdatePreferences } from "@neoforma/shared";
import { CURRENT_PRIVACY_POLICY_VERSION } from "@neoforma/shared";
import { ConsentService } from "../consent/service.js";

export class ProfileError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "ProfileError";
  }
}

export function isProfileError(err: unknown): err is ProfileError {
  return err instanceof ProfileError;
}

export type TravailleurMe = Travailleur & {
  profilActivite: ProfilActivite | null;
  preferences: Preferences | null;
  consentements: Consentement[];
};

const meInclude = {
  profilActivite: true,
  preferences: true,
  consentements: true,
} as const;

/** RM-P01 : métier + ancienneté + CA estimé. */
export function isProfilComplet(profil: ProfilActivite | null | undefined): boolean {
  return Boolean(profil?.metier && profil?.ancienneteActivite && profil?.caJournalierEstime);
}

export class ProfileService {
  private readonly consents: ConsentService;

  constructor(private readonly prisma: PrismaClient) {
    this.consents = new ConsentService(prisma);
  }

  async getMe(travailleurId: string): Promise<TravailleurMe> {
    await this.consents.ensureDefaults(travailleurId);
    const me = await this.prisma.travailleur.findUnique({
      where: { id: travailleurId },
      include: meInclude,
    });
    if (!me) {
      throw new ProfileError("not_found", "Utilisateur introuvable", 404);
    }
    return me;
  }

  async ensurePreferences(
    travailleurId: string,
    langue = "fr"
  ): Promise<Preferences> {
    return this.prisma.preferences.upsert({
      where: { travailleurId },
      create: {
        travailleurId,
        langue,
        modeIconographique: false,
        assistanceVocaleActive: false,
        theme: "dark",
        fuseau: "Africa/Ouagadougou",
      },
      update: {},
    });
  }

  async updateActivite(
    travailleurId: string,
    input: UpdateActivite
  ): Promise<TravailleurMe> {
    await this.assertExists(travailleurId);

    const identityData: { nomAffiche?: string; genre?: string | null } = {};
    if (input.displayName !== undefined) identityData.nomAffiche = input.displayName;
    if (input.genre !== undefined) identityData.genre = input.genre;

    if (Object.keys(identityData).length > 0) {
      await this.prisma.travailleur.update({
        where: { id: travailleurId },
        data: identityData,
      });
    }

    await this.upsertProfilActivite(travailleurId, input);
    return this.getMe(travailleurId);
  }

  async updatePreferences(
    travailleurId: string,
    input: UpdatePreferences
  ): Promise<TravailleurMe> {
    await this.assertExists(travailleurId);
    await this.ensurePreferences(travailleurId);

    await this.prisma.preferences.update({
      where: { travailleurId },
      data: {
        ...(input.language !== undefined ? { langue: input.language } : {}),
        ...(input.modeIconographique !== undefined
          ? { modeIconographique: input.modeIconographique }
          : {}),
        ...(input.assistanceVocaleActive !== undefined
          ? { assistanceVocaleActive: input.assistanceVocaleActive }
          : {}),
        ...(input.theme !== undefined ? { theme: input.theme } : {}),
        ...(input.fuseau !== undefined ? { fuseau: input.fuseau } : {}),
      },
    });

    return this.getMe(travailleurId);
  }

  /**
   * Mise à jour agrégée (parcours onboarding UI).
   * Consentements délégués au module consent.
   */
  async applyOnboardingUpdate(
    travailleurId: string,
    input: OnboardingUpdate
  ): Promise<TravailleurMe> {
    await this.assertExists(travailleurId);

    const identityData: {
      nomAffiche?: string;
      genre?: string | null;
    } = {};

    if (input.displayName !== undefined) identityData.nomAffiche = input.displayName;
    if (input.genre !== undefined) identityData.genre = input.genre;

    if (
      input.consentAnonymized !== undefined ||
      input.consentCreditPartners !== undefined ||
      input.consentMarketing !== undefined
    ) {
      await this.consents.applyLegacyBatch(travailleurId, {
        consentAnonymized: input.consentAnonymized,
        consentCreditPartners: input.consentCreditPartners,
        consentMarketing: input.consentMarketing,
        versionPolitique: CURRENT_PRIVACY_POLICY_VERSION,
      });
    }

    if (input.onboardingCompleted === true) {
      if (Object.keys(identityData).length > 0) {
        await this.prisma.travailleur.update({
          where: { id: travailleurId },
          data: identityData,
        });
      }
      await this.upsertProfilActivite(travailleurId, input);
      if (input.language !== undefined) {
        await this.ensurePreferences(travailleurId, input.language);
        await this.prisma.preferences.update({
          where: { travailleurId },
          data: { langue: input.language },
        });
      }
      return this.completeOnboarding(travailleurId);
    }

    if (Object.keys(identityData).length > 0) {
      await this.prisma.travailleur.update({
        where: { id: travailleurId },
        data: identityData,
      });
    }

    await this.upsertProfilActivite(travailleurId, input);

    if (input.language !== undefined) {
      await this.ensurePreferences(travailleurId, input.language);
      await this.prisma.preferences.update({
        where: { travailleurId },
        data: { langue: input.language },
      });
    }

    return this.getMe(travailleurId);
  }

  /** RM-P01 + nom affiché → onboardingTermine + statut actif. */
  async completeOnboarding(travailleurId: string): Promise<TravailleurMe> {
    const me = await this.getMe(travailleurId);

    if (!me.nomAffiche?.trim()) {
      throw new ProfileError(
        "onboarding_incomplete",
        "Nom affiché requis pour terminer l'onboarding",
        422
      );
    }

    if (!isProfilComplet(me.profilActivite)) {
      throw new ProfileError(
        "onboarding_incomplete",
        "Profil incomplet : métier, ancienneté et CA journalier requis (RM-P01)",
        422
      );
    }

    await this.prisma.travailleur.update({
      where: { id: travailleurId },
      data: {
        onboardingTermine: true,
        statutCompte: me.statutCompte === "suspendu" ? "suspendu" : "actif",
      },
    });

    return this.getMe(travailleurId);
  }

  private async assertExists(travailleurId: string): Promise<void> {
    const exists = await this.prisma.travailleur.findUnique({
      where: { id: travailleurId },
      select: { id: true },
    });
    if (!exists) {
      throw new ProfileError("not_found", "Utilisateur introuvable", 404);
    }
  }

  private async upsertProfilActivite(
    travailleurId: string,
    input: {
      metier?: string;
      anciennete?: string;
      caJour?: string;
      tontine?: boolean;
      tontineCotis?: number;
      mobileMoney?: string;
      compte?: string;
      city?: string;
      zone?: string;
    }
  ): Promise<void> {
    const data = {
      ...(input.metier !== undefined ? { metier: input.metier } : {}),
      ...(input.anciennete !== undefined
        ? { ancienneteActivite: input.anciennete }
        : {}),
      ...(input.caJour !== undefined ? { caJournalierEstime: input.caJour } : {}),
      ...(input.tontine !== undefined ? { participationTontine: input.tontine } : {}),
      ...(input.tontineCotis !== undefined
        ? { cotisationTontine: input.tontineCotis }
        : {}),
      ...(input.mobileMoney !== undefined
        ? { usageMobileMoney: input.mobileMoney }
        : {}),
      ...(input.compte !== undefined ? { statutCompteBancaire: input.compte } : {}),
      ...(input.city !== undefined ? { ville: input.city } : {}),
      ...(input.zone !== undefined ? { zone: input.zone } : {}),
    };

    if (Object.keys(data).length === 0) return;

    await this.prisma.profilActivite.upsert({
      where: { travailleurId },
      create: { travailleurId, ...data },
      update: data,
    });
  }
}
