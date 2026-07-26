/**
 * Module identity / Auth — MFA OTP+PIN, sessions JWT, refresh, reset PIN.
 *
 * Endpoints :
 * - POST /auth/otp/request | /otp/verify
 * - POST /auth/register | /login | /refresh | /logout
 * - POST /auth/forgot-password | /reset-password
 * - GET  /auth/me
 */
export { identityRoutes } from "./routes.js";
export { IdentityService } from "./service.js";
export { IdentityError, isIdentityError } from "./errors.js";
export { identityConfig } from "./config.js";
