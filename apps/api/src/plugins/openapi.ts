import swagger from "@fastify/swagger";
import swaggerUi from "@fastify/swagger-ui";
import type { FastifyInstance } from "fastify";

export async function registerOpenApi(app: FastifyInstance) {
  await app.register(swagger, {
    openapi: {
      info: {
        title: "NeoForma API",
        description:
          "Inclusion financière — secteur informel Burkina Faso (MFA, cahier, NeoScore, crédit)",
        version: "0.1.0",
      },
      servers: [{ url: "/", description: "API" }],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
          },
        },
      },
      tags: [
        { name: "health" },
        { name: "auth" },
        { name: "profile" },
        { name: "ledger" },
        { name: "sync" },
        { name: "score" },
        { name: "credit" },
        { name: "partners" },
      ],
    },
  });

  await app.register(swaggerUi, {
    routePrefix: "/docs",
    uiConfig: {
      docExpansion: "list",
      deepLinking: true,
    },
  });
}
