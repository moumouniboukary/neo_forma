import type { Travailleur } from "@prisma/client";

/** DTO identité minimal — pas de dépendance aux mappers profil. */
export function toAuthUser(user: Travailleur) {
  return {
    id: user.id,
    phone: user.telephone,
    displayName: user.nomAffiche || user.telephone,
    language: "fr" as const,
    consentAnonymized: true,
    consentCreditPartners: false,
    consentMarketing: false,
    onboardingCompleted: user.onboardingTermine,
    statutCompte: user.statutCompte as "brouillon" | "actif" | "suspendu",
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  };
}
