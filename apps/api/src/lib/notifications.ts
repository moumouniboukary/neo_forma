import type { Prisma, PrismaClient } from "@prisma/client";

export type NotifyInput = {
  travailleurId: string;
  type: string;
  titre: string;
  corps: string;
  meta?: Prisma.InputJsonValue;
};

export async function createNotification(
  prisma: PrismaClient,
  input: NotifyInput
) {
  return prisma.notificationInApp.create({
    data: {
      travailleurId: input.travailleurId,
      type: input.type,
      titre: input.titre,
      corps: input.corps,
      meta: input.meta ?? undefined,
    },
  });
}

/** Crée une notif par créance en retard (idempotent ~1 / jour / créance). */
export async function notifyOverdueCreances(prisma: PrismaClient): Promise<number> {
  const overdue = await prisma.operation.findMany({
    where: {
      type: "creance",
      statutCreance: "en_retard",
    },
    include: { client: true },
    take: 200,
  });
  let n = 0;
  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  for (const op of overdue) {
    const existing = await prisma.notificationInApp.findFirst({
      where: {
        travailleurId: op.travailleurId,
        type: "creance_retard",
        createdAt: { gte: dayStart },
        meta: { path: ["operationId"], equals: op.id },
      },
    });
    if (existing) continue;
    const reste = op.montantFcfa - (op.montantRegleFcfa ?? 0);
    await createNotification(prisma, {
      travailleurId: op.travailleurId,
      type: "creance_retard",
      titre: "Créance en retard",
      corps: `${op.client?.nom ?? "Client"} — ${reste} FCFA à encaisser`,
      meta: { operationId: op.id },
    });
    n += 1;
  }
  return n;
}
