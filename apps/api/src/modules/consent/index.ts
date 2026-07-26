/**
 * Module consent — Consentement versionné, vérification, révocation.
 *
 * Routes (préfixe /me/consents) :
 * - GET  /me/consents
 * - PUT  /me/consents
 * - PUT  /me/consents/:type
 * - POST /me/consents/:type/revoke
 */
export { consentRoutes } from "./routes.js";
export {
  ConsentService,
  ConsentError,
  isConsentError,
  toConsentDto,
} from "./service.js";
