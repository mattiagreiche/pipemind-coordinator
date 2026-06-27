# Pipemind — Reste à faire
Branche de travail : `dev/justin`
Mis à jour : 2026-06-27

---

## Fait — P0 complet

### Infrastructure & DB
- [x] `docker-compose.yml`, `.env.example`, `config/roster.example.json`
- [x] Migration `001-init-pipemind-schema.sql` — toutes les tables pipemind
- [x] Workflow 00 — Startup / Config Validation (validé + durci)

### Workflows P0 (tous audités par l'agent sécurité)
- [x] **F-03** — Approval Gate (01, 01b, 01c + delivery executor 01c)
- [x] **F-08** — Aggregation Boundary (sous-workflow réutilisable)
- [x] **F-16** — Team Lead Interaction (listener Discord channel TL)
- [x] **F-01** — Client Progress Report (schedule + on-demand, idempotent)
- [x] **F-02** — Client Q&A (Discord client channel → F-08 → F-03)
- [x] **F-15** — Client Welcome (guildMemberAdd, atomic slot claim)
- [x] **F-17** — Developer Queries (DM, pas de gate, audit SC-03 local)

### Sécurité P0 — patterns universels en place
- SC-11 : LLM endpoint private-only (+ IPv6 ULA, `::ffff:`, `0.0.0.0`) dans F-08 et F-17
- SC-03 : zero attribution individuelle (normalize + hasWordBoundary + metric patterns) dans F-08 et F-17
- safeQuestion : strip control chars + `<>|{}` dans F-02 et F-17
- Approval gate : F-03 avant tout envoi client (F-01, F-02, F-15)
- Idempotence : `ON CONFLICT DO NOTHING RETURNING` dans F-01 et F-15
- Validate channel : assert `context_json.client_channel_id === $env.CLIENT_CHANNEL_ID` dans delivery executor

---

## Avant de tester en vrai

### Variables n8n à setter après import (Settings → Variables)
```
F08_WORKFLOW_ID  → ID de  "02 — F-08: Aggregation Boundary"
F03_WORKFLOW_ID  → ID de  "01 — F-03: Approval Gate"
F01_WORKFLOW_ID  → ID de  "04 — F-01: Client Progress Report"
```

### Discord Developer Portal
- Activer le privileged intent **GUILD_MEMBERS** pour que F-15 reçoive les `guildMemberAdd` events

---

## P1 — En cours

### ✅ F-14 — Persistent Memory (Postgres) — FAIT

- Migration 003 : tables `project_signals`, `standup_records`, `outreach_log`, `qa_history`
- Workflow 08 : sous-workflow `memory-reader` — purpose-gated (`report` / `tl_internal` / `dev_self`)
- Audité sécurité : HIGH-1 (SQL paramétrisé), HIGH-2 (roster guard), MED-1–4 fixés

### ✅ F-04 — Standup Ingestion — FAIT

- Google Drive trigger → LLM extract → standup_records + project_signals (via F-08)
- SC-14 double-pass, SC-11, SC-03 post-LLM name scan, F-14.5 newer signal wins
- Audité sécurité : CRIT-1 (F-08 rewritten text), CRIT-2, HIGH-1, HIGH-2, MED-1–2 fixés

### F-05 — Check-ins Développeurs

- DM optionnel à chaque dev le matin (vérifier Clockify/Calendar avant)
- **SC-06** : contacter seulement les gens schedulés ce jour-là
- Le dev peut répondre ou ignorer — jamais de relance
- Résultats agrégés (pas nominatifs) vers TL via F-03

### F-07 — Time-Logging Helper

- En fin de journée (`EOD_TIME`)
- Suggérer des entrées Clockify basées sur Git/Calendar
- Draft → approbation dev → écriture Clockify (write approuvé uniquement)
- Dépend de F-14 pour l'historique

### Ordre recommandé P1
```
✅ F-14 → ✅ F-04 → F-05 → F-07
```

---

## Beyond P1

### F-06 — Unblock Assistance

- Détecter des patterns de blocage (ex. PR en review depuis 2 jours)
- Proposer de l'aide au dev concerné (DM uniquement)
- Jamais de remontée individuelle au TL

---

## Dettes techniques / Sécurité

| Priorité | Item | Détail |
|----------|------|--------|
| MED | HIGH-04 : Validation channel draft expiré | Dans 01b, `Notify Expired` envoie au `discord_channel_id` du draft — pas de validation que ce channel est encore le bon |
| MED | F-17 : SC-03 local vs F-08 | F-17 audite SC-03 localement sans passer par F-08 — un seul point de vérité serait mieux. Refacto à planifier en P1. |
| LOW | Workflow 06 — Expiry Janitor | Cron qui passe les drafts `pending` expirés à `expired` dans la DB |
| LOW | Docker network `internal: false` | Le réseau pipemind-internal est accessible depuis l'hôte — à durcir avant prod |
