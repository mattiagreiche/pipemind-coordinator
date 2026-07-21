# Pipemind — Plan de test end-to-end

*Créé le 2026-07-11, mis à jour le 2026-07-21 après la session qui a pull les 27 commits F-18/
F-19/F-20 du collègue, corrigé ~10 bugs (dont un dans `discord-forwarder` qui rendait le flow ✏️
mort depuis le début du projet), et complété la première suite de tests Team Lead réussie de bout
en bout (voir point 1 de "Blocages connus", maintenant entièrement résolu). Répartition des tests
entre Justin et Mattia selon les rôles définis dans `config/roster.json`.*

**Important** : Justin et Mattia font chacun tourner leur **propre instance locale séparée**
(Docker/Postgres/n8n indépendants) — un fix appliqué chez l'un ne s'applique pas automatiquement
chez l'autre. Chacun doit `git pull` + réimporter les workflows modifiés dans son propre n8n
(voir la commande `n8n import:workflow --input=...` + réactivation + **redémarrage du conteneur
n8n obligatoire** pour que l'activation prenne effet). Les credentials Google (Drive/Calendar/
Gmail) sont **spécifiques à chaque instance** — voir point 7 de "Blocages connus", important
avant de retester `01b`/`01c`. Les deux instances partagent le même token de bot Discord ; ce
n'est probablement plus considéré comme la cause du bug de réactions (voir point 1).

## Qui teste quoi

### Justin — rôle `team_lead`

Teste tout ce qui s'adresse au Team Lead, avec son propre compte Discord (celui
enregistré comme `team_lead` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `03 — F-16: Team Lead Interaction` | Écrire dans `#tl-approvals` (ex: "what's the project status", "explain what you do", "sur quels projets travaille X ?", "lier X à github.com/...", "qui est bloqué ?") | ✅ Testé, fonctionne — tous les intents confirmés le 2026-07-21 (status générique anonymisé, capacity_query nommé → F-20, link_project → F-19, refus F-16.5 anti-fishing, explain_request) |
| `04 — F-01: Client Progress Report` (on-demand) | Écrire "generate the weekly report" dans `#tl-approvals` (passe par `03`) | ✅ Testé, fonctionne (2026-07-11, reconfirmé 2026-07-13 et 2026-07-21) |
| Approval Gate (F-03) — réagir ✅ (approve) sur un draft `report` | Réagir ✅ sur un draft posté dans `#tl-approvals` | ✅ Confirmé avec de vraies réactions Discord le 2026-07-18. Livraison Drive bloquée séparément (credential sans token valide, voir "Blocages connus") |
| Approval Gate (F-03) — réagir ❌ (reject) | Réagir ❌ sur un draft | ✅ Confirmé avec de vraies réactions Discord le 2026-07-18 |
| Approval Gate (F-03) — réagir ✏️ (edit) | Réagir ✏️ → répondre en **vrai Reply Discord** (clic droit → Reply, pas juste taper dans le canal) au message du draft avec le texte corrigé → réagir ✅ sur sa propre réponse | ✅ **Confirmé le 2026-07-21, première fois de l'histoire du projet.** Bloqué depuis le début par un bug de `discord-forwarder` (ne relayait jamais `referenced_message`, donc jamais aucun reply n'était reconnu comme tel) — corrigé, testé de bout en bout (edited_text sauvegardé → draft `approved`) |
| `18 — F-18: Clockify Project & Assignment Sync` | Webhook manuel `POST /webhook/clockify-sync-manual` avec header `X-Sync-Secret`, ou attendre le schedule (2h) | ✅ Testé le 2026-07-21 avec de vraies données (36 projets, 47 memberships réels) |
| `19 — F-19: Project-Repository Linking` | Se déclenche automatiquement via `18` sur un nouveau projet ; le TL répond "lier [projet] à github.com/..." dans `#tl-approvals` | ✅ Testé le 2026-07-21 (via `03`, format sans `https://` comme suggéré par le message du bot) |
| `20 — F-20: Capacity & Bandwidth Query` | "sur quels projets travaille [nom] ?" / "combien d'heures a loggé [nom] ?" dans `#tl-approvals` | ✅ Testé le 2026-07-21 (réponse structurelle correcte ; données vides car pas encore de membership réelle liée à un développeur du roster) |

### Mattia — rôle `developer`

