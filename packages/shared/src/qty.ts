import { z } from "zod";

/** Quantité stock / vente : jusqu’à 3 décimales (1,5 kg). */
export function roundQty(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 1000) / 1000;
}

function coerceQtyValue(v: unknown): number {
  if (typeof v === "number") return roundQty(v);
  if (typeof v === "string") {
    return roundQty(Number(v.replace(/[\s\u00a0]/g, "").replace(",", ".")));
  }
  return Number.NaN;
}

/** 0 autorisé (stock à zéro). Pas d’entier obligatoire. */
export const QtySchema = z
  .union([z.number(), z.string()])
  .transform(coerceQtyValue)
  .refine((n) => Number.isFinite(n) && n >= 0 && n <= 1_000_000, {
    message: "Quantité invalide",
  });

/** > 0, décimales OK (1,5 kg). */
export const PositiveQtySchema = z
  .union([z.number(), z.string()])
  .transform(coerceQtyValue)
  .refine((n) => Number.isFinite(n) && n > 0 && n <= 1_000_000, {
    message: "Quantité invalide",
  });

export const STOCK_UNIT_VALUES = ["u", "kg", "g", "l"] as const;
export type StockUnit = (typeof STOCK_UNIT_VALUES)[number];

export function normalizeStockUnit(raw?: string | null): StockUnit {
  const x = (raw ?? "u").trim().toLowerCase();
  if (x === "kg" || x === "kilo" || x === "kilos") return "kg";
  if (x === "g" || x === "gr" || x === "gramme" || x === "grammes") return "g";
  if (x === "l" || x === "litre" || x === "litres") return "l";
  return "u";
}
