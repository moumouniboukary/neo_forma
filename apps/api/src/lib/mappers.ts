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

export function toUserProfile(user: TravailleurWithProfile): UserProfile {
  const profil = user.profilActivite;
  const prefs = user.preferences;
  const flags = consentFlags(user.consentements);

  return {
    id: user.id,
    phone: user.telephone,
    displayName: user.nomAffiche || user.telephone,
    language: (prefs?.langue ?? "fr") as UserProfile["language"],
    theme: (prefs?.theme === "light" ? "light" : "dark") as UserProfile["theme"],
    metier: (profil?.metier as UserProfile["metier"]) ?? undefined,
    anciennete: (profil?.ancienneteActivite as UserProfile["anciennete"]) ?? undefined,
    caJour: (profil?.caJournalierEstime as UserProfile["caJour"]) ?? undefined,
    tontine: profil?.participationTontine ?? undefined,
    tontineCotis: profil?.cotisationTontine ?? undefined,
    mobileMoney: (profil?.usageMobileMoney as UserProfile["mobileMoney"]) ?? undefined,
    compte: (profil?.statutCompteBancaire as UserProfile["compte"]) ?? undefined,
    city: profil?.ville ?? undefined,
    zone: profil?.zone ?? undefined,
    ...flags,
    onboardingCompleted: user.onboardingTermine,
    statutCompte: user.statutCompte as UserProfile["statutCompte"],
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
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
  return {
    id: app.id,
    userId: app.travailleurId,
    reference: app.reference,
    amountFcfa: app.montantDemandeFcfa,
    purpose: app.usage as CreditDto["purpose"],
    repayment: app.modaliteRemboursement as CreditDto["repayment"],
    status: app.statut as CreditDto["status"],
    scoreAtSubmit: app.snapshotScore?.valeur ?? 0,
    offreId: app.offreId,
    imfId: app.imfId,
    dateSoumission: app.dateSoumission?.toISOString() ?? null,
    createdAt: app.createdAt.toISOString(),
    updatedAt: app.updatedAt.toISOString(),
  };
}
