import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  calibrateAgentScorecard,
  computeAgentScorecard,
  type AgentLabeledSample,
} from "../src/index.js";
import type { AgentScoreInput } from "@neoforma/shared";

function base(partial: Partial<AgentScoreInput> = {}): AgentScoreInput {
  return {
    clientNom: "Test",
    clientConnu: true,
    secteurActivite: "commerce",
    tailleMenage: 3,
    incidentsPaiement: 0,
    regulariteDepots: 3,
    ancienneteCompteMois: 18,
    remboursementsAnterieurs: 2,
    ancienneteActiviteAns: 4,
    tontine: true,
    tontineAns: 2,
    nbGarants: 2,
    ancienneteCoopAns: 2,
    saisonnalite: "stable",
    actifTerrain: true,
    actifBetail: false,
    actifMateriel: true,
    revenuMensuelFcfa: 200_000,
    chargesMensuellesFcfa: 40_000,
    montantDemandeFcfa: 80_000,
    dureeMois: 3,
    ...partial,
  };
}

function makeSamples(): AgentLabeledSample[] {
  const samples: AgentLabeledSample[] = [];
  // Bons profils
  for (let i = 0; i < 15; i++) {
    samples.push({
      outcome: "rembourse_ok",
      input: base({
        regulariteDepots: 4,
        remboursementsAnterieurs: 3,
        incidentsPaiement: 0,
        ancienneteActiviteAns: 5,
        revenuMensuelFcfa: 220_000 + i * 1000,
        montantDemandeFcfa: 60_000,
      }),
    });
  }
  // Défauts
  for (let i = 0; i < 10; i++) {
    samples.push({
      outcome: "defaut",
      input: base({
        regulariteDepots: 0,
        remboursementsAnterieurs: 0,
        incidentsPaiement: 2,
        ancienneteActiviteAns: 0,
        tontine: false,
        nbGarants: 0,
        revenuMensuelFcfa: 80_000,
        chargesMensuellesFcfa: 50_000,
        montantDemandeFcfa: 150_000,
      }),
    });
  }
  return samples;
}

describe("calibrateAgentScorecard", () => {
  it("produit une calibration utilisable par computeAgentScorecard", () => {
    const calibration = calibrateAgentScorecard(makeSamples());
    assert.equal(calibration.engine, "calibrated_scorecard");
    assert.ok(calibration.nSamples >= 20);
    assert.ok(calibration.nDefaults >= 3);
    assert.ok(Object.keys(calibration.partWeights).length > 0);
    assert.ok(calibration.recommendMin > calibration.analyseMin);

    const expert = computeAgentScorecard(base());
    const calibrated = computeAgentScorecard(base(), new Date(), calibration);
    assert.equal(calibrated.engine, "calibrated_scorecard");
    assert.equal(calibrated.modelVersion, calibration.version);
    assert.ok(calibrated.score >= 300 && calibrated.score <= 850);
    assert.ok(expert.engine === "expert_scorecard");
  });

  it("refuse un jeu trop petit", () => {
    assert.throws(() =>
      calibrateAgentScorecard([
        { outcome: "rembourse_ok", input: base() },
        { outcome: "defaut", input: base({ incidentsPaiement: 2 }) },
      ])
    );
  });
});
