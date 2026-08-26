-- Profil activité : capacité remboursement et saisonnalité
ALTER TABLE "profils_activite" ADD COLUMN IF NOT EXISTS "chargesFixesMensuelles" INTEGER;
ALTER TABLE "profils_activite" ADD COLUMN IF NOT EXISTS "saisonnalite" TEXT DEFAULT 'stable';
ALTER TABLE "profils_activite" ADD COLUMN IF NOT EXISTS "garantieSolidaire" BOOLEAN DEFAULT false;
