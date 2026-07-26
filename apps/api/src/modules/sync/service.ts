import type { OperationHorsLigne, PrismaClient } from "@prisma/client";
import type { CreateOperation, SyncMutation } from "@neoforma/shared";
import { toClient, toOperation } from "../../lib/mappers.js";
import { LedgerService, isLedgerError } from "../ledger/service.js";
import { ProfileService, isProfileError } from "../profile/service.js";
import { ConsentService, isConsentError } from "../consent/service.js";
import { CreditService, isCreditError } from "../credit/service.js";

export class SyncError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "SyncError";
  }
}

export function isSyncError(err: unknown): err is SyncError {
  return err instanceof SyncError;
}

export type SyncPushResult = {
  accepted: string[];
  rejected: Array<{ clientMutationId: string; reason: string }>;
  serverTime: string;
};

export type SyncPullResult = {
  operations: ReturnType<typeof toOperation>[];
  clients: ReturnType<typeof toClient>[];
  serverTime: string;
  /** Curseur à renvoyer au prochain pull (ISO). */
  nextSince: string;
  hasMore: boolean;
};

export class SyncService {
  private readonly ledger: LedgerService;
  private readonly profiles: ProfileService;
  private readonly consents: ConsentService;
  private readonly credit: CreditService;

  constructor(private readonly prisma: PrismaClient) {
    this.ledger = new LedgerService(prisma);
    this.profiles = new ProfileService(prisma);
    this.consents = new ConsentService(prisma);
    this.credit = new CreditService(prisma);
  }

  async listQueue(
    travailleurId: string,
    etat?: string
  ): Promise<OperationHorsLigne[]> {
    return this.prisma.operationHorsLigne.findMany({
      where: {
        travailleurId,
        ...(etat ? { etat } : {}),
      },
      orderBy: { createdAt: "asc" },
      take: 200,
    });
  }

  async enqueue(
    travailleurId: string,
    input: {
      clientMutationId: string;
      payload: CreateOperation;
      createdAt: string;
    }
  ): Promise<OperationHorsLigne> {
    const existing = await this.prisma.operationHorsLigne.findUnique({
      where: { identifiantLocal: input.clientMutationId },
    });
    if (existing) return existing;

    return this.prisma.operationHorsLigne.create({
      data: {
        travailleurId,
        identifiantLocal: input.clientMutationId,
        payload: JSON.stringify(input.payload),
        dateSaisieLocale: new Date(input.createdAt),
        etat: "en_attente",
      },
    });
  }

  /**
   * Push multi-kind (ops, clients, profil, consentements) — idempotent.
   */
  async pushMutations(
    travailleurId: string,
    mutations: SyncMutation[]
  ): Promise<SyncPushResult> {
    const accepted: string[] = [];
    const rejected: Array<{ clientMutationId: string; reason: string }> = [];

    for (const mutation of mutations) {
      try {
        await this.acceptOne(travailleurId, mutation);
        accepted.push(mutation.clientMutationId);
      } catch (err) {
        const reason =
          isLedgerError(err) ||
          isSyncError(err) ||
          isProfileError(err) ||
          isConsentError(err) ||
          isCreditError(err)
            ? err.message
            : err instanceof Error
              ? err.message
              : "unknown";
        rejected.push({
          clientMutationId: mutation.clientMutationId,
          reason,
        });
        await this.markRejected(
          travailleurId,
          mutation.clientMutationId,
          mutation.payload,
          mutation.createdAt,
          reason
        );
      }
    }

    return {
      accepted,
      rejected,
      serverTime: new Date().toISOString(),
    };
  }

  /**
   * Pull incrémental : opérations + clients modifiés depuis `since`.
   * Pagination via `limit` + `hasMore` / `nextSince`.
   */
  async pull(
    travailleurId: string,
    opts: { since?: Date; limit?: number } = {}
  ): Promise<SyncPullResult> {
    const since = opts.since ?? new Date(0);
    const limit = Math.min(Math.max(opts.limit ?? 100, 1), 200);
    const serverTime = new Date();

    const [ops, clients] = await Promise.all([
      this.prisma.operation.findMany({
        where: {
          travailleurId,
          updatedAt: { gt: since },
        },
        include: { client: true },
        orderBy: { updatedAt: "asc" },
        take: limit + 1,
      }),
      this.prisma.clientInformel.findMany({
        where: {
          travailleurId,
          updatedAt: { gt: since },
        },
        orderBy: { updatedAt: "asc" },
        take: limit + 1,
      }),
    ]);

    const opsHasMore = ops.length > limit;
    const clientsHasMore = clients.length > limit;
    const opsPage = opsHasMore ? ops.slice(0, limit) : ops;
    const clientsPage = clientsHasMore ? clients.slice(0, limit) : clients;
    const hasMore = opsHasMore || clientsHasMore;

    // nextSince = max(updatedAt) des éléments renvoyés, sinon serverTime.
    let maxUpdated = since.getTime();
    for (const o of opsPage) {
      maxUpdated = Math.max(maxUpdated, o.updatedAt.getTime());
    }
    for (const c of clientsPage) {
      maxUpdated = Math.max(maxUpdated, c.updatedAt.getTime());
    }
    const nextSince =
      opsPage.length || clientsPage.length
        ? new Date(maxUpdated).toISOString()
        : serverTime.toISOString();

    return {
      operations: opsPage.map(toOperation),
      clients: clientsPage.map(toClient),
      serverTime: serverTime.toISOString(),
      nextSince,
      hasMore,
    };
  }

