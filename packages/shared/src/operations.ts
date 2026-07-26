import { z } from "zod";
import {
  NatureStockSchema,
  OperationTypeCanonicalSchema,
  OperationTypeSchema,
  StatutCreanceSchema,
} from "./enums.js";

export function toCanonicalOperationType(
  type: z.infer<typeof OperationTypeSchema>
): z.infer<typeof OperationTypeCanonicalSchema> {
  return type === "dette" ? "creance" : type;
}

export const OperationSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().uuid(),
  type: OperationTypeCanonicalSchema,
  amountFcfa: z.number().int().positive(),
  label: z.string().max(200).optional(),
  clientId: z.string().uuid().optional(),
  clientName: z.string().max(120).optional(),
  natureStock: NatureStockSchema.optional(),
  categorieDepense: z.string().max(80).optional(),
  dueAt: z.string().datetime().optional(),
  settledAt: z.string().datetime().nullable().optional(),
  statutCreance: StatutCreanceSchema.optional(),
  statutSync: z.enum(["locale", "synchronisee", "en_conflit"]).optional(),
  canal: z.enum(["especes", "mobile_money"]).optional(),
  createdAt: z.string().datetime(),
  dateOperation: z.string().datetime().optional(),
  clientMutationId: z.string().uuid().optional(),
  syncedAt: z.string().datetime().nullable().optional(),
});
export type Operation = z.infer<typeof OperationSchema>;

export const CreateOperationSchema = z
  .object({
    type: OperationTypeSchema,
    amountFcfa: z.number().int().positive(),
    label: z.string().max(200).optional(),
    clientId: z.string().uuid().optional(),
    clientName: z.string().max(120).optional(),
    natureStock: NatureStockSchema.optional(),
    categorieDepense: z.string().max(80).optional(),
    /** Canal de paiement : especes | mobile_money */
    canal: z.enum(["especes", "mobile_money"]).optional(),
    dueAt: z.string().datetime().optional(),
    clientMutationId: z.string().uuid().optional(),
    createdAt: z.string().datetime().optional(),
    dateOperation: z.string().datetime().optional(),
  })
  .superRefine((data, ctx) => {
    const type = toCanonicalOperationType(data.type);
    if (type === "creance" && !data.clientId && !data.clientName?.trim()) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Créance : clientId ou clientName requis (RM-O03)",
        path: ["clientName"],
      });
    }
  });
export type CreateOperation = z.infer<typeof CreateOperationSchema>;

export const ClientInformelSchema = z.object({
  id: z.string().uuid(),
  nom: z.string().min(1).max(120),
  telephone: z.string().max(20).optional().nullable(),
  note: z.string().max(500).optional().nullable(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});
export type ClientInformelDto = z.infer<typeof ClientInformelSchema>;

export const CreateClientSchema = z.object({
  nom: z.string().min(1).max(120),
  telephone: z.string().max(20).optional(),
  note: z.string().max(500).optional(),
});
export type CreateClient = z.infer<typeof CreateClientSchema>;

export const UpdateClientSchema = CreateClientSchema.partial();
export type UpdateClient = z.infer<typeof UpdateClientSchema>;

export const DashboardStatsSchema = z.object({
  monthSalesFcfa: z.number().int().nonnegative(),
  openDebtsFcfa: z.number().int().nonnegative(),
  overdueDebtsCount: z.number().int().nonnegative(),
  last7DaysSales: z.array(
    z.object({
      day: z.string(),
      totalFcfa: z.number().int().nonnegative(),
    })
  ),
  recentOperations: z.array(OperationSchema),
});
export type DashboardStats = z.infer<typeof DashboardStatsSchema>;
