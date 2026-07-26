# Revue UML NeoForma — Corrections proposées

| | |
|---|---|
| **Document** | Analyse de cohérence des diagrammes UML |
| **Fichiers revus** | `01-use-cases.puml`, `02-class-diagram.puml`, `03-sequence-login-mfa.puml`, `04-activity-login-mfa.puml` |
| **Référentiels** | `analysis-report.md`, `domain-model.md`, `architecture.md` |
| **Décision** | Corrections **appliquées** aux `.puml` (juil. 2026) — toujours **sans** génération de code |
| **Version** | 1.1 (post-correction) |
| **Statut** | Voir `README.md` pour le détail des décisions D1–D5 retenues |

---

## 1. Synthèse exécutive

| Diagramme | Verdict | Gravité max |
|-----------|---------|-------------|
| Cas d’utilisation | Correct dans l’ensemble ; includes/extends à clarifier | Moyenne |
| Classes | Plusieurs écarts de cardinalité / composition vs domaine | **Haute** |
| Séquence Login MFA | Cohérent avec le MFA OTP+PIN ; lacunes de règles | Moyenne |
| Activité Login MFA | Légèrement plus riche que la séquence (désalignement) | Moyenne |

**Point critique** : le diagramme de classes n’est pas encore fidèle au `domain-model.md` sur `ClientInformel`, `OperationHorsLigne`, `OffreCredit` et l’absence d’héritage volontaire (OK) vs spécialisations d’`Operation` omises.

---

## 2. Cohérence inter-diagrammes

### 2.1 Ce qui est aligné

- MFA = **OTP (possession) + PIN (connaissance)** : UC02, séquence et activité sont d’accord.
- Acteurs principaux (Travailleur, Agent, IMF, SMS) cohérents UC ↔ analyse.
- Préconditions crédit (onboarding, éligibilité, consentement) présentes en note UC16 et note classe `DemandeCredit`.

### 2.2 Incohérences à corriger

| ID | Problème | Diagrammes | Correction proposée |
|----|----------|------------|---------------------|
| COH-01 | La **séquence** ne montre pas le renvoi OTP ni le seuil de tentatives PIN ; l’**activité** oui | 03 vs 04 | Aligner : soit enrichir la séquence (alt renvoi OTP + compteur PIN), soit simplifier l’activité au même niveau MVP |
| COH-02 | Compte `brouillon` : domaine l’autorise ; login MFA exige « actif » en séquence/activité — **création de compte** non chaînée au login | UC01, 03, 04, classes | Clarifier règle : après inscription + OTP, statut passe `brouillon`→`actif` ; login MFA refuse `brouillon` et `suspendu` |
| COH-03 | UC13 « Synchroniser » est à la fois **use case autonome** (acteur TI) et **extend** des enregistrements — double lecture confuse | 01 | Garder UC13 comme UC système/acteur ; remplacer `<<extend>>` par note « peut déclencher sync » **ou** faire de la sync un `<<include>>` conditionnel documenté |
| COH-04 | `DefiOTP` / `Session` absents du diagramme de classes mais centraux dans séquence MFA | 02 vs 03 | Ajouter classes métier `DefiOTP` et `SessionAuthentifiee` (ou les marquer « services d’application » hors modèle domaine strict) — **décision à trancher** |
| COH-05 | Pas de UC « Régler une créance » alors que la classe a `reglerCreance()` | 01 vs 02 | Ajouter UC21 « Régler / clôturer une créance » |

---

## 3. Cardinalités (diagramme de classes)

### 3.1 Erreurs / écarts vs `domain-model.md`

| ID | Relation actuelle | Problème | Cardinalité / type proposé |
|----|-------------------|----------|----------------------------|
| CARD-01 | `ClientInformel "1" <-- "0..*" Operation` | Toute opération n’a **pas** de client ; seul `creance` en a. Cardinalité côté client fausse (« 1 » obligatoire) | `ClientInformel "0..1" <-- "0..*" Operation : concerne` **et** contrainte : si `type=creance` alors client **1** |
| CARD-02 | `TravailleurInformel` ↔ `ClientInformel` **absente** | RM-CI01 : client scoped au travailleur | `TravailleurInformel "1" *-- "0..*" ClientInformel : possede` |
| CARD-03 | `Operation "1" o-- "0..1" OperationHorsLigne` | Sens inverse du domaine : la file hors-ligne **porte** l’intention d’opération ; une OpHL n’est pas un accessoire optionnel d’une Operation déjà persistée | `OperationHorsLigne "0..1" --> "1" Operation` (intention) **ou** composition `Travailleur "1" *-- "0..*" OperationHorsLigne` avec lien d’idempotence ; supprimer l’aggregation ambiguë actuelle |
| CARD-04 | `NeoScore "1" --> "0..1" OffreCredit` | Domaine : une offre **concerne** aussi le travailleur ; une offre peut donner 0..\* demandes. Lien Score→Offre OK mais incomplet | Ajouter `TravailleurInformel "1" --> "0..*" OffreCredit` **ou** `OffreCredit --> Travailleur` ; garder `NeoScore "1" --> "0..*" OffreCredit` (plusieurs offres dans le temps) plutôt que 0..1 |
| CARD-05 | `DemandeCredit "0..*" --> "0..1" OffreCredit` | Après soumission, l’offre de référence devrait être **obligatoire** (RM-DC02) | `DemandeCredit "0..*" --> "1" OffreCredit` pour statut ≥ `soumise` (documenter contrainte d’état) |
| CARD-06 | `DemandeCredit ..> NeoScore` (dépendance) | `scoreAuDepot` est un **snapshot**, pas une association vivante | Remplacer par attribut seul **ou** association `fige` vers une **valeur immuable** `SnapshotScore` ; éviter une dépendance navigable vers le NeoScore courant (qui change) |
| CARD-07 | `AccesProfilImf "0..1" --> "0..1" DemandeCredit` | Un accès peut exister sans demande ; une demande peut avoir 0..\* accès | `AccesProfilImf "0..*" --> "0..1" DemandeCredit` |
| CARD-08 | `Commission "1" --> "1" DemandeCredit` | Sens PlantUML ambigu (chaque commission → 1 demande OK) ; manque unicité inverse | Ajouter contrainte : **au plus une** commission par demande décaissée (`DemandeCredit "1" --> "0..1" Commission`) |

