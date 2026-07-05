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
Tous les CRIT et HIGH de cet audit sont maintenant résolus (voir ci-dessous pour les commits).
Restent les MEDIUM et LOW, non bloquants.

Findings par sévérité :

**CRIT — les deux résolus (2026-07-04)**
- [x] Canal d'approbation mort (01b webhook + réactions Discord) — voir commit `7d01c51`
- [x] Bug de comparateur booléen n8n 1.91.3 — 26 nodes convertis (25 IF + 1 Switch
  `Route Message Type` dans 07, trouvé lors de la revue sécurité du premier passage) au
  pattern Code node `if (cond) return []; return $input.all();`, dans 00, 01b, 02, 03, 05, 06,
  07, 10, 12 — voir commit `b365c1b`. Bonus : bug de câblage inversé corrigé dans 01b
  (`If Time Parsed?` avait ses branches vraie/fausse échangées).

**HIGH — les 5 résolus (2026-07-04)**
- [x] LIKE injection dans la recherche de collègue (`01b`) — passé en exact match (commit `e55f4dc`)
- [x] Check Google Calendar ajouté pour SC-06a (`01b`, merge Clockify+Calendar, stricter-wins,
      fail-closed) — commit `e55f4dc`. Deux bugs préexistants trouvés et corrigés au passage :
      `If Colleague Found?` avait ses branches vraie/fausse inversées, et `Check Colleague
      Scheduled` n'activait pas "Full Response" donc son `statusCode`/`body` n'existaient jamais.
- [x] F-06.2/F-06.3 réparés — `discord_message_id` maintenant rattaché au draft après l'envoi
      Discord (`Save Colleague/Meeting Draft Message ID`) — commit `e55f4dc`
- [x] Variables `TL_CHANNEL_ID`/`TEAM_LEAD_APPROVAL_CHANNEL_ID` unifiées en une seule
      (`TL_CHANNEL_ID`, validée au démarrage) dans 6 workflows + `.env.example` +
      `docker-compose.yml` — commit `0412558`. Le problème était plus large que prévu : les deux
      variables coexistaient dans tout le coeur de l'approval gate (01/03/04/05/06), pas
      seulement dans l'alerte de 00. Note : retirer manuellement l'ancienne ligne
      `TEAM_LEAD_APPROVAL_CHANNEL_ID=` du `.env` local (morte, plus lue par aucun workflow).
- [x] `04-client-report` — point d'entrée à la demande ajouté (`On-Demand Trigger`,
      `executeWorkflowTrigger`, câblé sur le même chemin d'audit/approbation que le trigger
      planifié) — commit `df3efd8`

**MEDIUM**
- [x] `boundary_audit_passed` jamais vérifié en DB — migration `007` ajoute le check dans
      `check_status_transition()` (commit `0c8bea6`). Investigation complète avant de coder :
      tous les chemins d'écriture actuels (01, 01b, 11) mettent déjà ce flag correctement avant
      d'atteindre `status='approved'` — ce fix est du renforcement en profondeur, pas la
      correction d'un contournement actif.
- [x] `05-client-qa` n'appelle jamais F-08 — **vérifié, faux positif** : `05` appelle bien F-08,
      indirectement via le workflow 01 (Approval Gate) partagé, qui audite automatiquement tout
      draft `content_type IN ('report','qa_reply','welcome')` avant que le TL le voie. Le finding
      original comparait à tort à l'audit inline de 03 sans tracer ce chemin. Aucun fix de code.
- [x] `05-client-qa` node `Too Many Pending?` perd silencieusement le message client si ≥2 drafts
      en attente — corrigé, alerte maintenant le TL (sans contenu client) au lieu de `return []`
      sans route ; le NoOp `Skip — Too Many Pending` était en fait déjà orphelin, retiré —
      commit `81fa24a`
- [x] `01c-delivery-executor` — race condition sur retry concurrent corrigée sur les 7 flux de
      livraison (Drive/Gmail/QA/Welcome/Clockify/DM collègue/Calendar) : `INSERT ... ON CONFLICT
      DO NOTHING RETURNING` posé AVANT l'action externe (claim atomique), avec rollback (`DELETE`)
      si l'action échoue pour rester réessayable. Ajouté au passage la vérification succès/échec
      manquante sur Drive/Gmail/QA/Welcome (le "delivered" se posait avant même en cas d'échec) et
      corrigé `Log Client Welcomed` qui tournait même si le post échouait — commit `a287d10`.
      2 bugs trouvés et corrigés en review avant ce commit : `Save to Drive`/`Send Gmail` sans
      `continueOnFail` (aurait transformé une erreur API transitoire en fuite de claim permanente
      bloquant tout retry futur), et la notif "pas d'email calendrier" qui perdait sa référence de
      channel après l'insertion du nouveau node de rollback.
- [ ] `11-time-log-offer` — `Log Outreach` s'exécute avant confirmation d'envoi DM
- [x] `08-memory-reader` fait confiance aux données — **vérifié, déjà mitigé** : `project_signals`
      est gardé par un `throw` explicite dans le workflow 09 avant écriture si
      `boundary_audit_passed` n'est pas vrai. `qa_history` n'est écrit par AUCUN workflow
      actuellement (F-14 pas encore branché côté écriture) — pas de risque de fuite tant que ça
      reste le cas. À surveiller : si `qa_history` reçoit un jour un writer, lui ajouter le même
      garde que 09. Aucun fix de code pour l'instant.
- [ ] F-08.3 non mitigé pour petites équipes (compte brut de développeurs bloqués sans seuil)
- [ ] `dm_channel_id` périmé confirmé dans `01b` (10/11/12 rouvrent déjà le channel à chaque fois, ok)

**LOW**
- [ ] Pas d'Expiry Janitor générique pour `approval_drafts` (concerne toute la table, pas
      seulement le workflow 06)
- [ ] `qa_history` toujours sans colonne `written_by_workflow`
- [ ] Nodes `Skip?`/NoOp devenus orphelins après la conversion CRIT (`Skip — Invalid Message`,
      `Skip — Not Client`, `Skip — Too Many Pending`, `Skip — Not Join Event`, `Skip — Not DM`,
      `Skip — Not Developer` dans 03/05/06/07) — comportement fonctionnel identique (c'étaient
      déjà des dead-ends), juste du nettoyage cosmétique à faire un jour

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

## Note technique — Bug IF/Switch nodes n8n 1.91.3 — RÉSOLU (2026-07-04)

Les IF/Switch nodes avec comparateur `{type:"boolean", operation:"equals"}` (`=== true`/`=== false`)
se comportaient de façon imprévisible dans cette version. **Corrigé partout** (commit `b365c1b`) :
26 nodes convertis (25 IF + 1 Switch `Route Message Type` dans 07) au pattern suivant :

```javascript
// Dans un Code node — à la place d'un IF/Switch node
if (conditionPourStopper) return [];  // arrête l'exécution silencieusement
return $input.all();                  // continue
```

Quand un seul côté de la branche menait à une action réelle (l'autre à un dead-end/NoOp) : IF
remplacé en place par un seul Code node. Quand les deux côtés menaient à des actions différentes :
IF/Switch remplacé par deux Code nodes (`Nom (yes)`/`Nom (no)`), chacun câblé vers sa vraie cible
d'origine.

Si un nouveau node IF/Switch booléen apparaît, vérifier avec :
```
grep '"type": "boolean"' workflows/*.json
```
(au 2026-07-04, les seuls hits restants sont légitimes — un champ `boundary_audit_passed` de type
boolean dans deux Set nodes de `02-aggregation-boundary.json`, pas des comparateurs de routage).
