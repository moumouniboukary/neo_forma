# NeoForma — Rapport d’analyse des besoins

| | |
|---|---|
| **Document** | Analyse des besoins (phase de conception) |
| **Projet** | NeoForma |
| **Sources analysées** | `NeoForma_Dossier_DAMINA_2026`, `NeoForma_Dossier_POESAM_2026`, `architecture.md` |
| **Périmètre géographique initial** | Burkina Faso (Ouagadougou — pilote) |
| **Secteur** | FinTech · Inclusion financière · Intelligence artificielle |
| **Stade déclaré** | Conception / validation terrain · MVP à venir |
| **Version** | 1.0 |
| **Date** | Juillet 2026 |

---

## 1. Objet du document

Ce rapport formalise, à partir des dossiers de candidature et de la note d’architecture technique, une **analyse de besoins de type entreprise** (ingénierie des exigences).

Il ne prescrit pas d’implémentation. Il sert de base pour :

- le cadrage produit ;
- la rédaction du cahier des charges ;
- la priorisation MVP / pilote ;
- la conception architecture et les spécifications ultérieures.

---

## 2. Contexte et problème métier

### 2.1 Contexte

Au Burkina Faso, plus de **80 % des actifs** travaillent dans le secteur informel (INSD, 2022). Environ **20 %** seulement de la population adulte est bancarisée (Banque mondiale, 2021). Des millions de commerçants, artisans, mécaniciens, menuisiers génèrent des revenus réels, mais leur activité reste **invisible** pour le système financier formel (cahier papier ou mémoire).

Les institutions de microfinance (IMF) cherchent à servir ce marché sans disposer d’outils adaptés pour évaluer la solvabilité hors critères bancaires classiques.

### 2.2 Problème central

> L’activité économique du travailleur informel est réelle, mais non documentée de façon exploitable : absence d’historique financier → exclusion du crédit.

### 2.3 Positionnement de NeoForma

NeoForma se positionne comme **tiers de confiance numérique** :

1. transformer le cahier traditionnel en **passeport financier numérique** ;
2. construire un **historique d’activité** (ventes, stocks, créances) ;
3. produire un **score de solvabilité alternatif (NeoScore)** ;
4. **mettre en relation**, avec consentement, l’utilisateur et les IMF partenaires.

---

## 3. Besoins identifiés

### 3.1 Besoins utilisateurs finaux (travailleurs informels)

| ID | Besoin | Formulation |
|----|--------|-------------|
| B-U01 | Traçabilité simple de l’activité | Enregistrer ventes, dépenses, stocks et dettes clients sans formation lourde |
| B-U02 | Continuité d’usage terrain | Pouvoir travailler malgré connectivité limitée (mode hors ligne) |
| B-U03 | Accessibilité | Utiliser l’outil malgré faible alphabétisation (icônes, vocal, langues locales) |
| B-U04 | Visibilité de l’activité | Comprendre l’évolution de son chiffre d’affaires, créances, clients |
| B-U05 | Accès au financement | Obtenir un microcrédit sur la base d’un historique réel, pas de garanties classiques |
| B-U06 | Contrôle des données | Consentir explicitement au partage de profil avec des partenaires financiers |
| B-U07 | Confiance / non-peur fiscale | Adopter l’outil sans crainte que les données soient utilisées contre soi (besoin de confiance) |

### 3.2 Besoins institutions de microfinance (IMF)

| ID | Besoin | Formulation |
|----|--------|-------------|
| B-I01 | Données de solvabilité | Évaluer des clients informels sans bulletin de salaire ni historique bancaire |
| B-I02 | Scoring exploitable | Disposer d’un score et d’un profil qualifié, idéalement via API / tableau de bord |
| B-I03 | Réduction du risque | S’appuyer sur des signaux comportementaux (régularité, volume, progression, créances) |
| B-I04 | Accès à un nouveau marché | Atteindre un segment solvable aujourd’hui inaccessible |

