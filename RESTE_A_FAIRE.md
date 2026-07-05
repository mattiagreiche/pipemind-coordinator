# Pipemind Coordinator — État du projet

*Mis à jour le 2026-07-05 — audit sécurité global post-merge (branche `main`) entièrement clos,
puis câblage de F-14 (Persistent Memory) dans les workflows consommateurs. Cette section reflète
l'état réel vérifié par l'agent de sécurité, pas l'état espéré.*

## F-14 (Persistent Memory) câblé — 2026-07-05

**Why:** `09-standup-ingestion` écrivait déjà les signaux de standup dans
`pipemind.project_signals`, mais rien ne les relisait — `04`/`05`/`07` construisaient leurs
réponses uniquement depuis GitHub/Jira, et `03` avait un TODO littéral en attendant ce câblage.
Ça violait la Règle #3 en pratique (les standups n'influençaient jamais un rapport, une réponse
Q&A, une réponse TL, ou une réponse dev).

**How to apply:** `08-memory-reader.json` est maintenant appelé (nouvelle variable
`F14_WORKFLOW_ID`, à régler comme les autres `*_WORKFLOW_ID` — voir section 2) par :
- `04-client-report` et `05-client-qa` (`purpose='report'`, Tier 1/Client) — commit `04503d6`
- `03-tl-interaction` (`purpose='tl_internal'`, Tier 2) — remplace le TODO par de vrais signaux
  anonymisés de zone/blocage
- `07-developer-query` (`purpose='dev_self'`) — ajoute les standups du développeur lui-même
  (F-17.2) en plus du contexte projet général (F-17.1)

Deux vrais trous trouvés et corrigés pendant 4 passages de review sécurité successifs (pas
seulement le câblage lui-même) :
1. `status_summary` (remonte in fine à un transcript de standup, la donnée la moins fiable du
   pipeline) entrait dans chaque prompt LLM sans filtre anti-injection — corrigé dans les 4
   fichiers avec le même filtre étendu que `09-standup-ingestion` (délimiteurs `System:`/`###`/
   `[INST]`/`<|im_start|>` etc.), + alignement de `Audit TL Response` (03) sur les `metricPatterns`
   de `02-aggregation-boundary` (07 les avait déjà).
2. Le masquage petite-équipe de `08-memory-reader` (F-08.3) ne portait que sur l'effectif total
   (`< 3` développeurs actifs) — une zone à propriétaire unique reste ré-identifiable même sur une
   équipe plus grande. Pour `purpose='report'` (Client, Tier 1, le plus strict — "aucune
   attribution individuelle, nommée ou non" par F-08.1), `has_blocker` est maintenant retiré de
   façon inconditionnelle, peu importe la taille d'équipe. `tl_internal`/`dev_self` gardent le
   seuil par taille d'équipe existant (accepté tel quel — Tier 2 autorise explicitement les
   signaux anonymisés de zone par F-08.2).

**Risque résiduel accepté, à revisiter si besoin** : pour `tl_internal`/`dev_self`, une zone à
propriétaire unique sur une équipe de 3+ développeurs reste ré-identifiable via `has_blocker`
(le seuil ne regarde que l'effectif total, pas le nombre de contributeurs par zone). Corriger ça
proprement demanderait une nouvelle requête (compter les contributeurs distincts par
`feature_area` dans `standup_records`) — pas fait cette session, jugé disproportionné vs. le
risque (Tier 2 autorise déjà ce type de signal par design). À revoir si une équipe réelle a une
zone à propriétaire unique évidente.

## État global (résumé au 2026-07-05, audit clos)

**Bugs de l'audit sécurité** : tous réglés. CRIT 2/2, HIGH 5/5, MEDIUM 6/8 (+ 2 des 8 étaient des
faux positifs vérifiés sûrs, pas de vrai bug), LOW 3/3. Chaque fix a été vérifié par un agent de
sécurité adversarial avant commit, et plusieurs bugs de câblage cachés (branches vraie/fausse
inversées, réponses HTTP mal formées, nodes morts non couverts au premier passage) ont été
trouvés et corrigés au passage — pas juste les findings de l'audit initial.

**Mais "logique correcte sur papier" ≠ "testé et qui marche"** : zéro flux n'a encore tourné de
bout en bout en conditions réelles dans Discord/n8n. Deux choses bloquent complètement le test
réel, indépendamment de l'audit (jamais touchées cette session) :
- Credentials manquants : GitHub, Jira, Google OAuth
- IDs de workflow pas mis à jour dans `.env` + plusieurs workflows pas activés dans n8n (voir
  sections 1/2/3 plus bas)

Donc le code est probablement bon, mais rien ne remplace un vrai test end-to-end une fois les
credentials en place.

**Côté audit** : les CRIT, HIGH, MEDIUM et maintenant les LOW sont tous réglés (voir "LOW" plus
bas, fermé le 2026-07-05). Il ne reste plus aucun finding ouvert de l'audit du 2026-07-04/05.

## Méthode suivie pendant la session d'audit (2026-07-04/05)

Pour chacun des 18 findings traités (2 CRIT, 5 HIGH, 8 MEDIUM, 3 LOW), le même motif a été
répété :

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

