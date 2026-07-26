# NeoForma — Modèle de domaine métier

| | |
|---|---|
| **Document** | Modèle de domaine (Domain Model) |
| **Projet** | NeoForma |
| **Source** | `docs/analysis-report.md` |
| **Niveau** | Métier uniquement (pas de persistance, pas d’ORM, pas de schéma SQL) |
| **Version** | 1.0 |
| **Date** | Juillet 2026 |

---

## 1. Objet et principes

Ce document décrit le **langage ubiquitaire** et les **entités métier** de NeoForma.

Il répond à la question : *de quoi parle le métier ?*  
Il ne prescrit ni base de données, ni framework, ni API.

### 1.1 Principes de modélisation

- Une **entité** a une identité métier stable dans le temps.
- Une **valeur** (value object) n’a pas d’identité propre ; elle se définit par ses attributs.
- Une **agrégation** regroupe des entités cohérentes autour d’une racine.
- Les **règles métier** sont des invariants ou des politiques du domaine.
- Les montants sont exprimés en **FCFA** (entier).

### 1.2 Contextes métier (vues)

| Contexte | Intention |
|----------|-----------|
| **Identité & accès** | Qui est le travailleur et comment s’authentifie-t-il |
| **Profil d’activité** | Caractériser l’activité informelle et les préférences |
| **Consentement & partage** | Contrôler ce qui peut être transmis aux partenaires |
| **Cahier numérique** | Historiser ventes, stocks, dépenses, créances |
| **Solvabilité (NeoScore)** | Transformer l’historique en score et éligibilité |
| **Crédit & mise en relation** | Offre, demande, lien avec une IMF |
| **Partenariat IMF** | Institution consommatrice du scoring |
| **Accompagnement terrain** | Onboarding humain du pilote |
| **Continuité hors ligne** | Opérations saisies sans réseau, à réconcilier |

---

## 2. Cartographie des relations (vue d’ensemble)

```mermaid
erDiagram
  TRAVAILLEUR ||--o| PROFIL_ACTIVITE : possede
  TRAVAILLEUR ||--o| PREFERENCES : possede
  TRAVAILLEUR ||--|{ CONSENTEMENT : declare
  TRAVAILLEUR ||--|{ OPERATION : enregistre
  TRAVAILLEUR ||--o| NEOSCORE : possede
  TRAVAILLEUR ||--|{ DEMANDE_CREDIT : soumet
  TRAVAILLEUR }o--o| AGENT_TERRAIN : est_accompagne_par

  OPERATION }o--o| CLIENT_INFORMEL : concerne
  OPERATION ||--o| OPERATION_HORS_LIGNE : peut_etre

  NEOSCORE ||--|| CRITERES_SCORE : detaille
  NEOSCORE ||--o| OFFRE_CREDIT : conditionne

  DEMANDE_CREDIT }o--|| OFFRE_CREDIT : s_appuie_sur
  DEMANDE_CREDIT }o--o| IMF : est_orientee_vers
  DEMANDE_CREDIT }o--|| NEOSCORE : fige_le_score_de

  IMF ||--o{ ACCES_PROFIL : consulte
  ACCES_PROFIL }o--|| TRAVAILLEUR : cible
  ACCES_PROFIL }o--|| CONSENTEMENT : autorise_par
```

---

## 3. Catalogue des entités métier

---

### 3.1 TravailleurInformel *(agrégat racine — Identité)*

**Responsabilité**  
Représenter la personne du secteur informel utilisatrice de NeoForma : identité d’accès, existence du compte, et point d’ancrage de tout l’historique économique.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant métier | Identité unique du travailleur |
| `telephone` | Téléphone (E.164 local, ex. +226…) | Canal principal d’identité |
| `codeSecret` | Secret d’accès (PIN conceptuel) | Authentification locale |
| `nomAffiche` | Texte | Nom / prénom affiché |
| `genre` | Enumération optionnelle | Utile aux indicateurs d’inclusion |
| `statutCompte` | `brouillon` \| `actif` \| `suspendu` | Cycle de vie du compte |
| `onboardingTermine` | Booléen | Profil minimal complété |
| `dateCreation` | Date-heure | Ouverture du compte |
| `dateDerniereConnexion` | Date-heure optionnelle | Suivi d’activité |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-T01 | Un travailleur est identifié de façon unique par son numéro de téléphone. |
| RM-T02 | La création de compte exige un téléphone valide et un code secret. |
| RM-T03 | Sans onboarding terminé, l’accès aux fonctions avancées (score exploitable, demande de crédit) est restreint. |
| RM-T04 | L’application reste gratuite pour le travailleur (pas de facturation utilisateur final). |
| RM-T05 | La suspension du compte bloque les nouvelles demandes de crédit. |