### 3.3 Besoins écosystème / institutionnels

| ID | Besoin | Formulation |
|----|--------|-------------|
| B-E01 | Formalisation progressive | Contribuer à structurer le secteur informel (vision nationale / ODD) |
| B-E02 | Inclusion des femmes | Prioriser les commerçantes (cible > 50 % d’utilisatrices) |
| B-E03 | Inclusion numérique | Lever la barrière linguistique et d’alphabétisation (mooré, dioula, fulfuldé) |
| B-E04 | Scalabilité régionale | Préparer une extension Ouest-africaine (Mali, Niger, Côte d’Ivoire, Sénégal…) |

### 3.4 Besoins plateforme (issus de l’architecture technique)

| ID | Besoin | Formulation |
|----|--------|-------------|
| B-P01 | Identité et accès | Authentifier l’utilisateur (OTP, PIN, session sécurisée) |
| B-P02 | Synchronisation | Réconcilier opérations locales et serveur de façon fiable / idempotente |
| B-P03 | Scoring runtime | Calculer un NeoScore à partir du profil et de l’activité récente |
| B-P04 | Cycle crédit | Proposer une offre, soumettre une demande, suivre un statut |
| B-P05 | Évolution ML | Séparer score runtime et entraînement / recalibrage batch |

---

## 4. Objectifs reformulés

### 4.1 Objectif stratégique (mission)

**Rendre visible et finançable l’activité économique des travailleurs du secteur informel** en produisant un historique numérique fiable et un scoring alternatif accepté par les IMF.

### 4.2 Objectifs métier

| ID | Objectif | Indicateur associé (docs) |
|----|----------|---------------------------|
| O-M01 | Créer des profils numériques d’activité pour les travailleurs informels | Nombre de profils créés |
| O-M02 | Faciliter l’octroi de microcrédits via la plateforme | Nombre et montants de crédits accordés |
| O-M03 | Valider la qualité du scoring | Taux de remboursement des crédits |
| O-M04 | Mesurer l’impact économique utilisateur | Croissance du CA après accès au crédit |
| O-M05 | Favoriser l’inclusion des femmes | Proportion d’utilisatrices > 50 % |
| O-M06 | Atteindre un pilote terrain viable | 50–100 commerçants (MVP) ; projection A1 : 2 000 utilisateurs actifs |

### 4.3 Objectifs produit

| ID | Objectif |
|----|----------|
| O-P01 | Fournir un **cahier numérique ultra-simplifié** (enregistrement quotidien) |
| O-P02 | Produire un **NeoScore** compréhensible (0–100, critères comportementaux) |
| O-P03 | Assurer une **mise en relation consentie** avec les IMF |
| O-P04 | Offrir un **tableau de bord** simple d’activité |
| O-P05 | Garantir **accessibilité** (icônes → vocal → langues locales) |

### 4.4 Objectifs techniques (architecture)

| ID | Objectif |
|----|----------|
| O-T01 | Application mobile / PWA utilisable hors ligne avec synchronisation |
| O-T02 | API métier (auth, users, operations, dashboard, score, credit, sync) |
| O-T03 | Contrats de domaine partagés et moteur de scoring runtime |
| O-T04 | Pipeline ML séparé pour entraînement / recalibrage |
| O-T05 | Évolutivité vers Postgres, SMS réel, app native, modèle exportable |

### 4.5 Objectifs économiques (modèle)

| ID | Objectif |
|----|----------|
| O-E01 | Application **gratuite** pour l’utilisateur final |
| O-E02 | Revenus principaux par **commission** sur crédits accordés (ex. 1,5–3 %) |
| O-E03 | Revenus complémentaires par **abonnement IMF** (API scoring / dashboard) |
| O-E04 | Services premium utilisateurs à partir de l’année 2 |

---

## 5. Fonctionnalités identifiées

