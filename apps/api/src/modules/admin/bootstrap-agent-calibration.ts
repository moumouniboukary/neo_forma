/**
 * Bootstrap DigiCoop : crée des dossiers agent synthétiques labellisés
 * puis lance le calibrage (utile avant d’avoir assez de vrais remboursements).
 */
import type { PrismaClient } from "@prisma/client";
import type { AgentScoreInput } from "@neoforma/shared";
import { AgentDossierService } from "./agent-dossiers.js";

function goodInput(i: number): AgentScoreInput {
  return {
    clientNom: `Bootstrap Bon ${i}`,
    clientTelephone: `+22670${String(100000 + i).slice(-6)}`,
    clientConnu: true,
    secteurActivite: "commerce",
    tailleMenage: 3 + (i % 3),
    incidentsPaiement: 0,
    regulariteDepots: 3 + (i % 2),
    ancienneteCompteMois: 12 + i,
    remboursementsAnterieurs: 2 + (i % 2),
    ancienneteActiviteAns: 3 + (i % 3),
    tontine: true,
    tontineAns: 2,
    nbGarants: 1 + (i % 2),
    ancienneteCoopAns: 1 + (i % 2),
    saisonnalite: "stable",
    actifTerrain: i % 2 === 0,
    actifBetail: false,
    actifMateriel: true,
    revenuMensuelFcfa: 180_000 + i * 2_000,
    chargesMensuellesFcfa: 40_000,
    montantDemandeFcfa: 70_000 + i * 1_000,
    dureeMois: 3,
  };
}

function badInput(i: number): AgentScoreInput {
  return {
    clientNom: `Bootstrap Defaut ${i}`,
    clientTelephone: `+22671${String(100000 + i).slice(-6)}`,
    clientConnu: true,
    secteurActivite: "commerce",
    tailleMenage: 6,
    incidentsPaiement: 2,
    regulariteDepots: 0,
    ancienneteCompteMois: 2,
    remboursementsAnterieurs: 0,
    ancienneteActiviteAns: 0,
    tontine: false,
    tontineAns: 0,
    nbGarants: 0,
    ancienneteCoopAns: 0,
    saisonnalite: "forte",
    actifTerrain: false,
    actifBetail: false,
    actifMateriel: false,
    revenuMensuelFcfa: 70_000,
    chargesMensuellesFcfa: 45_000,
    montantDemandeFcfa: 150_000,
    dureeMois: 3,
  };
}

export async function bootstrapAgentCalibration(
  prisma: PrismaClient,
  opts?: { notes?: string }
) {
  const agent = await prisma.travailleur.findFirst({
    orderBy: { createdAt: "asc" },
    select: { id: true },
  });
  if (!agent) {
    throw Object.assign(
      new Error("Aucun travailleur en base pour rattacher les dossiers bootstrap"),
      { statusCode: 400, code: "no_agent" }
    );
  }

  const existing = await prisma.agentDossier.count({
    where: { note: "bootstrap-calibration" },
  });
  if (existing < 25) {
    const rows = [];
    for (let i = 0; i < 15; i++) {
      const input = goodInput(i);
      const id = `bootstrap-good-${i}`;
      rows.push({
        id,
        clientMutationId: id,
        agentUserId: agent.id,
        clientNom: input.clientNom,
        clientTelephone: input.clientTelephone ?? null,
        inputJson: input,
        score: 720,
        recommendation: "recommande",
        chargeRate: 0.28,
        montantSoutenableFcfa: 100_000,
        echeanceEstimeeFcfa: 25_000,
        revenuMensuelFcfa: input.revenuMensuelFcfa,
        montantDemandeFcfa: input.montantDemandeFcfa,
        driversJson: [],
        resultJson: { score: 720, engine: "expert_scorecard" },
        note: "bootstrap-calibration",
        statut: "validee",
        outcome: "rembourse_ok",
        outcomeAt: new Date(),
        engine: "expert_scorecard",
      });
    }
    for (let i = 0; i < 10; i++) {
      const input = badInput(i);
      const id = `bootstrap-bad-${i}`;
      rows.push({
        id,
        clientMutationId: id,
        agentUserId: agent.id,
        clientNom: input.clientNom,
        clientTelephone: input.clientTelephone ?? null,
        inputJson: input,
        score: 480,
        recommendation: "a_reexaminer",
        chargeRate: 0.55,
        montantSoutenableFcfa: 20_000,
        echeanceEstimeeFcfa: 40_000,
        revenuMensuelFcfa: input.revenuMensuelFcfa,
        montantDemandeFcfa: input.montantDemandeFcfa,
        driversJson: [],
        resultJson: { score: 480, engine: "expert_scorecard" },
        note: "bootstrap-calibration",
        statut: "a_revoir",
        outcome: "defaut",
        outcomeAt: new Date(),
        engine: "expert_scorecard",
      });
    }
    for (const row of rows) {
      await prisma.agentDossier.upsert({
        where: { clientMutationId: row.clientMutationId },
        create: row,
        update: {
          outcome: row.outcome,
          outcomeAt: row.outcomeAt,
          inputJson: row.inputJson,
          note: row.note,
        },
      });
    }
  }

  const service = new AgentDossierService(prisma);
  return service.calibrateAndActivate({
    notes: opts?.notes ?? "Bootstrap synthétique DigiCoop (à remplacer par labels réels)",
  });
}
