-- NeoScore : moteur ML + version modèle
ALTER TABLE "neoscores" ADD COLUMN IF NOT EXISTS "moteur" TEXT NOT NULL DEFAULT 'heuristic';
ALTER TABLE "neoscores" ADD COLUMN IF NOT EXISTS "modelVersion" TEXT;

-- Demande crédit : features figées + labels remboursement
ALTER TABLE "demandes_credit" ADD COLUMN IF NOT EXISTS "featuresSnapshot" JSONB;
ALTER TABLE "demandes_credit" ADD COLUMN IF NOT EXISTS "dateDecaissement" TIMESTAMP(3);
ALTER TABLE "demandes_credit" ADD COLUMN IF NOT EXISTS "dateEcheance" TIMESTAMP(3);
ALTER TABLE "demandes_credit" ADD COLUMN IF NOT EXISTS "dateCloture" TIMESTAMP(3);
ALTER TABLE "demandes_credit" ADD COLUMN IF NOT EXISTS "outcome" TEXT;

CREATE INDEX IF NOT EXISTS "demandes_credit_outcome_idx" ON "demandes_credit"("outcome");

-- Runs d'entraînement ML
CREATE TABLE IF NOT EXISTS "ml_model_runs" (
    "id" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "trainedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "nSamples" INTEGER NOT NULL,
    "nDefaults" INTEGER NOT NULL,
    "auc" DOUBLE PRECISION,
    "source" TEXT NOT NULL DEFAULT 'mixed',
    "notes" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "ml_model_runs_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ml_model_runs_version_key" ON "ml_model_runs"("version");
CREATE INDEX IF NOT EXISTS "ml_model_runs_trainedAt_idx" ON "ml_model_runs"("trainedAt");
