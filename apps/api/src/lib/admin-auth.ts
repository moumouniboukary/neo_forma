import type { FastifyReply, FastifyRequest } from "fastify";

/** Auth admin agents — header X-Admin-Key = ADMIN_API_KEY. */
export function requireAdminKey(
  request: FastifyRequest,
  reply: FastifyReply
): boolean {
  const expected = process.env.ADMIN_API_KEY;
  if (!expected) {
    reply.status(503).send({
      error: "admin_disabled",
      message: "ADMIN_API_KEY non configurée",
    });
    return false;
  }
  const key =
    (request.headers["x-admin-key"] as string | undefined) ??
    (request.headers.authorization?.replace(/^Bearer\s+/i, "") ?? "");
  if (key !== expected) {
    reply.status(401).send({
      error: "unauthorized",
      message: "Clé admin invalide",
    });
    return false;
  }
  return true;
}
