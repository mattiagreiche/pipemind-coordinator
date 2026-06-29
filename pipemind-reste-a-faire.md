# Pipemind — Reste à faire
Branche de travail : `dev/justin`
Mis à jour : 2026-06-28

---

## ✅ P0 + P1 + Beyond P1 — COMPLET

### Infrastructure & DB
- [x] `docker-compose.yml`, `.env.example`, `config/roster.example.json`
- [x] Migrations `001` à `006`
- [x] Workflow 00 — Startup / Config Validation

### Workflows (tous audités par l'agent sécurité)
- [x] **F-03** — Approval Gate (01, 01b, 01c)
- [x] **F-08** — Aggregation Boundary
- [x] **F-16** — Team Lead Interaction
- [x] **F-01** — Client Progress Report
- [x] **F-02** — Client Q&A
- [x] **F-15** — Client Welcome
- [x] **F-17** — Developer Queries
- [x] **F-14** — Persistent Memory
- [x] **F-04** — Standup Ingestion
- [x] **F-05** — Check-ins Développeurs
- [x] **F-07** — Time-Logging Helper
- [x] **F-06** — Unblock Assistance (Beyond P1)

---

## Pour la prochaine session — Setup à compléter

### 1. Re-importer 7 workflows dans n8n (fix $vars → $env)
Les workflows suivants ont été modifiés localement mais pas encore re-importés dans n8n.
Pour chaque : ouvrir le workflow dans n8n → `...` → **Import from file** → sélectionner le fichier.
```
workflows/01-approval-gate.json
workflows/03-tl-interaction.json
workflows/04-client-report.json
workflows/05-client-qa.json
workflows/06-client-welcome.json
workflows/07-developer-query.json
workflows/09-standup-ingestion.json
```

### 2. Configurer roster.json
Copier `config/roster.example.json` → `config/roster.json` et remplir avec les vrais membres :
```json
{
  "team_lead": { "name": "...", "discord_id": "...", "clockify_user_id": "..." },
  "developers": [{ "name": "...", "discord_id": "...", "clockify_user_id": "..." }],
  "client": { "name": "...", "discord_id": "...", "discord_channel_id": "..." }
}
```

### 3. Puller le modèle Ollama
```
docker exec pipemind-coordinator-ollama-1 ollama pull llama3.2
```

### 4. Activer les workflows dans n8n (dans cet ordre)
1. **Workflow 00** — Startup Config Validation (active en premier — valide le roster)
2. **Workflow 01b** — Approval Resolution (Discord trigger)
3. **Workflow 01** — Approval Gate (sub-workflow)
4. **Workflow 01c** — Delivery Executor (sub-workflow)
5. **Workflow 02** — Aggregation Boundary (sub-workflow)
6. Tous les autres

### 5. Discord Developer Portal
- Activer le privileged intent **GUILD_MEMBERS** pour que F-15 reçoive les `guildMemberAdd` events
- Vérifier que le bot est bien dans le serveur Discord

### Variables n8n (déjà configurées dans .env)
```
F08_WORKFLOW_ID               = cWGTd6h2UKJV5GoM
F03_WORKFLOW_ID               = VATsRDYQMO5oYlP2
F01_WORKFLOW_ID               = wmNFx8yYrC7VLdGI
DELIVERY_EXECUTOR_WORKFLOW_ID = 1fGuoRwEUVwCGRpi
```
Note : Variables n8n est Enterprise-only — ces IDs sont passés via `$env` maintenant.

---

## Dettes techniques / Sécurité

### Audit pré-déploiement (2026-06-28) — fixes appliqués ✅
- [x] **CRIT-1** : Token Discord réel retiré de `.env.example` → remplacé par `op://` référence
- [x] **CRIT-2** : 5 variables manquantes ajoutées (`CLOCKIFY_WORKSPACE_ID`, `GITHUB_OWNER`, `GITHUB_REPO`, `JIRA_PROJECT_KEY`, `JIRA_AUTH`) dans `.env.example`, `docker-compose.yml`, Workflow 00
- [x] **CRIT-3** : Workflow 11 — `Save Message ID to Draft` ajouté après `Send Draft DM` (F-07 approval réparé)
- [x] **MED-2** : Workflow 00 — `Env Vars OK? false` branch branche maintenant aussi sur `Set roster_valid = false`

### ⚠️ Action manuelle requise : purge git history
Le token réel a été commité dans `f9a314e` (`.env.example`). À faire avant de merge ou pusher :
```
git filter-repo --path .env.example --invert-paths
# ou utiliser BFG Repo Cleaner
```
Token déjà révoqué dans Discord Developer Portal ? ✓

### Restant à corriger

| Priorité | Item | Détail |
|----------|------|--------|
| HIGH | F-06 : LIKE injection collègue | Dans 01b, `LIKE '%' || $1 || '%'` — changer pour `= LOWER($1)` (exact match) |
| HIGH | F-06 : Google Calendar check collègue | SC-06a partiel — seul Clockify est vérifié pour le schedule du collègue |
| MED | HIGH-04 : Validation channel draft expiré | Dans 01b, `Notify Expired` envoie au `discord_channel_id` sans revalider |
| MED | F-06 : dm_channel_id staleness | `dm_channel_id` peut être périmé si Discord réassigne |
| MED | F-17 : SC-03 local vs F-08 | F-17 audite SC-03 localement sans passer par F-08 |
| LOW | Docker network `internal: true` | Risque : n8n ne peut pas joindre Discord/GitHub/Jira/Clockify — vérifier en prod |
| LOW | Workflow 06 — Expiry Janitor | Cron qui passe les drafts `pending` expirés à `expired` |
| LOW | F-14 : `qa_history` sans `written_by_workflow` | Colonne manquante pour la traçabilité |
| LOW | F-02 : pas d'ack au client si 2 QAs pending | Client reçoit silence si cap atteint |

---

## Gaps identifiés (specs pas encore implémentées)

Ces items sont dans les specs mais **pas implémentés**. À décider si on les garde, simplifie, ou retire.

| Priorité | Item | Détail |
|----------|------|--------|
| HIGH | F-02.2/F-02.3 — ask-a-teammate | Q&A va directement LLM → F-03 sans consulter un coéquipier |
| MED | SC-12 — self-mute/unmute par DM | Colonne `muted` existe mais aucun handler "mute"/"unmute" dans les workflows |
| MED | SC-13 — commande explain | Zéro implémentation |
| MED | F-04.2 — transcription audio | Pas de node Whisper/STT — un fichier mp3 dans Drive échouerait silencieusement |
| LOW | F-15.4 — bot offline au join | Pas de récupération si le bot était offline quand le client a rejoint |

Items **partiellement couverts** :

| Item | Gap résiduel |
|------|-------------|
| F-01.8 — zéro signaux | Pas de branche structurelle "aucun signal" — LLM seul gère ça |
| F-04.4 — transcript en double | Pas de check "déjà ingéré aujourd'hui" avant l'appel LLM |
| F-04.5 — format non supporté | Pas de branche explicite "skip + notifier TL" |
| F-17.2 — dev demande son propre travail | memory-reader (08) jamais appelé depuis workflow 07 |
