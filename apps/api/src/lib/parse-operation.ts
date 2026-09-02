import {
  CreateOperationSchema,
  roundQty,
  type CreateOperation,
} from "@neoforma/shared";
import type { SafeParseReturnType, ZodError } from "zod";

function toQty(v: unknown): number | undefined {
  if (v == null || v === "") return undefined;
  const n =
    typeof v === "number"
      ? v
      : Number(String(v).replace(/[\s\u00a0]/g, "").replace(",", "."));
  if (!Number.isFinite(n) || n <= 0) return undefined;
  return roundQty(n);
}

/**
 * Parse une opération même si `@neoforma/shared` encore en cache
 * exige `quantity` entier (Render / node_modules périmé).
 */
export function parseCreateOperation(
  body: unknown
): SafeParseReturnType<unknown, CreateOperation> {
  const first = CreateOperationSchema.safeParse(body);
  if (first.success) return first;

  const qtyBlocked = first.error.issues.some(
    (i) =>
      (i.path[0] === "quantity" || i.path[0] === "quantiteStock") &&
      /integer/i.test(i.message)
  );
  if (!qtyBlocked || !body || typeof body !== "object") return first;

  const raw = { ...(body as Record<string, unknown>) };
  const qty = toQty(raw.quantity);
  const qtyStock = toQty(raw.quantiteStock);
  delete raw.quantity;
  delete raw.quantiteStock;

  const second = CreateOperationSchema.safeParse(raw);
  if (!second.success) return second;

  return {
    success: true,
    data: {
      ...second.data,
      ...(qty != null ? { quantity: qty } : {}),
      ...(qtyStock != null ? { quantiteStock: qtyStock } : {}),
    },
  };
}

export function formatCreateOpError(error: ZodError): string {
  const first = error.issues[0];
  const where = first?.path?.length
    ? `${first.path.join(".")}: ${first.message}`
    : first?.message;
  return where ? `Opération invalide (${where})` : "Opération invalide";
}