### 3.2 Compositions (`*--`) à revoir

| ID | Point | Proposition |
|----|-------|-------------|
| COMP-01 | `Travailleur *-- Operation` | Acceptable (agrégat cahier). OK |
| COMP-02 | `Travailleur *-- NeoScore` en 0..1 | Domaine = « vue courante ». Mieux : `1 -- 0..*` historiques + association dérivée `scoreCourant`, **ou** garder 0..1 « courant » + `HistoriqueScore` |
| COMP-03 | `Travailleur *-- Consentement` | OK ; ajouter contrainte d’unicité `(travailleur, type)` |

---

## 4. Héritages

### 4.1 Constat

**Aucun héritage** n’est modélisé. Ce n’est pas une erreur en soi (composition + enums).

### 4.2 Risque / oubli de conception

`Operation` mélange attributs de tous les types (`echeance`, `statutCreance`…), ce qui affaiblit les invariants RM-O03..O05.

| ID | Proposition (au choix) |
|----|------------------------|
| HER-01a | **Spécialisations** : `Vente`, `MouvementStock`, `Depense`, `CreanceClient` héritent de `Operation` (ou réalisent un type abstrait) |
| HER-01b | **Pas d’héritage** (préféré DDD strict) : garder une seule `Operation` + **contraintes OCL/règles** documentées par type ; retirer du diagramme les attributs non pertinents via stéréotypes / notes |

**Recommandation** : **HER-01b** pour rester aligné « modèle métier sans sur-ingénierie », mais **ajouter des notes de contraintes** par `TypeOperation`. Si l’équipe préfère UML pédagogique école, alors **HER-01a**.

Pas d’héritage acteur manquant : Agent / Travailleur / IMF sont des **rôles distincts**, pas une hiérarchie — correct.

---

## 5. Dépendances / includes / extends

### 5.1 Cas d’utilisation

| ID | Relation | Diagnostic | Correction |
|----|----------|------------|------------|
| DEP-01 | `UC16 <<include>> UC07` | Trop fort : ce n’est pas « exécuter la gestion des consentements », c’est **vérifier** un consentement déjà accordé | Remplacer par `<<include>> Vérifier consentement partage IMF` (UC dédié) **ou** précondition textuelle |
| DEP-02 | `UC15 <<include>> UC14` | Discutable : l’offre **dépend** du score, mais l’utilisateur ne « consulte » pas forcément le détail score | `UC15 ..> UC14 : <<include>>` → plutôt dépendance système « calculer/lire NeoScore » sans forcer l’UC consultation |
| DEP-03 | `UC08..11 <<extend>> UC13` | **Sens UML incorrect** : l’extend va de l’extension **vers** le base. Ici UC13 étendrait UC08, donc flèche `UC13 ..> UC08 <<extend>>`, pas l’inverse | **Inverser** les flèches extend **ou** abandonner extend (recommandé) |
| DEP-04 | `UC04 ..> SMS` | SMS est acteur externe : association OK, mais ce n’est pas un include entre UC | Garder association acteur ; retirer la notation include-like |
| DEP-05 | `UC18 <<include>> UC07` | Même problème que DEP-01 | Include « Vérifier consentement » |

### 5.2 Classes

| ID | Point | Correction |
|----|-------|------------|
| DEP-06 | Dépendance `DemandeCredit ..> NeoScore` | Voir CARD-06 (snapshot) |
| DEP-07 | Enums liés sans multiplicité | OK ; optionnel : `usage` / `modaliteRemboursement` / `etat` OperationHorsLigne → enums nommés (aujourd’hui `Enum` anonyme) |

---

## 6. Règles métier oubliées ou sous-représentées