**Relations**

- 1 — 0..1 → `ProfilActivite`
- 1 — 0..1 → `PreferencesUtilisateur`
- 1 — 0..* → `Consentement`
- 1 — 0..* → `Operation`
- 1 — 0..1 → `NeoScore` (vue courante)
- 1 — 0..* → `DemandeCredit`
- 0..* — 0..1 → `AgentTerrain` (accompagnement)

---

### 3.2 ProfilActivite

**Responsabilité**  
Décrire l’activité économique du travailleur (métier, maturité, signaux de fiabilité informelle) afin d’alimenter le scoring et la compréhension métier.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `metier` | Enumération | commerce, mécanique, artisanat, menuiserie, restauration, transport, agriculture, services… |
| `ancienneteActivite` | Échelle ordinale | Ex. &lt;1 an, 1–2, 3–5, 6–10, &gt;10 ans |
| `caJournalierEstime` | Échelle ordinale (FCFA) | Tranche de chiffre d’affaires journalier déclaré |
| `participationTontine` | Booléen | Signal de fiabilité communautaire |
| `cotisationTontine` | Montant FCFA optionnel | Intensité de la tontine |
| `usageMobileMoney` | Échelle | jamais → quotidien |
| `statutCompteBancaire` | Enumération | aucun / dormant / actif |
| `ville` | Texte | Ex. Ouagadougou |
| `zone` | Texte optionnel | Quartier / zone d’activité |
| `dateMiseAJour` | Date-heure | Dernière actualisation du profil |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-P01 | Le profil doit contenir au minimum métier + ancienneté + estimation d’activité pour être considéré « complet ». |
| RM-P02 | Les attributs de tontine / Mobile Money / compte bancaire sont des **signaux**, pas des preuves bancaires formelles. |
| RM-P03 | Une modification majeure du profil peut nécessiter un recalcul du NeoScore. |

**Relations**

- 1 → appartient à 1 `TravailleurInformel`

---

### 3.3 PreferencesUtilisateur

**Responsabilité**  
Capturer les choix d’expérience (langue, mode d’interaction) sans mélanger cela au profil économique.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `langue` | Enumération | fr, mooré, dioula, fulfuldé… |
| `modeIconographique` | Booléen | Priorité icônes / faible littératie |
| `assistanceVocaleActive` | Booléen | Roadmap accessibilité |
| `fuseau` | Texte | Contexte temporel local |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-PR01 | La langue par défaut initiale est le français ; les langues locales s’ajoutent progressivement. |
| RM-PR02 | L’activation vocale n’est pas un prérequis MVP. |

**Relations**

- 1 → appartient à 1 `TravailleurInformel`

---

### 3.4 Consentement

**Responsabilité**  
Matérialiser le contrôle de l’utilisateur sur l’usage et le partage de ses données — condition sine qua non de la mise en relation IMF.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité du consentement |
| `type` | Enumération | `anonymisation_recherche` \| `partage_imf` \| `marketing_partenaires` |
| `accorde` | Booléen | Accord donné ou refusé |
| `dateDecision` | Date-heure | Moment de la décision |
| `versionPolitique` | Texte | Référence de la politique acceptée |
| `retractable` | Booléen | Possibilité de retrait |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-C01 | Aucun partage de profil vers une IMF n’est autorisé sans consentement `partage_imf` = vrai. |
| RM-C02 | Un profil partagé peut être anonymisé selon le consentement d’anonymisation / paramétrage associé. |
| RM-C03 | Le retrait du consentement de partage empêche tout **nouvel** accès IMF ; les accès passés restent audités. |
| RM-C04 | Les décisions de consentement sont horodatées et traçables. |

**Relations**

- * → appartient à 1 `TravailleurInformel`
- autorise 0..* → `AccesProfilImf`

---

### 3.5 ClientInformel *(client du travailleur, pas client NeoForma)*

**Responsabilité**  
Représenter la personne ou entité à qui le travailleur vend à crédit (créance). Entité légère du « cahier ».

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité locale du client |
| `nom` | Texte | Nom usuel (ex. Koné Ibrahim) |
| `telephone` | Téléphone optionnel | Pour relance |
| `note` | Texte optionnel | Mémo libre |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-CI01 | Un client informel n’existe métier que dans le périmètre d’un travailleur (pas de référentiel national). |
| RM-CI02 | Le nom est obligatoire pour rattacher une créance. |

