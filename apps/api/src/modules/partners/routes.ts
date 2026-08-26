/**
 * Module partners — IMF (lecture + décision crédit + commissions).
 * Auth partenaire : header X-Partner-Key (= Imf.apiKeyHash ou PARTNER_API_KEY).
 * Auth travailleur JWT conservée pour /imf et /profiles.
 */
import type { FastifyInstance, FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { ConsentService } from "../consent/service.js";
import { ScoringService } from "../scoring/service.js";
import { CreditService, isCreditError } from "../credit/service.js";
import { toCredit } from "../../lib/mappers.js";
import { hashPartnerApiKey } from "../../lib/partner-keys.js";

const DecideSchema = z.object({
  statut: z.enum(["en_examen", "approuvee", "refusee", "decaissee"]),
  motifDecision: z.string().max(500).optional(),
  dureeMois: z.number().int().min(1).max(24).optional(),
});

const OutcomeSchema = z.object({
  outcome: z.enum(["rembourse_ok", "defaut"]),
  motif: z.string().max(500).optional(),
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

  const keyHash = hashPartnerApiKey(key);
  let imf = await app.prisma.imf.findFirst({
    where: { apiKeyHash: keyHash, statutPartenariat: "actif" },
  });

  if (!imf) {
    // Fallback legacy clé en clair — migration paresseuse vers apiKeyHash.
    const legacy = await app.prisma.imf.findFirst({
      where: { apiKey: key, statutPartenariat: "actif" },
    });
    if (legacy) {
      imf = await app.prisma.imf.update({
        where: { id: legacy.id },
        data: { apiKeyHash: keyHash, apiKey: null },
      });
    }
  }

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
  void credit.ensurePilotImf().catch((err) => {
    app.log.warn({ err }, "ensurePilotImf reporté (base pas encore prête)");
  });

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

  /** Reporting synthétique pour le portail IMF / impact coopérative. */
  app.get("/stats", async (request, reply) => {
    const imf = await resolvePartnerImf(app, request, reply);
    if (!imf) return;

    const whereImf = {
      OR: [{ imfId: imf.id }, { imfId: null }],
    };
    const decidedStatuts = ["approuvee", "refusee", "decaissee"] as const;

    const [
      total,
      soumises,
      enExamen,
      approuvees,
      refusees,
      decaissees,
      withScore,
      rembourses,
      defauts,
      enCours,
      amountsAll,
      amountsDecaisse,
      commissions,
      decidedRows,
    ] = await Promise.all([
      app.prisma.demandeCredit.count({ where: whereImf }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, statut: "soumise" },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, statut: "en_examen" },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, statut: "approuvee" },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, statut: "refusee" },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, statut: "decaissee" },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, snapshotScoreId: { not: null } },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, outcome: "rembourse_ok" },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, outcome: "defaut" },
      }),
      app.prisma.demandeCredit.count({
        where: { ...whereImf, outcome: "en_cours" },
      }),
      app.prisma.demandeCredit.aggregate({
        where: whereImf,
        _sum: { montantDemandeFcfa: true },
      }),
      app.prisma.demandeCredit.aggregate({
        where: { ...whereImf, statut: "decaissee" },
        _sum: { montantDemandeFcfa: true },
      }),
      app.prisma.commission.aggregate({
        where: { imfId: imf.id },
        _sum: { montantCommissionFcfa: true },
        _count: true,
      }),
      app.prisma.demandeCredit.findMany({
        where: {
          ...whereImf,
          statut: { in: [...decidedStatuts] },
          dateSoumission: { not: null },
        },
        select: {
          dateSoumission: true,
          dateDecaissement: true,
          updatedAt: true,
        },
        take: 500,
      }),
    ]);

    const delaysHours: number[] = [];
    for (const row of decidedRows) {
      if (!row.dateSoumission) continue;
      const end = row.dateDecaissement ?? row.updatedAt;
      const ms = end.getTime() - row.dateSoumission.getTime();
      if (ms >= 0) delaysHours.push(ms / (1000 * 60 * 60));
    }
    const avgDelayHours =
      delaysHours.length > 0
        ? Math.round(
            (delaysHours.reduce((a, b) => a + b, 0) / delaysHours.length) * 10
          ) / 10
        : null;

    return {
      imf: {
        id: imf.id,
        raisonSociale: imf.raisonSociale,
        tauxCommission: imf.tauxCommission,
      },
      demandes: {
        total,
        soumises,
        enExamen,
        approuvees,
        refusees,
        decaissees,
      },
      impact: {
        /** Dossiers avec score NeoForma figé à la soumission */
        dossiersScores: withScore,
        montantDemandeTotalFcfa: amountsAll._sum.montantDemandeFcfa ?? 0,
        montantDecaisseFcfa: amountsDecaisse._sum.montantDemandeFcfa ?? 0,
        /** Délai moyen soumission → décision (h), proxy via updatedAt / décaissement */
        delaiInstructionMoyenHeures: avgDelayHours,
        delaiEchantillon: delaysHours.length,
        outcomes: {
          rembourses,
          defauts,
          enCours,
        },
      },
      commissions: {
        count: commissions._count,
        totalFcfa: commissions._sum.montantCommissionFcfa ?? 0,
      },
    };
  });

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

  /** Fiche risque d'un dossier (score figé + critères). */
  app.get("/applications/:id", async (request, reply) => {
    const imf = await resolvePartnerImf(app, request, reply);
    if (!imf) return;

    const { id } = request.params as { id: string };
    const row = await app.prisma.demandeCredit.findFirst({
      where: {
        id,
        OR: [{ imfId: imf.id }, { imfId: null }],
      },
      include: { snapshotScore: true },
    });
    if (!row) {
      return reply.status(404).send({
        error: "not_found",
        message: "Dossier introuvable",
      });
    }
    return toCredit(row);
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

  /**
   * Clôture solvabilité (label ML) : rembourse_ok | defaut.
   * À appeler quand le crédit est soldé ou en défaut.
   */
  app.post("/applications/:id/outcome", async (request, reply) => {
    const imf = await resolvePartnerImf(app, request, reply);
    if (!imf) return;

    const parsed = OutcomeSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Outcome invalide (rembourse_ok | defaut)",
        details: parsed.error.flatten(),
      });
    }
    const { id } = request.params as { id: string };
    try {
      const row = await credit.recordOutcome(id, parsed.data);
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
