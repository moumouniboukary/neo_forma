/**
 * Charge apps/api/.env avant tout autre module (config.ts lit process.env
 * au chargement). No-op si absent — en prod les env sont injectées.
 * Ne remplace pas les variables déjà définies.
 */
import { fileURLToPath } from "node:url";
import path from "node:path";

try {
  const envPath = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
    ".env"
  );
  process.loadEnvFile(envPath);
} catch {
  /* pas de .env */
}
