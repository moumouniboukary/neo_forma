-- AlterTable
ALTER TABLE "operations" ADD COLUMN IF NOT EXISTS "montantRegleFcfa" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "operations" ADD COLUMN IF NOT EXISTS "articleStockId" TEXT;
ALTER TABLE "operations" ADD COLUMN IF NOT EXISTS "quantiteStock" INTEGER;
ALTER TABLE "operations" ADD COLUMN IF NOT EXISTS "derniereRelanceAt" TIMESTAMP(3);

-- AlterTable Imf
ALTER TABLE "imf" ADD COLUMN IF NOT EXISTS "apiKeyHash" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "imf_apiKeyHash_key" ON "imf"("apiKeyHash");

-- CreateTable
CREATE TABLE IF NOT EXISTS "articles_stock" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "nom" TEXT NOT NULL,
    "unite" TEXT NOT NULL DEFAULT 'u',
    "quantite" INTEGER NOT NULL DEFAULT 0,
    "prixUnitaireFcfa" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "articles_stock_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "articles_stock_travailleurId_nom_key" ON "articles_stock"("travailleurId", "nom");
CREATE INDEX IF NOT EXISTS "articles_stock_travailleurId_idx" ON "articles_stock"("travailleurId");

CREATE TABLE IF NOT EXISTS "tontines" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "nom" TEXT NOT NULL,
    "cotisationFcfa" INTEGER NOT NULL,
    "frequence" TEXT NOT NULL DEFAULT 'mensuel',
    "membres" INTEGER NOT NULL DEFAULT 1,
    "note" TEXT,
    "actif" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "tontines_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "tontines_travailleurId_actif_idx" ON "tontines"("travailleurId", "actif");

CREATE TABLE IF NOT EXISTS "tontine_cotisations" (
    "id" TEXT NOT NULL,
    "tontineId" TEXT NOT NULL,
    "montantFcfa" INTEGER NOT NULL,
    "datePaiement" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "tontine_cotisations_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "tontine_cotisations_tontineId_datePaiement_idx" ON "tontine_cotisations"("tontineId", "datePaiement");

CREATE TABLE IF NOT EXISTS "notifications_in_app" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "titre" TEXT NOT NULL,
    "corps" TEXT NOT NULL,
    "lu" BOOLEAN NOT NULL DEFAULT false,
    "meta" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_in_app_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "notifications_in_app_travailleurId_lu_createdAt_idx" ON "notifications_in_app"("travailleurId", "lu", "createdAt");

-- FKs (ignore if already exist)
DO $$ BEGIN
  ALTER TABLE "articles_stock" ADD CONSTRAINT "articles_stock_travailleurId_fkey"
    FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE "tontines" ADD CONSTRAINT "tontines_travailleurId_fkey"
    FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE "tontine_cotisations" ADD CONSTRAINT "tontine_cotisations_tontineId_fkey"
    FOREIGN KEY ("tontineId") REFERENCES "tontines"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE "notifications_in_app" ADD CONSTRAINT "notifications_in_app_travailleurId_fkey"
    FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE "operations" ADD CONSTRAINT "operations_articleStockId_fkey"
    FOREIGN KEY ("articleStockId") REFERENCES "articles_stock"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
