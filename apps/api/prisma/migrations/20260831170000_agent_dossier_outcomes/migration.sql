-- Labels remboursement + moteur de scoring pour recalibrage DigiCoop
ALTER TABLE "agent_dossiers" ADD COLUMN IF NOT EXISTS "outcome" TEXT;
ALTER TABLE "agent_dossiers" ADD COLUMN IF NOT EXISTS "outcomeAt" TIMESTAMP(3);
ALTER TABLE "agent_dossiers" ADD COLUMN IF NOT EXISTS "outcomeNote" TEXT;
ALTER TABLE "agent_dossiers" ADD COLUMN IF NOT EXISTS "engine" TEXT NOT NULL DEFAULT 'expert_scorecard';
ALTER TABLE "agent_dossiers" ADD COLUMN IF NOT EXISTS "modelVersion" TEXT;

CREATE INDEX IF NOT EXISTS "agent_dossiers_outcome_idx" ON "agent_dossiers"("outcome");

ALTER TABLE "ml_model_runs" ADD COLUMN IF NOT EXISTS "payloadJson" JSONB;