**Relations**

- 1 → appartient au périmètre d’un `TravailleurInformel`
- 1 — 0..* → `Operation` de type créance

---

### 3.6 Operation *(agrégat racine — Cahier numérique)*

**Responsabilité**  
Enregistrer un fait économique du quotidien : vente, stock, dépense ou créance client. C’est la brique qui construit l’historique.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité de l’opération |
| `type` | Enumération | `vente` \| `stock` \| `depense` \| `creance` |
| `montantFcfa` | Montant entier &gt; 0 | Valeur économique |
| `libelle` | Texte optionnel | Description courte |
| `dateOperation` | Date-heure | Moment métier de l’événement |
| `sens` | Dérivé | Crédit / débit selon le type |
| `statutSync` | Enumération | `locale` \| `synchronisee` \| `en_conflit` |
| `identifiantIdempotence` | Identifiant optionnel | Garantit l’absence de doublon après sync |

**Attributs spécifiques selon le type**

| Type | Attributs additionnels |
|------|------------------------|
| `vente` | `libelle` produit / service |
| `stock` | `nature` (entrée / sortie), `libelle` article |
| `depense` | `categorie` optionnelle |
| `creance` | `client` (réf. ClientInformel), `echeance`, `dateReglement` optionnelle, `statutCreance` |

**Statut de créance** : `ouverte` \| `en_retard` \| `reglee` \| `annulee`

**Règles métier**

| ID | Règle |
|----|-------|
| RM-O01 | Le montant doit être strictement positif, en FCFA entier. |
| RM-O02 | Une opération appartient toujours à un et un seul travailleur. |
| RM-O03 | Une créance exige un client et, de préférence, une échéance. |
| RM-O04 | Une créance est `en_retard` si non réglée et `echeance` &lt; maintenant. |
| RM-O05 | Le règlement d’une créance positionne `dateReglement` et passe le statut à `reglee`. |
| RM-O06 | Les opérations peuvent être créées hors ligne ; leur identité d’idempotence empêche le doublon à la synchronisation. |
| RM-O07 | Une opération synchronisée ne doit pas être altérée silencieusement côté client sans nouvelle version métier. |
| RM-O08 | L’historique d’opérations est la source principale du NeoScore. |

**Relations**

- * → appartient à 1 `TravailleurInformel`
- 0..1 → `ClientInformel` (si créance)
- 0..1 → décrite par `OperationHorsLigne` (tant que non synchronisée)

---

### 3.7 OperationHorsLigne *(concept métier de continuité)*

**Responsabilité**  
Représenter une opération saisie sans réseau, en attente de réconciliation avec le référentiel central.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `identifiantLocal` | Identifiant | Clé d’idempotence |
| `payloadOperation` | Valeur Operation | Contenu métier à pousser |
| `dateSaisieLocale` | Date-heure | Horodatage device |
| `etat` | Enumération | `en_attente` \| `acceptee` \| `rejetee` |
| `motifRejet` | Texte optionnel | Si rejet |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-OL01 | Tant que l’état est `en_attente`, l’opération compte pour le cahier local de l’utilisateur. |
| RM-OL02 | À l’acceptation, l’opération devient une `Operation` synchronisée et quitte la file. |
| RM-OL03 | Un même `identifiantLocal` ne peut produire qu’une seule opération acceptée. |

**Relations**

- 1 → matérialise 1 intention d’`Operation`
- * → appartiennent au périmètre d’un `TravailleurInformel`

---

### 3.8 NeoScore *(agrégat racine — Solvabilité)*

**Responsabilité**  
Exprimer la solvabilité alternative du travailleur à un instant donné, de façon compréhensible et actionnable (éligibilité crédit).

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `valeur` | Entier 0–100 | Score global |
| `seuilEligibilite` | Entier (ex. 50) | Seuil politique métier |
| `eligible` | Booléen | `valeur >= seuilEligibilite` |
| `segment` | Enumération | Ex. A régulier stable, B potentiel volatil, C primo-entrant, D exclusion |
| `dateCalcul` | Date-heure | Instant du calcul |
| `periodeAnalyse` | Durée / fenêtre | Ex. 30 derniers jours + profil |
| `historique` | Liste {période, valeur} | Évolution récente du score |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-S01 | Le NeoScore est dérivé de l’historique d’activité et du profil ; il n’est pas un score bancaire classique. |
| RM-S02 | Critères minimaux obligatoires : régularité, volume, progression/croissance, gestion des créances. |
| RM-S03 | `eligible` est vrai seulement si `valeur >= seuilEligibilite`. |
| RM-S04 | Un NeoScore obsolète (historique trop changé) doit être recalculé avant décision de crédit. |
| RM-S05 | Le détail des critères doit rester explicable à l’utilisateur (transparence). |

