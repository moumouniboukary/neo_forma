import bcrypt from "bcryptjs";
import type { PrismaClient, Session, Travailleur } from "@prisma/client";
import type { OtpPurpose } from "@neoforma/shared";
import { identityConfig } from "./config.js";
import {
  generateFamilyId,
  generateOtpCode,
  generateRefreshToken,
  normalizePhone,
  sha256,
} from "./crypto.js";
import { IdentityError } from "./errors.js";
import { isSmsConfigured, smsGateway } from "../../lib/sms.js";
import { enqueueOrRun } from "../../lib/jobs.js";

export type OtpRequestResult = {
  ok: true;
  expiresIn: number;
  challengeId?: string;
  /** Dev only — jamais en production. */
  devCode?: string;
};

export type IssuedTokens = {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  sessionId: string;
};

type AccessSigner = (payload: {
  sub: string;
  phone: string;
  typ: "access";
  sid: string;
}) => Promise<string> | string;

export class IdentityService {
  constructor(private readonly prisma: PrismaClient) {}

  assertPinStrength(pin: string): void {
    if (identityConfig.weakPins.has(pin)) {
      throw new IdentityError(
        "weak_pin",
        "PIN trop faible — choisissez un code moins prévisible",
        400
      );
    }
  }

  /**
   * Émet un défi OTP (possession).
   * - register : téléphone libre
   * - login : compte actif uniquement (UML)
   * - reset : compte existant non suspendu ; anti-énumération côté route
   */
  async requestOtp(
    phoneRaw: string,
    purpose: OtpPurpose
  ): Promise<OtpRequestResult> {
    const telephone = normalizePhone(phoneRaw);
    const existing = await this.prisma.travailleur.findUnique({
      where: { telephone },
    });

    if (purpose === "register") {
      if (existing) {
        throw new IdentityError("exists", "Compte déjà existant", 409);
      }
    } else if (purpose === "login") {
      if (!existing) {
        throw new IdentityError("account_missing", "Compte inexistant", 404);
      }
      // brouillon autorisé — reprise onboarding après perte de session
      if (existing.statutCompte === "suspendu") {
        throw new IdentityError(
          "account_suspended",
          "Compte suspendu — connexion impossible",
          403
        );
      }
      if (existing.pinLockedUntil && existing.pinLockedUntil > new Date()) {
        throw new IdentityError(
          "pin_locked",
          "Accès temporairement bloqué — réessayez plus tard",
          423
        );
      }
    } else if (purpose === "reset") {
      if (existing?.statutCompte === "suspendu") {
        throw new IdentityError(
          "account_suspended",
          "Compte suspendu",
          403
        );
      }
      // Anti-énumération : si inconnu, on simule un succès sans créer de défi réel
      if (!existing) {
        return {
          ok: true,
          expiresIn: Math.floor(identityConfig.otpTtlMs / 1000),
        };
      }
    }

    await this.enforceOtpRateLimit(telephone);

    const code = generateOtpCode();
    const codeHash = await bcrypt.hash(code, identityConfig.bcryptRounds);
    const expireA = new Date(Date.now() + identityConfig.otpTtlMs);

    const challenge = await this.prisma.defiOtp.create({
      data: {
        telephone,
        codeHash,
        purpose,
        expireA,
        travailleurId: existing?.id ?? null,
      },
    });

    const smsBody = `NeoForma : votre code est ${code}. Valable quelques minutes.`;
    try {
      await enqueueOrRun(
        "sms",
        { to: telephone, body: smsBody },
        () => smsGateway.send({ to: telephone, body: smsBody })
      );
    } catch (err) {
      console.error("[sms] envoi échoué", err);
      if (process.env.NODE_ENV === "production") {
        throw new IdentityError(
          "sms_failed",
          "Impossible d'envoyer le SMS — réessayez",
          503
        );
      }
    }

    const result: OtpRequestResult = {
      ok: true,
      expiresIn: Math.floor(identityConfig.otpTtlMs / 1000),
      challengeId: challenge.id,
    };
    // Sans passerelle SMS : exposer le code dans la réponse (mode test)
    if (!isSmsConfigured()) {
      result.devCode = code;
    }
    return result;
  }

