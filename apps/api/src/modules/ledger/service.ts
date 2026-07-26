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
import { createNotification } from "../../lib/notifications.js";
import { smsGateway } from "../../lib/sms.js";

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
  articleStock?: { nom: string } | null;
};

const operationInclude = {
  client: true,
  articleStock: { select: { nom: true } },
} as const;

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
      include: operationInclude,
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
        include: operationInclude,
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

    let articleStockId: string | null = null;
    const natureStock = type === "stock" ? (input.natureStock ?? "entree") : null;
    const nomArticle = (input.productName ?? input.articleName)?.trim();
    const quantiteInput = input.quantiteStock ?? input.quantity;
    if (type === "stock" && input.articleStockId) {
      const quantite = quantiteInput ?? 1;
      const delta = natureStock === "sortie" ? -quantite : quantite;
      const article = await this.adjustArticleQuantity(
        travailleurId,
        input.articleStockId,
        delta
      );
      articleStockId = article.id;
    } else if (type === "stock" && nomArticle) {
      const quantite = quantiteInput ?? 1;
      const delta = natureStock === "sortie" ? -quantite : quantite;
      const article = await this.upsertArticleQuantity(
        travailleurId,
        nomArticle,
        delta
      );
      articleStockId = article.id;
    }

    const echeance = input.dueAt ? new Date(input.dueAt) : null;
    const data: Prisma.OperationCreateInput = {
      type,
      montantFcfa: input.amountFcfa,
      libelle: input.label?.trim() || null,
      dateOperation,
      statutSync: "synchronisee",
      identifiantIdempotence: input.clientMutationId ?? null,
      natureStock,
      quantiteStock: type === "stock" ? (quantiteInput ?? null) : null,
      categorieDepense: type === "depense" ? input.categorieDepense ?? null : null,
      canal: input.canal ?? null,
      echeance: type === "creance" ? echeance : null,
      statutCreance:
        type === "creance" ? resolveCreanceStatut(echeance) : null,
      travailleur: { connect: { id: travailleurId } },
      ...(clientId ? { client: { connect: { id: clientId } } } : {}),
      ...(articleStockId ? { articleStock: { connect: { id: articleStockId } } } : {}),
    };

    return this.prisma.operation.create({
      data,
      include: operationInclude,
    });
  }

  /** Crée l'article s'il n'existe pas, sinon ajuste la quantité (+/-). */
  private async upsertArticleQuantity(
    travailleurId: string,
    nom: string,
    delta: number
  ) {
    const existing = await this.prisma.articleStock.findUnique({
      where: { travailleurId_nom: { travailleurId, nom } },
    });
    if (existing) {
      return this.prisma.articleStock.update({
        where: { id: existing.id },
        data: { quantite: Math.max(0, existing.quantite + delta) },
      });
    }
    return this.prisma.articleStock.create({
      data: { travailleurId, nom, quantite: Math.max(0, delta) },
    });
  }

  /** Ajuste la quantité d'un article existant référencé par id (RM-simplicité — articleStockId direct). */
  private async adjustArticleQuantity(
    travailleurId: string,
    articleStockId: string,
    delta: number
  ) {
    const existing = await this.prisma.articleStock.findFirst({
      where: { id: articleStockId, travailleurId },
    });
    if (!existing) {
      throw new LedgerError("not_found", "Article stock introuvable", 404);
    }
    return this.prisma.articleStock.update({
      where: { id: existing.id },
      data: { quantite: Math.max(0, existing.quantite + delta) },
    });
  }

  /**
   * RM-O05 — règlement créance (total ou partiel).
   * `amountFcfa` optionnel : si fourni et < solde restant, règlement partiel
   * (la créance reste ouverte/en_retard) ; sinon règlement total.
   */
  async settleCreance(
    travailleurId: string,
    operationId: string,
    amountFcfa?: number
  ): Promise<OperationWithClient> {
    const op = await this.prisma.operation.findFirst({
      where: { id: operationId, travailleurId },
      include: operationInclude,
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

    const solde = op.montantFcfa - op.montantRegleFcfa;
    if (amountFcfa !== undefined && amountFcfa < solde) {
      const montantRegleFcfa = op.montantRegleFcfa + amountFcfa;
      return this.prisma.operation.update({
        where: { id: operationId },
        data: { montantRegleFcfa },
        include: operationInclude,
      });
    }

    return this.prisma.operation.update({
      where: { id: operationId },
      data: {
        statutCreance: "reglee",
        dateReglement: new Date(),
        montantRegleFcfa: op.montantFcfa,
      },
      include: operationInclude,
    });
  }

  /** Relance client pour une créance ouverte — SMS (si téléphone) + notif in-app. */
  async remindCreance(
    travailleurId: string,
    operationId: string
  ): Promise<OperationWithClient> {
    const op = await this.prisma.operation.findFirst({
      where: { id: operationId, travailleurId },
      include: operationInclude,
    });
    if (!op) {
      throw new LedgerError("not_found", "Opération introuvable", 404);
    }
    if (op.type !== "creance") {
      throw new LedgerError("validation", "Seule une créance peut être relancée", 400);
    }
    if (op.statutCreance === "reglee" || op.statutCreance === "annulee") {
      throw new LedgerError("validation", "Créance déjà close", 400);
    }

    const solde = op.montantFcfa - op.montantRegleFcfa;
    if (op.client?.telephone) {
      try {
        await smsGateway.send({
          to: op.client.telephone,
          body: `NeoForma : rappel — vous devez ${solde} FCFA${
            op.libelle ? ` (${op.libelle})` : ""
          }. Merci de régulariser.`,
        });
      } catch {
        // Best effort — la relance in-app reste enregistrée.
      }
    }

    await createNotification(this.prisma, {
      travailleurId,
      type: "creance_relance",
      titre: "Relance envoyée",
      corps: `${op.client?.nom ?? "Client"} — ${solde} FCFA relancé(e)`,
      meta: { operationId: op.id },
    });

    return this.prisma.operation.update({
      where: { id: operationId },
      data: { derniereRelanceAt: new Date() },
      include: operationInclude,
    });
  }

  /** Modifie l'échéance d'une créance et recalcule son statut. */
  async updateDueDate(
    travailleurId: string,
    operationId: string,
    dueAt: string
  ): Promise<OperationWithClient> {
    const op = await this.prisma.operation.findFirst({
      where: { id: operationId, travailleurId },
      include: operationInclude,
    });
    if (!op) {
      throw new LedgerError("not_found", "Opération introuvable", 404);
    }
    if (op.type !== "creance") {
      throw new LedgerError("validation", "Seule une créance a une échéance", 400);
    }
    if (op.statutCreance === "reglee" || op.statutCreance === "annulee") {
      throw new LedgerError("validation", "Créance close — échéance non modifiable", 400);
    }
    const echeance = new Date(dueAt);
    if (Number.isNaN(echeance.getTime())) {
      throw new LedgerError("validation", "Échéance invalide", 400);
    }

    return this.prisma.operation.update({
      where: { id: operationId },
      data: {
        echeance,
        statutCreance: resolveCreanceStatut(echeance),
      },
      include: operationInclude,
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
