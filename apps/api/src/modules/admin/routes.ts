/**
 * Admin agents — outils internes (terrain / ops / ML).
 * Auth : header X-Admin-Key = ADMIN_API_KEY.
 */
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { requireAdminKey } from "../../lib/admin-auth.js";
import { CreditService, isCreditError } from "../credit/service.js";
import { notifyOverdueCreances } from "../../lib/notifications.js";
import {
  isMlScoringEnabled,
  mlHealth,
  mlTrain,
} from "../../lib/ml-scoring.js";
import { config } from "../../config.js";
import { hashPartnerApiKey } from "../../lib/partner-keys.js";
import { enqueueOrRun } from "../../lib/jobs.js";
import { LedgerService, isLedgerError } from "../ledger/service.js";
import { CreateOperationSchema, CreateClientSchema } from "@neoforma/shared";
import { AgentDossierService } from "./agent-dossiers.js";
import { bootstrapAgentCalibration } from "./bootstrap-agent-calibration.js";

const RetrainSchema = z.object({
  nSynthetic: z.number().int().min(0).max(5000).optional().default(200),
});

const OutcomeSchema = z.object({
  outcome: z.enum(["rembourse_ok", "defaut"]),
  motif: z.string().max(500).optional(),
});

const AgentOutcomeSchema = z.object({
  outcome: z.enum(["rembourse_ok", "defaut", "en_cours"]),
  note: z.string().max(500).optional(),
});

const ApiKeySchema = z.object({
  apiKey: z.string().min(8).max(200),
});

const AssistSchema = z.object({
  phone: z.string().min(8).max(20),
  kind: z.enum(["create_operation", "create_client"]),
  payload: z.unknown(),
});

