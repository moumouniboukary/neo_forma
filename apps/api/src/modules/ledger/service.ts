import type {
  ClientInformel,
  Operation,
  Prisma,
  PrismaClient,
} from "@prisma/client";
import type {
  CreateClient,
  CreateOperation,
  UpdateClient,
} from "@neoforma/shared";
import { toCanonicalOperationType } from "@neoforma/shared";

export class LedgerError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "LedgerError";
  }
}

export function isLedgerError(err: unknown): err is LedgerError {
  return err instanceof LedgerError;
}

export type OperationWithClient = Operation & {
  client: ClientInformel | null;
};

function resolveCreanceStatut(
  echeance: Date | null | undefined,
  now = new Date()
): "ouverte" | "en_retard" {
  if (echeance && echeance < now) return "en_retard";
  return "ouverte";
}

export class LedgerService {
  constructor(private readonly prisma: PrismaClient) {}

  // ─── Clients ─────────────────────────────────────────────

  async listClients(travailleurId: string): Promise<ClientInformel[]> {
    return this.prisma.clientInformel.findMany({
      where: { travailleurId },
      orderBy: { nom: "asc" },
    });
  }

  async createClient(
    travailleurId: string,
    input: CreateClient
  ): Promise<ClientInformel> {
    const nom = input.nom.trim();
    if (!nom) {
      throw new LedgerError("validation", "Nom client obligatoire (RM-CI02)", 400);
    }
    return this.prisma.clientInformel.create({
      data: {
        travailleurId,
        nom,
        telephone: input.telephone?.trim() || null,
        note: input.note?.trim() || null,
      },
    });
  }

  async updateClient(
    travailleurId: string,
    clientId: string,
    input: UpdateClient
  ): Promise<ClientInformel> {
    await this.requireOwnedClient(travailleurId, clientId);
    return this.prisma.clientInformel.update({
      where: { id: clientId },
      data: {
        ...(input.nom !== undefined ? { nom: input.nom.trim() } : {}),
        ...(input.telephone !== undefined
          ? { telephone: input.telephone?.trim() || null }
          : {}),
        ...(input.note !== undefined ? { note: input.note?.trim() || null } : {}),
      },
    });
  }

  async deleteClient(travailleurId: string, clientId: string): Promise<void> {
    await this.requireOwnedClient(travailleurId, clientId);
    const open = await this.prisma.operation.count({
      where: {
        clientId,
        type: "creance",
        statutCreance: { in: ["ouverte", "en_retard"] },
      },
    });
    if (open > 0) {
      throw new LedgerError(
        "client_has_open_debts",
        "Impossible de supprimer un client avec des créances ouvertes",
        409
      );
    }
    await this.prisma.clientInformel.delete({ where: { id: clientId } });
  }

  // ─── Operations ──────────────────────────────────────────

  async listOperations(
    travailleurId: string,
    opts: { type?: string; limit?: number } = {}
  ): Promise<OperationWithClient[]> {
    let type = opts.type;
    if (type === "dette") type = "creance";

    return this.prisma.operation.findMany({
      where: {
        travailleurId,
        ...(type ? { type } : {}),
      },
      include: { client: true },
      orderBy: { dateOperation: "desc" },
      take: Math.min(opts.limit ?? 50, 200),
    });
  }

  async createOperation(
    travailleurId: string,
    input: CreateOperation
  ): Promise<OperationWithClient> {
    if (input.amountFcfa <= 0) {
      throw new LedgerError("validation", "Montant doit être > 0 (RM-O01)", 400);
    }

    const type = toCanonicalOperationType(input.type);

    if (input.clientMutationId) {
      const existing = await this.prisma.operation.findUnique({
        where: { identifiantIdempotence: input.clientMutationId },
        include: { client: true },
      });
      if (existing) return existing;
    }

    const dateOperation = input.dateOperation
      ? new Date(input.dateOperation)
      : input.createdAt
        ? new Date(input.createdAt)
        : new Date();

    let clientId = input.clientId ?? null;
    if (type === "creance") {
      if (clientId) {
        await this.requireOwnedClient(travailleurId, clientId);
      } else {
        const client = await this.createClient(travailleurId, {
          nom: input.clientName!.trim(),
        });
        clientId = client.id;
      }
    } else if (clientId) {
      throw new LedgerError(
        "validation",
        "clientId réservé aux opérations de type créance",
        400
      );
    }

    const echeance = input.dueAt ? new Date(input.dueAt) : null;
    const data: Prisma.OperationCreateInput = {
      type,
      montantFcfa: input.amountFcfa,
      libelle: input.label?.trim() || null,
      dateOperation,
      statutSync: "synchronisee",
      identifiantIdempotence: input.clientMutationId ?? null,
      natureStock: type === "stock" ? (input.natureStock ?? "entree") : null,
      categorieDepense: type === "depense" ? input.categorieDepense ?? null : null,
      canal: input.canal ?? null,
      echeance: type === "creance" ? echeance : null,
      statutCreance:
        type === "creance" ? resolveCreanceStatut(echeance) : null,
      travailleur: { connect: { id: travailleurId } },
      ...(clientId ? { client: { connect: { id: clientId } } } : {}),
    };

    return this.prisma.operation.create({
      data,
      include: { client: true },
    });
  }

