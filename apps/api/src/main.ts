import "./load-env.js";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { initObservability } from "./lib/observability.js";

initObservability();

const app = await buildApp();

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, "Arrêt en cours…");
  try {
    await app.close();
    process.exit(0);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));

try {
  await app.listen({ port: config.port, host: config.host });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
