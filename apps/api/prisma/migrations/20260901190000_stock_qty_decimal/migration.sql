-- Quantités décimales (boucherie au kg : 1,5 kg).
ALTER TABLE "articles_stock" ALTER COLUMN "quantite" SET DATA TYPE DECIMAL(12,3);
ALTER TABLE "operations" ALTER COLUMN "quantiteStock" SET DATA TYPE DECIMAL(12,3);
