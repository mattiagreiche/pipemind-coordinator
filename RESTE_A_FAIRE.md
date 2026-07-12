# Pipemind Coordinator — État du projet

*Mis à jour le 2026-07-11 — premier test end-to-end réel du projet (00/03/04 validés, premier
draft client généré), 2 blocages restants (réactions Discord, audit IF natifs 01/01b/01c). Section
2026-07-05 (audit sécurité + F-14) conservée ci-dessous, toujours vraie. Cette section reflète
l'état réel vérifié, pas l'état espéré.*

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

## F-02.2/F-02.3 (teammate escalation) et SC-13 (auto-explication) construits — 2026-07-05

**Why:** En comparant `specs/coordination-agent.md` au code après le câblage F-14, deux écarts
identifiés : F-02.2/F-02.3 (demander à un coéquipier avant de répondre au client, avec fenêtre de
2h) était totalement absent de `05-client-qa` (elle allait toujours direct au message d'attente
sans jamais essayer de trouver quelqu'un à qui demander) ; SC-13 (l'agent peut expliquer ce qu'il
fait) n'existait nulle part, alors que c'est une contrainte système contraignante, pas une feature
optionnelle.

**How to apply:**
- **F-02.2/F-02.3** — commit `d6bde04`. Nouvelle table `pipemind.teammate_queries` (migration
  `009`). `05-client-qa` identifie la zone de la question (mot-entier contre `project_signals`,
  jamais de données Jira assignee — SC-17), trouve le développeur le plus récemment actif sur
  cette zone via `standup_records` (signal primaire, pas Jira), vérifie sa disponibilité en
  réutilisant le pattern Clockify+Calendar déjà audité de `01b`, lui envoie un DM, et enregistre
  la requête en attente (deadline = min(+2h, EOD_TIME du jour même)). `07-developer-query` capture
  sa réponse (claim atomique `UPDATE...RETURNING`), compose la réponse client via un nouvel appel
  Ollama dédié, et la fait passer par F-03 comme n'importe quel `qa_reply`. `13-expiry-janitor`
  bascule les requêtes expirées vers le message d'attente honnête existant.
- **SC-13** — commit `d5a5212`. `03-tl-interaction` et `07-developer-query` reconnaissent un
  nouvel intent `explain_request` (mots-clés, vérifié en premier pour ne pas confondre avec une
  question de statut), répondent avec une description statique de l'agent + l'activité récente
  DU DEMANDEUR LUI-MÊME uniquement (drafts approuvés/rejetés pour le TL, historique d'outreach
  pour le développeur) — jamais de donnée d'un tiers, sans passer par F-03 (cohérent avec F-16.4
  et F-17 qui n'exigent déjà pas d'approbation pour ce type de réponse informationnelle).

Durci en cours de route dans `02-aggregation-boundary` (`Pattern Audit`/`Extract & Re-Audit`) :
nouveau pattern pour attraper une attribution individuelle anonymisée du type "a developer
said..." — nécessaire parce que F-02.2 est le premier chemin qui fabrique la réponse brute d'UN
SEUL coéquipier comme matière première d'un contenu client.

**Deux vrais bugs trouvés et corrigés avant commit** (2 passages de review sécurité) :
1. HIGH — dans `07`, le check "réponse en attente d'un coéquipier ?" tournait AVANT la détection
   de commande d'approbation (F-07). Un développeur avec les deux états en attente en même temps
   (rare mais possible) voyait son "yes"/"no" happé par le mauvais flux. Réordonné : la commande
   d'approbation est vérifiée en premier, le check coéquipier seulement dans la branche "query"
   restante.
2. MEDIUM — `Insert Teammate Query` (05) n'avait pas de gestion d'échec ; un problème DB aurait
   fait disparaître la question du client sans jamais produire de réponse d'attente. Ajouté
   `continueOnFail` + repli vers le message d'attente existant en cas d'échec. Également : le
   compteur "trop de demandes en attente" compte maintenant `teammate_queries` en plus des
   drafts, pour éviter que deux questions client quasi-simultanées déclenchent deux DM séparés.

