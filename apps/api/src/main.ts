import "./load-env.js";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { initObservability } from "./lib/observability.js";

initObservability();

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

async function boot(): Promise<void> {
  const attempts = 5;
  for (let i = 1; i <= attempts; i++) {
    try {
      const app = await buildApp();
      try {
        await app.listen({ port: config.port, host: config.host });
      } catch (err) {
        await app.close().catch(() => undefined);
        throw err;
      }

      const shutdown = async (signal: string): Promise<void> => {
        app.log.info({ signal }, "Arrêt en cours…");
        try {
          await app.close();
          process.exit(0);
        } catch (err) {
          app.log.error(err);
          process.exit(1);
        }
      };
      process.on("SIGTERM", () => void shutdown("SIGTERM"));
      process.on("SIGINT", () => void shutdown("SIGINT"));
      return;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[boot] essai ${i}/${attempts} échoué: ${msg}`);
      if (i === attempts) {
        process.exit(1);
      }
      await sleep(4000);
    }
  }
}

await boot();
