import { z } from "zod";

export const LanguageSchema = z.enum(["fr", "mr"]);
export type Language = z.infer<typeof LanguageSchema>;

/** Coerce legacy codes (dl, ff, …) vers une langue supportée. */
export function normalizeLanguage(code: string | null | undefined): Language {
  return code === "mr" ? "mr" : "fr";
}


export const MetierSchema = z.enum([
  "commerce",
  "mecanique",
  "artisanat",
  "menuiserie",
  "restauration",
  "transport",
  "agriculture",
  "services",
]);
export type Metier = z.infer<typeof MetierSchema>;

export const OperationTypeSchema = z.enum([
  "vente",
  "stock",
  "depense",
  "creance",
  /** @deprecated alias UI — normalisé en creance */
  "dette",
]);
export type OperationType = z.infer<typeof OperationTypeSchema>;

/** Type canonique stocké en base. */
export const OperationTypeCanonicalSchema = z.enum([
  "vente",
  "stock",
  "depense",
  "creance",
]);
export type OperationTypeCanonical = z.infer<typeof OperationTypeCanonicalSchema>;

export const NatureStockSchema = z.enum(["entree", "sortie"]);
export type NatureStock = z.infer<typeof NatureStockSchema>;

export const StatutCreanceSchema = z.enum([
  "ouverte",
  "en_retard",
  "reglee",
  "annulee",
]);
export type StatutCreance = z.infer<typeof StatutCreanceSchema>;

export const CreditStatusSchema = z.enum([
  "brouillon",
  "soumise",
  "en_examen",
  "approuvee",
  "refusee",
  "decaissee",
]);
export type CreditStatus = z.infer<typeof CreditStatusSchema>;

export const NeoSegmentSchema = z.enum(["A", "B", "C", "D"]);
export type NeoSegment = z.infer<typeof NeoSegmentSchema>;

export const ConsentTypeSchema = z.enum([
  "anonymisation_recherche",
  "partage_imf",
  "marketing_partenaires",
]);
export type ConsentType = z.infer<typeof ConsentTypeSchema>;

export const SEGMENT_LABELS: Record<NeoSegment, string> = {
  A: "Régulier stable",
  B: "Potentiel volatil",
  C: "Primo-entrant",
  D: "Exclusion totale",
};