  private async acceptOne(
    travailleurId: string,
    mutation: SyncMutation
  ): Promise<void> {
    const existingQueue = await this.prisma.operationHorsLigne.findUnique({
      where: { identifiantLocal: mutation.clientMutationId },
    });
    if (existingQueue?.etat === "acceptee") {
      return;
    }

    switch (mutation.kind) {
      case "create_operation": {
        const existingOp = await this.prisma.operation.findUnique({
          where: { identifiantIdempotence: mutation.clientMutationId },
        });
        if (existingOp) {
          await this.upsertAccepted(
            travailleurId,
            mutation,
            existingOp.id,
            existingQueue?.id
          );
          return;
        }
        const op = await this.ledger.createOperation(travailleurId, {
          ...mutation.payload,
          clientMutationId: mutation.clientMutationId,
          createdAt: mutation.createdAt,
          dateOperation: mutation.createdAt,
        });
        await this.upsertAccepted(
          travailleurId,
          mutation,
          op.id,
          existingQueue?.id
        );
        return;
      }
      case "create_client": {
        await this.ledger.createClient(travailleurId, mutation.payload);
        await this.upsertAccepted(
          travailleurId,
          mutation,
          null,
          existingQueue?.id
        );
        return;
      }
      case "update_profile": {
        await this.profiles.applyOnboardingUpdate(
          travailleurId,
          mutation.payload as Parameters<ProfileService["applyOnboardingUpdate"]>[1]
        );
        await this.upsertAccepted(
          travailleurId,
          mutation,
          null,
          existingQueue?.id
        );
        return;
      }
      case "update_consents": {
        await this.consents.applyLegacyBatch(travailleurId, mutation.payload);
        await this.upsertAccepted(
          travailleurId,
          mutation,
          null,
          existingQueue?.id
        );
        return;
      }
      case "submit_credit": {
        await this.credit.ensurePilotImf();
        await this.credit.submit(travailleurId, mutation.payload);
        await this.upsertAccepted(
          travailleurId,
          mutation,
          null,
          existingQueue?.id
        );
        return;
      }
      default: {
        const _exhaustive: never = mutation;
        throw new SyncError(
          "unknown_kind",
          `Kind inconnu: ${(_exhaustive as SyncMutation).kind}`
        );
      }
    }
  }

  private async upsertAccepted(
    travailleurId: string,
    mutation: SyncMutation,
    operationId: string | null,
    existingId?: string
  ): Promise<void> {
    const payload = JSON.stringify(mutation.payload);
    if (existingId) {
      await this.prisma.operationHorsLigne.update({
        where: { id: existingId },
        data: {
          etat: "acceptee",
          operationId,
          motifRejet: null,
          payload,
        },
      });
      return;
    }
    await this.prisma.operationHorsLigne.create({
      data: {
        travailleurId,
        identifiantLocal: mutation.clientMutationId,
        payload,
        dateSaisieLocale: new Date(mutation.createdAt),
        etat: "acceptee",
        operationId,
      },
    });
  }

  private async markRejected(
    travailleurId: string,
    clientMutationId: string,
    payload: unknown,
    createdAt: string,
    reason: string
  ): Promise<void> {
    const existing = await this.prisma.operationHorsLigne.findUnique({
      where: { identifiantLocal: clientMutationId },
    });
    if (existing?.etat === "acceptee") return;

    if (existing) {
      await this.prisma.operationHorsLigne.update({
        where: { id: existing.id },
        data: {
          etat: "rejetee",
          motifRejet: reason.slice(0, 500),
        },
      });
      return;
    }

    await this.prisma.operationHorsLigne.create({
      data: {
        travailleurId,
        identifiantLocal: clientMutationId,
        payload: JSON.stringify(payload),
        dateSaisieLocale: new Date(createdAt),
        etat: "rejetee",
        motifRejet: reason.slice(0, 500),
      },
    });
  }
}