  async verifyOtp(
    phoneRaw: string,
    code: string,
    purpose: OtpPurpose
  ): Promise<{
    phone: string;
    proof: { phone: string; purpose: "otp_verified"; otpPurpose: OtpPurpose };
    expiresIn: number;
  }> {
    const telephone = normalizePhone(phoneRaw);
    const challenge = await this.prisma.defiOtp.findFirst({
      where: {
        telephone,
        purpose,
        consomme: false,
        expireA: { gt: new Date() },
      },
      orderBy: { createdAt: "desc" },
    });

    if (!challenge) {
      throw new IdentityError("otp_invalid", "Code incorrect ou expiré", 401);
    }

    if (challenge.tentatives >= identityConfig.otpMaxAttempts) {
      await this.prisma.defiOtp.update({
        where: { id: challenge.id },
        data: { consomme: true },
      });
      throw new IdentityError(
        "otp_locked",
        "Trop de tentatives — redemandez un code",
        401
      );
    }

    const match = await bcrypt.compare(code, challenge.codeHash);
    if (!match) {
      await this.prisma.defiOtp.update({
        where: { id: challenge.id },
        data: { tentatives: { increment: 1 } },
      });
      throw new IdentityError("otp_invalid", "Code incorrect ou expiré", 401);
    }

    await this.prisma.defiOtp.update({
      where: { id: challenge.id },
      data: { consomme: true },
    });

    return {
      phone: telephone,
      proof: {
        phone: telephone,
        purpose: "otp_verified",
        otpPurpose: purpose,
      },
      expiresIn: identityConfig.otpProofTtlSec,
    };
  }

  assertOtpProof(
    payload: {
      phone?: string;
      purpose?: string;
      otpPurpose?: string;
    },
    expectedPhone: string,
    expectedOtpPurpose: OtpPurpose
  ): void {
    const telephone = normalizePhone(expectedPhone);
    if (
      payload.purpose !== "otp_verified" ||
      !payload.phone ||
      normalizePhone(payload.phone) !== telephone ||
      payload.otpPurpose !== expectedOtpPurpose
    ) {
      throw new IdentityError(
        "otp_proof_invalid",
        "Preuve OTP invalide ou expirée — recommencez la vérification",
        401
      );
    }
  }

  /** Inscription — compte brouillon ; session immédiate pour onboarding. */
  async register(input: {
    phone: string;
    pin: string;
    displayName: string;
    language?: string;
  }): Promise<Travailleur> {
    this.assertPinStrength(input.pin);
    const displayName = input.displayName.trim();
    if (displayName.length < 2) {
      throw new IdentityError(
        "validation",
        "Le nom affiché est requis (2 caractères minimum)",
        400
      );
    }
    const telephone = normalizePhone(input.phone);
    const existing = await this.prisma.travailleur.findUnique({
      where: { telephone },
    });
    if (existing) {
      throw new IdentityError("exists", "Compte déjà existant", 409);
    }

    const pinHash = await bcrypt.hash(input.pin, identityConfig.bcryptRounds);
    const langue = input.language ?? "fr";
    return this.prisma.travailleur.create({
      data: {
        telephone,
        pinHash,
        nomAffiche: displayName,
        statutCompte: "brouillon",
        onboardingTermine: false,
        preferences: {
          create: { langue },
        },
      },
    });
  }

  /**
   * Facteur 2 — PIN (UML).
   * Login : actif ou brouillon (reprise onboarding). Suspendu refusé.
   */
  async authenticatePin(
    phoneRaw: string,
    pin: string,
    opts: { requireActif: boolean } = { requireActif: false }
  ): Promise<Travailleur> {
    const telephone = normalizePhone(phoneRaw);
    const travailleur = await this.prisma.travailleur.findUnique({
      where: { telephone },
    });

    // Message générique — anti-énumération
    if (!travailleur) {
      throw new IdentityError("auth", "Téléphone ou PIN incorrect", 401);
    }

    if (travailleur.statutCompte === "suspendu") {
      throw new IdentityError(
        "account_suspended",
        "Compte suspendu — connexion impossible",
        403
      );
    }

    if (opts.requireActif && travailleur.statutCompte === "brouillon") {
      throw new IdentityError(
        "account_draft",
        "Finaliser l'activation du compte",
        403
      );
    }

    if (travailleur.pinLockedUntil && travailleur.pinLockedUntil > new Date()) {
      throw new IdentityError(
        "pin_locked",
        "Accès temporairement bloqué — réessayez plus tard",
        423
      );
    }

    const pinOk = await bcrypt.compare(pin, travailleur.pinHash);
    if (!pinOk) {
      await this.registerPinFailure(travailleur);
      throw new IdentityError("auth", "Téléphone ou PIN incorrect", 401);
    }

    return this.prisma.travailleur.update({
      where: { id: travailleur.id },
      data: {
        dateDerniereConnexion: new Date(),
        pinFailCount: 0,
        pinLockedUntil: null,
      },
    });
  }

