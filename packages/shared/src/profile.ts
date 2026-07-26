import { z } from "zod";
import { LanguageSchema, MetierSchema } from "./enums.js";

export const AncienneteSchema = z.enum(["m1", "1_2", "3_5", "6_10", "p10"]);
export type Anciennete = z.infer<typeof AncienneteSchema>;

export const CaJournalierSchema = z.enum([
  "m5k",
  "5_15k",
  "15_30k",
  "30_60k",
  "60_100k",
  "p100k",
]);
export type CaJournalier = z.infer<typeof CaJournalierSchema>;

export const MobileMoneySchema = z.enum([
  "jamais",
  "occasionnel",
  "regulier",
  "quotidien",
]);
export type MobileMoney = z.infer<typeof MobileMoneySchema>;

export const CompteBancaireSchema = z.enum(["non", "oui_actif", "oui_dormant"]);
export type CompteBancaire = z.infer<typeof CompteBancaireSchema>;

export const ProfilActiviteSchema = z.object({
  metier: MetierSchema.optional(),
  anciennete: AncienneteSchema.optional(),
  caJour: CaJournalierSchema.optional(),
  tontine: z.boolean().optional(),
  tontineCotis: z.number().int().nonnegative().optional(),
  mobileMoney: MobileMoneySchema.optional(),
  compte: CompteBancaireSchema.optional(),
  city: z.string().max(80).optional(),
  zone: z.string().max(80).optional(),
});
export type ProfilActiviteDto = z.infer<typeof ProfilActiviteSchema>;

export const ThemeSchema = z.enum(["light", "dark"]);
export type ThemePreference = z.infer<typeof ThemeSchema>;

export const PreferencesSchema = z.object({
  language: LanguageSchema,
  modeIconographique: z.boolean(),
  assistanceVocaleActive: z.boolean(),
  theme: ThemeSchema.default("dark"),
  fuseau: z.string().min(1).max(64),
});
export type PreferencesDto = z.infer<typeof PreferencesSchema>;

/** Mise à jour partielle du profil d'activité + identité affichée. */
export const UpdateActiviteSchema = z
  .object({
    displayName: z.string().min(1).max(120).optional(),
    genre: z.string().max(20).optional(),
  })
  .merge(ProfilActiviteSchema);
export type UpdateActivite = z.infer<typeof UpdateActiviteSchema>;

export const UpdatePreferencesSchema = z.object({
  language: LanguageSchema.optional(),
  modeIconographique: z.boolean().optional(),
  assistanceVocaleActive: z.boolean().optional(),
  theme: ThemeSchema.optional(),
  fuseau: z.string().min(1).max(64).optional(),
});
export type UpdatePreferences = z.infer<typeof UpdatePreferencesSchema>;

/**
 * Payload d'onboarding (étapes UI) — agrège activité + préférences.
 * Les clés consent* sont déléguées au module consent.
 */
export const OnboardingUpdateSchema = z.object({
  displayName: z.string().min(1).max(120).optional(),
  genre: z.string().max(20).optional(),
  language: LanguageSchema.optional(),
  metier: MetierSchema.optional(),
  anciennete: AncienneteSchema.optional(),
  caJour: CaJournalierSchema.optional(),
  tontine: z.boolean().optional(),
  tontineCotis: z.number().int().nonnegative().optional(),
  mobileMoney: MobileMoneySchema.optional(),
  compte: CompteBancaireSchema.optional(),
  city: z.string().max(80).optional(),
  zone: z.string().max(80).optional(),
  consentAnonymized: z.boolean().optional(),
  consentCreditPartners: z.boolean().optional(),
  consentMarketing: z.boolean().optional(),
  onboardingCompleted: z.boolean().optional(),
});
export type OnboardingUpdate = z.infer<typeof OnboardingUpdateSchema>;
