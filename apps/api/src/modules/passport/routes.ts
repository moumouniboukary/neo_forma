/**
 * Passeport financier — résumé consolidé du travailleur (profil, score,
 * ventes 30j, dettes ouvertes, stock, tontines).
 * GET /me/passport (JSON) et GET /me/passport.txt (texte, pour SMS/USSD/impression).
 */
import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import { toUserProfile } from "../../lib/mappers.js";
import { ProfileService } from "../profile/service.js";
import { ScoringService } from "../scoring/service.js";

async function buildPassport(app: FastifyInstance, travailleurId: string) {
  const profiles = new ProfileService(app.prisma);
  const scoring = new ScoringService(app.prisma);

  const since30 = new Date();
  since30.setDate(since30.getDate() - 30);

  const [me, score, sales30, openDebts, articles, tontines] = await Promise.all([
    profiles.getMe(travailleurId),
    scoring.getCurrent(travailleurId),
    app.prisma.operation.findMany({
      where: {
        travailleurId,
        type: "vente",
        dateOperation: { gte: since30 },
      },
      select: { montantFcfa: true },
    }),
    app.prisma.operation.findMany({
      where: {
        travailleurId,
        type: "creance",
        statutCreance: { in: ["ouverte", "en_retard"] },
      },
      select: { montantFcfa: true, montantRegleFcfa: true, statutCreance: true },
    }),
    app.prisma.articleStock.findMany({
      where: { travailleurId },
      select: { nom: true, quantite: true, unite: true, prixUnitaireFcfa: true },
      orderBy: { nom: "asc" },
    }),
    app.prisma.tontine.findMany({
      where: { travailleurId, actif: true },
      include: {
        cotisations: { orderBy: { datePaiement: "desc" }, take: 100 },
      },
    }),
  ]);

  const salesLast30Fcfa = sales30.reduce((s, o) => s + o.montantFcfa, 0);
  const openDebtsFcfa = openDebts.reduce(
    (s, o) => s + Math.max(0, o.montantFcfa - (o.montantRegleFcfa ?? 0)),
    0
  );
  const overdueCount = openDebts.filter((o) => o.statutCreance === "en_retard").length;

  const stockValueFcfa = articles.reduce(
    (s, a) => s + a.quantite * (a.prixUnitaireFcfa ?? 0),
    0
  );

  const tontinesSummary = tontines.map((t) => ({
    nom: t.nom,
    cotisationFcfa: t.cotisationFcfa,
    frequence: t.frequence,
    totalCotiseFcfa: t.cotisations.reduce((s, c) => s + c.montantFcfa, 0),
  }));

  return {
    profile: toUserProfile(me),
    score: {
      valeur: score.score,
      segment: score.segment,
      eligible: score.eligible,
    },
    sales30d: {
      totalFcfa: salesLast30Fcfa,
      count: sales30.length,
    },
    openDebts: {
      totalFcfa: openDebtsFcfa,
      count: openDebts.length,
      overdueCount,
    },
    stock: {
      articleCount: articles.length,
      valueFcfa: stockValueFcfa,
      items: articles.map((a) => ({
        nom: a.nom,
        quantite: a.quantite,
        unite: a.unite,
      })),
    },
    tontines: tontinesSummary,
    generatedAt: new Date().toISOString(),
  };
}

function toPassportText(p: Awaited<ReturnType<typeof buildPassport>>): string {
  const lines = [
    `NeoForma — Passeport financier`,
    `Nom : ${p.profile.displayName}`,
    `Téléphone : ${p.profile.phone}`,
    ``,
    `NeoScore : ${p.score.valeur}/100 (segment ${p.score.segment}) — ${
      p.score.eligible ? "éligible crédit" : "non éligible"
    }`,
    ``,
    `Ventes (30j) : ${p.sales30d.totalFcfa} FCFA (${p.sales30d.count} opérations)`,
    `Dettes ouvertes : ${p.openDebts.totalFcfa} FCFA (${p.openDebts.count}, dont ${p.openDebts.overdueCount} en retard)`,
    `Stock : ${p.stock.articleCount} article(s), valeur estimée ${p.stock.valueFcfa} FCFA`,
  ];
  if (p.tontines.length > 0) {
    lines.push(``, `Tontines :`);
    for (const t of p.tontines) {
      lines.push(`- ${t.nom} : ${t.cotisationFcfa} FCFA/${t.frequence} — total cotisé ${t.totalCotiseFcfa} FCFA`);
    }
  }
  lines.push(``, `Généré le ${new Date(p.generatedAt).toLocaleString("fr-FR")}`);
  return lines.join("\n");
}

export const passportRoutes: FastifyPluginAsync = async (app) => {
  app.get("/passport", { preHandler: [app.authenticate] }, async (request) => {
    return buildPassport(app, request.user.sub);
  });

  app.get(
    "/passport.txt",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const passport = await buildPassport(app, request.user.sub);
      reply.header("Content-Type", "text/plain; charset=utf-8");
      return toPassportText(passport);
    }
  );
};
