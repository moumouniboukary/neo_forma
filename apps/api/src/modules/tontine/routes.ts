import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";

const CreateTontineSchema = z.object({
  nom: z.string().min(1).max(120),
  cotisationFcfa: z.number().int().positive(),
  frequence: z.enum(["quotidien", "hebdo", "mensuel"]).optional(),
  membres: z.number().int().positive().optional(),
  note: z.string().max(500).optional(),
});

const UpdateTontineSchema = CreateTontineSchema.partial().extend({
  actif: z.boolean().optional(),
});

const CreateCotisationSchema = z.object({
  montantFcfa: z.number().int().positive(),
  note: z.string().max(200).optional(),
});

function toTontineDto(t: {
  id: string;
  nom: string;
  cotisationFcfa: number;
  frequence: string;
  membres: number;
  note: string | null;
  actif: boolean;
  createdAt: Date;
  cotisations?: Array<{
    id: string;
    montantFcfa: number;
    datePaiement: Date;
    note: string | null;
  }>;
}) {
  return {
    id: t.id,
    nom: t.nom,
    cotisationFcfa: t.cotisationFcfa,
    frequence: t.frequence,
    membres: t.membres,
    note: t.note ?? undefined,
    actif: t.actif,
    createdAt: t.createdAt.toISOString(),
    cotisations: t.cotisations?.map((c) => ({
      id: c.id,
      montantFcfa: c.montantFcfa,
      datePaiement: c.datePaiement.toISOString(),
      note: c.note ?? undefined,
    })),
  };
}

/** Suivi tontine — CRUD /tontines, POST /tontines/:id/cotisations. */
export const tontineRoutes: FastifyPluginAsync = async (app) => {
  app.get("/", { preHandler: [app.authenticate] }, async (request) => {
    const items = await app.prisma.tontine.findMany({
      where: { travailleurId: request.user.sub },
      include: {
        cotisations: { orderBy: { datePaiement: "desc" }, take: 12 },
      },
      orderBy: { createdAt: "desc" },
    });
    return { items: items.map(toTontineDto) };
  });

  app.get("/:id", { preHandler: [app.authenticate] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const tontine = await app.prisma.tontine.findFirst({
      where: { id, travailleurId: request.user.sub },
      include: {
        cotisations: { orderBy: { datePaiement: "desc" }, take: 50 },
      },
    });
    if (!tontine) {
      return reply
        .status(404)
        .send({ error: "not_found", message: "Tontine introuvable" });
    }
    return toTontineDto(tontine);
  });

  app.post("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = CreateTontineSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Tontine invalide",
        details: parsed.error.flatten(),
      });
    }
    const { nom, cotisationFcfa, frequence, membres, note } = parsed.data;
    const tontine = await app.prisma.tontine.create({
      data: {
        travailleurId: request.user.sub,
        nom: nom.trim(),
        cotisationFcfa,
        frequence: frequence ?? "mensuel",
        membres: membres ?? 1,
        note: note?.trim() || null,
      },
    });
    return reply.status(201).send(toTontineDto(tontine));
  });

  app.patch("/:id", { preHandler: [app.authenticate] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = UpdateTontineSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Tontine invalide",
        details: parsed.error.flatten(),
      });
    }
    const existing = await app.prisma.tontine.findFirst({
      where: { id, travailleurId: request.user.sub },
    });
    if (!existing) {
      return reply
        .status(404)
        .send({ error: "not_found", message: "Tontine introuvable" });
    }
    const { nom, cotisationFcfa, frequence, membres, note, actif } = parsed.data;
    const tontine = await app.prisma.tontine.update({
      where: { id },
      data: {
        ...(nom !== undefined ? { nom: nom.trim() } : {}),
        ...(cotisationFcfa !== undefined ? { cotisationFcfa } : {}),
        ...(frequence !== undefined ? { frequence } : {}),
        ...(membres !== undefined ? { membres } : {}),
        ...(note !== undefined ? { note: note?.trim() || null } : {}),
        ...(actif !== undefined ? { actif } : {}),
      },
    });
    return toTontineDto(tontine);
  });

  app.delete("/:id", { preHandler: [app.authenticate] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const existing = await app.prisma.tontine.findFirst({
      where: { id, travailleurId: request.user.sub },
    });
    if (!existing) {
      return reply
        .status(404)
        .send({ error: "not_found", message: "Tontine introuvable" });
    }
    await app.prisma.tontine.delete({ where: { id } });
    return reply.status(204).send();
  });

  app.post(
    "/:id/cotisations",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const parsed = CreateCotisationSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Cotisation invalide",
          details: parsed.error.flatten(),
        });
      }
      const tontine = await app.prisma.tontine.findFirst({
        where: { id, travailleurId: request.user.sub },
      });
      if (!tontine) {
        return reply
          .status(404)
          .send({ error: "not_found", message: "Tontine introuvable" });
      }
      const cotisation = await app.prisma.tontineCotisation.create({
        data: {
          tontineId: tontine.id,
          montantFcfa: parsed.data.montantFcfa,
          note: parsed.data.note?.trim() || null,
        },
      });
      return reply.status(201).send({
        id: cotisation.id,
        montantFcfa: cotisation.montantFcfa,
        datePaiement: cotisation.datePaiement.toISOString(),
        note: cotisation.note ?? undefined,
      });
    }
  );
};