### 5.1 Modules produit (dossiers DAMINA / POESAM)

| Module | Fonctionnalités |
|--------|-----------------|
| **Enregistrement** | Saisie ventes, dépenses, stocks, crédits clients ; interface icônes ; support vocal prévu ; mode hors ligne |
| **Scoring (NeoScore)** | Score de solvabilité automatique (régularité, volume, progression / croissance, gestion des créances) ; ML adapté aux données informelles |
| **Mise en relation** | Accès IMF au profil anonymisé / scoré ; consentement explicite utilisateur ; interface sécurisée |
| **Tableau de bord** | CA mensuel, meilleurs clients, créances en cours, évolution d’activité |

### 5.2 Capacités techniques complémentaires (architecture.md)

| Domaine | Fonctionnalités |
|---------|-----------------|
| **Auth** | OTP, enregistrement / connexion PIN, jeton JWT |
| **Onboarding / profil** | Collecte métier, tontine, mobile money, consentements |
| **Opérations** | CRUD métier des opérations (vente / stock / dette) |
| **Sync** | File offline → push idempotent (`clientMutationId`) |
| **Crédit** | Calcul d’offre selon score, soumission de demande, suivi de statut |
| **ML batch** | Entraînement / recalibrage NeoScore (service Python) |

### 5.3 Roadmap d’accessibilité (fonctionnalités différées)

| Phase | Capacité |
|-------|----------|
| 1 | Interface à icônes universelles (sans lecture obligatoire) |
| 2 | Module vocal FR + langues locales via API existantes |
| 3 | Reconnaissance vocale dédiée mooré / dioula / fulfuldé (ex. partenariat type Masakhane) |

### 5.4 Fonctionnalités hors MVP immédiat (business plan)

- Rapports avancés utilisateurs  
- Module assurance micro  
- Formations financières digitales  
- Intégration paiements Mobile Money (Orange Money, etc.) — partenariat stratégique  

---

## 6. Contraintes identifiées

### 6.1 Contraintes métier et marché

| ID | Contrainte |
|----|------------|
| C-M01 | Public majoritairement **non ou peu bancarisé**, parfois peu alphabétisé |
| C-M02 | **Méfiance** potentielle des commerçants (peur fiscale / contrôles) |
| C-M03 | Adoption conditionnée à la **confiance** et à la simplicité perçue |
| C-M04 | Dépendance aux **partenariats IMF** pour la valeur crédit |
| C-M05 | Pilote initial limité (50–100 commerçants) avant montée en charge |

### 6.2 Contraintes techniques et infrastructurelles

| ID | Contrainte |
|----|------------|
| C-T01 | **Connectivité mobile** intermittente ; zones rurales limitées |
| C-T02 | Usage sur **smartphone** (pénétration mobile > 50 %, mais hétérogène) |
| C-T03 | Mode **hors ligne obligatoire** pour l’enregistrement quotidien |
| C-T04 | Score basé sur des **données comportementales** souvent bruitées / non structurées |
| C-T05 | Architecture actuelle : PWA + API ; évolution prévue vers native, Postgres, SMS réel |

### 6.3 Contraintes réglementaires et éthiques

| ID | Contrainte |
|----|------------|
| C-R01 | **Consentement explicite** avant partage de profil avec IMF |
| C-R02 | Possibilité de **profil anonymisé** côté partenaires |
| C-R03 | Traitement de données financières personnelles → exigences de confidentialité / sécurité |
| C-R04 | Alignement social attendu (ODD 1, 4, 5, 8, 10) — contrainte de mission, pas seulement marketing |

### 6.4 Contraintes organisationnelles et projet

| ID | Contrainte |
|----|------------|
| C-O01 | Projet en **phase initiale** ; MVP lié à la mobilisation de fonds |
| C-O02 | Équipe jeune / pluridisciplinaire (produit, tech, terrain) — capacité limitée |
| C-O03 | Besoin d’**agents terrain** pour onboarding et collecte |
| C-O04 | Budget A1 projeté sous tension (résultat net négatif année 1 dans les dossiers) |

