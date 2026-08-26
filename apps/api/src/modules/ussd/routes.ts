/**
 * USSD — passerelle Africa's Talking (ou compatible).
 * POST /ussd/webhook — form-urlencoded AT ou JSON.
 * Menu : ventes, score, dettes, offre crédit, statut demande, KYC.
 */
import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import querystring from "node:querystring";

type UssdBody = {
  sessionId?: string;
  serviceCode?: string;
  phoneNumber?: string;
  phone?: string;
  text?: string;
};

async function findTravailleurByPhone(app: FastifyInstance, rawPhone: string) {
  const digits = rawPhone.replace(/\D/g, "");
  if (!digits) return null;
  const exact = await app.prisma.travailleur.findFirst({
    where: { telephone: rawPhone },
  });
  if (exact) return exact;

  const suffix = digits.slice(-8);
  const rows = await app.prisma.$queryRawUnsafe<Array<{ id: string }>>(
    `SELECT id FROM travailleurs WHERE regexp_replace(telephone, '\\D', '', 'g') LIKE $1 LIMIT 1`,
    `%${suffix}`
  );
  if (rows[0]) {
    return app.prisma.travailleur.findUnique({ where: { id: rows[0].id } });
  }
  return null;
}

function menuText(): string {
  return [
    "CON Bienvenue sur NeoForma",
    "1. Ventes du mois",
    "2. Mon NeoScore",
    "3. Mes dettes ouvertes",
    "4. Offre de credit",
    "5. Statut demande credit",
    "6. Statut KYC",
  ].join("\n");
}

function fmt(n: number): string {
  return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}

export const ussdRoutes: FastifyPluginAsync = async (app) => {
  app.addContentTypeParser(
    "application/x-www-form-urlencoded",
    { parseAs: "string" },
    (_req, body, done) => {
      try {
        done(null, querystring.parse(body as string));
      } catch (err) {
        done(err as Error, undefined);
      }
    }
  );

  app.post("/webhook", async (request, reply) => {
    reply.header("Content-Type", "text/plain; charset=utf-8");

    const body = (request.body ?? {}) as UssdBody;
    const phoneNumber = String(body.phoneNumber ?? body.phone ?? "").trim();
    const text = String(body.text ?? "").trim();

    if (!phoneNumber) {
      return reply.status(400).send("END Numéro manquant");
    }

    if (text === "") {
      return reply.send(menuText());
    }

    const steps = text.split("*").filter(Boolean);
    const choice = steps[steps.length - 1] ?? "";

    const travailleur = await findTravailleurByPhone(app, phoneNumber);
    if (!travailleur) {
      return reply.send("END Compte NeoForma introuvable pour ce numéro.");
    }

    switch (choice) {
      case "1": {
        const monthStart = new Date();
        monthStart.setDate(1);
        monthStart.setHours(0, 0, 0, 0);
        const sales = await app.prisma.operation.findMany({
          where: {
            travailleurId: travailleur.id,
            type: "vente",
            dateOperation: { gte: monthStart },
          },
          select: { montantFcfa: true },
        });
        const total = sales.reduce((s, o) => s + o.montantFcfa, 0);
        return reply.send(
          `END Ventes du mois : ${fmt(total)} FCFA (${sales.length} ope.)`
        );
      }
      case "2": {
        const { ScoringService } = await import("../scoring/service.js");
        const scoring = new ScoringService(app.prisma);
        const score = await scoring.getCurrent(travailleur.id);
        return reply.send(
          `END NeoScore : ${score.score}/100 (segment ${score.segment}) — ${
            score.eligible ? "eligible credit" : "non eligible"
          }`
        );
      }
      case "3": {
        const debts = await app.prisma.operation.findMany({
          where: {
            travailleurId: travailleur.id,
            type: "creance",
            statutCreance: { in: ["ouverte", "en_retard"] },
          },
          select: { montantFcfa: true, montantRegleFcfa: true },
        });
        const total = debts.reduce(
          (s, o) => s + Math.max(0, o.montantFcfa - (o.montantRegleFcfa ?? 0)),
          0
        );
        return reply.send(
          `END Dettes ouvertes : ${fmt(total)} FCFA (${debts.length})`
        );
      }
      case "4": {
        const offre = await app.prisma.offreCredit.findFirst({
          where: { travailleurId: travailleur.id },
          orderBy: { createdAt: "desc" },
        });
        if (!offre) {
          return reply.send(
            "END Aucune offre. Ouvrez l'app pour activer votre NeoScore."
          );
        }
        return reply.send(
          `END Offre indicative : ${fmt(offre.montantSuggereFcfa)} FCFA ` +
            `(min ${fmt(offre.montantMinFcfa)} - max ${fmt(offre.montantMaxFcfa)})`
        );
      }
      case "5": {
        const demande = await app.prisma.demandeCredit.findFirst({
          where: { travailleurId: travailleur.id },
          orderBy: { createdAt: "desc" },
        });
        if (!demande) {
          return reply.send("END Aucune demande de credit en cours.");
        }
        return reply.send(
          `END Demande ${demande.reference} : ${demande.statut}` +
            (demande.motifDecision ? ` — ${demande.motifDecision}` : "")
        );
      }
      case "6": {
        const kyc = travailleur.kycStatut ?? "non_verifie";
        const tip =
          kyc === "verifie"
            ? "Identite verifiee."
            : "Completez piece d'identite dans Profil (app).";
        return reply.send(`END KYC : ${kyc}. ${tip}`);
      }
      default:
        return reply.send("END Choix invalide. Rappelez pour le menu.");
    }
  });
};
