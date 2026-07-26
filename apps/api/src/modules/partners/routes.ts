/**
 * Module partners — IMF (lecture + décision crédit + commissions).
 * Auth partenaire : header X-Partner-Key (= Imf.apiKey ou PARTNER_API_KEY).
 * Auth travailleur JWT conservée pour /imf et /profiles.
 */
import type { FastifyInstance, FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { ConsentService } from "../consent/service.js";
import { ScoringService } from "../scoring/service.js";
import { CreditService, isCreditError } from "../credit/service.js";
import { toCredit } from "../../lib/mappers.js";

const DecideSchema = z.object({
  statut: z.enum(["en_examen", "approuvee", "refusee", "decaissee"]),
  motifDecision: z.string().max(500).optional(),
});

const CommissionStatutSchema = z.object({
  statut: z.enum(["due", "facturee", "payee"]),
});

async function resolvePartnerImf(
  app: FastifyInstance,
  request: FastifyRequest,
  reply: FastifyReply
) {
  const key =
    (request.headers["x-partner-key"] as string | undefined) ??
    (request.headers.authorization?.replace(/^Bearer\s+/i, "") ?? "");
  if (!key) {
    reply.status(401).send({
      error: "unauthorized",
      message: "Clé partenaire manquante (X-Partner-Key)",
    });
    return null;
  }

  // Fallback global ops (MVP) ou clé par IMF.
  if (process.env.PARTNER_API_KEY && key === process.env.PARTNER_API_KEY) {
    const imf = await app.prisma.imf.findFirst({
      where: { statutPartenariat: "actif" },
      orderBy: { createdAt: "asc" },
    });
    if (!imf) {
      reply.status(503).send({
        error: "no_imf",
        message: "Aucune IMF active",
      });
      return null;
    }
    return imf;
  }

  const imf = await app.prisma.imf.findFirst({
    where: { apiKey: key, statutPartenariat: "actif" },
  });
  if (!imf) {
    reply.status(401).send({
      error: "unauthorized",
      message: "Clé partenaire invalide",
    });
    return null;
  }
  return imf;
}

export const partnersRoutes: FastifyPluginAsync = async (app) => {
  const consents = new ConsentService(app.prisma);
  const scoring = new ScoringService(app.prisma);
  const credit = new CreditService(app.prisma);
  await credit.ensurePilotImf();

  /** Liste IMF actives */
  app.get("/imf", { preHandler: [app.authenticate] }, async () => {
    return app.prisma.imf.findMany({
      where: { statutPartenariat: { in: ["actif", "prospect"] } },
      orderBy: { raisonSociale: "asc" },
      select: {
        id: true,
        raisonSociale: true,
        pays: true,
        statutPartenariat: true,
        niveauAcces: true,
        tauxCommission: true,
      },
    });
  });

  /**
   * Consultation profil consenti — gate partage_imf.
   */
  app.get(
    "/profiles/:travailleurId",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { travailleurId } = request.params as { travailleurId: string };
      if (request.user.sub !== travailleurId) {
        return reply.status(403).send({
          error: "forbidden",
          message: "Accès profil non autorisé",
        });
      }

      const ok = await consents.hasConsent(travailleurId, "partage_imf");
      if (!ok) {
        return reply.status(403).send({
          error: "consent_required",
          message: "Consentement partage_imf requis",
        });
      }

      const score = await scoring.getCurrent(travailleurId);
      const consent = await consents.getByType(travailleurId, "partage_imf");
      const anonymise = await consents.hasConsent(
        travailleurId,
        "anonymisation_recherche"
      );

      const imf = await app.prisma.imf.findFirst({
        where: { statutPartenariat: "actif" },
      });
      if (imf) {
        await app.prisma.accesProfilImf.create({
          data: {
            imfId: imf.id,
            travailleurId,
            consentementId: consent.id,
            finalite: "consultation_profil_mvp",
            anonymise,
            scorePresente: score.score,
          },
        });
      }

      const user = await app.prisma.travailleur.findUnique({
        where: { id: travailleurId },
        include: { profilActivite: true },
      });

      return {
        travailleurId,
        anonymise,
        displayName: anonymise
          ? `Travailleur-${travailleurId.slice(0, 8)}`
          : user?.nomAffiche,
        metier: user?.profilActivite?.metier,
        ville: user?.profilActivite?.ville,
        score: {
          valeur: score.score,
          segment: score.segment,
          eligible: score.eligible,
        },
      };
    }
  );

  /** File des demandes de crédit pour l'IMF partenaire. */
  app.get("/applications", async (request, reply) => {
    const imf = await resolvePartnerImf(app, request, reply);
    if (!imf) return;

    const query = request.query as { statut?: string };
    const apps = await app.prisma.demandeCredit.findMany({
      where: {
        OR: [{ imfId: imf.id }, { imfId: null }],
        ...(query.statut ? { statut: query.statut } : {}),
      },
      orderBy: { createdAt: "desc" },
      take: 100,
      include: { snapshotScore: true },
    });
    return apps.map(toCredit);
  });

  /** Décision sur une demande (+ commission si approuvée / décaissée). */
  app.post("/applications/:id/decide", async (request, reply) => {
    const imf = await resolvePartnerImf(app, request, reply);
    if (!imf) return;

    const parsed = DecideSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Décision invalide",
        details: parsed.error.flatten(),
      });
    }
    const { id } = request.params as { id: string };
    try {
      const row = await credit.decide(id, {
        ...parsed.data,
        imfId: imf.id,
      });
      return toCredit(row);
    } catch (err) {
      if (isCreditError(err)) {
        return reply.status(err.statusCode).send({
          error: err.code,
          message: err.message,
        });
      }
      throw err;
    }
  });

  /** Liste des commissions (facturation NeoForma ↔ IMF). */
  app.get("/commissions", async (request, reply) => {
    const imf = await resolvePartnerImf(app, request, reply);
    if (!imf) return;
    const query = request.query as { statut?: string };
    return credit.listCommissions({
      imfId: imf.id,
      statut: query.statut,
    });
  });

  /** Met à jour le statut de facturation d'une commission. */
  app.patch("/commissions/:id", async (request, reply) => {
    const imf = await resolvePartnerImf(app, request, reply);
    if (!imf) return;

    const parsed = CommissionStatutSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Statut commission invalide (due|facturee|payee)",
      });
    }
    const { id } = request.params as { id: string };
    try {
      const row = await app.prisma.commission.findFirst({
        where: { id, imfId: imf.id },
      });
      if (!row) {
        return reply.status(404).send({
          error: "not_found",
          message: "Commission introuvable",
        });
      }
      return await credit.updateCommissionStatut(id, parsed.data.statut);
    } catch (err) {
      if (isCreditError(err)) {
        return reply.status(err.statusCode).send({
          error: err.code,
          message: err.message,
        });
      }
      throw err;
    }
  });
};
