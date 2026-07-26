-- CreateTable
CREATE TABLE "kobo_submissions" (
    "id" TEXT NOT NULL,
    "submissionId" TEXT NOT NULL,
    "telephone" TEXT,
    "metier" TEXT,
    "ancienneteActivite" TEXT,
    "caJournalierEstime" TEXT,
    "participationTontine" BOOLEAN,
    "cotisationTontine" INTEGER,
    "usageMobileMoney" TEXT,
    "statutCompteBancaire" TEXT,
    "impayes" INTEGER,
    "nbTransactions" INTEGER,
    "interet" INTEGER,
    "langue" TEXT,
    "consentement" TEXT,
    "raw" JSONB NOT NULL,
    "matchedTravailleurId" TEXT,
    "importedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "kobo_submissions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "kobo_submissions_submissionId_key" ON "kobo_submissions"("submissionId");

-- CreateIndex
CREATE INDEX "kobo_submissions_telephone_idx" ON "kobo_submissions"("telephone");

-- CreateIndex
CREATE INDEX "kobo_submissions_matchedTravailleurId_idx" ON "kobo_submissions"("matchedTravailleurId");

