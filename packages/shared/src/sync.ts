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
  "create_tontine_cotisation",
]);
export type SyncMutationKind = z.infer<typeof SyncMutationKindSchema>;

/** Payload de règlement hors-ligne (settle_creance) — cible l'opération par son id serveur. */
export const SettleCreanceMutationSchema = SettleCreanceSchema.extend({
  operationId: z.string().uuid(),
});
export type SettleCreanceMutation = z.infer<typeof SettleCreanceMutationSchema>;

/** Cotisation tontine hors-ligne — cible la tontine par son id serveur. */
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
    kind: z.literal("create_tontine_cotisation"),
    payload: CreateTontineCotisationMutationSchema,
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