| ID | Règle (domaine) | Où elle manque | Correction proposée |
|----|-----------------|----------------|---------------------|
| RM-01 | RM-T01 téléphone unique | Classe : note seulement | Contrainte `{unique}` sur `telephone` |
| RM-02 | RM-T03 / RM-T05 : pas de crédit si onboarding incomplet ou compte suspendu | Méthode `peutDemanderCredit()` sans détail | Note OCL / post-condition sur `DemandeCredit.soumettre()` |
| RM-03 | RM-C01..C03 révocation consentement | Absente UC + classes | UC « Révoquer consentement » ; règle sur `AccesProfilImf` |
| RM-04 | RM-O01 montant > 0 | Absente | Contrainte `{montantFcfa > 0}` |
| RM-05 | RM-O04 créance en retard | Méthode seule | Note dérivation `en_retard` |
| RM-06 | RM-OL03 idempotence sync | Absente diagrammes | Contrainte `{unique identifiantLocal}` + mention dans UC13 |
| RM-07 | RM-S03 eligible ⇔ score ≥ seuil | Note NeoScore OK | Ajouter sur séquence crédit (futur) ; OK pour l’instant |
| RM-08 | RM-DC04 scoreAuDepot immuable | Absente | Stéréotype `« immutable after submit »` |
| RM-09 | RM-DC05 transitions de statut ordonnées | Enum seule | Machine à états **recommandée** (diagramme 05 à créer) |
| RM-10 | RM-IMF01 partenariat actif | Méthode seule | Précondition UC18/UC19 |
| RM-11 | RM-AT01 agent n’accède pas au PIN | Absente | Note de sécurité sur UC20 |
| RM-12 | Login : défi OTP consommé une seule fois | Séquence OK partiellement | Ajouter en activité/séquence « OTP déjà consommé → rejet » |
| RM-13 | Échec SMS (passerelle indisponible) | Absent 03/04 | Alt `SMS échec` → message utilisateur |
| RM-14 | Compte `brouillon` post-register | Absent | Règle de cycle de vie compte (état) |

---

## 7. Corrections proposées par fichier (backlog)

### 7.1 `01-use-cases.puml`

1. Corriger ou supprimer les `<<extend>>` (DEP-03).  
2. Remplacer includes consentement par UC « Vérifier consentement partage ».  
3. Ajouter UC « Régler une créance ».  
4. Ajouter préconditions visibles sur UC18 (partenariat actif + consentement).  
5. Optionnel MVP : UC « Renvoyer OTP », « Mot de passe / PIN oublié » (hors scope actuel OK si noté).

### 7.2 `02-class-diagram.puml`

1. Appliquer CARD-01 à CARD-08.  
2. Lier `ClientInformel` au `TravailleurInformel`.  
3. Revoir `OperationHorsLigne`.  
4. Nommer les enums anonymes (`UsageCredit`, `ModaliteRemboursement`, `EtatOperationHorsLigne`, `StatutCompteBancaire`, `StatutCommission`).  
5. Décider HER-01a vs HER-01b + documenter contraintes par type d’opération.  
6. Ajouter `DefiOTP` / `SessionAuthentifiee` **ou** les exclure explicitement du modèle domaine (package « Application »).  
7. Inverser Commission ↔ Demande pour `0..1` commission.

### 7.3 `03-sequence-login-mfa.puml`

1. Ajouter alt **échec envoi SMS**.  
2. Ajouter boucle / limite **renvoi OTP**.  
3. Ajouter **compteur tentatives PIN** (alignement activité).  
4. Distinguer compte `brouillon` vs `suspendu` vs inexistant.  
5. Montrer consommation OTP (interdit de réutiliser le même défi).

### 7.4 `04-activity-login-mfa.puml`

1. Après PIN incorrect (sous seuil), permettre **nouvelle saisie** (boucle) au lieu de `stop` immédiat — sinon UX trop punitive vs séquence.  
2. Ajouter nœud « Échec envoi SMS ».  
3. Harmoniser avec la séquence une fois COH-01 tranché.

---

## 8. Décisions à valider (avant de modifier les `.puml`)

| # | Question | Options | Impact |
|---|----------|---------|--------|
| D1 | `Operation` spécialisée par héritage ? | Oui (HER-01a) / Non + contraintes (HER-01b) | Classes |
| D2 | `DefiOTP` / `Session` dans le domaine ? | Domaine / couche application séparée | Classes + séquence |
| D3 | Cardinalité OffreCredit dans le temps | 0..1 courant / 0..\* historique | Classes |
| D4 | Extend sync | Garder (corrigé) / supprimer | Use cases |
| D5 | Aligner séquence ↔ activité sur renvoi OTP & PIN | Enrichir 03 / simplifier 04 | MFA |

---

## 9. Conclusion

Les diagrammes forment une **bonne première version pédagogique**, mais **ne sont pas encore une baseline saine pour coder** :

1. **Cardinalités classes** à corriger en priorité (`ClientInformel`, `OperationHorsLigne`, `OffreCredit`, snapshot score).  
2. **Includes/extends** use cases à assainir (surtout sync).  
3. **Séquence vs activité MFA** à aligner.  
4. Plusieurs **RM-*** du domain model absentes ou implicites.

**Prochaine étape recommandée** : valider les décisions D1–D5, puis régénérer les `.puml` corrigés — toujours **sans génération de code**.
