/**
 * Module scoring — NeoScore, critères, historique, offre.
 * Features : ./features.js (partagé avec credit via ScoringService).
 */
export { scoringRoutes } from "./routes.js";
export { ScoringService, ScoringError, isScoringError } from "./service.js";
export { featuresFromProfilAndOps } from "./features.js";
