-- CreateTable
CREATE TABLE "agent_dossiers" (
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
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agent_dossiers_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "agent_dossiers_clientMutationId_key" ON "agent_dossiers"("clientMutationId");

-- CreateIndex
CREATE INDEX "agent_dossiers_agentUserId_createdAt_idx" ON "agent_dossiers"("agentUserId", "createdAt");

-- CreateIndex
CREATE INDEX "agent_dossiers_statut_idx" ON "agent_dossiers"("statut");

-- CreateIndex
CREATE INDEX "agent_dossiers_recommendation_idx" ON "agent_dossiers"("recommendation");

-- AddForeignKey
ALTER TABLE "agent_dossiers" ADD CONSTRAINT "agent_dossiers_agentUserId_fkey" FOREIGN KEY ("agentUserId") REFERENCES "travailleurs"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
