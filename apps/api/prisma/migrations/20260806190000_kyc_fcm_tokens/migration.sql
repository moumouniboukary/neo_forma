-- KYC léger (identité déclarative)
ALTER TABLE "travailleurs" ADD COLUMN IF NOT EXISTS "kycStatut" TEXT NOT NULL DEFAULT 'non_verifie';
ALTER TABLE "travailleurs" ADD COLUMN IF NOT EXISTS "pieceIdentiteType" TEXT;
ALTER TABLE "travailleurs" ADD COLUMN IF NOT EXISTS "pieceIdentiteNumero" TEXT;
ALTER TABLE "travailleurs" ADD COLUMN IF NOT EXISTS "dateNaissance" TIMESTAMP(3);
ALTER TABLE "travailleurs" ADD COLUMN IF NOT EXISTS "adresse" TEXT;

-- Jetons FCM / APNs pour push distant
CREATE TABLE IF NOT EXISTS "device_push_tokens" (
    "id" TEXT NOT NULL,
    "travailleurId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "platform" TEXT NOT NULL DEFAULT 'android',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "device_push_tokens_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "device_push_tokens_travailleurId_token_key"
  ON "device_push_tokens"("travailleurId", "token");

CREATE INDEX IF NOT EXISTS "device_push_tokens_travailleurId_idx"
  ON "device_push_tokens"("travailleurId");

DO $$ BEGIN
  ALTER TABLE "device_push_tokens"
    ADD CONSTRAINT "device_push_tokens_travailleurId_fkey"
    FOREIGN KEY ("travailleurId") REFERENCES "travailleurs"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
