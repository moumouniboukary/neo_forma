import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  assignSegment,
  buildOfferAmount,
  computeCriteria,
  computeNeoScore,
  computeScore,
  ELIGIBILITY_THRESHOLD,
} from "../src/index.js";
import type { ScoreFeatures } from "@neoforma/shared";

const baseFeatures = (over: Partial<ScoreFeatures> = {}): ScoreFeatures => ({
  anciennete: 3,
  caJour: 3,
  partCredit: 1,
  impayes: 0,
  tontine: false,
  tontineAns: 0,
  mobileMoney: 1,
  telephone: 2,
  compte: 0,
  creditHist: 0,
  opsLast30Days: 10,
  salesLast30Fcfa: 150_000,
  openDebtsFcfa: 0,
  overdueDebtsCount: 0,
  ...over,
});

describe("@neoforma/neoscore", () => {
  it("calcule un score 0–100 déterministe", () => {
    const criteria = computeCriteria(baseFeatures());
    const score = computeScore(criteria);
    assert.ok(score >= 0 && score <= 100);
    assert.equal(computeScore(criteria), score);
  });

  it(`éligibilité au seuil ${ELIGIBILITY_THRESHOLD}`, () => {
    const high = computeNeoScore(
      baseFeatures({
        opsLast30Days: 20,
        salesLast30Fcfa: 400_000,
        caJour: 5,
        anciennete: 5,
        tontine: true,
        tontineAns: 4,
        mobileMoney: 3,
        compte: 2,
        creditHist: 2,
      })
    );
    assert.equal(high.eligible, high.score >= ELIGIBILITY_THRESHOLD);
    assert.equal(high.threshold, 50);
    assert.ok(high.score >= ELIGIBILITY_THRESHOLD);

    const low = computeNeoScore(
      baseFeatures({
        opsLast30Days: 0,
        salesLast30Fcfa: 0,
        caJour: 1,
        anciennete: 1,
        impayes: 4,
        overdueDebtsCount: 4,
        openDebtsFcfa: 200_000,
        mobileMoney: 0,
      })
    );
    assert.equal(low.eligible, false);
    assert.deepEqual(buildOfferAmount(low.score), {
      minFcfa: 0,
      maxFcfa: 0,
      suggestedFcfa: 0,
    });
  });

  it("ne fabrique pas d'historique synthétique", () => {
    const empty = computeNeoScore(baseFeatures(), []);
    assert.deepEqual(empty.history, []);

    const hist = [{ month: "juillet 2026", score: 62 }];
    const withHist = computeNeoScore(baseFeatures(), hist);
    assert.deepEqual(withHist.history, hist);
  });

  it("assigne les segments A–D", () => {
    assert.equal(assignSegment(30, baseFeatures({ opsLast30Days: 2 })), "D");
    assert.equal(assignSegment(50, baseFeatures({ anciennete: 1 })), "C");
    assert.equal(
      assignSegment(70, baseFeatures({ impayes: 0, opsLast30Days: 15 })),
      "A"
    );
    assert.equal(assignSegment(60, baseFeatures()), "B");
  });

  it("partCredit et creditHist influencent le score", () => {
    const weak = computeScore(computeCriteria(baseFeatures({ partCredit: 1, creditHist: 0 })));
    const strong = computeScore(
      computeCriteria(baseFeatures({ partCredit: 4, creditHist: 2 }))
    );
    assert.ok(strong >= weak);
  });

  it("offre bornée pour score éligible", () => {
    const offer = buildOfferAmount(70);
    assert.equal(offer.minFcfa, 50_000);
    assert.ok(offer.maxFcfa >= offer.minFcfa);
    assert.ok(offer.maxFcfa <= 500_000);
    assert.ok(offer.suggestedFcfa >= offer.minFcfa);
    assert.ok(offer.suggestedFcfa <= offer.maxFcfa);
  });
});
