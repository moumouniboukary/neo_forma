/**
 * Module ledger — cahier numérique (opérations, clients, créances).
 *
 * Routes :
 * - /operations …
 * - /clients …
 * Dashboard réutilise LedgerService.getDashboardStats.
 */
export { ledgerOperationRoutes, ledgerClientRoutes } from "./routes.js";
export { LedgerService, LedgerError, isLedgerError } from "./service.js";
