/**
 * White-label / branding — configuration runtime.
 * GET /branding (public) — couleurs, nom, logo URL.
 * Overridable via env BRAND_* ou PARTNER_BRAND_JSON.
 */
import type { FastifyPluginAsync } from "fastify";

export type BrandingConfig = {
  appName: string;
  primaryColor: string;
  secondaryColor: string;
  logoUrl: string | null;
  supportPhone: string | null;
  partnerId: string | null;
};

function loadBranding(): BrandingConfig {
  const fromJson = process.env.PARTNER_BRAND_JSON;
  if (fromJson) {
    try {
      return {
        appName: "NeoForma",
        primaryColor: "#2DB88A",
        secondaryColor: "#5DCAA5",
        logoUrl: null,
        supportPhone: null,
        partnerId: null,
        ...JSON.parse(fromJson),
      };
    } catch {
      /* fallback */
    }
  }
  return {
    appName: process.env.BRAND_APP_NAME ?? "NeoForma",
    primaryColor: process.env.BRAND_PRIMARY_COLOR ?? "#2DB88A",
    secondaryColor: process.env.BRAND_SECONDARY_COLOR ?? "#5DCAA5",
    logoUrl: process.env.BRAND_LOGO_URL ?? null,
    supportPhone: process.env.BRAND_SUPPORT_PHONE ?? null,
    partnerId: process.env.BRAND_PARTNER_ID ?? null,
  };
}

export const brandingRoutes: FastifyPluginAsync = async (app) => {
  app.get("/", async () => loadBranding());
};
