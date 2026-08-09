import { z } from "zod";
import {
  CreateOperationSchema,
  CreateClientSchema,
  SettleCreanceSchema,
} from "./operations.js";
import { OnboardingUpdateSchema, UpdatePreferencesSchema } from "./profile.js";
import { UpdateConsentsBatchSchema } from "./consent.js";
import { SubmitCreditSchema } from "./credit.js";

export const SyncMutationKindSchema = z.enum([
  "create_operation",
  "create_client",
  "update_profile",
  "update_consents",
  "submit_credit",
  "settle_creance",
  "delete_operation",
  "create_tontine",
  "create_tontine_cotisation",
  "upsert_stock",
]);
export type SyncMutationKind = z.infer<typeof SyncMutationKindSchema>;

/** Upsert article stock hors-ligne (même sémantique que POST /stock/articles). */
export const UpsertStockMutationSchema = z.object({
  nom: z.string().min(1).max(120),
  unite: z.string().max(20).optional(),
  quantite: z.number().int().nonnegative().optional(),
  prixUnitaireFcfa: z.number().int().nonnegative().optional(),
});
export type UpsertStockMutation = z.infer<typeof UpsertStockMutationSchema>;

/** Payload de règlement hors-ligne (settle_creance) — cible l'opération par son id serveur. */
export const SettleCreanceMutationSchema = SettleCreanceSchema.extend({
  operationId: z.string().uuid(),
});
export type SettleCreanceMutation = z.infer<typeof SettleCreanceMutationSchema>;

/** Suppression d'opération hors-ligne (correction). */
export const DeleteOperationMutationSchema = z.object({
  operationId: z.string().uuid(),
});
export type DeleteOperationMutation = z.infer<
  typeof DeleteOperationMutationSchema
>;

/** Création tontine hors-ligne — l'id serveur = clientMutationId (UUID). */
export const CreateTontineMutationSchema = z.object({
  nom: z.string().min(1).max(120),
  cotisationFcfa: z.number().int().positive(),
  frequence: z.enum(["quotidien", "hebdo", "mensuel"]).optional(),
  membres: z.number().int().positive().optional(),
  note: z.string().max(500).optional(),
});
export type CreateTontineMutation = z.infer<typeof CreateTontineMutationSchema>;

/** Cotisation tontine hors-ligne — cible la tontine par son id serveur (ou UUID local syncé). */
export const CreateTontineCotisationMutationSchema = z.object({
  tontineId: z.string().uuid(),
  montantFcfa: z.number().int().positive(),
  note: z.string().max(200).optional(),
});
export type CreateTontineCotisationMutation = z.infer<
  typeof CreateTontineCotisationMutationSchema
>;

const baseMutation = {
  clientMutationId: z.string().uuid(),
  createdAt: z.string().datetime(),
};

export const SyncMutationSchema = z.discriminatedUnion("kind", [
  z.object({
    ...baseMutation,
    kind: z.literal("create_operation"),
    payload: CreateOperationSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("create_client"),
    payload: CreateClientSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("update_profile"),
    payload: OnboardingUpdateSchema.or(UpdatePreferencesSchema),
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("update_consents"),
    payload: UpdateConsentsBatchSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("submit_credit"),
    payload: SubmitCreditSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("settle_creance"),
    payload: SettleCreanceMutationSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("delete_operation"),
    payload: DeleteOperationMutationSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("create_tontine"),
    payload: CreateTontineMutationSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("create_tontine_cotisation"),
    payload: CreateTontineCotisationMutationSchema,
  }),
  z.object({
    ...baseMutation,
    kind: z.literal("upsert_stock"),
    payload: UpsertStockMutationSchema,
  }),
]);
export type SyncMutation = z.infer<typeof SyncMutationSchema>;

export const SyncPushRequestSchema = z.object({
  mutations: z.array(SyncMutationSchema).max(100),
});
export type SyncPushRequest = z.infer<typeof SyncPushRequestSchema>;

export const SyncPushResponseSchema = z.object({
  accepted: z.array(z.string().uuid()),
  rejected: z.array(
    z.object({
      clientMutationId: z.string().uuid(),
      reason: z.string(),
    })
  ),
  serverTime: z.string().datetime(),
});
export type SyncPushResponse = z.infer<typeof SyncPushResponseSchema>;

export const SyncPullQuerySchema = z.object({
  since: z.string().datetime().optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
});
export type SyncPullQuery = z.infer<typeof SyncPullQuerySchema>;