Teste tout ce qui s'adresse à un développeur, avec son propre compte Discord
(celui enregistré comme `developer` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `07 — F-17: Developer Project-Status Query` | DM au bot ("what's the project status", "explain what you do") | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull` |
| `10 — F-05: Developer Check-In` | Attendre le déclenchement automatique (10h), ou webhook manuel temporaire pour un test ponctuel | ✅ Chaîne complète testée le 2026-07-21 (Clockify + Google Calendar inclus), résultat "personne à contacter" légitime avec les données actuelles. Le vrai scénario "check-in envoyé → dev répond" côté Discord jamais exercé (aucun cas déclenché encore) |
| `11 — F-07: Time-Log Offer (EOD)` | Attendre `EOD_TIME` (17h), ou webhook manuel temporaire | ✅ Chaîne complète testée le 2026-07-21, même résultat "rien à faire" légitime |
| `12 — F-06: Unblock Assistance` | Répondre "yes"/"colleague"/"meeting"/"just-talk" à une offre d'aide | ✅ Côté envoi d'offre testé le 2026-07-21 (chaîne complète, 0 candidat bloqué — confirmé en base, pas un bug). Le bug de branches inversées côté réponse (`01b`) reste corrigé depuis le 2026-07-13 mais le **flux de réponse dev (yes/colleague/meeting/just-talk) reste jamais exercé en conditions réelles**, faute d'offre active à répondre |

### Mattia jouant le rôle "Client"

Comme il n'y a pas de vraie personne cliente pour l'instant, Mattia peut simuler
ce rôle en écrivant dans le channel client (`CLIENT_CHANNEL_ID`, `#client`).
Ces workflows se déclenchent sur le **channel**, pas sur une identité Discord
précise — n'importe qui avec accès au channel peut tester.

| Workflow | Comment tester | État |
|---|---|---|
| `05 — F-02: Client Question Answering` | Poser une question dans `#client` (ex: "what's the status of the auth feature") | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull`. Note : un draft `qa_reply` a déjà été généré avec succès sur l'instance de Mattia le 2026-07-11 avant même ce fix — donc ce chemin précis ne l'avait peut-être pas touché. Un 2e bug (résidu d'auth cassé sur `Check Candidate Scheduled`, chemin teammate-escalation F-02.2/F-02.3) corrigé le 2026-07-13, pas encore testé. |
| `06 — F-15: Client Welcome Message` | Se joindre au channel `#client` / premier message | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull` |

## Blocages connus (mis à jour 2026-07-21)

1. **Les réactions Discord (✅/❌/✏️) ne remontaient jamais jusqu'à `01b`** — **entièrement résolu.**
   ✅/❌ confirmées avec de vraies réactions le 2026-07-18 (le token Discord partagé n'a jamais été
   la vraie cause — un bug de code dans `Classify Event`, voir `RESTE_A_FAIRE.md`). ✏️ (edit)
   confirmé le 2026-07-21 : bug distinct trouvé dans `discord-forwarder/index.js`, qui ne relayait
   jamais le champ `message.reference` (nécessaire pour détecter un vrai Discord "Reply") — corrigé,
   testé de bout en bout avec succès. **Plus aucun blocage connu sur le canal d'approbation.**
2. **Bug pairedItem `.item`/`.first()`** — corrigé partout (`03`: commit `59bea5d`,
   `05`/`06`/`07`: commit `3dd8e11`). Chaque instance doit `git pull` + réimporter pour en
   bénéficier.
3. **`CLOCKIFY_WORKSPACE_ID`** — configuré et fonctionnel depuis au moins le 2026-07-21 (sync F-18
   confirmé avec de vraies données). `10`/`11`/`12`/`01b`/`01c` restent à retester en direct malgré
   ça (plus bloqués par Clockify, juste pas encore testés).
4. **Jira / GitHub non configurés** — dégradent proprement (signal secondaire seulement,
   jamais bloquant). Note : la spec dit Jira "retiré du scope" mais `04`/`05` l'appellent encore
   réellement dans le code — écart doc-vs-code non corrigé.
5. **Incohérence de langue** — messages codés en dur en français/anglais mélangés, contenu
   généré par Ollama en anglais par défaut (system prompt ne spécifie aucune langue cible).
   Pas bloquant, à uniformiser.
6. **IF natifs dans `01`/`01b`/`01c`** — audité et corrigé le 2026-07-13 (31 nodes convertis,
   voir `RESTE_A_FAIRE.md`). Plus un blocage.
7. **Les credentials Google (Calendar/Drive/Gmail) ont un ID différent sur chaque instance —
   important pour Mattia avant de retester `01b`/`01c` après ce `git pull`.** n8n génère un ID
   aléatoire à la création de chaque credential ; il n'y a **aucun fallback automatique** si
   l'ID référencé dans le JSON n'existe pas localement (confirmé ce soir : erreur franche
   `"Credential with ID X does not exist"`, pas de résolution par nom ou par type). Concrètement,
   après ce `git pull` + réimport, Mattia va très probablement retomber sur la même erreur que
   Justin ce soir, car les IDs corrigés dans le JSON (`QLPhcT7Vchnjrqsp` pour Calendar,
   `SAyj8Ovli7hMCL9c` pour Drive) sont ceux de **l'instance de Justin**, pas de la sienne. Pour
   corriger côté Mattia :
   - Créer/vérifier ses propres credentials n8n (Google Drive OAuth2, Google Calendar OAuth2 —
     Gmail n'existe même pas encore chez Justin, à créer des deux côtés)
   - Dans l'UI n8n, ouvrir chaque node concerné (`Save to Drive`, `Create Calendar Event`,
     `Check Colleague Calendar OOO`, `Send Gmail`) et sélectionner le bon credential dans le menu
     déroulant — ça met à jour l'ID en base **localement**, sans toucher au fichier JSON
   - ⚠️ Un futur `git pull` + réimport écrasera à nouveau ce choix local avec l'ID de Justin —
     c'est exactement le piège qui a cassé Drive ce soir (un fix manuel antérieur, jamais commité,
     écrasé par un réimport). Si ça devient récurrent, il faudra soit committer les vrais IDs de
     chaque instance dans des fichiers `.env`-like séparés, soit ne plus réimporter ces 2-3 nodes
     depuis le JSON une fois configurés localement.

## Notes

- Chaque instance (Justin, Mattia) tourne sa propre stack Docker locale complètement
  séparée — vérifier les résultats dans SA PROPRE base (`execution_entity`), pas celle
  de l'autre.
- Après chaque exécution, on peut vérifier le résultat directement en base
  (`execution_entity`) sans dépendre uniquement de l'UI.
- Détail complet des bugs trouvés/corrigés le 2026-07-11 : voir `RESTE_A_FAIRE.md`
  section "5. Bugs trouvés le 2026-07-11".
