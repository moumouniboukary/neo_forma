# Architecture technique NeoForma

> **Référence complète** : voir [`software-architecture.md`](./software-architecture.md)  
> (backend, frontend, base de données, API, sécurité, déploiement — post-UML validés).

## Esquisse dépôt (historique)

```mermaid
flowchart LR
  PWA[apps/web PWA] -->|REST JWT| API[apps/api Fastify]
  API --> DB[(PostgreSQL cible)]
  API --> REDIS[(Redis OTP/sessions)]
  API --> NS[@neoforma/neoscore]
  PWA --> OQ[Offline queue]
  OQ -->|/sync/push| API
  ML[services/neoscore Python] -.->|batch| NS
```

## Modules API cibles

`identity` · `profile` · `consent` · `ledger` · `sync` · `scoring` · `credit` · `partners`

## Flux critiques

- **Auth MFA** : OTP SMS → PIN → session  
- **Sync** : `identifiantLocal` idempotent  
- **Crédit** : éligibilité + offre + consentement + `SnapshotScore`