**Relations**

- 1 → appartient à 1 `TravailleurInformel`
- 1 → composé de 1 `CriteresScore`
- conditionne 0..1 → `OffreCredit`

---

### 3.9 CriteresScore *(valeur / composant du NeoScore)*

**Responsabilité**  
Détailler les dimensions comportementales du score.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `regularite` | 0–100 | Assiduité des enregistrements |
| `volume` | 0–100 | Intensité économique (CA / flux) |
| `gestionCreances` | 0–100 | Qualité de suivi des dettes clients |
| `croissance` | 0–100 | Progression de l’activité |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-CS01 | Chaque critère est borné entre 0 et 100. |
| RM-CS02 | La combinaison des critères produit la `valeur` NeoScore selon une politique de pondération définie par NeoForma (modifiable par recalibrage métier/ML). |

**Relations**

- 1 → fait partie de 1 `NeoScore`

---

### 3.10 OffreCredit

**Responsabilité**  
Proposer une enveloppe de financement indicative, conditionnée au NeoScore et aux règles partenaires.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `montantMinFcfa` | Montant | Borne basse |
| `montantMaxFcfa` | Montant | Borne haute |
| `montantSuggereFcfa` | Montant | Proposition par défaut |
| `dureeMois` | Entier | Ex. 3 mois |
| `tauxMensuelIndicatif` | Pourcentage | Ex. 2,5 % / mois (indicatif) |
| `eligible` | Booléen | Cohérent avec NeoScore |
| `dateGeneration` | Date-heure | Validité contextuelle |
| `validite` | Durée optionnelle | Expiration de l’offre |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-OC01 | Aucune offre réelle si NeoScore non éligible (`montantMax = 0` ou offre refusée). |
| RM-OC02 | Le montant demandé ultérieurement doit être compris entre min et max. |
| RM-OC03 | L’offre est indicative tant qu’une IMF n’a pas décidé. |
| RM-OC04 | Une offre est liée au score calculé à un instant donné. |

**Relations**

- 1 → conditionnée par 1 `NeoScore`
- 1 → concerne 1 `TravailleurInformel`
- 0..* → peut donner lieu à `DemandeCredit`

---

### 3.11 DemandeCredit *(agrégat racine — Crédit)*

**Responsabilité**  
Matérialiser la volonté du travailleur d’obtenir un microcrédit via NeoForma, et suivre son cycle de vie jusqu’à la décision partenaire.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité de la demande |
| `reference` | Référence métier | Exposable à l’utilisateur (ex. NF-2026-xxxx) |
| `montantDemandeFcfa` | Montant | Montant sollicité |
| `usage` | Enumération | stock, équipement, fonds de roulement, autre |
| `modaliteRemboursement` | Enumération | hebdomadaire, mensuel… |
| `statut` | Enumération | voir ci-dessous |
| `scoreAuDepot` | Entier 0–100 | NeoScore figé à la soumission |
| `dateSoumission` | Date-heure | Dépôt |
| `dateMiseAJour` | Date-heure | Dernier changement de statut |
| `motifDecision` | Texte optionnel | Commentaire IMF / plateforme |

**Statuts**

`brouillon` → `soumise` → `en_etude` → `approuvee` \| `refusee` → (`decaisee` si approuvée)

**Règles métier**

| ID | Règle |
|----|-------|
| RM-DC01 | Une demande ne peut être soumise que si le travailleur est éligible au moment du dépôt. |
| RM-DC02 | Le montant doit respecter l’offre en vigueur. |
| RM-DC03 | Le consentement de partage IMF doit être actif avant orientation vers une IMF. |
| RM-DC04 | Le `scoreAuDepot` est immuable après soumission (auditabilité). |
| RM-DC05 | Les transitions de statut sont ordonnées ; pas de retour arbitraire `refusee` → `approuvee` sans nouvelle demande. |
| RM-DC06 | La référence métier est unique et communicable à l’utilisateur. |