  async resetPin(phoneRaw: string, newPin: string): Promise<void> {
    this.assertPinStrength(newPin);
    const telephone = normalizePhone(phoneRaw);
    const travailleur = await this.prisma.travailleur.findUnique({
      where: { telephone },
    });
    if (!travailleur) {
      // Anti-énumération
      throw new IdentityError("otp_proof_invalid", "Preuve OTP invalide", 401);
    }
    if (travailleur.statutCompte === "suspendu") {
      throw new IdentityError("account_suspended", "Compte suspendu", 403);
    }

    const pinHash = await bcrypt.hash(newPin, identityConfig.bcryptRounds);
    await this.prisma.travailleur.update({
      where: { id: travailleur.id },
      data: {
        pinHash,
        pinFailCount: 0,
        pinLockedUntil: null,
      },
    });
    await this.revokeAllSessions(travailleur.id);
  }

  async issueSession(
    travailleur: Travailleur,
    signAccess: AccessSigner,
    meta: { userAgent?: string; ip?: string }
  ): Promise<IssuedTokens> {
    const familyId = generateFamilyId();
    const refreshToken = generateRefreshToken();
    const expireA = new Date(Date.now() + identityConfig.refreshTokenTtlMs);

    const session = await this.prisma.session.create({
      data: {
        travailleurId: travailleur.id,
        refreshTokenHash: sha256(refreshToken),
        familyId,
        statut: "active",
        expireA,
        userAgent: meta.userAgent?.slice(0, 300) ?? null,
        ip: meta.ip ?? null,
      },
    });

    const accessToken = await signAccess({
      sub: travailleur.id,
      phone: travailleur.telephone,
      typ: "access",
      sid: session.id,
    });

    await this.prisma.session.update({
      where: { id: session.id },
      data: { accessTokenHash: sha256(accessToken) },
    });

    return {
      accessToken,
      refreshToken,
      expiresIn: identityConfig.accessTokenTtlSec,
      sessionId: session.id,
    };
  }

  /**
   * Rotation refresh (OWASP) — ancien token invalidé ;
   * réutilisation d'un token déjà tourné ⇒ révocation de la famille.
   */
  async refreshSession(
    refreshToken: string,
    signAccess: AccessSigner,
    meta: { userAgent?: string; ip?: string }
  ): Promise<IssuedTokens & { travailleur: Travailleur }> {
    const hash = sha256(refreshToken);
    const session = await this.prisma.session.findUnique({
      where: { refreshTokenHash: hash },
    });

    if (!session) {
      // Possible reuse of rotated token — tenter détection via... on ne peut pas sans stocker l'historique.
      // Si hash inconnu : échec générique.
      throw new IdentityError("refresh_invalid", "Refresh token invalide", 401);
    }

    if (session.statut !== "active" || session.expireA < new Date()) {
      if (session.statut === "revoquee") {
        await this.revokeFamily(session.familyId);
      }
      throw new IdentityError("refresh_invalid", "Refresh token invalide", 401);
    }

    const travailleur = await this.prisma.travailleur.findUnique({
      where: { id: session.travailleurId },
    });
    if (!travailleur || travailleur.statutCompte === "suspendu") {
      await this.revokeFamily(session.familyId);
      throw new IdentityError("refresh_invalid", "Refresh token invalide", 401);
    }

    // Invalider l'ancien refresh (rotation)
    await this.prisma.session.update({
      where: { id: session.id },
      data: { statut: "revoquee", revoqueeA: new Date() },
    });

    const tokens = await this.issueSessionInFamily(
      travailleur,
      session.familyId,
      signAccess,
      meta
    );

    return { ...tokens, travailleur };
  }

