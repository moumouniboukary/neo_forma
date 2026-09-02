import { z } from "zod";

/** Quantité stock / vente : jusqu’à 3 décimales (1,5 kg). */
export function roundQty(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 1000) / 1000;
}

/** "1,5" (FR) ou "1.5" → nombre. `null` / `""` laissés tels quels. */
function parseQtyInput(v: unknown): unknown {
  if (typeof v === "string") {
    const s = v.replace(/[\s\u00a0]/g, "").replace(",", ".");
    return s === "" ? v : s;
  }
  return v;
}

export const QtySchema = z.preprocess(
  parseQtyInput,
  z.coerce.number().finite().min(0).max(1_000_000).transform(roundQty)
);

export const PositiveQtySchema = z.preprocess(
  parseQtyInput,
  z.coerce.number().finite().gt(0).max(1_000_000).transform(roundQty)
);

export const STOCK_UNIT_VALUES = ["u", "kg", "g", "l"] as const;
export type StockUnit = (typeof STOCK_UNIT_VALUES)[number];

export function normalizeStockUnit(raw?: string | null): StockUnit {
  const x = (raw ?? "u").trim().toLowerCase();
  if (x === "kg" || x === "kilo" || x === "kilos") return "kg";
  if (x === "g" || x === "gr" || x === "gramme" || x === "grammes") return "g";
  if (x === "l" || x === "litre" || x === "litres") return "l";
  return "u";
}
