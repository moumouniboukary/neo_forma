import { z } from "zod";
import { LanguageSchema, MetierSchema } from "./enums.js";
import {
  AncienneteSchema,
  CaJournalierSchema,
  CompteBancaireSchema,
  MobileMoneySchema,
  SaisonnaliteSchema,
} from "./profile.js";

export const PhoneSchema = z
  .string()
  .regex(/^\+226\s?\d{2}\s?\d{2}\s?\d{2}\s?\d{2}$/, "Numéro Burkina (+226) invalide");

export const PinSchema = z.string().regex(/^\d{4}$/, "PIN à 4 chiffres");

export const UserProfileSchema = z.object({
  id: z.string().uuid(),
  phone: PhoneSchema,
  displayName: z.string().min(1).max(120),
  language: LanguageSchema.default("fr"),
  theme: z.enum(["light", "dark", "system"]).default("system"),
  metier: MetierSchema.optional(),
  anciennete: AncienneteSchema.optional(),
  caJour: CaJournalierSchema.optional(),
  tontine: z.boolean().optional(),
  tontineCotis: z.number().int().nonnegative().optional(),
  mobileMoney: MobileMoneySchema.optional(),
  compte: CompteBancaireSchema.optional(),
  city: z.string().optional(),
  zone: z.string().optional(),
  chargesFixesMensuelles: z.number().int().nonnegative().optional(),
  saisonnalite: SaisonnaliteSchema.optional(),
  garantieSolidaire: z.boolean().optional(),
  consentAnonymized: z.boolean().default(true),
  consentCreditPartners: z.boolean().default(false),
  consentMarketing: z.boolean().default(false),
  onboardingCompleted: z.boolean().default(false),
  statutCompte: z.enum(["brouillon", "actif", "suspendu"]).optional(),
  kycStatut: z
    .enum(["non_verifie", "en_cours", "verifie", "refuse"])
    .optional(),
  pieceIdentiteType: z
    .enum(["cni", "passport", "consulaire", "autre"])
    .optional(),
  pieceIdentiteNumero: z.string().optional(),
  dateNaissance: z.string().datetime().optional(),
  adresse: z.string().optional(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});
export type UserProfile = z.infer<typeof UserProfileSchema>;

export {
  OnboardingUpdateSchema,
  UpdateActiviteSchema,
  UpdatePreferencesSchema,
} from "./profile.js";
export type {
  OnboardingUpdate,
  UpdateActivite,
  UpdatePreferences,
} from "./profile.js";