export const adminRoutes: FastifyPluginAsync = async (app) => {
  const credit = new CreditService(app.prisma);
  const ledger = new LedgerService(app.prisma);
  const agentDossiers = new AgentDossierService(app.prisma);

  app.addHook("preHandler", async (request, reply) => {
    if (!requireAdminKey(request, reply)) return reply;
  });

  /** Vue d'ensemble pour agents. */
  app.get("/stats", async () => {
    const [
      travailleurs,
      actifs,
      operations,
      creancesOuvertes,
      demandes,
      kobo,
      commissionsDue,
      labelsMl,
      ml,
    ] = await Promise.all([
      app.prisma.travailleur.count(),
      app.prisma.travailleur.count({ where: { statutCompte: "actif" } }),
      app.prisma.operation.count(),
      app.prisma.operation.count({
        where: {
          type: "creance",
          statutCreance: { in: ["ouverte", "en_retard"] },
        },
      }),
      app.prisma.demandeCredit.count(),
      app.prisma.koboSubmission.count(),
      app.prisma.commission.count({ where: { statut: "due" } }),
      app.prisma.demandeCredit.count({
        where: { outcome: { in: ["rembourse_ok", "defaut"] } },
      }),
      mlHealth(),
    ]);

    return {
      travailleurs: { total: travailleurs, actifs },
      operations,
      creancesOuvertes,
      demandesCredit: demandes,
      koboSubmissions: kobo,
      commissionsDue,
      ml: {
        enabled: isMlScoringEnabled(),
        url: config.scoringMlUrl || null,
        health: ml,
        labeledOutcomes: labelsMl,
      },
      time: new Date().toISOString(),
    };
  });

  /** Recherche travailleur par téléphone. */
  app.get("/travailleurs", async (request) => {
    const q = request.query as { phone?: string; limit?: string };
    const limit = Math.min(Number(q.limit ?? 50), 200);
    if (q.phone) {
      const row = await app.prisma.travailleur.findUnique({
        where: { telephone: q.phone },
        select: {
          id: true,
          telephone: true,
          nomAffiche: true,
          statutCompte: true,
          onboardingTermine: true,
          createdAt: true,
        },
      });
      return { items: row ? [row] : [] };
    }
    const items = await app.prisma.travailleur.findMany({
      orderBy: { createdAt: "desc" },
      take: limit,
      select: {
        id: true,
        telephone: true,
        nomAffiche: true,
        statutCompte: true,
        onboardingTermine: true,
        createdAt: true,
      },
    });
    return { items };
  });

  /** Dernières demandes crédit (suivi agents). */
  app.get("/credit-applications", async (request) => {
    const q = request.query as { statut?: string; limit?: string };
    const items = await app.prisma.demandeCredit.findMany({
      where: q.statut ? { statut: q.statut } : undefined,
      orderBy: { createdAt: "desc" },
      take: Math.min(Number(q.limit ?? 50), 200),
      select: {
        id: true,
        reference: true,
        montantDemandeFcfa: true,
        statut: true,
        outcome: true,
        usage: true,
        dateSoumission: true,
        travailleurId: true,
      },
    });
    return { items };
  });

  /** Enregistrer un outcome solvabilité (agents). */
  app.post("/credit-applications/:id/outcome", async (request, reply) => {
    const parsed = OutcomeSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Outcome invalide",
        details: parsed.error.flatten(),
      });
    }
    const { id } = request.params as { id: string };
    try {
      const row = await credit.recordOutcome(id, parsed.data);
      return {
        id: row.id,
        reference: row.reference,
        statut: row.statut,
        outcome: row.outcome,
      };
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

  /** Déclenche la génération de notifications pour créances en retard (cron manuel). */
  app.post("/notify-overdue", async () => {
    const count = await notifyOverdueCreances(app.prisma);
    return { ok: true, notified: count, time: new Date().toISOString() };
  });

  /**
   * Enfile (ou exécute en direct sans worker) la relance des créances en retard.
   * À brancher sur un cron externe (Render Cron Job / GitHub Actions).
   */
  app.post("/jobs/overdue-notify", async () => {
    const mode = await enqueueOrRun("overdue_notify", {}, async () => {
      await notifyOverdueCreances(app.prisma);
    });
    return { ok: true, mode, time: new Date().toISOString() };
  });

  /** Définit / fait tourner la clé API d'une IMF (hash seul persisté). */
  app.post("/imf/:id/api-key", async (request, reply) => {
    const parsed = ApiKeySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Clé API invalide",
        details: parsed.error.flatten(),
      });
    }
    const { id } = request.params as { id: string };
    const imf = await app.prisma.imf.findUnique({ where: { id } });
    if (!imf) {
      return reply.status(404).send({
        error: "not_found",
        message: "IMF introuvable",
      });
    }
    const updated = await app.prisma.imf.update({
      where: { id },
      data: {
        apiKeyHash: hashPartnerApiKey(parsed.data.apiKey),
        apiKey: null,
      },
      select: { id: true, raisonSociale: true, apiKeyHash: true },
    });
    return { ok: true, imf: updated };
  });

  /**
   * Assistance agent — agit à la place d'un travailleur (terrain, USSD, guichet).
   * Utilisé par le module USSD et les agents terrain sans app installée.
   */
  app.post("/assist", async (request, reply) => {
    const parsed = AssistSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Requête assist invalide",
        details: parsed.error.flatten(),
      });
    }
    const { phone, kind, payload } = parsed.data;
    const travailleur = await app.prisma.travailleur.findUnique({
      where: { telephone: phone },
    });
    if (!travailleur) {
      return reply.status(404).send({
        error: "not_found",
        message: "Travailleur introuvable pour ce numéro",
      });
    }

    try {
      if (kind === "create_operation") {
        const body = CreateOperationSchema.safeParse(payload);
        if (!body.success) {
          return reply.status(400).send({
            error: "validation",
            message: "Opération invalide",
            details: body.error.flatten(),
          });
        }
        const op = await ledger.createOperation(travailleur.id, body.data);
        return reply.status(201).send({ ok: true, kind, result: op });
      }

      const body = CreateClientSchema.safeParse(payload);
      if (!body.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Client invalide",
          details: body.error.flatten(),
        });
      }
      const client = await ledger.createClient(travailleur.id, body.data);
      return reply.status(201).send({ ok: true, kind, result: client });
    } catch (err) {
      if (isLedgerError(err)) {
        return reply.status(err.statusCode).send({
          error: err.code,
          message: err.message,
        });
      }
      throw err;
    }
  });

  /** Dataset labellisé pour le ML. */
  app.get("/ml/dataset", async (request) => {
    const q = request.query as { limit?: string };
    const samples = await credit.exportMlTrainingSamples(
      Number(q.limit ?? 2000)
    );
    return {
      count: samples.length,
      samples,
    };
  });

  /**
   * Ré-entraîne le modèle ML avec les labels réels (+ synthétique).
   * Enregistre un MlModelRun.
   */
  app.post("/ml/retrain", async (request, reply) => {
    if (!isMlScoringEnabled()) {
      return reply.status(503).send({
        error: "ml_disabled",
        message: "SCORING_ML_URL non configurée",
      });
    }
    const parsed = RetrainSchema.safeParse(request.body ?? {});
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Body invalide",
        details: parsed.error.flatten(),
      });
    }

    const samples = await credit.exportMlTrainingSamples(5000);
    const trainPayload = samples.map((s) => ({
      features: s.features as never,
      outcome: s.outcome,
      default: s.default,
    }));

    const result = await mlTrain({
      samples: trainPayload,
      nSynthetic: parsed.data.nSynthetic,
    });
    if (!result) {
      return reply.status(502).send({
        error: "ml_train_failed",
        message: "Échec appel service ML /train",
      });
    }

    const version = String(result.version ?? `run-${Date.now()}`);
    await app.prisma.mlModelRun.updateMany({ data: { active: false } });
    const run = await app.prisma.mlModelRun.create({
      data: {
        version,
        nSamples: Number(result.nSamples ?? 0),
        nDefaults: Number(result.nDefaults ?? 0),
        auc: typeof result.auc === "number" ? result.auc : null,
        source: String(result.source ?? "mixed"),
        notes: `Retrain admin — ${samples.length} labels réels`,
        active: true,
      },
    });

    return {
      ok: true,
      labeledUsed: samples.length,
      ml: result,
      run,
    };
  });

  /** Historique des entraînements. */
  app.get("/ml/runs", async () => {
    const items = await app.prisma.mlModelRun.findMany({
      orderBy: { trainedAt: "desc" },
      take: 50,
    });
    return { items };
  });

  // ——— DigiCoop / TeriyaScore : labels + recalibrage scorecard ———

  /** Liste des dossiers agent (pour labelliser les remboursements). */
  app.get("/agent-dossiers", async (request) => {
    const q = request.query as { outcome?: string; limit?: string };
    const items = await agentDossiers.list({
      outcome: q.outcome,
      limit: Number(q.limit ?? 100),
    });
    return { items, count: items.length };
  });

  /** Pose un label rembourse_ok / defaut / en_cours. */
  app.patch("/agent-dossiers/:id/outcome", async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = AgentOutcomeSchema.safeParse(request.body ?? {});
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Body invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      const row = await agentDossiers.setOutcome(
        id,
        parsed.data.outcome,
        parsed.data.note
      );
      return { ok: true, dossier: row };
    } catch (err) {
      const e = err as { statusCode?: number; code?: string; message?: string };
      if (e.statusCode === 404) {
        return reply.status(404).send({
          error: e.code ?? "not_found",
          message: e.message ?? "Dossier introuvable",
        });
      }
      throw err;
    }
  });

  /** Dataset labellisé pour calibrage DigiCoop. */
  app.get("/agent-score/dataset", async (request) => {
    const q = request.query as { limit?: string };
    const samples = await agentDossiers.exportLabeledSamples(
      Number(q.limit ?? 2000)
    );
    return {
      count: samples.length,
      nDefaults: samples.filter((s) => s.outcome === "defaut").length,
      nGoods: samples.filter((s) => s.outcome === "rembourse_ok").length,
      samples,
    };
  });

  /** Calibration active (poids statistiques) ou null = expert. */
  app.get("/agent-score/calibration", async () => {
    const calibration = await agentDossiers.getActiveCalibration();
    return {
      active: Boolean(calibration),
      engine: calibration?.engine ?? "expert_scorecard",
      calibration,
    };
  });

  /**
   * Recalibre le scorecard DigiCoop (logistique → poids) et active la version.
   * Min. 20 labels dont ≥3 rembourse_ok et ≥3 defaut.
   */
  app.post("/agent-score/calibrate", async (request, reply) => {
    const body = z
      .object({ notes: z.string().max(500).optional() })
      .safeParse(request.body ?? {});
    if (!body.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Body invalide",
        details: body.error.flatten(),
      });
    }
    try {
      const result = await agentDossiers.calibrateAndActivate({
        notes: body.data.notes,
      });
      return { ok: true, ...result };
    } catch (err) {
      const message = err instanceof Error ? err.message : "Calibrage échoué";
      return reply.status(400).send({
        error: "calibration_failed",
        message,
      });
    }
  });

  /**
   * Seed synthétique (15 bons / 10 défauts) + calibrage.
   * À remplacer ensuite par de vrais labels DigiCoop.
   */
  app.post("/agent-score/bootstrap", async (request, reply) => {
    const body = z
      .object({ notes: z.string().max(500).optional() })
      .safeParse(request.body ?? {});
    if (!body.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Body invalide",
        details: body.error.flatten(),
      });
    }
    try {
      const result = await bootstrapAgentCalibration(app.prisma, {
        notes: body.data.notes,
      });
      return { ok: true, bootstrap: true, ...result };
    } catch (err) {
      const e = err as { statusCode?: number; code?: string; message?: string };
      const message = e.message ?? "Bootstrap échoué";
      return reply.status(e.statusCode ?? 400).send({
        error: e.code ?? "bootstrap_failed",
        message,
      });
    }
  });
};
