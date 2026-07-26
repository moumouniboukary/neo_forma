import { z } from "zod";
import { AuthTokensSchema } from "./auth.js";
import { NeoScoreResultSchema } from "./score.js";

export { AuthTokensSchema } from "./auth.js";
export type { AuthTokens } from "./auth.js";

export const ApiErrorSchema = z.object({
  error: z.string(),
  message: z.string(),
  details: z.unknown().optional(),
});
export type ApiError = z.infer<typeof ApiErrorSchema>;

export const ScoreResponseSchema = NeoScoreResultSchema;

/** @deprecated — utiliser AuthTokensSchema (inclut refreshToken). */
export const LegacyAuthTokensSchema = AuthTokensSchema;
