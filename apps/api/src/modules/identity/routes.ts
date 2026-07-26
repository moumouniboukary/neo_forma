import type { FastifyPluginAsync, FastifyReply } from "fastify";
import {
  ForgotPasswordRequestSchema,
  LoginRequestSchema,
  LogoutRequestSchema,
  OtpRequestSchema,
  OtpVerifySchema,
  RefreshTokenRequestSchema,
  RegisterRequestSchema,
  ResetPasswordRequestSchema,
} from "@neoforma/shared";
import { identityConfig } from "./config.js";
import { IdentityError, isIdentityError } from "./errors.js";
import { toAuthUser } from "./mapper.js";
import { IdentityService } from "./service.js";

type OtpProofPayload = {
  phone: string;
  purpose: "otp_verified";
  otpPurpose: "register" | "login" | "reset";
};

function sendIdentityError(reply: FastifyReply, err: unknown) {
  if (isIdentityError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
    });
  }
  throw err;
}

function verifyOtpToken(
  app: { jwt: { verify: (token: string) => unknown } },
  token: string
): OtpProofPayload {
  try {
    return app.jwt.verify(token) as OtpProofPayload;
  } catch {
    throw new IdentityError(
      "otp_proof_invalid",
      "Preuve OTP invalide ou expirée — recommencez la vérification",
      401
    );
  }
}

export const identityRoutes: FastifyPluginAsync = async (app) => {
  const identity = new IdentityService(app.prisma);

  /** POST /auth/otp/request */
  app.post("/otp/request", async (request, reply) => {
    const parsed = OtpRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Requête OTP invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      return await identity.requestOtp(parsed.data.phone, parsed.data.purpose);
    } catch (err) {
      return sendIdentityError(reply, err);
    }
  });

  /** POST /auth/otp/verify */
  app.post("/otp/verify", async (request, reply) => {
    const parsed = OtpVerifySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "OTP invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      const result = await identity.verifyOtp(
        parsed.data.phone,
        parsed.data.code,
        parsed.data.purpose
      );
      const otpToken = app.jwt.sign(result.proof, {
        expiresIn: result.expiresIn,
      });
      return {
        ok: true as const,
        otpToken,
        expiresIn: result.expiresIn,
      };
    } catch (err) {
      return sendIdentityError(reply, err);
    }
  });

  /** POST /auth/register */
  app.post("/register", async (request, reply) => {
    const parsed = RegisterRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Données d'inscription invalides",
        details: parsed.error.flatten(),
      });
    }
    try {
      const proof = verifyOtpToken(app, parsed.data.otpToken);
      identity.assertOtpProof(proof, parsed.data.phone, "register");

      const travailleur = await identity.register({
        phone: parsed.data.phone,
        pin: parsed.data.pin,
        displayName: parsed.data.displayName,
        language: parsed.data.language,
      });

      const tokens = await identity.issueSession(
        travailleur,
        (p) =>
          reply.jwtSign(p, { expiresIn: identityConfig.accessTokenTtlSec }),
        {
          userAgent: request.headers["user-agent"],
          ip: request.ip,
        }
      );

      return {
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        tokenType: "Bearer" as const,
        expiresIn: tokens.expiresIn,
        user: {
          ...toAuthUser(travailleur),
          language: parsed.data.language,
        },
      };
    } catch (err) {
      return sendIdentityError(reply, err);
    }
  });

  /** POST /auth/login — MFA OTP + PIN (actif ou brouillon → onboarding) */
  app.post("/login", async (request, reply) => {
    const parsed = LoginRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Identifiants invalides",
        details: parsed.error.flatten(),
      });
    }
    try {
      const proof = verifyOtpToken(app, parsed.data.otpToken);
      identity.assertOtpProof(proof, parsed.data.phone, "login");

      const travailleur = await identity.authenticatePin(
        parsed.data.phone,
        parsed.data.pin,
        { requireActif: false }
      );

      const tokens = await identity.issueSession(
        travailleur,
        (p) =>
          reply.jwtSign(p, { expiresIn: identityConfig.accessTokenTtlSec }),
        {
          userAgent: request.headers["user-agent"],
          ip: request.ip,
        }
      );

      return {
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        tokenType: "Bearer" as const,
        expiresIn: tokens.expiresIn,
        user: toAuthUser(travailleur),
      };
    } catch (err) {
      return sendIdentityError(reply, err);
    }
  });

  /** POST /auth/refresh */
  app.post("/refresh", async (request, reply) => {
    const parsed = RefreshTokenRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Refresh token requis",
        details: parsed.error.flatten(),
      });
    }
    try {
      const result = await identity.refreshSession(
        parsed.data.refreshToken,
        (p) =>
          reply.jwtSign(p, { expiresIn: identityConfig.accessTokenTtlSec }),
        {
          userAgent: request.headers["user-agent"],
          ip: request.ip,
        }
      );
      return {
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        tokenType: "Bearer" as const,
        expiresIn: result.expiresIn,
        user: toAuthUser(result.travailleur),
      };
    } catch (err) {
      return sendIdentityError(reply, err);
    }
  });

  /** POST /auth/logout */
  app.post("/logout", async (request, reply) => {
    const parsed = LogoutRequestSchema.safeParse(request.body ?? {});
    const body = parsed.success ? parsed.data : {};

    if (body.refreshToken) {
      await identity.revokeByRefreshToken(body.refreshToken);
    }

    const auth = request.headers.authorization;
    if (auth?.startsWith("Bearer ")) {
      await identity.revokeByAccessToken(auth.slice(7));
    }

    return reply.status(200).send({ ok: true });
  });

  /** POST /auth/forgot-password — reset PIN via OTP (anti-énumération) */
  app.post("/forgot-password", async (request, reply) => {
    const parsed = ForgotPasswordRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Téléphone invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      const result = await identity.requestOtp(parsed.data.phone, "reset");
      return {
        ok: true,
        message:
          "Si un compte existe pour ce numéro, un code OTP a été envoyé",
        expiresIn: result.expiresIn,
        ...(result.devCode ? { devCode: result.devCode } : {}),
      };
    } catch (err) {
      if (
        isIdentityError(err) &&
        (err.code === "account_suspended" || err.code === "otp_rate_limited")
      ) {
        return sendIdentityError(reply, err);
      }
      return {
        ok: true,
        message:
          "Si un compte existe pour ce numéro, un code OTP a été envoyé",
        expiresIn: Math.floor(identityConfig.otpTtlMs / 1000),
      };
    }
  });

  /** POST /auth/reset-password */
  app.post("/reset-password", async (request, reply) => {
    const parsed = ResetPasswordRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Données de réinitialisation invalides",
        details: parsed.error.flatten(),
      });
    }
    try {
      const proof = verifyOtpToken(app, parsed.data.otpToken);
      identity.assertOtpProof(proof, parsed.data.phone, "reset");
      await identity.resetPin(parsed.data.phone, parsed.data.newPin);
      return {
        ok: true,
        message: "PIN mis à jour — reconnectez-vous",
      };
    } catch (err) {
      return sendIdentityError(reply, err);
    }
  });

  /** GET /auth/me */
  app.get("/me", { preHandler: [app.authenticate] }, async (request, reply) => {
    const travailleur = await identity.findById(request.user.sub);
    if (!travailleur) {
      return reply.status(404).send({
        error: "not_found",
        message: "Utilisateur introuvable",
      });
    }
    return toAuthUser(travailleur);
  });
};
