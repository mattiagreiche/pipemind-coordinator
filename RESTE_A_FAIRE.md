# Pipemind Coordinator — État du projet

*Mis à jour le 2026-07-04 suite à l'audit sécurité global post-merge (branche `main`). Cette
section reflète l'état réel vérifié par l'agent de sécurité, pas l'état espéré.*

## État global (résumé au 2026-07-04 soir, pour reprendre le 2026-07-05)

**Bugs de l'audit sécurité** : la grosse majorité est réglée. CRIT 2/2, HIGH 5/5, MEDIUM 5/8
(+ 2 des 8 étaient des faux positifs vérifiés sûrs, pas de vrai bug), LOW pas encore touchés
(cosmétique). Chaque fix a été vérifié par un agent de sécurité adversarial avant commit, et
plusieurs bugs de câblage cachés (branches vraie/fausse inversées, réponses HTTP mal formées)
ont été trouvés et corrigés au passage — pas juste les findings de l'audit initial.

**Mais "logique correcte sur papier" ≠ "testé et qui marche"** : zéro flux n'a encore tourné de
bout en bout en conditions réelles dans Discord/n8n. Deux choses bloquent complètement le test
réel, indépendamment de l'audit (jamais touchées cette session) :
- Credentials manquants : GitHub, Jira, Google OAuth
- IDs de workflow pas mis à jour dans `.env` + plusieurs workflows pas activés dans n8n (voir
  sections 1/2/3 plus bas)

Donc le code est probablement bon, mais rien ne remplace un vrai test end-to-end une fois les
credentials en place.

## Méthode suivie pendant la session d'audit (2026-07-04/05)

Pour chacun des 15 findings traités (2 CRIT, 5 HIGH, 8 MEDIUM), le même motif a été répété :

1. **Comprendre avant de coder** — retracer le vrai chemin du bug dans le graphe `connections`
   des workflows (pas juste lire le nom du node), plutôt que corriger à l'aveugle. Ça a permis de
   fermer 2 findings comme faux positifs (`05` appelle bien F-08 indirectement, `08` était déjà
   gardé pour `project_signals`) au lieu de coder un fix inutile.
2. **Vérifier l'intégrité structurelle après chaque édition** — script Python : aucun ID/nom de
   node dupliqué, aucune connexion pendante, **aucun cycle** (détection ajoutée après avoir
   moi-même introduit une boucle infinie dans `11-time-log-offer` en réordonnant des nodes —
   retrouvée par DFS avant même d'envoyer en revue).
3. **Agent de sécurité adversarial avant chaque commit** — jamais committé sans revue. Sur les
   ~15 fixes, l'agent a trouvé et fait corriger avant commit : un `webhookId` dupliqué, deux
   branches vraie/fausse inversées préexistantes (`If Time Parsed?`, `If Colleague Found?`), une
   réponse HTTP mal formée (`Check Colleague Scheduled` sans "Full Response"), un `continueOnFail`
   manquant qui aurait transformé une erreur API transitoire en blocage permanent (Drive/Gmail
   dans `01c`), et une référence de channel cassée par l'insertion mécanique d'un node de rollback.
4. **Commit atomique par fix, doc mise à jour en parallèle** — jamais de fix "en attente" sans
   trace dans ce fichier, pour qu'une coupure de session ne perde pas le contexte.

Résultat : code plus solide qu'avant l'audit, mais toujours **zéro test end-to-end réel** — voir
"État global" ci-dessous pour ce que ça veut dire concrètement.

## Prochaine session — reprendre ici

Tous les CRIT (2), HIGH (5) et MEDIUM (8, + 1 trouvé en cours de route) de l'audit du 2026-07-04
sont réglés (ou vérifiés faux positifs), agent sécurité + commit à chaque fois. Il reste :

1. [ ] Les LOW cosmétiques (liste plus bas — nodes orphelins, colonne `qa_history` inutilisée,
   pas d'Expiry Janitor générique).
2. [ ] `08-memory-reader` n'est câblé nulle part encore (découvert le 2026-07-05, voir section
   MEDIUM ci-dessous) — pas urgent, mais à garder en tête le jour où F-14/P1 le branche pour de
   vrai : deux points de masquage additionnels à vérifier à ce moment-là.

Une fois ça traité (ou si on décide de le laisser), le vrai blocage pour tester en prod reste les
**credentials manquants** (GitHub et Google faits, Jira à confirmer) et les **IDs de workflow à
mettre à jour dans `.env`** — voir sections 1 et 2 plus bas, inchangées depuis le début.

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
- [x] `11-time-log-offer` — `Log Outreach` s'exécutait avant confirmation d'envoi DM sur les
      chemins Offer et Info — corrigé pour matcher le pattern déjà correct de `10-checkin.json`
      (log uniquement après `$json.id` non-vide sur la réponse Discord). Boucle infinie trouvée
      et corrigée par moi-même avant la revue (détection de cycle par DFS, puis vérifiée sur les
      15 fichiers workflows) — commit `a5c0aaa`
- [x] `08-memory-reader` fait confiance aux données — **vérifié, déjà mitigé** : `project_signals`
      est gardé par un `throw` explicite dans le workflow 09 avant écriture si
      `boundary_audit_passed` n'est pas vrai. `qa_history` n'est écrit par AUCUN workflow
      actuellement (F-14 pas encore branché côté écriture) — pas de risque de fuite tant que ça
      reste le cas. À surveiller : si `qa_history` reçoit un jour un writer, lui ajouter le même
      garde que 09. Aucun fix de code pour l'instant.
- [x] F-08.3 non mitigé pour petites équipes — `08-memory-reader` masque maintenant
      `active_blocker_developer_count` (sous forme `'none'`/`'some'`, commit `4510881`) ET
      `feature_areas[].has_blocker` par zone nommée (retiré du tableau, commit `f419b7d`) quand
      l'équipe active a moins de 3 développeurs, pour `purpose='tl_internal'`. **Découverte
      importante en cours de route** : `08-memory-reader` n'est actuellement appelé par AUCUN
      workflow (`04-client-report` construit son propre draft sans passer par lui ; `07` non plus
      pour `dev_self`) — donc le risque réel aujourd'hui est nul, ce fix est du renforcement pour
      quand ce workflow sera câblé (probablement F-14/P1). Deux points à garder en tête pour ce
      jour-là : (1) l'audit F-08 réel (`02-aggregation-boundary.json`, différent malgré le nom
      similaire) ne détecte que des noms/IDs du roster — un texte du style "Auth: bloqué" sans nom
      ne serait PAS attrapé si `feature_areas` non masqué finissait dans un draft `report` ; (2)
      `purpose='dev_self'` reçoit aussi `feature_areas` complet sans masquage — même risque
      théorique, pas encore traité, pas bloquant tant que rien n'appelle ce workflow.
- [x] `dm_channel_id` périmé dans `01b` — remplacé par `$('Classify Event').item.json.channel_id`
      (le channel de l'événement Discord entrant, garanti à jour par construction puisqu'on répond
      dans la même conversation) sur les ~10 nodes d'envoi + les 2 `queryReplacement` de création
      de draft — plus simple que de répliquer le pattern "reopen" de 10/11/12 — commit `746be5d`

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