**Relations**

- * → soumise par 1 `TravailleurInformel`
- 0..1 → s’appuie sur 1 `OffreCredit`
- 0..1 → orientée vers 1 `InstitutionMicrofinance`
- fige 1 → `NeoScore` (valeur au dépôt)

---

### 3.12 InstitutionMicrofinance *(IMF)*

**Responsabilité**  
Représenter le partenaire financier qui consomme le scoring et peut octroyer un crédit.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité partenaire |
| `raisonSociale` | Texte | Ex. RCPB, Coris, ACEP… |
| `pays` | Texte | Burkina Faso (initial) |
| `statutPartenariat` | Enumération | prospect, actif, suspendu |
| `niveauAcces` | Enumération | consultation, api_scoring, full |
| `contact` | Valeur contact | Référent partenariat |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-IMF01 | Seule une IMF au statut `actif` peut recevoir des demandes / consulter des profils. |
| RM-IMF02 | L’accès à un profil exige un consentement valide du travailleur. |
| RM-IMF03 | L’IMF ne voit que les données autorisées (profil scoré, éventuellement anonymisé). |

**Relations**

- 1 — 0..* → `DemandeCredit`
- 1 — 0..* → `AccesProfilImf`
- future : 0..* → `Commission` (modèle économique)

---

### 3.13 AccesProfilImf

**Responsabilité**  
Tracer un accès (ou une mise à disposition) du profil scoré d’un travailleur à une IMF — preuve de mise en relation consentie.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité de l’accès |
| `dateAcces` | Date-heure | Quand |
| `finalite` | Texte | Étude de crédit, revue dossier… |
| `anonymise` | Booléen | Profil anonymisé ou nominatif |
| `scorePresente` | Entier | Score exposé |
| `demandeLiee` | Réf. optionnelle | Lien éventuel vers DemandeCredit |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-AP01 | Tout accès est refusé si consentement `partage_imf` absent. |
| RM-AP02 | Chaque accès est journalisé (traçabilité). |
| RM-AP03 | Si anonymisation requise, aucun identifiant directement nominatif n’est exposé. |

**Relations**

- * → effectué par 1 `InstitutionMicrofinance`
- * → cible 1 `TravailleurInformel`
- * → autorisé par 1 `Consentement` (type partage)

---

### 3.14 AgentTerrain

**Responsabilité**  
Représenter l’accompagnant humain du pilote : sensibilisation, onboarding, collecte de retours.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité agent |
| `nom` | Texte | Identité |
| `zoneIntervention` | Texte | Ex. Ouagadougou |
| `actif` | Booléen | En mission |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-AT01 | Un agent n’accède pas aux secrets d’authentification du travailleur. |
| RM-AT02 | L’accompagnement n’implique pas la propriété des données du travailleur. |

**Relations**

- 1 — 0..* → `TravailleurInformel` (accompagnés)

---

### 3.15 Commission *(entité économique — post-MVP / structurante)*

**Responsabilité**  
Représenter la rémunération de NeoForma lorsqu’un crédit est effectivement accordé via la plateforme.

| Attribut | Type métier | Description |
|----------|-------------|-------------|
| `id` | Identifiant | Identité |
| `demandeCredit` | Réf. | Demande à l’origine |
| `montantCreditFcfa` | Montant | Principal décaissé |
| `tauxCommission` | Pourcentage | Ex. 1,5–3 % |
| `montantCommissionFcfa` | Montant | Calculé |
| `statut` | Enumération | due, facturee, payee |

**Règles métier**

| ID | Règle |
|----|-------|
| RM-COM01 | Une commission n’existe que si un crédit est effectivement accordé / décaissé via NeoForma. |
| RM-COM02 | Le travailleur n’est pas facturé directement. |

**Relations**

- 1 → liée à 1 `DemandeCredit`
- * → facturée à 1 `InstitutionMicrofinance`

---

## 4. Objets-valeurs récurrents

| Valeur | Définition métier |
|--------|-------------------|
| **MontantFcfa** | Entier ≥ 0 (strictement &gt; 0 pour opérations) |
| **TelephoneBurkina** | Numéro national utilisable comme identité |
| **Periode** | Intervalle de dates pour dashboard / score |
| **TrancheOrdinale** | Échelle qualitative (ancienneté, CA, Mobile Money) |
| **ReferenceMetier** | Code lisible humain (demande de crédit) |
| **PolitiqueConsentement** | Version textuelle acceptée |

---

