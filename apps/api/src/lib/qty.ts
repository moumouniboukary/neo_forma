import { roundQty } from "@neoforma/shared";

/** Prisma.Decimal | number | string → nombre à 3 décimales. */
export function toQty(v: unknown): number {
  if (v == null) return 0;
  if (typeof v === "object" && v !== null && "toNumber" in v) {
    return roundQty(Number((v as { toNumber: () => number }).toNumber()));
  }
  return roundQty(Number(v));
}
