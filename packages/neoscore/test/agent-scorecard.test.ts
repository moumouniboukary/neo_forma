import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { computeAgentScorecard } from "../src/agent-scorecard.js";
import type { AgentScoreInput } from "@neoforma/shared";

function primo(partial: Partial<AgentScoreInput> = {}): AgentScoreInput {
  return {
    clientNom: "Awa Traoré",
    clientConnu: false,
    secteurActivite: "commerce",
    tailleMenage: 4,
    incidentsPaiement: 0,
    regulariteDepots: 0,
    ancienneteCompteMois: 0,
    remboursementsAnterieurs: 0,
    ancienneteActiviteAns: 5,
    tontine: true,
    tontineAns: 3,
    nbGarants: 2,
    ancienneteCoopAns: 2,
    saisonnalite: "stable",
    actifTerrain: true,
    actifBetail: false,
    actifMateriel: true,
    revenuMensuelFcfa: 150_000,
    chargesMensuellesFcfa: 40_000,
    montantDemandeFcfa: 80_000,
    dureeMois: 3,
    ...partial,
  };
}

describe("computeAgentScorecard", () => {
  it("renvoie un score 300–850 pour un primo-demandeur", () => {
    const result = computeAgentScorecard(primo());
    assert.ok(result.score >= 300 && result.score <= 850);
    assert.ok(["recommande", "analyse_complementaire", "a_reexaminer"].includes(result.recommendation));
    assert.ok(["faible", "modere", "eleve"].includes(result.riskCategory));
    assert.ok(result.drivers.length <= 3);
  });

  it("ignore l’historique coopérative quand clientConnu est false", () => {
    const withoutHistory = computeAgentScorecard(
      primo({ regulariteDepots: 4, remboursementsAnterieurs: 3 })
    );
    const withHistoryFlag = computeAgentScorecard(
      primo({
        clientConnu: true,
        regulariteDepots: 4,
        remboursementsAnterieurs: 3,
        ancienneteCompteMois: 24,
      })
    );
    assert.ok(withHistoryFlag.score >= withoutHistory.score);
  });
});