Tous les CRIT (2), HIGH (5), MEDIUM (8, + 1 trouvé en cours de route) et LOW (3) de l'audit du
2026-07-04/05 sont réglés (ou vérifiés faux positifs), et F-14 (Persistent Memory) est maintenant
câblé dans 03/04/05/07 (voir section dédiée plus haut). Le vrai blocage pour tester en prod reste
les **credentials manquants** (GitHub et Google faits, Jira à confirmer) et les **IDs de workflow
à mettre à jour dans `.env`** (dont le nouveau `F14_WORKFLOW_ID`) — voir sections 1 et 2 plus bas.

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
      `boundary_audit_passed` n'est pas vrai. `qa_history` n'est toujours écrit par AUCUN workflow
      (F-14 câblé côté lecture le 2026-07-05, pas encore côté écriture pour `qa_history`) — pas de
      risque de fuite tant que ça reste le cas. À surveiller : si `qa_history` reçoit un jour un
      writer, lui ajouter le même garde que 09.
- [x] F-08.3 non mitigé pour petites équipes — `08-memory-reader` masque
      `active_blocker_developer_count`/`active_blocker_area_count` (sous forme `'none'`/`'some'`,
      commits `4510881`, `04503d6`) ET `feature_areas[].has_blocker` (retiré du tableau, commits
      `f419b7d`, `04503d6`) quand l'équipe active a moins de 3 développeurs, pour
      `purpose='tl_internal'`/`'dev_self'` — et de façon inconditionnelle (peu importe la taille
      d'équipe) pour `purpose='report'` (Tier 1, le plus strict). **Ce risque est devenu réel le
      2026-07-05** : `08-memory-reader` est maintenant câblé dans `03`/`04`/`05`/`07` (voir section
      F-14 en haut du fichier) — le masquage ci-dessus n'est plus du renforcement préventif, c'est
      ce qui empêche activement la fuite dans un contenu client/TL/dev réel. Risque résiduel
      documenté et accepté dans la section F-14 : une zone à propriétaire unique reste
      ré-identifiable pour `tl_internal`/`dev_self` sur une équipe de 3+ développeurs (le seuil ne
      regarde que l'effectif total, pas les contributeurs par zone).
- [x] `dm_channel_id` périmé dans `01b` — remplacé par `$('Classify Event').item.json.channel_id`
      (le channel de l'événement Discord entrant, garanti à jour par construction puisqu'on répond
      dans la même conversation) sur les ~10 nodes d'envoi + les 2 `queryReplacement` de création
      de draft — plus simple que de répliquer le pattern "reopen" de 10/11/12 — commit `746be5d`

**LOW — les 3 résolus le 2026-07-05**
- [x] Expiry Janitor générique ajouté — nouveau workflow `13-expiry-janitor.json` (Schedule
      Trigger horaire + `UPDATE ... SET status = 'expired', settled_at = now() WHERE status =
      'pending' AND expires_at <= now()`), couvre toute la table `approval_drafts` tous
      content_type confondus, sur le même modèle que "Sweep Expired Offers" déjà en prod dans
      `12-unblock-assistance.json` — commit `5799387`. Vérifié : transition `pending → expired`
      passe `check_status_transition()` sans exception, et la clause `WHERE` est mutuellement
      exclusive avec les requêtes d'approbation/rejet de `01b` (pas de race destructive). Bonus
      trouvé en review : `Mark Rejected` dans `01b` ne vérifie pas `expires_at > now()` (TOCTOU
      préexistant, cosmétique — un rejet peut réussir sur un draft déjà expiré sans conséquence
      réelle puisque les deux issues aboutissent à "rien n'est envoyé") — laissé tel quel, pas
      bloquant.
- [x] `qa_history.written_by_workflow` ajoutée — migration `008-qa-history-provenance.sql`,
      colonne nullable avec la même contrainte de format que `feature_area` (whitelist
      alphanumérique) pour empêcher qu'un futur writer y stocke un `discord_id` ou un nom en
      clair — commit `83b5982`. Toujours aucun workflow n'écrit dans `qa_history` (F-14.1 pas
      câblé), donc pur schema future-proofing.
- [x] Nodes morts issus de la conversion IF→Code du CRIT nettoyés, en deux passes (la 1re revue
      sécurité avait raté une partie du problème en filtrant seulement par type NoOp) — commit
      `da9e6c9` :
      - 6 NoOp `Skip — X` (Invalid Message, Not Client ×2, Not Join Event, Not DM, Not Developer)
        dans 05/06/07 — dead-ends sans connexion entrante
      - 6 nodes Code supplémentaires trouvés au 2e passage : `Skip?` orphelin dans 03/05/06/07
        (superflu depuis que les nodes `Filter ... Message` amont ont absorbé la logique de skip
        directement) et `Too Many Pending?` dans 05 (superflu, remplacé par la paire
        `(yes)`/`(no)` issue de la même conversion)
      Confirmé par un balayage exhaustif des 16 fichiers (tous types de nodes, pas seulement
      NoOp) : plus aucun node orphelin, aucune connexion pendante, aucun id/nom dupliqué, aucun
      cycle. Diff = suppressions uniquement, aucun chemin fonctionnel touché.

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
- [ ] `F14_WORKFLOW_ID` — ID du workflow 08 dans n8n (nouveau, requis par 03/04/05/07 depuis le câblage F-14 du 2026-07-05)
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