### 6.5 Contraintes de modèle économique

| ID | Contrainte |
|----|------------|
| C-E01 | Gratuité utilisateur final → monétisation côté **IMF / commission** |
| C-E02 | Conversion crédit estimée ~10 % des actifs / an (hypothèse dossier) |
| C-E03 | Dépendance au volume de crédits réellement décaissés |

---

## 7. Acteurs identifiés

### 7.1 Acteurs primaires

| Acteur | Rôle | Intérêt |
|--------|------|---------|
| **Travailleur informel** (commerçant, artisan, mécanicien, menuisier…) | Utilisateur principal de l’app | Gérer son activité, construire un historique, accéder au crédit |
| **Commerçante / femme du secteur informel** | Segment prioritaire | Même usage + objectif d’inclusion genre |
| **Institution de microfinance (IMF)** (ex. RCPB, Coris, ACEP) | Partenaire / consommateur du scoring | Évaluer le risque, octroyer des crédits, élargir le portefeuille |
| **Agent terrain NeoForma** | Onboarding, sensibilisation, collecte | Déployer le pilote, accompagner l’adoption |

### 7.2 Acteurs secondaires

| Acteur | Rôle |
|--------|------|
| **Opérateur Mobile Money** (ex. Orange Money) | Partenaire paiement / intégration future |
| **Ministère du Commerce / PME** | Légitimité institutionnelle, cadre d’appui |
| **Équipe NeoForma** (CEO produit/scoring, tech, terrain) | Conception, exploitation, partenariats |
| **Initiatives NLP africaines** (ex. Masakhane) | Partenaires accessibilité vocale langues locales |

### 7.3 Acteurs système (techniques)

| Acteur système | Rôle |
|----------------|------|
| Application client (PWA / mobile) | Interface utilisateur, cache offline |
| API NeoForma | Orchestration métier, auth, sync, crédit |
| Moteur NeoScore (runtime) | Calcul du score |
| Service ML (batch) | Entraînement / recalibrage |
| Base de données | Persistance profils, opérations, demandes de crédit |
| Passerelle SMS (future) | Délivrance OTP réelle |

### 7.4 Diagramme des acteurs (vue métier)

```mermaid
flowchart TB
  TI[Travailleur informel]
  IMF[Institution de microfinance]
  AT[Agent terrain]
  MM[Opérateur Mobile Money]
  MIN[Ministère / institutions]
  NF[Plateforme NeoForma]

  TI -->|enregistre activité / consulte score / demande crédit| NF
  AT -->|onborde et accompagne| TI
  AT -->|remonte feedback terrain| NF
  IMF -->|consulte profils scorés consentis / API| NF
  NF -->|met en relation / signaux de risque| IMF
  MM -.->|intégration paiement future| NF
  MIN -.->|légitimité / cadre| NF
```

---

## 8. Exigences fonctionnelles

Convention : **EF-xxx** — exigence fonctionnelle. Priorité indicative : **M** (Must / MVP), **S** (Should), **C** (Could / roadmap).

### 8.1 Authentification et compte

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-AUTH-01 | L’utilisateur doit pouvoir créer un compte (téléphone + code secret / PIN) | M | architecture |
| EF-AUTH-02 | Le système doit permettre une vérification OTP du numéro | M | architecture |
| EF-AUTH-03 | L’utilisateur doit pouvoir se connecter et maintenir une session sécurisée | M | architecture |
| EF-AUTH-04 | L’utilisateur doit pouvoir se déconnecter | S | architecture / usage app |

