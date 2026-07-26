import type { PrismaClient } from "@prisma/client";

export class KoboError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "KoboError";
  }
}

export function isKoboError(err: unknown): err is KoboError {
  return err instanceof KoboError;
}

/** Champs normalisés issus d'une soumission KoboCollect. */
type NormalizedSubmission = {
  submissionId: string;
  telephone: string | null;
  metier: string | null;
  ancienneteActivite: string | null;
  caJournalierEstime: string | null;
  participationTontine: boolean | null;
  cotisationTontine: number | null;
  usageMobileMoney: string | null;
  statutCompteBancaire: string | null;
  impayes: number | null;
  nbTransactions: number | null;
  interet: number | null;
  langue: string | null;
  consentement: string | null;
  raw: Record<string, unknown>;
};

export type KoboImportResult = {
  received: number;
  imported: number;
  duplicates: number;
  matchedProfiles: number;
};

const str = (v: unknown): string | null => {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  return s.length ? s : null;
};

const num = (v: unknown): number | null => {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

const bool = (v: unknown): boolean | null => {
  if (v === null || v === undefined || v === "") return null;
  const s = String(v).toLowerCase();
  if (["oui", "yes", "true", "1"].includes(s)) return true;
  if (["non", "no", "false", "0"].includes(s)) return false;
  return null;
};

/** Récupère la 1re clé présente (Kobo aplatit parfois avec des préfixes de groupe). */
function pick(row: Record<string, unknown>, ...keys: string[]): unknown {
  for (const k of keys) {
    if (row[k] !== undefined) return row[k];
    // Support des noms préfixés type "groupe/champ"
    const suffixed = Object.keys(row).find((rk) => rk.endsWith(`/${k}`));
    if (suffixed) return row[suffixed];
  }
  return undefined;
}

export class KoboService {
  constructor(private readonly prisma: PrismaClient) {}

  /** Mappe les noms de champs Kobo (cf. NeoForma_KoboCollect_XLSForm) vers le modèle. */
  private normalize(row: Record<string, unknown>): NormalizedSubmission {
    const submissionId =
      str(pick(row, "_uuid", "meta/instanceID", "submissionId")) ??
      `kobo-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

    return {
      submissionId,
      telephone: str(pick(row, "telephone", "phone", "numero")),
      metier: str(pick(row, "metier")),
      ancienneteActivite: str(pick(row, "anciennete", "ancienneteActivite")),
      caJournalierEstime: str(pick(row, "ca_jour", "caJournalierEstime")),
      participationTontine: bool(pick(row, "tontine", "participationTontine")),
      cotisationTontine: num(pick(row, "tontine_cotis", "cotisationTontine")),
      usageMobileMoney: str(pick(row, "mobile_money", "usageMobileMoney")),
      statutCompteBancaire: str(pick(row, "compte", "statutCompteBancaire")),
      impayes: num(pick(row, "impayes")),
      nbTransactions: num(pick(row, "nb_transactions", "nbTransactions")),
      interet: num(pick(row, "interet")),
      langue: str(pick(row, "langue")),
      consentement: str(pick(row, "consentement")),
      raw: row,
    };
  }

  /**
   * Importe une ou plusieurs soumissions Kobo (idempotent par submissionId).
   * Si le téléphone correspond à un compte, met à jour son ProfilActivite.
   */
  async import(payload: unknown): Promise<KoboImportResult> {
    const rows = Array.isArray(payload)
      ? payload
      : payload && typeof payload === "object" && "results" in payload
        ? (payload as { results: unknown[] }).results
        : [payload];

    if (!Array.isArray(rows) || rows.length === 0) {
      throw new KoboError("empty", "Aucune soumission à importer", 400);
    }

    let imported = 0;
    let duplicates = 0;
    let matchedProfiles = 0;

    for (const raw of rows) {
      if (!raw || typeof raw !== "object") continue;
      const sub = this.normalize(raw as Record<string, unknown>);

      const existing = await this.prisma.koboSubmission.findUnique({
        where: { submissionId: sub.submissionId },
        select: { id: true },
      });
      if (existing) {
        duplicates += 1;
        continue;
      }

      let matchedTravailleurId: string | null = null;
      if (sub.telephone) {
        const worker = await this.prisma.travailleur.findUnique({
          where: { telephone: sub.telephone },
          select: { id: true },
        });
        matchedTravailleurId = worker?.id ?? null;
      }

      await this.prisma.koboSubmission.create({
        data: {
          submissionId: sub.submissionId,
          telephone: sub.telephone,
          metier: sub.metier,
          ancienneteActivite: sub.ancienneteActivite,
          caJournalierEstime: sub.caJournalierEstime,
          participationTontine: sub.participationTontine,
          cotisationTontine: sub.cotisationTontine,
          usageMobileMoney: sub.usageMobileMoney,
          statutCompteBancaire: sub.statutCompteBancaire,
          impayes: sub.impayes,
          nbTransactions: sub.nbTransactions,
          interet: sub.interet,
          langue: sub.langue,
          consentement: sub.consentement,
          raw: sub.raw as object,
          matchedTravailleurId,
        },
      });
      imported += 1;

      // Enrichit le profil du travailleur existant (les champs terrain priment si absents).
      if (matchedTravailleurId) {
        const profilData = {
          ...(sub.metier ? { metier: sub.metier } : {}),
          ...(sub.ancienneteActivite
            ? { ancienneteActivite: sub.ancienneteActivite }
            : {}),
          ...(sub.caJournalierEstime
            ? { caJournalierEstime: sub.caJournalierEstime }
            : {}),
          ...(sub.participationTontine !== null
            ? { participationTontine: sub.participationTontine }
            : {}),
          ...(sub.cotisationTontine !== null
            ? { cotisationTontine: sub.cotisationTontine }
            : {}),
          ...(sub.usageMobileMoney
            ? { usageMobileMoney: sub.usageMobileMoney }
            : {}),
          ...(sub.statutCompteBancaire
            ? { statutCompteBancaire: sub.statutCompteBancaire }
            : {}),
        };
        if (Object.keys(profilData).length > 0) {
          await this.prisma.profilActivite.upsert({
            where: { travailleurId: matchedTravailleurId },
            create: { travailleurId: matchedTravailleurId, ...profilData },
            update: profilData,
          });
          matchedProfiles += 1;
        }
      }
    }

    return {
      received: rows.length,
      imported,
      duplicates,
      matchedProfiles,
    };
  }

  async list(limit = 50): Promise<
    Array<{
      id: string;
      submissionId: string;
      telephone: string | null;
      metier: string | null;
      matchedTravailleurId: string | null;
      importedAt: Date;
    }>
  > {
    return this.prisma.koboSubmission.findMany({
      orderBy: { importedAt: "desc" },
      take: Math.min(Math.max(limit, 1), 200),
      select: {
        id: true,
        submissionId: true,
        telephone: true,
        metier: true,
        matchedTravailleurId: true,
        importedAt: true,
      },
    });
  }

  async stats(): Promise<{ total: number; matched: number; unmatched: number }> {
    const total = await this.prisma.koboSubmission.count();
    const matched = await this.prisma.koboSubmission.count({
      where: { NOT: { matchedTravailleurId: null } },
    });
    return { total, matched, unmatched: total - matched };
  }
}
