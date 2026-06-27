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

### ✅ F-05 — Check-ins Développeurs — FAIT

- Migration 004 : colonnes `muted`, `muted_at` (trigger auto-stamp), `calendar_email` sur roster
- Workflow 10 : Schedule → Roster guard → Fetch status (heard_from + already_contacted en 1 query) → Clockify → Strip PII → Calendar (freeBusy, max 50) → Compute → DM → Log
- SC-06/SC-06a : Clockify primary + Calendar secondary, stricter wins
- SC-18 : both unavailable → fail-safe + notify TL Discord channel
- SC-12 : mute flag filtré en DB (WHERE muted = FALSE)
- Audité sécurité : H-01 (nom exclu des logs execution), H-02 (Clockify strip userId-only), M-01 (continueOnFail sur DM nodes), M-02 (discord_id forwarded explicitement via Merge Send Result), M-03 (slice(0,50) freeBusy), M-04 (TL notification SC-18), L-02 (muted_at trigger), L-03 ([Pipemind] attribution) fixés

### ✅ F-07 — Time-Logging Helper — FAIT

- Migration 005 : `content_type` élargi à `'time_entry'` dans `approval_drafts`
- Workflow 11 : Schedule EOD → Roster guard → Fetch status (already_offered) → Clockify time-off → Strip → Calendar → Compute Actions (SC-06a/SC-18) → Split → Fetch standup (LEFT JOIN) → Check Dev Clockify Today → Build Draft or Route → Switch (offer / info_dm)
  - `offer` : Open DM → Create Approval Draft (RETURNING) → Send Draft DM → Merge Offer Result → If DM Sent? → Log Outreach
  - `info_dm` : Open DM → Send Info DM → Log Outreach
- 01c étendu : Route time_entry → Dedup Clockify → Fetch Dev Clockify ID → Parse Time Entry (hours from context_json + edited_text override) → Write Clockify Entry → Log Clockify Delivered → Confirm Dev DM
- Idempotent : dedup_key = `clockify_write:{draft_id}` dans delivered_actions
- SC-05 : Clockify entries existantes aujourd'hui → info_dm, jamais d'interprétation comme blocage
- **TODO connu** : Le DM response listener (gestionnaire des réponses "yes"/"edit Xh"/"no") n'est pas encore implémenté. La route doit être ajoutée à F-17 (workflow 07) pour détecter les commandes d'approbation dans les DM développeurs et appeler le delivery executor (01c) avec le draft_id.

### Ordre recommandé P1
```
✅ F-14 → ✅ F-04 → ✅ F-05 → ✅ F-07
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