### 8.2 Onboarding et profil

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-PROF-01 | L’utilisateur doit renseigner des éléments de profil d’activité (métier, ancienneté, niveau d’activité…) | M | dossiers + architecture |
| EF-PROF-02 | L’utilisateur doit pouvoir indiquer tontine / usage Mobile Money / compte | S | architecture / terrain |
| EF-PROF-03 | L’utilisateur doit gérer ses consentements (anonymisation, partage IMF, marketing) | M | dossiers (consentement explicite) |
| EF-PROF-04 | L’utilisateur doit pouvoir choisir une langue d’interface (FR + langues locales à terme) | S → C | dossiers accessibilité |

### 8.3 Enregistrement d’activité

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-OPS-01 | L’utilisateur doit pouvoir enregistrer une **vente** (montant, libellé éventuel) | M | dossiers |
| EF-OPS-02 | L’utilisateur doit pouvoir enregistrer un mouvement de **stock** | M | dossiers |
| EF-OPS-03 | L’utilisateur doit pouvoir enregistrer une **dette / créance client** (client, montant, échéance) | M | dossiers |
| EF-OPS-04 | L’utilisateur doit pouvoir enregistrer des **dépenses** | S | dossiers DAMINA/POESAM |
| EF-OPS-05 | L’interface d’enregistrement doit être ultra-simplifiée (peu d’étapes, montants en FCFA) | M | dossiers |
| EF-OPS-06 | L’enregistrement doit être possible **hors ligne** | M | dossiers + architecture |
| EF-OPS-07 | Les opérations hors ligne doivent être synchronisées dès le retour réseau sans doublon | M | architecture |

### 8.4 Tableau de bord

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-DASH-01 | L’utilisateur doit voir son chiffre d’affaires sur une période (ex. mois) | M | dossiers |
| EF-DASH-02 | L’utilisateur doit voir le montant des créances en cours | M | dossiers |
| EF-DASH-03 | L’utilisateur doit voir une évolution récente de l’activité (ex. 7 jours) | S | architecture / maquette |
| EF-DASH-04 | L’utilisateur doit consulter les dernières opérations | M | architecture |
| EF-DASH-05 | L’utilisateur doit identifier ses meilleurs clients / créances critiques | S | dossiers |

### 8.5 NeoScore

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-SCR-01 | Le système doit calculer un score de solvabilité (NeoScore) à partir de l’historique | M | dossiers |
| EF-SCR-02 | Le score doit intégrer au minimum régularité, volume, progression/croissance et qualité de gestion des créances | M | dossiers |
| EF-SCR-03 | L’utilisateur doit pouvoir consulter son score et des détails compréhensibles | M | dossiers / architecture |
| EF-SCR-04 | Le système doit déterminer une éligibilité crédit selon un seuil | M | architecture |
| EF-SCR-05 | Le moteur doit pouvoir être recalibré via un processus ML batch | C | architecture |

### 8.6 Crédit et mise en relation IMF

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-CRD-01 | Un utilisateur éligible doit pouvoir consulter une offre indicative de crédit | M | architecture |
| EF-CRD-02 | L’utilisateur doit pouvoir soumettre une demande de crédit (montant, usage, modalités) | M | architecture |
| EF-CRD-03 | Le système doit enregistrer et exposer le statut de la demande | M | architecture |
| EF-CRD-04 | Une IMF partenaire doit pouvoir accéder à un profil scoré **uniquement avec consentement** | M | dossiers |
| EF-CRD-05 | Le profil partagé doit pouvoir être anonymisé selon le paramétrage de consentement | M | dossiers |
| EF-CRD-06 | Les IMF doivent pouvoir consommer le scoring via API / tableau de bord partenaire | S | dossiers (abonnement IMF) |

### 8.7 Accessibilité

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-ACC-01 | L’UI doit proposer une navigation majoritairement iconographique | S | dossiers |
| EF-ACC-02 | Le système doit supporter une saisie / assistance vocale (FR puis langues locales) | C | dossiers |
| EF-ACC-03 | Le système doit viser le support mooré, dioula, fulfuldé | C | dossiers |

