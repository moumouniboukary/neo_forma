-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "travailleurs" (
    "id" TEXT NOT NULL,
    "telephone" TEXT NOT NULL,
    "pinHash" TEXT NOT NULL,
    "nomAffiche" TEXT NOT NULL DEFAULT '',
    "genre" TEXT,
    "statutCompte" TEXT NOT NULL DEFAULT 'brouillon',
    "onboardingTermine" BOOLEAN NOT NULL DEFAULT false,
    "dateDerniereConnexion" TIMESTAMP(3),
    "pinFailCount" INTEGER NOT NULL DEFAULT 0,
    "pinLockedUntil" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "travailleurs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "profils_activite" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "metier" TEXT,
    "ancienneteActivite" TEXT,
    "caJournalierEstime" TEXT,
    "participationTontine" BOOLEAN,
    "cotisationTontine" INTEGER,
    "usageMobileMoney" TEXT,
    "statutCompteBancaire" TEXT,
    "ville" TEXT,
    "zone" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "profils_activite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "preferences" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "langue" TEXT NOT NULL DEFAULT 'fr',
    "modeIconographique" BOOLEAN NOT NULL DEFAULT false,
    "assistanceVocaleActive" BOOLEAN NOT NULL DEFAULT false,
    "fuseau" TEXT NOT NULL DEFAULT 'Africa/Ouagadougou',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "preferences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "consentements" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "accorde" BOOLEAN NOT NULL DEFAULT false,
    "dateDecision" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "versionPolitique" TEXT NOT NULL,
    "retractable" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "consentements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "clients_informels" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "nom" TEXT NOT NULL,
    "telephone" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "clients_informels_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "operations" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "montantFcfa" INTEGER NOT NULL,
    "libelle" TEXT,
    "dateOperation" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "statutSync" TEXT NOT NULL DEFAULT 'synchronisee',
    "identifiantIdempotence" TEXT,
    "clientId" TEXT,
    "natureStock" TEXT,
    "categorieDepense" TEXT,
    "echeance" TIMESTAMP(3),
    "dateReglement" TIMESTAMP(3),
    "statutCreance" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "operations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "operations_hors_ligne" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "identifiantLocal" TEXT NOT NULL,
    "payload" TEXT NOT NULL,
    "dateSaisieLocale" TIMESTAMP(3) NOT NULL,
    "etat" TEXT NOT NULL DEFAULT 'en_attente',
    "motifRejet" TEXT,
    "operationId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "operations_hors_ligne_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "neoscores" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "valeur" INTEGER NOT NULL,
    "seuilEligibilite" INTEGER NOT NULL DEFAULT 50,
    "eligible" BOOLEAN NOT NULL,
    "segment" TEXT NOT NULL,
    "critereRegularite" INTEGER NOT NULL,
    "critereVolume" INTEGER NOT NULL,
    "critereGestionCreances" INTEGER NOT NULL,
    "critereCroissance" INTEGER NOT NULL,
    "periodeAnalyseJours" INTEGER NOT NULL DEFAULT 30,
    "dateCalcul" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "neoscores_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "neoscore_historique" (
    "id" TEXT NOT NULL,
    "neoscoreId" TEXT NOT NULL,
    "periode" TEXT NOT NULL,
    "valeur" INTEGER NOT NULL,
    "enregistreAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "neoscore_historique_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "offres_credit" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "neoscoreId" TEXT NOT NULL,
    "montantMinFcfa" INTEGER NOT NULL,
    "montantMaxFcfa" INTEGER NOT NULL,
    "montantSuggereFcfa" INTEGER NOT NULL,
    "dureeMois" INTEGER NOT NULL,
    "tauxMensuelIndicatif" DOUBLE PRECISION NOT NULL,
    "eligible" BOOLEAN NOT NULL,
    "dateGeneration" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "valideJusqua" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "offres_credit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "snapshots_score" (
    "id" TEXT NOT NULL,
    "valeur" INTEGER NOT NULL,
    "segment" TEXT NOT NULL,
    "seuilEligibilite" INTEGER NOT NULL,
    "critereRegularite" INTEGER NOT NULL,
    "critereVolume" INTEGER NOT NULL,
    "critereGestionCreances" INTEGER NOT NULL,
    "critereCroissance" INTEGER NOT NULL,
    "dateFigee" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "snapshots_score_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "imf" (
    "id" TEXT NOT NULL,
    "raisonSociale" TEXT NOT NULL,
    "pays" TEXT NOT NULL DEFAULT 'Burkina Faso',
    "statutPartenariat" TEXT NOT NULL DEFAULT 'prospect',
    "niveauAcces" TEXT NOT NULL DEFAULT 'consultation',
    "contactEmail" TEXT,
    "contactNom" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "imf_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "demandes_credit" (
    "id" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "offreId" TEXT,
    "snapshotScoreId" TEXT,
    "imfId" TEXT,
    "montantDemandeFcfa" INTEGER NOT NULL,
    "usage" TEXT NOT NULL,
    "modaliteRemboursement" TEXT NOT NULL,
    "statut" TEXT NOT NULL DEFAULT 'brouillon',
    "dateSoumission" TIMESTAMP(3),
    "motifDecision" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "demandes_credit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "acces_profils_imf" (
    "id" TEXT NOT NULL,
    "imfId" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "consentementId" TEXT NOT NULL,
    "demandeCreditId" TEXT,
    "dateAcces" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "finalite" TEXT NOT NULL,
    "anonymise" BOOLEAN NOT NULL DEFAULT true,
    "scorePresente" INTEGER NOT NULL,

    CONSTRAINT "acces_profils_imf_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "commissions" (
    "id" TEXT NOT NULL,
    "demandeCreditId" TEXT NOT NULL,
    "imfId" TEXT NOT NULL,
    "montantCreditFcfa" INTEGER NOT NULL,
    "tauxCommission" DOUBLE PRECISION NOT NULL,
    "montantCommissionFcfa" INTEGER NOT NULL,
    "statut" TEXT NOT NULL DEFAULT 'due',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "commissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "defis_otp" (
    "id" TEXT NOT NULL,
    "telephone" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "purpose" TEXT NOT NULL DEFAULT 'login',
    "expireA" TIMESTAMP(3) NOT NULL,
    "consomme" BOOLEAN NOT NULL DEFAULT false,
    "tentatives" INTEGER NOT NULL DEFAULT 0,
    "travailleurId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "defis_otp_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sessions" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "refreshTokenHash" TEXT NOT NULL,
    "accessTokenHash" TEXT,
    "familyId" TEXT NOT NULL,
    "statut" TEXT NOT NULL DEFAULT 'active',
    "creeeA" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expireA" TIMESTAMP(3) NOT NULL,
    "revoqueeA" TIMESTAMP(3),
    "userAgent" TEXT,
    "ip" TEXT,

    CONSTRAINT "sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "travailleurs_telephone_key" ON "travailleurs"("telephone");

-- CreateIndex
CREATE UNIQUE INDEX "profils_activite_travailleurId_key" ON "profils_activite"("travailleurId");

-- CreateIndex
CREATE UNIQUE INDEX "preferences_travailleurId_key" ON "preferences"("travailleurId");

-- CreateIndex
CREATE INDEX "consentements_type_accorde_idx" ON "consentements"("type", "accorde");

-- CreateIndex
CREATE UNIQUE INDEX "consentements_travailleurId_type_key" ON "consentements"("travailleurId", "type");

-- CreateIndex
CREATE INDEX "clients_informels_travailleurId_idx" ON "clients_informels"("travailleurId");

-- CreateIndex
CREATE INDEX "clients_informels_travailleurId_nom_idx" ON "clients_informels"("travailleurId", "nom");

-- CreateIndex
CREATE UNIQUE INDEX "operations_identifiantIdempotence_key" ON "operations"("identifiantIdempotence");

-- CreateIndex
CREATE INDEX "operations_travailleurId_dateOperation_idx" ON "operations"("travailleurId", "dateOperation");

-- CreateIndex
CREATE INDEX "operations_travailleurId_type_idx" ON "operations"("travailleurId", "type");

-- CreateIndex
CREATE INDEX "operations_clientId_idx" ON "operations"("clientId");

-- CreateIndex
CREATE UNIQUE INDEX "operations_hors_ligne_identifiantLocal_key" ON "operations_hors_ligne"("identifiantLocal");

-- CreateIndex
CREATE INDEX "operations_hors_ligne_travailleurId_etat_idx" ON "operations_hors_ligne"("travailleurId", "etat");

-- CreateIndex
CREATE UNIQUE INDEX "neoscores_travailleurId_key" ON "neoscores"("travailleurId");

-- CreateIndex
CREATE INDEX "neoscore_historique_neoscoreId_enregistreAt_idx" ON "neoscore_historique"("neoscoreId", "enregistreAt");

-- CreateIndex
CREATE INDEX "offres_credit_travailleurId_dateGeneration_idx" ON "offres_credit"("travailleurId", "dateGeneration");

-- CreateIndex
CREATE UNIQUE INDEX "imf_raisonSociale_key" ON "imf"("raisonSociale");

-- CreateIndex
CREATE INDEX "imf_statutPartenariat_idx" ON "imf"("statutPartenariat");

-- CreateIndex
CREATE UNIQUE INDEX "demandes_credit_reference_key" ON "demandes_credit"("reference");

-- CreateIndex
CREATE INDEX "demandes_credit_travailleurId_createdAt_idx" ON "demandes_credit"("travailleurId", "createdAt");

-- CreateIndex
CREATE INDEX "demandes_credit_statut_idx" ON "demandes_credit"("statut");

-- CreateIndex
CREATE INDEX "acces_profils_imf_imfId_dateAcces_idx" ON "acces_profils_imf"("imfId", "dateAcces");

-- CreateIndex
CREATE INDEX "acces_profils_imf_travailleurId_dateAcces_idx" ON "acces_profils_imf"("travailleurId", "dateAcces");

-- CreateIndex
CREATE UNIQUE INDEX "commissions_demandeCreditId_key" ON "commissions"("demandeCreditId");

-- CreateIndex
CREATE INDEX "commissions_imfId_statut_idx" ON "commissions"("imfId", "statut");

-- CreateIndex
CREATE INDEX "defis_otp_telephone_createdAt_idx" ON "defis_otp"("telephone", "createdAt");

-- CreateIndex
CREATE INDEX "defis_otp_telephone_purpose_consomme_idx" ON "defis_otp"("telephone", "purpose", "consomme");

-- CreateIndex
CREATE UNIQUE INDEX "sessions_refreshTokenHash_key" ON "sessions"("refreshTokenHash");

-- CreateIndex
CREATE UNIQUE INDEX "sessions_accessTokenHash_key" ON "sessions"("accessTokenHash");

-- CreateIndex
CREATE INDEX "sessions_travailleurId_statut_idx" ON "sessions"("travailleurId", "statut");

-- CreateIndex
CREATE INDEX "sessions_familyId_idx" ON "sessions"("familyId");

-- AddForeignKey
ALTER TABLE "profils_activite" ADD CONSTRAINT "profils_activite_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "preferences" ADD CONSTRAINT "preferences_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "consentements" ADD CONSTRAINT "consentements_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "clients_informels" ADD CONSTRAINT "clients_informels_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "operations" ADD CONSTRAINT "operations_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "operations" ADD CONSTRAINT "operations_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "clients_informels"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "operations_hors_ligne" ADD CONSTRAINT "operations_hors_ligne_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "operations_hors_ligne" ADD CONSTRAINT "operations_hors_ligne_operationId_fkey" FOREIGN KEY ("operationId") REFERENCES "operations"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "neoscores" ADD CONSTRAINT "neoscores_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "neoscore_historique" ADD CONSTRAINT "neoscore_historique_neoscoreId_fkey" FOREIGN KEY ("neoscoreId") REFERENCES "neoscores"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "offres_credit" ADD CONSTRAINT "offres_credit_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "offres_credit" ADD CONSTRAINT "offres_credit_neoscoreId_fkey" FOREIGN KEY ("neoscoreId") REFERENCES "neoscores"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "demandes_credit" ADD CONSTRAINT "demandes_credit_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "demandes_credit" ADD CONSTRAINT "demandes_credit_offreId_fkey" FOREIGN KEY ("offreId") REFERENCES "offres_credit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "demandes_credit" ADD CONSTRAINT "demandes_credit_snapshotScoreId_fkey" FOREIGN KEY ("snapshotScoreId") REFERENCES "snapshots_score"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "demandes_credit" ADD CONSTRAINT "demandes_credit_imfId_fkey" FOREIGN KEY ("imfId") REFERENCES "imf"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "acces_profils_imf" ADD CONSTRAINT "acces_profils_imf_imfId_fkey" FOREIGN KEY ("imfId") REFERENCES "imf"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "acces_profils_imf" ADD CONSTRAINT "acces_profils_imf_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "acces_profils_imf" ADD CONSTRAINT "acces_profils_imf_consentementId_fkey" FOREIGN KEY ("consentementId") REFERENCES "consentements"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "acces_profils_imf" ADD CONSTRAINT "acces_profils_imf_demandeCreditId_fkey" FOREIGN KEY ("demandeCreditId") REFERENCES "demandes_credit"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commissions" ADD CONSTRAINT "commissions_demandeCreditId_fkey" FOREIGN KEY ("demandeCreditId") REFERENCES "demandes_credit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commissions" ADD CONSTRAINT "commissions_imfId_fkey" FOREIGN KEY ("imfId") REFERENCES "imf"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "defis_otp" ADD CONSTRAINT "defis_otp_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_travailleurId_fkey" FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;

