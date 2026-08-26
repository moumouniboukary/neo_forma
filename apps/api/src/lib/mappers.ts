import type {
  Travailleur,
  Operation,
  DemandeCredit,
  ProfilActivite,
  Preferences,
  Consentement,
  ClientInformel,
  SnapshotScore,
} from "@prisma/client";
import type {
  UserProfile,
  Operation as OpDto,
  CreditApplication as CreditDto,
  ClientInformelDto,
} from "@neoforma/shared";
import { normalizeLanguage } from "@neoforma/shared";

export type TravailleurWithProfile = Travailleur & {
  profilActivite?: ProfilActivite | null;
  preferences?: Preferences | null;
  consentements?: Consentement[];
};

function consentFlags(consentements: Consentement[] | undefined): {
  consentAnonymized: boolean;
  consentCreditPartners: boolean;
  consentMarketing: boolean;
} {
  const byType = Object.fromEntries(
    (consentements ?? []).map((c) => [c.type, c.accorde])
  );
  return {
    consentAnonymized: byType.anonymisation_recherche ?? true,
    consentCreditPartners: byType.partage_imf ?? false,
    consentMarketing: byType.marketing_partenaires ?? false,
  };
}

function toTheme(theme: string | null | undefined): UserProfile["theme"] {
  if (theme === "light" || theme === "dark" || theme === "system") return theme;
  return "system";
}

export function toUserProfile(user: TravailleurWithProfile): UserProfile {
  const profil = user.profilActivite;
  const prefs = user.preferences;
  const flags = consentFlags(user.consentements);

  return {
    id: user.id,
    phone: user.telephone,
    displayName: user.nomAffiche || user.telephone,
    language: normalizeLanguage(prefs?.langue),
    theme: toTheme(prefs?.theme),
    metier: (profil?.metier as UserProfile["metier"]) ?? undefined,
    anciennete: (profil?.ancienneteActivite as UserProfile["anciennete"]) ?? undefined,
    caJour: (profil?.caJournalierEstime as UserProfile["caJour"]) ?? undefined,
    tontine: profil?.participationTontine ?? undefined,
    tontineCotis: profil?.cotisationTontine ?? undefined,
    mobileMoney: (profil?.usageMobileMoney as UserProfile["mobileMoney"]) ?? undefined,
    compte: (profil?.statutCompteBancaire as UserProfile["compte"]) ?? undefined,
    city: profil?.ville ?? undefined,
    zone: profil?.zone ?? undefined,
    chargesFixesMensuelles: profil?.chargesFixesMensuelles ?? undefined,
    saisonnalite:
      (profil?.saisonnalite as UserProfile["saisonnalite"]) ?? undefined,
    garantieSolidaire: profil?.garantieSolidaire ?? undefined,
    ...flags,
    onboardingCompleted: user.onboardingTermine,
    statutCompte: user.statutCompte as UserProfile["statutCompte"],
    kycStatut: (user.kycStatut as UserProfile["kycStatut"]) ?? "non_verifie",
    pieceIdentiteType:
      (user.pieceIdentiteType as UserProfile["pieceIdentiteType"]) ?? undefined,
    pieceIdentiteNumero: user.pieceIdentiteNumero ?? undefined,
    dateNaissance: user.dateNaissance?.toISOString() ?? undefined,
    adresse: user.adresse ?? undefined,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  };
}

export function toArticleStock(a: {
  id: string;
  nom: string;
  unite: string;
  quantite: number;
  prixUnitaireFcfa: number | null;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: a.id,
    nom: a.nom,
    unite: a.unite,
    quantite: a.quantite,
    prixUnitaireFcfa: a.prixUnitaireFcfa ?? undefined,
    createdAt: a.createdAt.toISOString(),
    updatedAt: a.updatedAt.toISOString(),
  };
}

export type OperationWithClient = Operation & {
  client?: ClientInformel | null;
  articleStock?: { nom: string } | null;
};

export function toOperation(op: OperationWithClient): OpDto {
  return {
    id: op.id,
    userId: op.travailleurId,
    type: op.type as OpDto["type"],
    amountFcfa: op.montantFcfa,
    label: op.libelle ?? undefined,
    clientId: op.clientId ?? undefined,
    clientName: op.client?.nom ?? undefined,
    natureStock: (op.natureStock as OpDto["natureStock"]) ?? undefined,
    articleName: op.articleStock?.nom ?? undefined,
    quantity: op.quantiteStock ?? undefined,
    articleStockId: op.articleStockId ?? undefined,
    quantiteStock: op.quantiteStock ?? undefined,
    categorieDepense: op.categorieDepense ?? undefined,
    canal: (op.canal as OpDto["canal"]) ?? undefined,
    dueAt: op.echeance?.toISOString(),
    settledAt: op.dateReglement?.toISOString() ?? null,
    statutCreance: (op.statutCreance as OpDto["statutCreance"]) ?? undefined,
    statutSync: (op.statutSync as OpDto["statutSync"]) ?? undefined,
    amountSettledFcfa: op.montantRegleFcfa ?? undefined,
    montantRegleFcfa: op.montantRegleFcfa ?? undefined,
    remainingFcfa: Math.max(0, op.montantFcfa - (op.montantRegleFcfa ?? 0)),
    remindedAt: op.derniereRelanceAt?.toISOString() ?? null,
    createdAt: op.createdAt.toISOString(),
    dateOperation: op.dateOperation.toISOString(),
    clientMutationId: op.identifiantIdempotence ?? undefined,
    syncedAt:
      op.statutSync === "synchronisee" ? op.updatedAt.toISOString() : null,
  };
}

export function toClient(client: ClientInformel): ClientInformelDto {
  return {
    id: client.id,
    nom: client.nom,
    telephone: client.telephone,
    note: client.note,
    createdAt: client.createdAt.toISOString(),
    updatedAt: client.updatedAt.toISOString(),
  };
}

export type DemandeWithSnapshot = DemandeCredit & {
  snapshotScore?: SnapshotScore | null;
};

export function toCredit(app: DemandeWithSnapshot): CreditDto {
  const snap = app.snapshotScore;
  const score = snap?.valeur ?? 0;
  const threshold = snap?.seuilEligibilite ?? null;
  const eligible =
    snap != null && threshold != null ? score >= threshold : undefined;

  return {
    id: app.id,
    userId: app.travailleurId,
    reference: app.reference,
    amountFcfa: app.montantDemandeFcfa,
    purpose: app.usage as CreditDto["purpose"],
    repayment: app.modaliteRemboursement as CreditDto["repayment"],
    status: app.statut as CreditDto["status"],
    scoreAtSubmit: score,
    offreId: app.offreId,
    imfId: app.imfId,
    dateSoumission: app.dateSoumission?.toISOString() ?? null,
    createdAt: app.createdAt.toISOString(),
    updatedAt: app.updatedAt.toISOString(),
    eligible,
    segment: snap?.segment ?? null,
    threshold,
    criteria: snap
      ? {
          regularite: snap.critereRegularite,
          volume: snap.critereVolume,
          dettes: snap.critereGestionCreances,
          croissance: snap.critereCroissance,
        }
      : null,
    featuresSnapshot:
      app.featuresSnapshot &&
      typeof app.featuresSnapshot === "object" &&
      !Array.isArray(app.featuresSnapshot)
        ? (app.featuresSnapshot as Record<string, unknown>)
        : null,
    motifDecision: app.motifDecision ?? null,
    outcome: app.outcome ?? null,
  };
}