## 5. Agrégats et invariants transverses

| Agrégat racine | Invariant principal |
|----------------|---------------------|
| `TravailleurInformel` | Unicité téléphone ; cycle de vie du compte |
| `Operation` | Appartenance exclusive ; montant valide ; créance cohérente |
| `NeoScore` | Bornes 0–100 ; éligibilité = f(seuil) ; critères explicites |
| `DemandeCredit` | Éligibilité + offre + consentement avant soumission |
| `InstitutionMicrofinance` | Accès profils uniquement si partenariat actif + consentement |

### Invariants transverses

| ID | Invariant |
|----|-----------|
| INV-01 | Pas de mise en relation IMF sans consentement explicite. |
| INV-02 | Le cahier (opérations) est la vérité de l’activité utilisateur. |
| INV-03 | Le NeoScore ne crée pas de dette ; il éclaire une décision de crédit. |
| INV-04 | L’historique local hors ligne ne doit pas produire de doublons après synchronisation. |
| INV-05 | NeoForma est tiers de confiance : elle ne remplace pas l’IMF dans l’octroi final du crédit. |

---

## 6. Cycles de vie (résumé)

### 6.1 Opération

```text
saisie (online|offline) → (si offline: en_attente) → synchronisée → (si créance: ouverte → en_retard? → réglée)
```

### 6.2 Demande de crédit

```text
éligibilité NeoScore → consultation offre → saisie demande → soumission
  → en_étude (IMF) → approuvée | refusée → (si approuvée) décaissée → commission éventuelle
```

### 6.3 Consentement de partage

```text
refusé (défaut prudent) ⇄ accordé → autorise AccesProfilImf → révocable
```

---

## 7. Matrice entités × responsabilités

| Entité | Pourquoi elle existe |
|--------|----------------------|
| TravailleurInformel | Sujet de l’inclusion financière |
| ProfilActivite | Contextualiser le risque / l’activité |
| PreferencesUtilisateur | Accessibilité et UX |
| Consentement | Légalité et confiance du partage |
| ClientInformel | Suivre les créances du cahier |
| Operation | Historiser l’économie réelle |
| OperationHorsLigne | Continuité terrain |
| NeoScore / CriteresScore | Traduire l’historique en solvabilité |
| OffreCredit | Borner une proposition de financement |
| DemandeCredit | Porter la demande jusqu’à l’IMF |
| InstitutionMicrofinance | Partenaire d’octroi |
| AccesProfilImf | Preuve de mise en relation |
| AgentTerrain | Déploiement humain du pilote |
| Commission | Modèle économique plateforme |

---

## 8. Hors périmètre du modèle métier actuel

Explicitement **non modélisés** ici (ou reportés) :

- détails techniques de persistance (SQL, Prisma, index…) ;
- jetons JWT / hash cryptographique (mécanismes d’infra, pas langage métier) ;
- modèles ML internes (features numériques brutes) — seuls les **concepts** NeoScore / critères apparaissent ;
- assurance micro, formations premium, Mobile Money transactionnel (extensions futures).

---

## 9. Traçabilité vers l’analyse

| Entité | Exigences / besoins liés |
|--------|---------------------------|
| TravailleurInformel | B-U01..07, EF-AUTH-* |
| ProfilActivite | EF-PROF-01..02 |
| Consentement | B-U06, EF-PROF-03, EF-CRD-04..05, C-R01 |
| Operation / ClientInformel | EF-OPS-01..07, EF-DASH-* |
| OperationHorsLigne | B-U02, EF-OPS-06..07, ENF-AVL-* |
| NeoScore | B-I01..03, EF-SCR-* |
| OffreCredit / DemandeCredit | B-U05, EF-CRD-01..03 |
| InstitutionMicrofinance / AccesProfilImf | B-I02..04, EF-CRD-04..06 |
| AgentTerrain | EF-OPS-ADM-02, C-O03 |
| Commission | O-E02, C-E01 |

---

## 10. Conclusion

Le domaine NeoForma s’organise autour de trois vérités métier :

1. **Le cahier** (`Operation`) rend l’activité visible.  
2. **Le NeoScore** transforme cette visibilité en solvabilité.  
3. **Le consentement + la demande de crédit** permettent une mise en relation responsable avec les **IMF**.

Ce modèle constitue le référentiel sémantique pour les prochaines étapes de conception (cas d’utilisation, bounded contexts détaillés, spécifications) — **toujours indépendamment de toute technologie de stockage**.
