import { z } from "zod";
import { LanguageSchema } from "./enums.js";
import { PhoneSchema, PinSchema, UserProfileSchema } from "./user.js";

export const OtpPurposeSchema = z.enum(["register", "login", "reset"]);
export type OtpPurpose = z.infer<typeof OtpPurposeSchema>;

/** Preuve OTP JWT courte durée. */
export const OtpTokenSchema = z.string().min(20);

export const OtpRequestSchema = z.object({
  phone: PhoneSchema,
  /** Finalité du défi — défaut login (MFA). */
  purpose: OtpPurposeSchema.default("login"),
});
export type OtpRequest = z.infer<typeof OtpRequestSchema>;

export const OtpVerifySchema = z.object({
  phone: PhoneSchema,
  code: z.string().regex(/^\d{4}$/),
  purpose: OtpPurposeSchema.default("login"),
});
export type OtpVerify = z.infer<typeof OtpVerifySchema>;

export const OtpVerifyResponseSchema = z.object({
  ok: z.literal(true),
  otpToken: OtpTokenSchema,
  expiresIn: z.number().int().positive(),
});
export type OtpVerifyResponse = z.infer<typeof OtpVerifyResponseSchema>;

export const RegisterRequestSchema = z.object({
  phone: PhoneSchema,
  pin: PinSchema,
  displayName: z.string().trim().min(2).max(120),
  language: LanguageSchema.default("fr"),
  otpToken: OtpTokenSchema,
});
export type RegisterRequest = z.infer<typeof RegisterRequestSchema>;

export const LoginRequestSchema = z.object({
  phone: PhoneSchema,
  pin: PinSchema,
  otpToken: OtpTokenSchema,
});
export type LoginRequest = z.infer<typeof LoginRequestSchema>;

export const RefreshTokenRequestSchema = z.object({
  refreshToken: z.string().min(40),
});
export type RefreshTokenRequest = z.infer<typeof RefreshTokenRequestSchema>;

export const LogoutRequestSchema = z.object({
  refreshToken: z.string().min(40).optional(),
});
export type LogoutRequest = z.infer<typeof LogoutRequestSchema>;

/** Mot de passe métier = PIN (domaine NeoForma). */
export const ForgotPasswordRequestSchema = z.object({
  phone: PhoneSchema,
});
export type ForgotPasswordRequest = z.infer<typeof ForgotPasswordRequestSchema>;

export const ResetPasswordRequestSchema = z.object({
  phone: PhoneSchema,
  otpToken: OtpTokenSchema,
  newPin: PinSchema,
});
export type ResetPasswordRequest = z.infer<typeof ResetPasswordRequestSchema>;

export const AuthTokensSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  tokenType: z.literal("Bearer"),
  expiresIn: z.number().int().positive(),
  user: UserProfileSchema,
});
export type AuthTokens = z.infer<typeof AuthTokensSchema>;