### 8.8 Administration / exploitation (implicite entreprise)

| ID | Exigence | Priorité | Source |
|----|----------|----------|--------|
| EF-OPS-ADM-01 | L’équipe doit pouvoir suivre les indicateurs d’impact (profils, crédits, remboursements, genre) | S | dossiers |
| EF-OPS-ADM-02 | Les agents terrain doivent pouvoir accompagner l’inscription / l’usage (processus organisationnel + éventuel back-office) | S | dossiers équipe / fonds |

---

## 9. Exigences non fonctionnelles

Convention : **ENF-xxx**.

### 9.1 Utilisabilité et accessibilité

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-UX-01 | Prise en main sans formation formelle (solution « ultra-simple ») | M |
| ENF-UX-02 | Parcours d’enregistrement en un nombre minimal d’actions | M |
| ENF-UX-03 | Interface adaptée aux faibles compétences numériques / littératie | M |
| ENF-UX-04 | Support multilingue progressif (FR → langues locales) | S/C |
| ENF-UX-05 | Montants et libellés adaptés au contexte FCFA / métiers informels | M |

### 9.2 Disponibilité et résilience

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-AVL-01 | Fonctions critiques d’enregistrement disponibles hors ligne | M |
| ENF-AVL-02 | Reprise de synchronisation automatique à la reconnexion | M |
| ENF-AVL-03 | Tolérance à une connectivité intermittente | M |

### 9.3 Performance

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-PER-01 | Réponses API interactives adaptées à un réseau mobile moyen (latence perçue acceptable) | S |
| ENF-PER-02 | Calcul NeoScore suffisamment rapide pour consultation à la demande | M |
| ENF-PER-03 | Capacité à monter vers des milliers d’utilisateurs (projections A1–A3) | S |

### 9.4 Sécurité et confidentialité

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-SEC-01 | Authentification forte côté utilisateur (PIN + jeton de session) | M |
| ENF-SEC-02 | Protection des échanges client–serveur (canal sécurisé en production) | M |
| ENF-SEC-03 | Contrôle d’accès strict aux profils IMF (consentement + authentification partenaire) | M |
| ENF-SEC-04 | Minimisation / anonymisation des données partagées aux partenaires | M |
| ENF-SEC-05 | Traçabilité des consentements et des partages | S |
| ENF-SEC-06 | Stockage sécurisé des secrets (PIN hashé, clés hors code source) | M |

### 9.5 Fiabilité des données et intégrité

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-DAT-01 | Idempotence de la synchronisation (pas de doublons d’opérations) | M |
| ENF-DAT-02 | Cohérence du score avec l’historique réellement synchronisé | M |
| ENF-DAT-03 | Horodatage fiable des opérations (y compris créées offline) | M |

### 9.6 Maintenabilité et évolutivité

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-MAI-01 | Séparation claire présentation / API / scoring / ML batch | S |
| ENF-MAI-02 | Contrats de domaine partagés pour limiter les divergences client–serveur | S |
| ENF-MAI-03 | Possibilité de remplacer SQLite par Postgres sans refonte métier | S |
| ENF-MAI-04 | Roadmap native mobile sans casser les contrats métier | C |
| ENF-MAI-05 | Possibilité d’exporter le modèle ML (ex. vers format runtime portable) | C |

### 9.7 Interopérabilité

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-INT-01 | API consommable par les IMF (scoring / profils qualifiés) | S |
| ENF-INT-02 | Préparation d’intégration Mobile Money | C |
| ENF-INT-03 | OTP via passerelle SMS réelle en production | S |

### 9.8 Conformité et impact

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-CMP-01 | Respect du consentement comme prérequis au partage IMF | M |
| ENF-CMP-02 | Mesurabilité des indicateurs d’impact (profils, crédits, remboursement, genre) | S |
| ENF-CMP-03 | Conception non discriminatoire et inclusive (genre, langue, littératie) | M |

