# Diagrammes UML NeoForma (PlantUML)

## Contenu

| Fichier | Diagramme | Statut |
|---------|-----------|--------|
| `01-use-cases.puml` | Cas d'utilisation | Corrigé |
| `02-class-diagram.puml` | Classes métier | Corrigé |
| `03-sequence-login-mfa.puml` | Séquence Login MFA | Corrigé |
| `04-activity-login-mfa.puml` | Activité Login MFA | Corrigé |
| `uml-review.md` | Revue + backlog | Référence |

## Corrections appliquées (extrait)

- Extends sync **supprimés** ; UC13 autonome + note idempotence
- Include consentement → UC **Vérifier consentement partage IMF**
- UC ajoutés : renvoyer OTP, révoquer consentement, régler créance
- Cardinalités : Client 0..1, possession Client par Travailleur, Offre 0..\*, Commission 0..1
- `SnapshotScore` immuable (plus de dépendance vivante Demande→NeoScore)
- `OperationHorsLigne` rattachée au Travailleur ; lien post-acceptation vers Operation
- HER-01b : pas d’héritage Operation ; contraintes par type en note
- Package Application : `DefiOTP`, `SessionAuthentifiee`
- MFA : séquence ↔ activité alignées (SMS, renvoi, OTP consommé, boucle PIN, seuil)

## Décisions retenues

| # | Décision |
|---|----------|
| D1 | HER-01b — contraintes par type, pas d’héritage |
| D2 | `DefiOTP` / `Session` en package Application |
| D3 | OffreCredit **0..\*** dans le temps |
| D4 | Sync = UC autonome (pas d’extend) |
| D5 | Enrichir séquence pour coller à l’activité |

## Rendu

```bash
plantuml docs/uml/*.puml
```