**Risque résiduel accepté, documenté par la review, pas corrigé cette session** : dans le cas rare
où un développeur a À LA FOIS un draft de time-entry en attente ET une teammate_query en attente,
répondre "yes"/"no" est maintenant traité comme l'approbation de temps (silencieusement, sans DM
de confirmation en cas de succès) plutôt que comme la réponse au coéquipier — la teammate_query
expire alors proprement après 2h et bascule sur le message d'attente. C'est plus étroit et plus
sûr que la collision d'origine (une écriture Clockify non confirmée vs. un mauvais brouillon
encore filtré par le TL), mais pas éliminé. Piste si ça devient un problème réel : exiger des
mots-clés différents ("approve"/"reject" au lieu de "yes"/"no"), ou ajouter une confirmation DM
sur succès de `Call Delivery Executor` dans `07` (actuellement silencieux sur la branche succès).

**Limite pré-existante, non spécifique à cette feature** : le nouveau pattern d'attribution
anonymisée dans `02-aggregation-boundary` (comme tous les `metricPatterns` existants) est un
regex à liste fermée — contournable par paraphrase (pluriel "developers said", "our dev
mentioned", "according to a developer...", verbes hors liste). C'est déjà le mode de défense
accepté dans tout le repo (regex + réécriture LLM + re-audit + revue humaine TL en dernier
rempart), pas une régression. À garder en tête si le TL voit passer un draft avec ce genre de
tournure qui n'aurait pas dû être là.

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

## Prochaine session — reprendre ici (mis à jour 2026-07-11)

Premier vrai test end-to-end du projet fait le 2026-07-11 (zéro test avant cette date). Résultat :
`00`/`03`/`04` fonctionnent, premier draft client généré avec succès. Deux blocages restent :

1. **Priorité #1 — les réactions Discord (✅/❌/✏️) ne remontent pas jusqu'à `01b`.** Piste
   trouvée en fin de session : Justin et son collègue partagent le même token de bot Discord sur
   deux instances locales séparées — probablement la vraie cause (pas un bug de workflow). À
   vérifier en premier : couper un des deux `discord-forwarder` et retester.
2. **Priorité #2 — auditer les nodes IF natifs restants dans `01`/`01b`/`01c`** (voir note
   technique en bas de fichier) — le bug de comparateur n8n 1.91.3 touche plus de types que prévu,
   et ce chemin (approval gate + delivery) n'a jamais été vérifié pour ce pattern.

Voir section "4. Tests end-to-end" et "5. Bugs trouvés le 2026-07-11" plus bas pour le détail
complet. Credentials manquants (Clockify, GitHub, Jira) et sections 1-3 aussi mis à jour.

## Ce qui est fait

### Infrastructure
- [x] Stack Docker complète : n8n 1.91.3 + Postgres 16 + Ollama + discord-forwarder
- [x] Schéma Postgres complet (`pipemind.*`) avec migrations 001-009
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

- [ ] **GitHub** : `GITHUB_OWNER`/`GITHUB_REPO` toujours vides au 2026-07-11 (confirmé — dégrade
      proprement depuis les fixs `continueOnFail` du 2026-07-11, mais aucun signal réel)
- [ ] **Jira** : toujours vide au 2026-07-11 (dégrade proprement, aucun signal réel)
- [ ] **Clockify** : `CLOCKIFY_WORKSPACE_ID` toujours vide au 2026-07-11 — **bloque visiblement**
      (par design) les workflows `10`, `11`, `12`, `01b`, `01c`
- [x] **Ollama** : modèle `llama3.2` téléchargé
- [ ] **Google OAuth** (workflow 09 — standup ingestion)
  - App Google OAuth en mode "test" → ajouter les emails dans Audience
  - Se connecter dans n8n → Credentials → Google Docs OAuth2

