# Pipemind Coordinator — État du projet

## Ce qui est fait

### Infrastructure
- [x] Stack Docker complète : n8n 1.91.3 + Postgres 16 + Ollama + discord-forwarder
- [x] Schéma Postgres complet (`pipemind.*`) avec migrations 001-006
- [x] Secrets via 1Password CLI (`op://` refs) — aucune vraie valeur dans les fichiers
- [x] `config/roster.json` — source de vérité pour l'équipe et le client

### Discord
- [x] Service `discord-forwarder` : bridge entre Discord Gateway et n8n webhooks
  - Messages `#client` → webhook `client-qa`
  - Messages `#tl-approvals` → webhook `tl-interaction`
  - DMs → webhook `dev-query`
  - Nouveau membre → webhook `member-join`
- [x] Bot Pipemind ajouté au serveur Discord et aux channels privés `#client` / `#tl-approvals`

### Workflows n8n (logique validée)
Les workflows suivants reçoivent les messages Discord, vérifient l'identité via Postgres,
et appliquent les règles de privacy — la logique est correcte jusqu'aux appels API externes.

| Workflow | Feature | Validé jusqu'à |
|----------|---------|----------------|
| 03 — TL Interaction | F-16 | Classify Intent (bloque sur Ollama) |
| 05 — Client Q&A | F-02 | Fetch GitHub Signals (bloque sur token) |
| 06 — Client Welcome | F-15 | Call F-03 Approval Gate (bloque sur F03_WORKFLOW_ID) |
| 07 — Developer Query | F-17 | Route Message Type (bloque sur Ollama) |
| 01 — Approval Gate | F-03 | Importé, logique complète, non testé en prod |
| 01b — Approval Resolution | F-03 | Importé, non testé |
| 01c — Delivery Executor | F-03 | Importé, non testé |
| 02 — Aggregation Boundary | F-08 | Importé, non testé |

### Corrections techniques majeures
- Remplacement de `discordTrigger` (inexistant en n8n 1.91.3) par des webhook nodes
- Bug n8n 1.91.3 : les IF nodes avec comparaison booléenne sont imprévisibles → remplacés par des Code nodes avec `return []`
- Connexions IF inversées corrigées dans workflows 05, 06, 07

---

## Ce qui reste à faire

### 1. Credentials manquants — priorité haute
Sans ces credentials, les workflows s'arrêtent à mi-chemin.

- [ ] **GitHub** : `GITHUB_TOKEN`, `GITHUB_OWNER`, `GITHUB_REPO` dans `.env`
- [ ] **Jira** : `JIRA_BASE_URL`, `JIRA_TOKEN`, `JIRA_AUTH`, `JIRA_PROJECT_KEY` dans `.env`
- [ ] **Ollama** : télécharger un modèle LLM
  ```
  docker exec pipemind-coordinator-ollama-1 ollama pull llama3.2
  ```
- [ ] **Google OAuth** (workflow 09 — standup ingestion)
  - App Google OAuth en mode "test" → ajouter les emails dans Audience
  - Se connecter dans n8n → Credentials → Google Docs OAuth2

### 2. Variables d'environnement post-import
Mettre à jour `.env` avec les IDs des workflows importés dans n8n, puis `docker compose restart n8n` :
- [ ] `F03_WORKFLOW_ID` — ID du workflow 01 dans n8n
- [ ] `F08_WORKFLOW_ID` — ID du workflow 02 dans n8n
- [ ] `F01_WORKFLOW_ID` — ID du workflow 04 dans n8n
- [ ] `DELIVERY_EXECUTOR_WORKFLOW_ID` — ID du workflow 01c dans n8n

### 3. Activer les workflows restants dans n8n
- [ ] Workflow 01b — Approval Resolution (doit être actif pour recevoir les réactions ✅/❌ dans Discord)
- [ ] Workflow 04 — Client Report (schedule trigger vendredi 17h)
- [ ] Workflows 08, 09, 10, 11, 12 — P1 features (standup, check-ins, time-log)

### 4. Tests end-to-end (une fois credentials configurés)
- [ ] **Client Q&A** : message dans `#client` → draft dans `#tl-approvals` → réagir ✅ → réponse envoyée dans `#client`
- [ ] **Client Welcome** : nouveau membre rejoint le serveur → draft de bienvenue → approbation → message envoyé
- [ ] **Developer Query** : DM au bot → réponse directe dans le DM
- [ ] **TL Interaction** : message dans `#tl-approvals` → intent classifié → action exécutée
- [ ] **Client Report** : déclencher workflow 04 manuellement → draft rapport → approbation → envoi Gmail + Drive

---

## Note technique — Bug IF nodes n8n 1.91.3

Les IF nodes avec `=== true` se comportent de façon imprévisible dans cette version.
**Pattern à utiliser partout :**
```javascript
// Dans un Code node — à la place d'un IF node
if (conditionPourStopper) return [];  // arrête l'exécution silencieusement
return $input.all();                  // continue
```
Workflows déjà corrigés : 03, 05, 06, 07.
Workflows à surveiller si de nouveaux IF nodes posent problème : 01b, 03 (`Response Clean?`), 07 (`Response Clean?`, `Draft Found?`).