  async revokeByRefreshToken(refreshToken: string): Promise<void> {
    const hash = sha256(refreshToken);
    await this.prisma.session.updateMany({
      where: { refreshTokenHash: hash, statut: "active" },
      data: { statut: "revoquee", revoqueeA: new Date() },
    });
  }

  async revokeByAccessToken(accessToken: string): Promise<void> {
    const hash = sha256(accessToken);
    await this.prisma.session.updateMany({
      where: { accessTokenHash: hash, statut: "active" },
      data: { statut: "revoquee", revoqueeA: new Date() },
    });
  }

  async revokeAllSessions(travailleurId: string): Promise<void> {
    await this.prisma.session.updateMany({
      where: { travailleurId, statut: "active" },
      data: { statut: "revoquee", revoqueeA: new Date() },
    });
  }

  async assertSessionActive(sessionId: string): Promise<Session> {
    const session = await this.prisma.session.findUnique({
      where: { id: sessionId },
    });
    if (
      !session ||
      session.statut !== "active" ||
      session.expireA < new Date()
    ) {
      throw new IdentityError("unauthorized", "Session invalide ou révoquée", 401);
    }
    return session;
  }

  async findById(id: string): Promise<Travailleur | null> {
    return this.prisma.travailleur.findUnique({ where: { id } });
  }

  private async issueSessionInFamily(
    travailleur: Travailleur,
    familyId: string,
    signAccess: AccessSigner,
    meta: { userAgent?: string; ip?: string }
  ): Promise<IssuedTokens> {
    const refreshToken = generateRefreshToken();
    const expireA = new Date(Date.now() + identityConfig.refreshTokenTtlMs);

    const session = await this.prisma.session.create({
      data: {
        travailleurId: travailleur.id,
        refreshTokenHash: sha256(refreshToken),
        familyId,
        statut: "active",
        expireA,
        userAgent: meta.userAgent?.slice(0, 300) ?? null,
        ip: meta.ip ?? null,
      },
    });

    const accessToken = await signAccess({
      sub: travailleur.id,
      phone: travailleur.telephone,
      typ: "access",
      sid: session.id,
    });

    await this.prisma.session.update({
      where: { id: session.id },
      data: { accessTokenHash: sha256(accessToken) },
    });

    return {
      accessToken,
      refreshToken,
      expiresIn: identityConfig.accessTokenTtlSec,
      sessionId: session.id,
    };
  }

  private async revokeFamily(familyId: string): Promise<void> {
    await this.prisma.session.updateMany({
      where: { familyId, statut: "active" },
      data: { statut: "revoquee", revoqueeA: new Date() },
    });
  }

  private async registerPinFailure(travailleur: Travailleur): Promise<void> {
    const next = travailleur.pinFailCount + 1;
    const locked = next >= identityConfig.pinMaxAttempts;
    await this.prisma.travailleur.update({
      where: { id: travailleur.id },
      data: {
        pinFailCount: locked ? 0 : next,
        pinLockedUntil: locked
          ? new Date(Date.now() + identityConfig.pinLockMs)
          : travailleur.pinLockedUntil,
      },
    });
    if (locked) {
      throw new IdentityError(
        "pin_locked",
        "Accès temporairement bloqué — réessayez plus tard",
        423
      );
    }
  }

  private async enforceOtpRateLimit(telephone: string): Promise<void> {
    const { redisIncrWithTtl } = await import("../../lib/redis.js");
    const windowSec = Math.ceil(identityConfig.otpRateWindowMs / 1000);
    const redisCount = await redisIncrWithTtl(
      `otp:rl:${telephone}`,
      windowSec
    );
    if (redisCount !== null) {
      if (redisCount > identityConfig.otpRateMax) {
        throw new IdentityError(
          "otp_rate_limited",
          "Trop de demandes OTP — réessayez plus tard",
          429
        );
      }
      return;
    }

    const recentCount = await this.prisma.defiOtp.count({
      where: {
        telephone,
        createdAt: {
          gt: new Date(Date.now() - identityConfig.otpRateWindowMs),
        },
      },
    });
    if (recentCount >= identityConfig.otpRateMax) {
      throw new IdentityError(
        "otp_rate_limited",
        "Trop de demandes OTP — réessayez plus tard",
        429
      );
    }
  }
}