### 2. Variables d'environnement post-import
- [x] `F03_WORKFLOW_ID`, `F08_WORKFLOW_ID`, `F01_WORKFLOW_ID`, `F14_WORKFLOW_ID`,
      `DELIVERY_EXECUTOR_WORKFLOW_ID` — corrigés le 2026-07-11 (pointaient vers des IDs obsolètes
      qui n'existaient plus du tout, jamais réglés depuis le 2026-06-30 malgré la note "à
      reconfigurer"). Valeurs actuelles : voir `.env`, workflow IDs alignés avec les fichiers du
      repo depuis le réimport complet du 2026-07-11.

### 3. Activer les workflows restants dans n8n
- [x] Workflow 00, 03, 05, 07, 01b — actifs depuis le 2026-07-11
- [ ] Workflow 04 — Client Report — **volontairement inactif** (son Schedule Trigger vendredi
      n'est pas encore voulu en prod) ; reste appelable via `03` ("generate the weekly report")
      qui l'invoque en sous-workflow sans dépendre de son statut actif
- [ ] Workflows 06, 08, 09, 10, 11, 12, 13 — sous-workflows/features non encore testées (08 n'a
      pas besoin d'être actif, invoqué via Execute Workflow)

### 4. Tests end-to-end — premiers vrais tests le 2026-07-11 (zéro test avant cette date)
- [x] **TL Interaction (03)** : message dans `#tl-approvals` → intent classifié → réponse — validé
- [x] **Client Report (04)** : "generate the weekly report" dans `#tl-approvals` → `03`→`04`→
      `08`(F-14)→`01`(Approval Gate)→`02`(Aggregation Boundary)→draft posté dans `#tl-approvals`.
      **Premier draft de l'historique du projet** (`draft_id 443fac91-857b-48fc-a297-5740deddb97b`),
      contenu vérifié safe (aucune attribution individuelle, honnête sur l'absence de données).
- [ ] **Approbation d'un draft (réactions ✅/✏️/❌)** — **BLOQUÉ**, cause probable identifiée :
      Justin et son collègue font chacun tourner leur propre instance locale mais partagent le
      **même token de bot Discord** — deux connexions Gateway simultanées avec un seul token est
      une cause connue de livraison d'événements incohérente (une session peut "voler" des
      événements sans erreur visible). Les messages texte fonctionnaient parfaitement ce soir ;
      seules les réactions ne remontaient jamais jusqu'à `01b` (webhook bien enregistré côté n8n,
      confirmé). **Probablement pas un bug de code — à vérifier en premier la prochaine session**
      en isolant un seul `discord-forwarder` actif à la fois. Si confirmé, la vraie solution est un
      bot Discord distinct par développeur pour le dev local, pas un fix de workflow.
- [ ] **Client Q&A (05)** : bloqué par le bug pairedItem jusqu'au 2026-07-11 (corrigé, commit
      `3dd8e11`) — pas encore retesté après le fix
- [ ] **Client Welcome (06)** : même fix pairedItem appliqué le 2026-07-11 — pas encore testé
- [ ] **Developer Query (07)** : même fix — pas encore testé
- [ ] **Unblock Assistance (F-06)** : DM "yes" à une offre de check-in → flux colleague/meeting/just-talk
- [ ] Le chemin ✅ approve complet (jusqu'à un vrai envoi Gmail/Drive) — dépend du fix des réactions

### 5. Bugs trouvés le 2026-07-11 (premier vrai test end-to-end), tous documentés en détail plus haut
- [x] Chaîne `pairedItem` cassée (`.item` sans `pairedItem` en amont) dans `03`/`05`/`06`/`07` —
      corrigée (commits `59bea5d`, `3dd8e11`)
- [x] IF natifs avec comparateur string/number non fiable dans `03`/`04` — corrigés (`f1433d2`)
- [x] `Strip GitHub Fields` retournait un tableau comme valeur de `json` (viole la contrainte n8n
      "json doit être un objet") dans `04`/`05`/`07` — corrigé, en partie via les commits parallèles
      du collègue (`f1433d2`)
- [x] Chaîne de requêtes Postgres 0-row dans `08-memory-reader` (même classe de bug que le fix du
      collègue du 2026-07-09 dans `07`, mais jamais appliqué à `08`) — corrigé par le collègue via
      `alwaysOutputData: true` (commit `b24f13c`)
- [ ] **Non corrigé, notez pour plus tard** : incohérence de langue des messages (mélange
      français/anglais dans le texte codé en dur, et le contenu généré par Ollama sort en anglais
      faute de langue cible spécifiée dans le system prompt)
- [ ] **Non corrigé, notez pour plus tard** : le même pattern IF natif à auditer dans `01`/`01b`/`01c`
      (voir note technique plus bas) — `01b` seul a ~65 occurrences de `.item.json` non vérifiées
- [ ] **Ne PAS appliquer le fix pairedItem mécaniquement à `10`/`11`/`12`** — ces 3 fichiers ont de
      vrais nodes de fan-out (`Split Into ... Items`, un par développeur) où `.first()` renverrait
      toujours les données de la même personne au lieu de la bonne — risque réel de mélanger les
      données entre développeurs, pas juste un crash (trouvé par l'agent sécurité en review)

---

## Note technique — Bug IF/Switch nodes n8n 1.91.3 — PLUS LARGE QUE DOCUMENTÉ (mis à jour 2026-07-11)

**Correction importante** : cette section affirmait le bug "résolu" en ne couvrant que les
comparateurs `{type:"boolean"}`. Le 2026-07-11, premier vrai test end-to-end du projet (zéro test
avant cette date), on a trouvé le **même bug de comparateur sur des types STRING et NUMBER** dans
des nodes IF natifs ajoutés *après* le passage du 2026-07-04 (donc jamais convertis) :
- `03-tl-interaction.json` : `Explain Request?`/`Report Request?`/`Status Question?` (comparaison
  string sur `$json.intent`) — un message classé `report_request` prenait quand même la branche
  `explain_request`. Corrigé (restructuré en 4 gates Code node parallèles, alimentées directement
  par `Classify Intent`) — commit inclus dans `f1433d2`.
- `04-client-report.json` : `Already Drafted This Week?` (comparaison number `pending_count > 0`)
  — même symptôme. Corrigé (paire Code node yes/no) — commit `f1433d2`.

**Conclusion révisée : tout node `n8n-nodes-base.if`/`n8n-nodes-base.switch` restant dans le
projet est suspect, peu importe le type de comparaison (booléen, string, ou nombre).** Le grep
`"type": "boolean"` ne suffit pas à les trouver tous — chercher plutôt :
```
grep -c '"type": "n8n-nodes-base.if"\|"type": "n8n-nodes-base.switch"' workflows/*.json
```
**Pas encore audité (session dédiée nécessaire)** : `01-approval-gate.json`, `01b-approval-resolution.json`,
`01c-delivery-executor.json` ont un volume important de code non vérifié pour ce pattern — priorité
haute car c'est le chemin le plus critique (approval gate + delivery). Les fichiers `00`, `02`,
`08`, `09`, `10`, `11`, `12`, `13` n'ont pas non plus été audités mais sont moins prioritaires.

Pattern de fix établi (Code node unique, remplace un IF/Switch à une seule branche utile) :
```javascript
if (conditionPourStopper) return [];  // arrête l'exécution silencieusement
return $input.all();                  // continue
```
Pattern pour un routage à N branches mutuellement exclusives (remplace un IF/Switch à plusieurs
sorties utiles) : N gates Code node **parallèles**, toutes alimentées par le même node amont,
chacune vérifiant sa propre condition (voir `03-tl-interaction.json` : `Explain Request?`/
`Report Request?`/`Status Question?`/`No Recognized Intent?`) — pas une chaîne séquentielle.
