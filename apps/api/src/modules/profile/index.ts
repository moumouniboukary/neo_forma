/**
 * Module profile — ProfilActivite, PreferencesUtilisateur, onboarding.
 *
 * Routes (préfixe /me) :
 * - GET  /me
 * - PATCH /me
 * - PATCH /me/activite
 * - PATCH /me/preferences
 * - POST /me/onboarding/complete
 */
export { profileRoutes } from "./routes.js";
export {
  ProfileService,
  ProfileError,
  isProfileError,
  isProfilComplet,
} from "./service.js";