### 9.9 Contraintes de déploiement initial

| ID | Exigence | Priorité |
|----|----------|----------|
| ENF-DEP-01 | Déploiement MVP pour pilote Ouagadougou (50–100 utilisateurs) | M |
| ENF-DEP-02 | Coût d’entrée utilisateur nul (gratuité app) | M |
| ENF-DEP-03 | Architecture compatible avec une montée progressive partenaires IMF (3 → 15) | S |

---

## 10. Synthèse des priorités MVP (pilote)

À retenir pour la conception « entreprise » du premier livrable testable :

**Dans le MVP**
- Compte + authentification  
- Enregistrement vente / stock / dette  
- Hors ligne + sync fiable  
- Tableau de bord simple  
- NeoScore consultable + éligibilité  
- Demande de crédit + consentement de partage  

**Hors MVP strict (mais structurants)**
- Vocal / langues locales avancées  
- Back-office IMF complet  
- Mobile Money  
- Premium utilisateurs  
- Expansion panafricaine  

---

## 11. Risques liés aux exigences (extrait)

| Risque | Lien exigences | Mitigation conceptuelle |
|--------|----------------|-------------------------|
| Non-adoption par peur fiscale | B-U07, C-M02 | Pédagogie terrain, transparence consentements, message « passeport » non fiscal |
| Score peu fiable au démarrage | EF-SCR-*, données limitées | Pilote contrôlé, recalibrage ML, seuil d’éligibilité prudent |
| Dépendance connectivité | ENF-AVL-*, C-T01 | Offline-first dès le MVP |
| Blocage sans partenaires IMF | EF-CRD-04..06, C-M04 | Signature partenariats dès le pilote (objectif dossiers) |
| Exclusion numérique | EF-ACC-*, ENF-UX-03 | Icônes d’abord, vocal ensuite |

---

## 12. Conclusion

Les documents analysés convergent vers un produit d’**inclusion financière data-driven** :

1. **besoin massif** d’historisation de l’activité informelle ;  
2. **objectif** de transformer cette historisation en **accès au crédit** via un tiers de confiance ;  
3. **fonctionnalités** centrées sur enregistrement, scoring, dashboard et mise en relation ;  
4. **contraintes** fortes d’accessibilité, d’offline, de confiance et de partenariats ;  
5. **acteurs** clairement bipolaires (travailleur ↔ IMF), avec NeoForma comme plateforme médiatrice ;  
6. **exigences fonctionnelles** déjà structurables en domaines auth / ops / score / crédit / sync ;  
7. **exigences non fonctionnelles** dominées par utilisabilité, résilience réseau, sécurité des consentements et évolutivité.

Ce rapport constitue la **baseline d’exigences** pour les étapes suivantes de conception (cas d’utilisation, backlog MVP, architecture cible, spécifications détaillées) — **sans décision d’implémentation dans le présent document**.

---

## Annexe A — Traçabilité des sources

| Source | Apports principaux |
|--------|--------------------|
| Dossier DAMINA 2026 | Problème, marché, modules produit, NeoScore, accessibilité, modèle économique, impact, ODD |
| Dossier POESAM 2026 | Même socle + équipe, projections financières, usage des fonds, partenaires, vision panafricaine |
| `architecture.md` | Découpage technique, flux auth/offline/score, modules API, évolutions prévues |

## Annexe B — Glossaire

| Terme | Définition |
|-------|------------|
| **NeoScore** | Score de solvabilité alternatif (0–100) fondé sur des signaux comportementaux d’activité |
| **IMF** | Institution de microfinance |
| **MVP** | Minimum Viable Product — version minimale testable |
| **Offline-first** | Capacité à utiliser les fonctions critiques sans réseau, puis synchroniser |
| **Tiers de confiance** | Rôle de NeoForma entre travailleur informel et institution financière |
