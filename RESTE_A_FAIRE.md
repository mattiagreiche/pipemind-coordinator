# Pipemind Coordinator — État du projet

*Mis à jour le 2026-07-04 suite à l'audit sécurité global post-merge (branche `main`). Cette
section reflète l'état réel vérifié par l'agent de sécurité, pas l'état espéré.*

## Ce qui est fait

### Infrastructure
- [x] Stack Docker complète : n8n 1.91.3 + Postgres 16 + Ollama + discord-forwarder
- [x] Schéma Postgres complet (`pipemind.*`) avec migrations 001-006
- [x] Secrets via 1Password CLI (`op://` refs) — aucune vraie valeur dans les fichiers
- [x] `config/roster.json` — source de vérité pour l'équipe et le client
- [x] Modèle Ollama `llama3.2` téléchargé

### Discord
- [x] Service `discord-forwarder` : bridge entre Discord Gateway et n8n webhooks
  - Messages `#client` → webhook `client-qa`
  - Messages `#tl-approvals` → webhooks `tl-interaction` + `approval-resolution`
  - DMs → webhooks `dev-query` + `approval-resolution`
  - Réactions (✅/✏️/❌, n'importe où) → webhook `approval-resolution`
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
| 01b — Approval Resolution | F-03 | Webhook réparé (2026-07-04), reste non testé en prod |
| 01c — Delivery Executor | F-03 | Importé, non testé |
| 02 — Aggregation Boundary | F-08 | Importé, non testé |

### Corrections techniques majeures
- Remplacement de `discordTrigger` (inexistant en n8n 1.91.3) par des webhook nodes dans 03, 05, 06, 07, et 01b (2026-07-04)
- Ajout de l'écoute des réactions Discord (`MessageReactionAdd`) + intents associés dans `discord-forwarder` (2026-07-04)
- Connexions IF inversées corrigées dans workflows 05, 06, 07

---

## Ce qui reste à faire

### 0. Suite à l'audit sécurité global (2026-07-04) — priorité absolue

L'audit a trouvé que le canal d'approbation (réactions ✅/✏️/❌) était **mort de bout en bout** :
`01b` utilisait un node inexistant en n8n 1.91.3, et le forwarder n'écoutait pas les réactions.
**Fix appliqué le 2026-07-04** (webhook + intents réactions + double-forward TL channel et DM
vers 01b) — en attente de revue sécurité avant commit.

Findings encore ouverts, par sévérité :

**CRIT**
- [ ] Bug IF n8n (`=== true` imprévisible) corrigé seulement partiellement : 9/13 workflows
  encore affectés, y compris des gates critiques — `02-aggregation-boundary` (`Boundary Clean?`,
  `Rewrite Clean?`), `00-startup-config-validation` (`Roster Valid?`, `Env Vars OK?`), ~15 nodes
  dans `01b`, `Response Clean?`/`Developer Verified?` dans `07`. Ne pas se fier à la liste
  "workflows à surveiller" ci-dessous (obsolète) — régénérer via
  `grep '"type": "boolean"' workflows/*.json` avant de corriger.

**HIGH**
- [ ] LIKE injection dans la recherche de collègue (`01b`, node `Resolve Colleague from Roster`)
      — passer en exact match
- [ ] Check Google Calendar manquant pour SC-06a (`01b`, node `Check Colleague Scheduled`)
- [ ] F-06.2/F-06.3 (looper un collègue, planifier une réunion) = code mort — le
      `discord_message_id` n'est jamais rattaché au draft après l'envoi Discord dans `01b`,
      donc `Lookup Draft` ne peut jamais matcher la réaction ensuite
- [ ] `00-startup-config-validation` — alerte config cassée référence la variable legacy
      `TEAM_LEAD_APPROVAL_CHANNEL_ID` au lieu de `TL_CHANNEL_ID`, échoue silencieusement
- [ ] `04-client-report` — pas de point d'entrée à la demande (seulement Schedule Trigger vendredi)

**MEDIUM**
- [ ] `boundary_audit_passed` est un flag décoratif — jamais vérifié dans
      `check_status_transition()` (migration 002)
- [ ] `05-client-qa` n'appelle jamais le workflow 02 (F-08) malgré la dépendance déclarée dans les specs
- [ ] `05-client-qa` node `Too Many Pending?` perd silencieusement le message client si ≥2 drafts en attente
- [ ] `01c-delivery-executor` — race condition possible sur retry concurrent (SELECT-then-INSERT
      au lieu de INSERT...RETURNING avant l'action externe)
- [ ] `11-time-log-offer` — `Log Outreach` s'exécute avant confirmation d'envoi DM
- [ ] `08-memory-reader` fait confiance aux données sans re-vérifier `boundary_audit_passed`
- [ ] F-08.3 non mitigé pour petites équipes (compte brut de développeurs bloqués sans seuil)
- [ ] `dm_channel_id` périmé confirmé dans `01b` (10/11/12 rouvrent déjà le channel à chaque fois, ok)

**LOW**
- [ ] Pas d'Expiry Janitor générique pour `approval_drafts` (concerne toute la table, pas
      seulement le workflow 06)
- [ ] `qa_history` toujours sans colonne `written_by_workflow`
- [ ] Nodes `Skip?` morts dans 03/05/06/07 (jamais atteints dans le graphe `connections`)

**Confirmé sûr** (pas besoin de retravailler) : anti-spoofing Discord (snowflake ID, jamais
username) partout, aucun secret en dur, garde SSRF sur `LLM_BASE_URL`, SQL paramétrée partout,
idempotence propre en 06, sanitisation anti-injection en 09, SC-06a bien fait dans 10/11/12.

### 1. Credentials manquants — priorité haute
Sans ces credentials, les workflows s'arrêtent à mi-chemin.

- [ ] **GitHub** : `GITHUB_TOKEN`, `GITHUB_OWNER`, `GITHUB_REPO` dans `.env`
- [ ] **Jira** : `JIRA_BASE_URL`, `JIRA_TOKEN`, `JIRA_AUTH`, `JIRA_PROJECT_KEY` dans `.env`
- [x] **Ollama** : modèle `llama3.2` téléchargé
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
- [ ] Workflow 01b — Approval Resolution (doit être actif pour recevoir les réactions ✅/❌ dans Discord ;
      attendre la fin des corrections CRIT ci-dessus avant d'activer en prod)
- [ ] Workflow 04 — Client Report (schedule trigger vendredi 17h)
- [ ] Workflows 08, 09, 10, 11, 12 — P1 features (standup, check-ins, time-log)

### 4. Tests end-to-end (une fois credentials configurés ET findings CRIT/HIGH corrigés)
- [ ] **Client Q&A** : message dans `#client` → draft dans `#tl-approvals` → réagir ✅ → réponse envoyée dans `#client`
- [ ] **Client Welcome** : nouveau membre rejoint le serveur → draft de bienvenue → approbation → message envoyé
- [ ] **Developer Query** : DM au bot → réponse directe dans le DM
- [ ] **TL Interaction** : message dans `#tl-approvals` → intent classifié → action exécutée
- [ ] **Client Report** : déclencher workflow 04 manuellement → draft rapport → approbation → envoi Gmail + Drive
- [ ] **Unblock Assistance (F-06)** : DM "yes" à une offre de check-in → flux colleague/meeting/just-talk → vérifier
      que la réaction/réponse ultérieure matche bien le bon draft (dépend du fix du finding HIGH ci-dessus)

---

## Note technique — Bug IF nodes n8n 1.91.3

Les IF nodes avec `=== true` se comportent de façon imprévisible dans cette version.
**Pattern à utiliser partout :**
```javascript
// Dans un Code node — à la place d'un IF node
if (conditionPourStopper) return [];  // arrête l'exécution silencieusement
return $input.all();                  // continue
```
**Ne pas se fier à une liste manuelle de nodes "à surveiller"** — l'audit du 2026-07-04 a montré
que la liste précédente ici (03/05/06/07 "déjà corrigés") était fausse : seuls des nodes
secondaires avaient été convertis, jamais les gates d'identité/anti-fuite. Avant de corriger,
régénérer la liste réelle des nodes concernés :
```
grep -l '"type": "boolean"' workflows/*.json
```
puis vérifier chaque occurrence dans le fichier trouvé.
