# Pipemind — Reste à faire
Branche de travail : `dev/justin`
Mis à jour : 2026-06-27

---

## ✅ P0 + P1 — COMPLET

### Infrastructure & DB
- [x] `docker-compose.yml`, `.env.example`, `config/roster.example.json`
- [x] Migration `001-init-pipemind-schema.sql` — toutes les tables pipemind
- [x] Workflow 00 — Startup / Config Validation (validé + durci)

### Workflows (tous audités par l'agent sécurité)
- [x] **F-03** — Approval Gate (01, 01b, 01c + delivery executor 01c)
- [x] **F-08** — Aggregation Boundary (sous-workflow réutilisable)
- [x] **F-16** — Team Lead Interaction (listener Discord channel TL)
- [x] **F-01** — Client Progress Report (schedule + on-demand, idempotent)
- [x] **F-02** — Client Q&A (Discord client channel → F-08 → F-03)
- [x] **F-15** — Client Welcome (guildMemberAdd, atomic slot claim)
- [x] **F-17** — Developer Queries (DM, pas de gate, audit SC-03 local)
- [x] **F-14** — Persistent Memory (migration 003 + memory-reader 08)
- [x] **F-04** — Standup Ingestion (Drive trigger → LLM extract → F-08)
- [x] **F-05** — Check-ins Développeurs (migration 004 + workflow 10)
- [x] **F-07** — Time-Logging Helper (migration 005 + workflow 11 + 01c étendu + DM listener dans 07)

---

## Avant de tester en vrai

### Variables n8n à setter après import (Settings → Variables)
```
F08_WORKFLOW_ID               → ID de  "02 — F-08: Aggregation Boundary"
F03_WORKFLOW_ID               → ID de  "01 — F-03: Approval Gate"
F01_WORKFLOW_ID               → ID de  "04 — F-01: Client Progress Report"
DELIVERY_EXECUTOR_WORKFLOW_ID → ID de  "01c — F-03: Delivery Executor"
```

### Discord Developer Portal
- Activer le privileged intent **GUILD_MEMBERS** pour que F-15 reçoive les `guildMemberAdd` events

---

## Beyond P1

### F-06 — Unblock Assistance
- Détecter des patterns de blocage (ex. PR en review depuis 2 jours)
- Proposer de l'aide au dev concerné (DM uniquement)
- Jamais de remontée individuelle au TL

---

## Gaps identifiés par audit spec vs code

Ces items sont dans les specs mais **pas implémentés**. À décider si on les garde, simplifie, ou retire des specs.

| Priorité | Item | Détail |
|----------|------|--------|
| HIGH | F-02.2/F-02.3 — ask-a-teammate | Sous-flow entier manquant : Q&A va directement LLM → F-03 sans consulter un coéquipier |
| MED | SC-12 — self-mute/unmute par DM | Colonne `muted` existe et est appliquée, mais aucun handler "mute"/"unmute" dans workflow 07 |
| MED | SC-13 — commande explain | Zéro implémentation — ni dans workflow 03 (TL) ni dans workflow 07 (dev) |
| MED | F-04.2 — transcription audio | Pas de node Whisper/STT local — un fichier mp3 dans Drive échouerait silencieusement |
| LOW | F-15.4 — bot offline au join | Pas de récupération si le bot était offline quand le client a rejoint |

Items **partiellement couverts** (fonctionnels mais pas exhaustifs selon spec) :

| Item | Gap résiduel |
|------|-------------|
| F-01.8 — zéro signaux | Pas de branche structurelle "aucun signal" — LLM seul gère ça |
| F-04.4 — transcript en double | Pas de check "déjà ingéré aujourd'hui" avant l'appel LLM |
| F-04.5 — format non supporté | Pas de branche explicite "skip + notifier TL" |
| F-17.2 — dev demande son propre travail | memory-reader (08) jamais appelé depuis workflow 07 |
| SC-16 — validation startup | Workflow 00 valide le roster mais pas les env vars obligatoires |

---

## Dettes techniques / Sécurité

| Priorité | Item | Détail |
|----------|------|--------|
| MED | HIGH-04 : Validation channel draft expiré | Dans 01b, `Notify Expired` envoie au `discord_channel_id` du draft — pas de validation que ce channel est encore le bon |
| MED | F-17 : SC-03 local vs F-08 | F-17 audite SC-03 localement sans passer par F-08 — un seul point de vérité serait mieux. Refacto à planifier. |
| LOW | Workflow 06 — Expiry Janitor | Cron qui passe les drafts `pending` expirés à `expired` dans la DB |
| LOW | Docker network `internal: false` | Le réseau pipemind-internal est accessible depuis l'hôte — à durcir avant prod |
