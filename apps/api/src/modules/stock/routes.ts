import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { toArticleStock } from "../../lib/mappers.js";

const CreateArticleSchema = z.object({
  nom: z.string().min(1).max(120),
  unite: z.string().max(20).optional(),
  quantite: z.number().int().nonnegative().optional(),
  prixUnitaireFcfa: z.number().int().nonnegative().optional(),
});

const UpdateArticleSchema = z.object({
  nom: z.string().min(1).max(120).optional(),
  unite: z.string().max(20).optional(),
  /** Remplace la quantité (utiliser POST /articles pour un delta additif). */
  quantite: z.number().int().nonnegative().optional(),
  prixUnitaireFcfa: z.number().int().nonnegative().nullable().optional(),
});

/**
 * Catalogue stock local — GET/POST /stock/articles.
 * POST fait un upsert par nom : crée l'article ou incrémente la quantité
 * existante (RM-simplicité terrain — pas de doublon par nom).
 */
export const stockRoutes: FastifyPluginAsync = async (app) => {
  app.get(
    "/articles",
    { preHandler: [app.authenticate] },
    async (request) => {
      const items = await app.prisma.articleStock.findMany({
        where: { travailleurId: request.user.sub },
        orderBy: { nom: "asc" },
      });
      return { items: items.map(toArticleStock) };
    }
  );

  app.post(
    "/articles",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const parsed = CreateArticleSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Article invalide",
          details: parsed.error.flatten(),
        });
      }
      const { nom, unite, quantite, prixUnitaireFcfa } = parsed.data;
      const travailleurId = request.user.sub;
      const existing = await app.prisma.articleStock.findUnique({
        where: { travailleurId_nom: { travailleurId, nom: nom.trim() } },
      });
      const article = existing
        ? await app.prisma.articleStock.update({
            where: { id: existing.id },
            data: {
              quantite: existing.quantite + (quantite ?? 0),
              ...(unite ? { unite } : {}),
              ...(prixUnitaireFcfa !== undefined ? { prixUnitaireFcfa } : {}),
            },
          })
        : await app.prisma.articleStock.create({
            data: {
              travailleurId,
              nom: nom.trim(),
              unite: unite ?? "u",
              quantite: quantite ?? 0,
              prixUnitaireFcfa: prixUnitaireFcfa ?? null,
            },
          });
      return reply.status(201).send(toArticleStock(article));
    }
  );

  /** PATCH /stock/articles/:id — correction manuelle (nom, unité, quantité, prix). */
  app.patch(
    "/articles/:id",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const parsed = UpdateArticleSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Article invalide",
          details: parsed.error.flatten(),
        });
      }
      const travailleurId = request.user.sub;
      const existing = await app.prisma.articleStock.findFirst({
        where: { id, travailleurId },
      });
      if (!existing) {
        return reply
          .status(404)
          .send({ error: "not_found", message: "Article introuvable" });
      }
      const { nom, unite, quantite, prixUnitaireFcfa } = parsed.data;
      const article = await app.prisma.articleStock.update({
        where: { id },
        data: {
          ...(nom !== undefined ? { nom: nom.trim() } : {}),
          ...(unite !== undefined ? { unite } : {}),
          ...(quantite !== undefined ? { quantite } : {}),
          ...(prixUnitaireFcfa !== undefined ? { prixUnitaireFcfa } : {}),
        },
      });
      return toArticleStock(article);
    }
  );
};
