import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { featuresFromProfilAndOps } from "../src/modules/scoring/features.js";
import type { Operation, ProfilActivite } from "@prisma/client";

function op(partial: Partial<Operation> & Pick<Operation, "type" | "montantFcfa">): Operation {
  const now = new Date();
  return {
    id: "op",
    travailleurId: "u1",
    libelle: null,
    dateOperation: now,
    statutSync: "synchronisee",
    identifiantIdempotence: null,
    clientId: null,
    natureStock: null,
    categorieDepense: null,
    echeance: null,
    dateReglement: null,
    statutCreance: null,
    createdAt: now,
    updatedAt: now,
    ...partial,
  };
}

describe("featuresFromProfilAndOps", () => {
  it("dérive partCredit, creditHist, tontineAns et telephone", () => {
    const profil = {
      participationTontine: true,
      cotisationTontine: 20_000,
      ancienneteActivite: "6_10",
      caJournalierEstime: "30_60k",
      usageMobileMoney: "quotidien",
      statutCompteBancaire: "oui_actif",
    } as ProfilActivite;

    const features = featuresFromProfilAndOps({
      profil,
      hasSmartphone: true,
      demandes: [{ statut: "approuvee" }],
      ops: [
        op({ type: "vente", montantFcfa: 10_000 }),
        op({ type: "creance", montantFcfa: 30_000, statutCreance: "ouverte" }),
        op({ type: "creance", montantFcfa: 5_000, statutCreance: "reglee" }),
      ],
    });

    assert.equal(features.telephone, 2);
    assert.equal(features.creditHist, 2);
    assert.equal(features.tontine, true);
    assert.equal(features.tontineAns, 4);
    assert.equal(features.partCredit, 4); // 30k / 40k
    assert.equal(features.anciennete, 4);
    assert.equal(features.caJour, 4);
    assert.equal(features.mobileMoney, 3);
    assert.equal(features.compte, 2);
    assert.equal(features.expensesLast30Fcfa, 0);
    assert.ok(features.declaredCaMidpointFcfa > 0);
  });

  it("agrège dépenses, semaines actives et profil solvabilité", () => {
    const since = new Date();
    since.setDate(since.getDate() - 5);
    const profil = {
      chargesFixesMensuelles: 20_000,
      saisonnalite: "forte",
      garantieSolidaire: true,
      caJournalierEstime: "15_30k",
    } as ProfilActivite;

    const features = featuresFromProfilAndOps({
      profil,
      ops: [
        op({ type: "vente", montantFcfa: 50_000, dateOperation: since }),
        op({ type: "depense", montantFcfa: 10_000, dateOperation: since }),
      ],
      tontineCotisations30Fcfa: 5_000,
    });

    assert.equal(features.expensesLast30Fcfa, 10_000);
    assert.equal(features.monthlyFixedChargesFcfa, 20_000);
    assert.equal(features.tontineCotisations30Fcfa, 5_000);
    assert.equal(features.saisonnalite, "forte");
    assert.equal(features.garantieSolidaire, true);
    assert.ok(features.activeWeeksLast30 >= 1);
  });

  it("garde la rétrocompatibilité (profil, ops)", () => {
    const features = featuresFromProfilAndOps(null, []);
    assert.equal(features.opsLast30Days, 0);
    assert.equal(features.partCredit, 1);
    assert.equal(features.creditHist, 0);
    assert.equal(features.telephone, 2);
  });
});