  /** RM-O05 — règlement créance. */
  async settleCreance(
    travailleurId: string,
    operationId: string
  ): Promise<OperationWithClient> {
    const op = await this.prisma.operation.findFirst({
      where: { id: operationId, travailleurId },
      include: { client: true },
    });
    if (!op) {
      throw new LedgerError("not_found", "Opération introuvable", 404);
    }
    if (op.type !== "creance") {
      throw new LedgerError("validation", "Seule une créance peut être réglée", 400);
    }
    if (op.statutCreance === "reglee") {
      return op;
    }
    if (op.statutCreance === "annulee") {
      throw new LedgerError("validation", "Créance annulée — règlement impossible", 400);
    }

    return this.prisma.operation.update({
      where: { id: operationId },
      data: {
        statutCreance: "reglee",
        dateReglement: new Date(),
      },
      include: { client: true },
    });
  }

  /** Marque les créances ouvertes dont l'échéance est passée (RM-O04). */
  async refreshOverdue(travailleurId: string): Promise<number> {
    const result = await this.prisma.operation.updateMany({
      where: {
        travailleurId,
        type: "creance",
        statutCreance: "ouverte",
        echeance: { lt: new Date() },
      },
      data: { statutCreance: "en_retard" },
    });
    return result.count;
  }

  async getDashboardStats(travailleurId: string) {
    await this.refreshOverdue(travailleurId);

    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const weekAgo = new Date(now);
    weekAgo.setDate(weekAgo.getDate() - 6);
    weekAgo.setHours(0, 0, 0, 0);

    const [monthSales, openDebts, recent, weekOps] = await Promise.all([
      this.prisma.operation.findMany({
        where: {
          travailleurId,
          type: "vente",
          dateOperation: { gte: monthStart },
        },
      }),
      this.prisma.operation.findMany({
        where: {
          travailleurId,
          type: "creance",
          statutCreance: { in: ["ouverte", "en_retard"] },
        },
        include: { client: true },
      }),
      this.prisma.operation.findMany({
        where: { travailleurId },
        include: { client: true },
        orderBy: { dateOperation: "desc" },
        take: 10,
      }),
      this.prisma.operation.findMany({
        where: {
          travailleurId,
          type: "vente",
          dateOperation: { gte: weekAgo },
        },
      }),
    ]);

    const days = ["D", "L", "M", "M", "J", "V", "S"];
    const last7DaysSales = Array.from({ length: 7 }, (_, i) => {
      const d = new Date(weekAgo);
      d.setDate(weekAgo.getDate() + i);
      const key = d.toISOString().slice(0, 10);
      const totalFcfa = weekOps
        .filter((o) => o.dateOperation.toISOString().slice(0, 10) === key)
        .reduce((s, o) => s + o.montantFcfa, 0);
      return { day: days[d.getDay()], totalFcfa };
    });

    return {
      monthSalesFcfa: monthSales.reduce((s, o) => s + o.montantFcfa, 0),
      openDebtsFcfa: openDebts.reduce((s, o) => s + o.montantFcfa, 0),
      overdueDebtsCount: openDebts.filter((d) => d.statutCreance === "en_retard")
        .length,
      last7DaysSales,
      recentOperations: recent,
    };
  }

  private async requireOwnedClient(
    travailleurId: string,
    clientId: string
  ): Promise<ClientInformel> {
    const client = await this.prisma.clientInformel.findFirst({
      where: { id: clientId, travailleurId },
    });
    if (!client) {
      throw new LedgerError("not_found", "Client introuvable", 404);
    }
    return client;
  }
}
