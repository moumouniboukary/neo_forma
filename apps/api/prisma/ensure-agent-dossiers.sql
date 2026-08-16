CREATE TABLE IF NOT EXISTS "agent_dossiers" (
    "id" TEXT NOT NULL,
    "clientMutationId" TEXT NOT NULL,
    "agentUserId" TEXT NOT NULL,
    "clientNom" TEXT NOT NULL,
    "clientTelephone" TEXT,
    "inputJson" JSONB NOT NULL,
    "score" INTEGER NOT NULL,
    "recommendation" TEXT NOT NULL,
    "chargeRate" DOUBLE PRECISION NOT NULL,
    "montantSoutenableFcfa" INTEGER NOT NULL,
    "echeanceEstimeeFcfa" INTEGER NOT NULL,
    "revenuMensuelFcfa" INTEGER NOT NULL,
    "montantDemandeFcfa" INTEGER NOT NULL,
    "driversJson" JSONB NOT NULL,
    "resultJson" JSONB NOT NULL,
    "note" TEXT,
    "statut" TEXT NOT NULL DEFAULT 'soumise',
    "motifDecision" TEXT,
    "decidedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "agent_dossiers_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "agent_dossiers_clientMutationId_key" ON "agent_dossiers"("clientMutationId");
CREATE INDEX IF NOT EXISTS "agent_dossiers_agentUserId_createdAt_idx" ON "agent_dossiers"("agentUserId", "createdAt");
CREATE INDEX IF NOT EXISTS "agent_dossiers_statut_idx" ON "agent_dossiers"("statut");
CREATE INDEX IF NOT EXISTS "agent_dossiers_recommendation_idx" ON "agent_dossiers"("recommendation");
