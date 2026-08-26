import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  assignSegment,
  assessDataQuality,
  assessRepaymentCapacity,
  buildOfferAmount,
  computeCriteria,
  computeNeoScore,
  computeScore,
  ELIGIBILITY_THRESHOLD,
  isEligible,
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
  expensesLast30Fcfa: 40_000,
  monthlyFixedChargesFcfa: 15_000,
  tontineCotisations30Fcfa: 0,
  declaredCaMidpointFcfa: 22_500,
  salesVsDeclaredRatio: 150_000 / (22_500 * 30),
  activeWeeksLast30: 4,
  saisonnalite: "stable",
  garantieSolidaire: false,
  ...over,
});

describe("@neoforma/neoscore", () => {
  it("calcule un score 0–100 déterministe", () => {
    const criteria = computeCriteria(baseFeatures());
    const score = computeScore(criteria);
    assert.ok(score >= 0 && score <= 100);
    assert.equal(computeScore(criteria), score);
  });

  it(`éligibilité au seuil ${ELIGIBILITY_THRESHOLD} + activité + capacité`, () => {
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
        activeWeeksLast30: 4,
        salesVsDeclaredRatio: 1,
        monthlyFixedChargesFcfa: 10_000,
      })
    );
    assert.equal(high.eligible, high.score >= ELIGIBILITY_THRESHOLD);
    assert.equal(high.threshold, 50);
    assert.ok(high.score >= ELIGIBILITY_THRESHOLD);
    assert.ok(high.dataQuality?.minActivityMet);
    assert.ok((high.repaymentCapacity?.maxPrincipalFcfa ?? 0) >= 50_000);

    const low = computeNeoScore(
      baseFeatures({
        opsLast30Days: 0,
        activeWeeksLast30: 0,
        salesLast30Fcfa: 0,
        caJour: 1,
        anciennete: 1,
        impayes: 4,
        overdueDebtsCount: 4,
        openDebtsFcfa: 200_000,
        mobileMoney: 0,
        monthlyFixedChargesFcfa: 200_000,
      })
    );
    assert.equal(low.eligible, false);
    assert.deepEqual(buildOfferAmount(low.score, baseFeatures({
      opsLast30Days: 0,
      activeWeeksLast30: 0,
      salesLast30Fcfa: 0,
      monthlyFixedChargesFcfa: 200_000,
    })), {
      minFcfa: 0,
      maxFcfa: 0,
      suggestedFcfa: 0,
    });
  });

  it("refuse l'éligibilité si activité insuffisante malgré score élevé", () => {
    const f = baseFeatures({ opsLast30Days: 2, activeWeeksLast30: 1 });
    const criteria = computeCriteria(f);
    const score = computeScore(criteria);
    const quality = assessDataQuality(f);
    const capacity = assessRepaymentCapacity(f);
    assert.equal(isEligible(score, f, capacity, quality), false);
    const result = computeNeoScore(f);
    assert.equal(result.eligible, false);
    assert.ok(result.dataQuality?.warnings.some((w) => w.includes("Activité insuffisante")));
  });

  it("refuse l'éligibilité si trop d'impayés / créances en retard", () => {
    const f = baseFeatures({
      opsLast30Days: 20,
      activeWeeksLast30: 5,
      salesLast30Fcfa: 400_000,
      overdueDebtsCount: 2,
      impayes: 2,
      openDebtsFcfa: 80_000,
    });
    const result = computeNeoScore(f);
    assert.ok(result.score >= ELIGIBILITY_THRESHOLD);
    assert.equal(result.eligible, false);
  });

  it("pénalise l'écart CA déclaré / cahier", () => {
    const coherent = computeScore(
      computeCriteria(baseFeatures({ salesVsDeclaredRatio: 1, salesLast30Fcfa: 675_000 }))
    );
    const incoherent = computeScore(
      computeCriteria(
        baseFeatures({
          caJour: 1,
          declaredCaMidpointFcfa: 2_500,
          salesLast30Fcfa: 500_000,
          salesVsDeclaredRatio: 500_000 / (2_500 * 30),
        })
      )
    );
    assert.ok(coherent >= incoherent);
    const quality = assessDataQuality(
      baseFeatures({
        caJour: 1,
        declaredCaMidpointFcfa: 2_500,
        salesLast30Fcfa: 500_000,
        salesVsDeclaredRatio: 500_000 / (2_500 * 30),
      })
    );
    assert.equal(quality.declaredVsActualOk, false);
  });

  it("capacité : priorise le cahier et la marge nette (pas le CA déclaré)", () => {
    const inflatedDeclared = assessRepaymentCapacity(
      baseFeatures({
        salesLast30Fcfa: 300_000,
        expensesLast30Fcfa: 100_000,
        declaredCaMidpointFcfa: 80_000,
        salesVsDeclaredRatio: 300_000 / (80_000 * 30),
        monthlyFixedChargesFcfa: 20_000,
        saisonnalite: "stable",
      })
    );
    /** Net = 300k − 100k − 20k = 180k (pas max(2.4M, 300k)). */
    assert.equal(inflatedDeclared.estimatedMonthlyRevenueFcfa, 180_000);

    const highCogs = assessRepaymentCapacity(
      baseFeatures({
        salesLast30Fcfa: 500_000,
        expensesLast30Fcfa: 350_000,
        monthlyFixedChargesFcfa: 30_000,
        tontineCotisations30Fcfa: 10_000,
        saisonnalite: "forte",
      })
    );
    /** (500k − 350k) × 0.85 − 40k = 87_500 */
    assert.equal(highCogs.estimatedMonthlyRevenueFcfa, 87_500);
  });

  it("intègre la marge (ventes − dépenses) dans le volume", () => {
    const withMargin = computeScore(
      computeCriteria(baseFeatures({ expensesLast30Fcfa: 20_000 }))
    );
    const negativeMargin = computeScore(
      computeCriteria(baseFeatures({ expensesLast30Fcfa: 200_000 }))
    );
    assert.ok(withMargin >= negativeMargin);
  });

  it("plafonne l'offre par la capacité de remboursement", () => {
    const rich = buildOfferAmount(
      80,
      baseFeatures({
        salesLast30Fcfa: 2_000_000,
        expensesLast30Fcfa: 600_000,
        salesVsDeclaredRatio: 2_000_000 / (22_500 * 30),
        monthlyFixedChargesFcfa: 0,
        opsLast30Days: 15,
        activeWeeksLast30: 4,
      })
    );
    const poor = buildOfferAmount(
      80,
      baseFeatures({
        caJour: 1,
        declaredCaMidpointFcfa: 2_500,
        salesLast30Fcfa: 120_000,
        expensesLast30Fcfa: 40_000,
        salesVsDeclaredRatio: 120_000 / (2_500 * 30),
        monthlyFixedChargesFcfa: 25_000,
        opsLast30Days: 10,
        activeWeeksLast30: 4,
      })
    );
    assert.ok(rich.maxFcfa > 0);
    assert.ok(poor.maxFcfa < rich.maxFcfa);
    assert.ok(poor.maxFcfa <= 500_000);
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
    assert.equal(
      assignSegment(
        70,
        baseFeatures({ anciennete: 2, impayes: 0, opsLast30Days: 10 })
      ),
      "B"
    );
  });

  it("relève le segment avec garantie solidaire (hors junior)", () => {
    assert.equal(
      assignSegment(66, baseFeatures({ garantieSolidaire: true, impayes: 0, anciennete: 3 })),
      "A"
    );
    assert.equal(
      assignSegment(
        70,
        baseFeatures({
          garantieSolidaire: true,
          impayes: 0,
          anciennete: 2,
          opsLast30Days: 10,
        })
      ),
      "B"
    );
  });

  it("creditHist améliore le score ; partCredit (ventes à crédit) le dégrade", () => {
    const base = computeScore(computeCriteria(baseFeatures({ partCredit: 1, creditHist: 0 })));
    const withHist = computeScore(
      computeCriteria(baseFeatures({ partCredit: 1, creditHist: 2 }))
    );
    const highCreditSales = computeScore(
      computeCriteria(baseFeatures({ partCredit: 4, creditHist: 0 }))
    );
    assert.ok(withHist >= base);
    assert.ok(highCreditSales <= base);
  });

  it("offre bornée pour score éligible", () => {
    const offer = buildOfferAmount(
      70,
      baseFeatures({
        salesLast30Fcfa: 400_000,
        expensesLast30Fcfa: 120_000,
        monthlyFixedChargesFcfa: 15_000,
        opsLast30Days: 12,
        activeWeeksLast30: 4,
      })
    );
    assert.equal(offer.minFcfa, 50_000);
    assert.ok(offer.maxFcfa >= offer.minFcfa);
    assert.ok(offer.maxFcfa <= 500_000);
    assert.ok(offer.suggestedFcfa >= offer.minFcfa);
    assert.ok(offer.suggestedFcfa <= offer.maxFcfa);
  });
});
